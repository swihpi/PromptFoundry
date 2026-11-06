import PromptFoundryCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage(SettingsKeys.defaultRefinerModel) private var refinerModel = "gpt-5.6-terra"
    @AppStorage(SettingsKeys.defaultRefinerEffort) private var refinerEffortRaw = ReasoningEffort.medium.rawValue
    @AppStorage(SettingsKeys.refinementProvider) private var refinementProviderRaw = RefinementProvider.codex.rawValue
    @AppStorage(SettingsKeys.defaultCodexModel) private var codexModel = "gpt-5.6-terra"
    @AppStorage(SettingsKeys.defaultCodexEffort) private var codexEffortRaw = ReasoningEffort.medium.rawValue
    @AppStorage(SettingsKeys.defaultTarget) private var targetRaw = PromptTarget.codex.rawValue
    @AppStorage(SettingsKeys.defaultProjectDirectory) private var projectDirectory = ""
    @AppStorage(SettingsKeys.appearance) private var appearance = "system"
    @AppStorage(SettingsKeys.automaticSave) private var automaticSave = true
    @AppStorage(SettingsKeys.codexNeverAsk) private var codexNeverAsk = false
    @State private var apiKey = ""
    @State private var credentialStatus = "Not checked"
    @State private var showDeleteAll = false

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            modelsTab.tabItem { Label("Models", systemImage: "cpu") }
            privacyTab.tabItem { Label("Privacy", systemImage: "hand.raised") }
            codexTab.tabItem { Label("Codex", systemImage: "terminal") }
            shortcutsTab.tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 650, height: 470)
        .scenePadding()
        .alert("Delete All Prompt History?", isPresented: $showDeleteAll) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) { appModel.workspace.deleteAll() }
        } message: {
            Text("This permanently removes every locally saved prompt and version. Export a backup first if needed.")
        }
    }

    private var generalTab: some View {
        Form {
            Section("Defaults") {
                Picker("Target", selection: $targetRaw) { ForEach(PromptTarget.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                Toggle("Save meaningful edits automatically", isOn: $automaticSave)
                LabeledContent("Appearance", value: "Dark · V2 editorial theme")
            }
            Section("Local History") {
                LabeledContent("Database") { Text(appModel.persistence.storeURL?.path ?? "Temporary in-memory store").lineLimit(1).truncationMode(.middle) }
                HStack {
                    Button("Export Library…") { exportLibrary() }
                    Button("Import Library…") { importLibrary() }
                    Spacer()
                    Button("Delete All…", role: .destructive) { showDeleteAll = true }
                        .disabled(appModel.library.records.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var modelsTab: some View {
        Form {
            Section("Prompt Refinement") {
                Picker("Provider", selection: $refinementProviderRaw) {
                    ForEach(RefinementProvider.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                TextField("Model", text: $refinerModel)
                Picker("Reasoning", selection: $refinerEffortRaw) { ForEach(ReasoningEffort.allCases) { Text($0.displayName).tag($0.rawValue) } }
                if refinementProviderRaw == RefinementProvider.codex.rawValue {
                    Label("Uses your signed-in Codex account. No API key is required.", systemImage: "checkmark.shield")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Uses the optional API credential stored in Keychain.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("Codex Execution") {
                TextField("Model", text: $codexModel)
                Picker("Reasoning", selection: $codexEffortRaw) { ForEach(ReasoningEffort.allCases) { Text($0.displayName).tag($0.rawValue) } }
            }
            Section {
                HStack {
                    Text("Model lists are refreshed from the configured services and unavailable models fail with a specific message.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { Task { await appModel.workspace.refreshConnections() } }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: refinementProviderRaw) { Task { await appModel.workspace.refreshConnections() } }
    }

    private var privacyTab: some View {
        Form {
            Section("Optional OpenAI API Credential") {
                SecureField("API key", text: $apiKey)
                HStack {
                    Button("Save in Keychain") { saveCredential() }.disabled(apiKey.isEmpty)
                    Button("Remove", role: .destructive) { removeCredential() }
                    Spacer()
                    Text(credentialStatus).foregroundStyle(.secondary)
                }
            }
            Section("Privacy") {
                Label("Codex refinement uses a private ephemeral read-only task and requires no API key.", systemImage: "terminal")
                Label("Credentials are stored in macOS Keychain—not history, preferences, logs, or exports.", systemImage: "key.fill")
                Label("Prompt API requests disable server-side response storage.", systemImage: "externaldrive.badge.xmark")
                Label("PromptFoundry has no analytics, advertising, accounts, or cloud sync.", systemImage: "eye.slash")
            }
        }
        .formStyle(.grouped)
        .onAppear { credentialStatus = ((try? appModel.keychain.get(account: OpenAIRefinementService.credentialAccount)) ?? nil) == nil ? "Not configured" : "Stored in Keychain" }
    }

    private var codexTab: some View {
        Form {
            Section("Connection") {
                LabeledContent("Status") { codexStatusLabel }
                Text("This signed-in Codex connection powers professional prompt refinement as well as task handoff.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    TextField("Optional projects root", text: $projectDirectory)
                    Button("Choose…") { if let url = DesktopPanels.chooseDirectory() { projectDirectory = url.path } }
                }
                Text("When blank, PromptFoundry creates a named project in ~/Documents/PromptFoundry Projects. Referenced files in one folder take priority. Codex’s own state folder is never used as a project root.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Do not ask for Codex execution approvals", isOn: $codexNeverAsk)
                Text("Workspace Write is the default. Every run still shows its directory, model, reasoning, prompt, and file-access level before submission.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Check Connection") { Task { await appModel.workspace.refreshConnections() } }
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutsTab: some View {
        Form {
            Section("Keyboard Shortcuts") {
                ShortcutRow(action: "New Prompt", keys: "⌘N")
                ShortcutRow(action: "Generate", keys: "⌘↩")
                ShortcutRow(action: "Run in Codex", keys: "⇧⌘↩")
                ShortcutRow(action: "Save", keys: "⌘S")
                ShortcutRow(action: "Copy Professional Prompt", keys: "⇧⌘C")
                ShortcutRow(action: "Search History", keys: "⌘F")
                ShortcutRow(action: "Settings", keys: "⌘,")
                ShortcutRow(action: "Stop or Dismiss", keys: "Esc")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var codexStatusLabel: some View {
        switch appModel.workspace.codexStatus {
        case .checking: ProgressView().controlSize(.small)
        case .connected(let version): Label(version, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .unavailable(let message): Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
        }
    }

    private func saveCredential() {
        do {
            try appModel.keychain.set(apiKey, account: OpenAIRefinementService.credentialAccount)
            apiKey = ""
            credentialStatus = "Stored in Keychain"
            Task { await appModel.workspace.refreshConnections() }
        } catch { credentialStatus = error.localizedDescription }
    }

    private func removeCredential() {
        do {
            try appModel.keychain.delete(account: OpenAIRefinementService.credentialAccount)
            apiKey = ""
            credentialStatus = "Not configured"
        } catch { credentialStatus = error.localizedDescription }
    }

    private func exportLibrary() {
        do {
            let data = try PromptArchiveService.export(records: appModel.library.records)
            try DesktopPanels.export(data: data, suggestedName: "PromptFoundry-Library", extension: "json")
            appModel.workspace.showFeedback(.exported)
        } catch { appModel.workspace.presentError(error.localizedDescription) }
    }

    private func importLibrary() {
        do {
            guard let data = try DesktopPanels.importJSON() else { return }
            let archive = try PromptArchiveService.decode(data)
            try PromptArchiveService.merge(archive, into: appModel.library)
            appModel.workspace.showFeedback(.imported(archive.records.count))
        } catch { appModel.workspace.presentError(error.localizedDescription) }
    }
}

private struct ShortcutRow: View {
    let action: String
    let keys: String
    var body: some View {
        LabeledContent(action) {
            Text(keys).font(.body.monospaced()).padding(.horizontal, 8).padding(.vertical, 3).background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        }
    }
}
