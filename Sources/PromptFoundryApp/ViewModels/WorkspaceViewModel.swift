import AppKit
import Combine
import Foundation
import PromptFoundryCore

@MainActor
final class WorkspaceViewModel: ObservableObject {
    enum GenerationState: Equatable {
        case idle
        case generating
        case completed
        case failed
    }

    enum Feedback: Equatable {
        case copied, saved, created(String), openedInCodex, imported(Int), exported

        var message: String {
            switch self {
            case .copied: return "Copied"
            case .saved: return "Saved"
            case .created(let id): return "Codex task created: \(id)"
            case .openedInCodex: return "New Codex chat opened"
            case .imported(let count): return "Imported \(count) prompt\(count == 1 ? "" : "s")"
            case .exported: return "Export complete"
            }
        }
    }

    @Published var draft: PromptDraft
    @Published var selectedID: UUID?
    @Published var historySearch = ""
    @Published var historyFilter = HistoryFilter.all
    @Published var selectedTag: String?
    @Published var sort = PromptSort.modified
    @Published var generationState = GenerationState.idle
    @Published var feedback: Feedback?
    @Published var errorMessage: String?
    @Published var rawFailedResponse: String?
    @Published var showCodexReview = false
    @Published var showDeleteAllConfirmation = false
    @Published var showVersionBrowser = false
    @Published var codexStatus = CodexConnectionStatus.checking
    @Published var refinerModels = ModelCatalog.initialRefinerModels
    @Published var codexModels = ModelCatalog.initialRefinerModels
    @Published var isRefreshingModels = false
    @Published var codexWorkingDirectory = ""
    @Published var directoryRecommendation: CodexProjectDirectoryRecommendation?
    @Published var codexRecommendation: CodexHandoffRecommendation?

    let library: PromptLibraryStore
    private let codexRefiner: PromptRefining
    private let apiRefiner: PromptRefining
    private let credentials: CredentialStoring
    private let codex: CodexServicing
    private var generationTask: Task<Void, Never>?
    private var autosaveCancellable: AnyCancellable?
    private var feedbackTask: Task<Void, Never>?
    private var loadingDraft = false
    private var handoffProjectID = UUID()

    init(library: PromptLibraryStore, codexRefiner: PromptRefining, apiRefiner: PromptRefining, credentials: CredentialStoring, codex: CodexServicing) {
        self.library = library
        self.codexRefiner = codexRefiner
        self.apiRefiner = apiRefiner
        self.credentials = credentials
        self.codex = codex
        self.draft = Self.defaultDraft()
        autosaveCancellable = $draft
            .dropFirst()
            .debounce(for: .milliseconds(800), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.autosaveIfNeeded() }
    }

    var filteredRecords: [PromptRecord] {
        library.visibleRecords(search: historySearch, filter: historyFilter, tag: selectedTag, sort: sort)
    }

    var selectedRecord: PromptRecord? {
        selectedID.flatMap { id in library.records.first(where: { $0.id == id }) }
    }

    var canGenerate: Bool {
        !draft.originalIdea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && generationState != .generating
    }

    var canUsePrompt: Bool { !draft.professionalPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var wordCount: Int {
        draft.originalIdea.split(whereSeparator: \ .isWhitespace).count
    }

    var characterCount: Int { draft.originalIdea.count }

    var promptDepth: Int {
        get { draft.effectivePromptDepth }
        set { draft.effectivePromptDepth = newValue }
    }

    var supportedCodexEfforts: [ReasoningEffort] {
        codexModels.first(where: { $0.id == draft.codexModel })?.supportedEfforts ?? ReasoningEffort.allCases
    }

    func newPrompt() {
        stopGeneration()
        loadingDraft = true
        selectedID = nil
        draft = Self.defaultDraft()
        handoffProjectID = UUID()
        codexWorkingDirectory = ""
        directoryRecommendation = nil
        codexRecommendation = nil
        generationState = .idle
        errorMessage = nil
        rawFailedResponse = nil
        loadingDraft = false
    }

    func select(_ record: PromptRecord) {
        stopGeneration()
        loadingDraft = true
        selectedID = record.id
        draft = record.makeDraft()
        handoffProjectID = record.id
        codexWorkingDirectory = ""
        directoryRecommendation = nil
        codexRecommendation = CodexHandoffPlanner.recommend(for: draft, models: codexModels)
        generationState = draft.professionalPrompt.isEmpty ? .idle : .completed
        errorMessage = nil
        rawFailedResponse = nil
        try? library.markUsed(record)
        loadingDraft = false
    }

    func generate(mode: RefinementMode = .generate) {
        guard canGenerate || (mode != .generate && canUsePrompt) else { return }
        stopGeneration()
        errorMessage = nil
        rawFailedResponse = nil
        generationState = .generating
        let originalProfessionalPrompt = draft.professionalPrompt
        if mode == .generate || mode == .regenerate { draft.professionalPrompt = "" }
        let request = PromptRefinementRequest(
            idea: draft.originalIdea,
            context: draft.additionalContext,
            target: draft.target,
            taskType: draft.taskType,
            model: draft.refinerModel,
            reasoning: draft.refinerEffort,
            mode: mode,
            existingPrompt: mode == .generate ? nil : originalProfessionalPrompt,
            attachmentNames: draft.attachments.map(\.displayName),
            promptDepth: draft.effectivePromptDepth
        )
        let provider = UserDefaults.standard.string(forKey: SettingsKeys.refinementProvider)
            .flatMap(RefinementProvider.init(rawValue:)) ?? .codex
        let activeRefiner = provider == .codex ? codexRefiner : apiRefiner
        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in activeRefiner.refine(request) {
                    guard !Task.isCancelled else { return }
                    switch event {
                    case .started: break
                    case .delta(let text): draft.professionalPrompt += text
                    case .completed(let response, _):
                        draft.professionalPrompt = response.professionalPrompt
                        draft.title = response.suggestedTitle
                        draft.additions = response.additions
                        draft.assumptions = response.assumptions
                        draft.missingInformation = response.missingInformation
                        draft.questions = response.questions
                        draft.riskFlags = response.riskFlags
                        if let mapped = PromptTaskType(rawValue: response.taskType) { draft.taskType = mapped }
                        let record = try library.save(draft: draft, existingID: selectedID, preserveVersion: true, versionReason: mode.rawValue.capitalized)
                        selectedID = record.id
                        handoffProjectID = record.id
                        recommendCodexConfiguration(apply: true)
                        refreshDirectoryRecommendation()
                        generationState = .completed
                        showFeedback(.saved)
                    }
                }
            } catch let error as PromptFoundryError {
                if case .malformedResponse(let raw) = error { rawFailedResponse = raw }
                if error == .cancelled {
                    if draft.professionalPrompt.isEmpty { draft.professionalPrompt = originalProfessionalPrompt }
                    generationState = .idle
                } else {
                    generationState = .failed
                    errorMessage = error.localizedDescription
                }
            } catch {
                generationState = .failed
                errorMessage = error.localizedDescription
            }
        }
    }

    func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        if generationState == .generating { generationState = .idle }
    }

    func save() {
        guard !draft.originalIdea.isEmpty || !draft.professionalPrompt.isEmpty else { return }
        do {
            let record = try library.save(draft: draft, existingID: selectedID)
            selectedID = record.id
            showFeedback(.saved)
        } catch { errorMessage = error.localizedDescription }
    }

    func copyPrompt() {
        guard canUsePrompt else { return }
        let board = NSPasteboard.general
        board.clearContents()
        guard board.setString(draft.professionalPrompt, forType: .string) else {
            errorMessage = PromptFoundryError.clipboardFailed.localizedDescription
            return
        }
        showFeedback(.copied)
    }

    func pasteIdea() {
        guard let value = NSPasteboard.general.string(forType: .string), !value.isEmpty else { return }
        draft.originalIdea = value
    }

    func clearIdea() { draft.originalIdea = "" }

    func duplicate(_ record: PromptRecord) {
        do { select(try library.duplicate(record)) }
        catch { errorMessage = error.localizedDescription }
    }

    func toggleFavorite(_ record: PromptRecord) {
        do { try library.toggleFavorite(record) }
        catch { errorMessage = error.localizedDescription }
    }

    func rename(_ record: PromptRecord, title: String) {
        do { try library.rename(record, to: title) }
        catch { errorMessage = error.localizedDescription }
    }

    func delete(_ record: PromptRecord) {
        do {
            let wasSelected = selectedID == record.id
            try library.delete(record)
            if wasSelected { newPrompt() }
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteAll() {
        do { try library.deleteAll(); newPrompt() }
        catch { errorMessage = error.localizedDescription }
    }

    func addTag(_ raw: String) {
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, !draft.tags.contains(tag) else { return }
        draft.tags.append(tag)
    }

    func removeTag(_ tag: String) { draft.tags.removeAll { $0 == tag } }

    func addAttachments(_ urls: [URL]) {
        for url in urls where !draft.attachments.contains(where: { $0.path == url.path }) {
            let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            draft.attachments.append(PromptFileReference(displayName: url.lastPathComponent, path: url.path, bookmark: bookmark))
        }
    }

    func removeAttachment(_ reference: PromptFileReference) { draft.attachments.removeAll { $0.id == reference.id } }

    func prepareCodexReview() {
        guard canUsePrompt else { return }
        if codexRecommendation == nil { recommendCodexConfiguration(apply: true) }
        refreshDirectoryRecommendation()
        showCodexReview = true
    }

    func createCodexTask(run: Bool) async {
        if codexWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            refreshDirectoryRecommendation()
        }
        let directory = codexWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = CodexTaskRequest(
            prompt: draft.professionalPrompt,
            workingDirectory: directory,
            model: draft.codexModel,
            reasoning: draft.codexEffort,
            sandbox: draft.codexSandbox,
            approvalPolicy: UserDefaults.standard.bool(forKey: SettingsKeys.codexNeverAsk) ? "never" : "on-request"
        )
        do {
            try CodexProjectDirectoryResolver.prepare(directory)
            directoryRecommendation?.needsCreation = false
            if run {
                if CodexDesktopNavigator.openNewChat(
                    prompt: request.prompt,
                    workingDirectory: request.workingDirectory
                ) {
                    showFeedback(.openedInCodex)
                } else {
                    errorMessage = "macOS could not open a new chat in the Codex desktop app. Your professional prompt remains available in PromptFoundry."
                }
            } else {
                let result = try await codex.createTask(request)
                showFeedback(.created(result.threadID))
            }
            showCodexReview = false
            if let record = selectedRecord { try? library.markUsed(record) }
        } catch { errorMessage = error.localizedDescription }
    }

    func refreshConnections() async {
        isRefreshingModels = true
        codexStatus = await codex.connectionStatus()
        if codexStatus.isConnected, let models = try? await codex.availableModels(), !models.isEmpty {
            codexModels = models
            if refinementProvider == .codex { refinerModels = models }
            if canUsePrompt, codexRecommendation == nil { recommendCodexConfiguration(apply: true) }
        }
        if refinementProvider == .openAIAPI {
            let catalog = OpenAIModelCatalogService(credentials: credentials)
            if let models = try? await catalog.fetch(), !models.isEmpty { refinerModels = models }
        }
        isRefreshingModels = false
    }

    var refinementProvider: RefinementProvider {
        UserDefaults.standard.string(forKey: SettingsKeys.refinementProvider)
            .flatMap(RefinementProvider.init(rawValue:)) ?? .codex
    }

    func presentError(_ message: String) { errorMessage = message }

    func refreshDirectoryRecommendation(resetToAutomatic: Bool = false) {
        let configured = UserDefaults.standard.string(forKey: SettingsKeys.defaultProjectDirectory)
        let recommendation = CodexProjectDirectoryResolver.recommend(
            title: draft.title,
            promptID: selectedID ?? handoffProjectID,
            attachments: draft.attachments,
            configuredRoot: configured
        )
        directoryRecommendation = recommendation
        if resetToAutomatic || codexWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            codexWorkingDirectory = recommendation.path
        }
    }

    func recommendCodexConfiguration(apply: Bool) {
        guard let recommendation = CodexHandoffPlanner.recommend(for: draft, models: codexModels) else { return }
        codexRecommendation = recommendation
        guard apply else { return }
        draft.codexModel = recommendation.modelID
        draft.codexTier = recommendation.tier
        draft.codexEffort = recommendation.effort
    }

    func selectCodexModel(_ modelID: String) {
        draft.codexModel = modelID
        guard let descriptor = codexModels.first(where: { $0.id == modelID }) else {
            draft.codexTier = .custom
            return
        }
        draft.codexTier = descriptor.tier
        if !descriptor.supportedEfforts.contains(draft.codexEffort) {
            draft.codexEffort = descriptor.supportedEfforts.first(where: { $0 == .medium })
                ?? descriptor.supportedEfforts.first ?? .medium
        }
    }

    func restore(_ version: PromptVersion) {
        guard let record = selectedRecord else { return }
        do { draft = try library.restore(version: version, into: record); showVersionBrowser = false; showFeedback(.saved) }
        catch { errorMessage = error.localizedDescription }
    }

    func showFeedback(_ value: Feedback) {
        feedbackTask?.cancel()
        feedback = value
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.feedback = nil
        }
    }

    private func autosaveIfNeeded() {
        guard UserDefaults.standard.bool(forKey: SettingsKeys.automaticSave), !loadingDraft, selectedID != nil,
              !draft.originalIdea.isEmpty || !draft.professionalPrompt.isEmpty else { return }
        do { _ = try library.save(draft: draft, existingID: selectedID) }
        catch { errorMessage = error.localizedDescription }
    }

    private static func defaultDraft() -> PromptDraft {
        var draft = PromptDraft()
        draft.promptDepth = PromptDepth.defaultValue
        let defaults = UserDefaults.standard
        if let targetRaw = defaults.string(forKey: SettingsKeys.defaultTarget), let target = PromptTarget(rawValue: targetRaw) { draft.target = target }
        if let model = defaults.string(forKey: SettingsKeys.defaultRefinerModel), !model.isEmpty { draft.refinerModel = model; draft.refinerTier = ModelCatalog.tier(for: model) }
        if let effort = defaults.string(forKey: SettingsKeys.defaultRefinerEffort).flatMap(ReasoningEffort.init(rawValue:)) { draft.refinerEffort = effort }
        if let model = defaults.string(forKey: SettingsKeys.defaultCodexModel), !model.isEmpty { draft.codexModel = model; draft.codexTier = ModelCatalog.tier(for: model) }
        if let effort = defaults.string(forKey: SettingsKeys.defaultCodexEffort).flatMap(ReasoningEffort.init(rawValue:)) { draft.codexEffort = effort }
        return draft
    }
}

enum SettingsKeys {
    static let refinementProvider = "refinementProvider"
    static let defaultRefinerModel = "defaultRefinerModel"
    static let defaultRefinerEffort = "defaultRefinerEffort"
    static let defaultCodexModel = "defaultCodexModel"
    static let defaultCodexEffort = "defaultCodexEffort"
    static let defaultTarget = "defaultTarget"
    static let defaultProjectDirectory = "defaultProjectDirectory"
    static let appearance = "appearance"
    static let automaticSave = "automaticSave"
    static let codexNeverAsk = "codexNeverAsk"
    static let codexExecutablePath = "codexExecutablePath"
    static let onboardingCompleted = "onboardingCompleted"
}
