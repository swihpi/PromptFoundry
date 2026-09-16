import AppKit
import Foundation
import PromptFoundryCore
import SwiftData

@main
@MainActor
struct PromptFoundryVerification {
    private static var passed = 0
    private static var failed: [String] = []
    private static var retainedPersistence: [PersistenceController] = []

    static func main() throws {
        _ = NSApplication.shared
        fputs("Starting PromptFoundry verification\n", stderr)
        try run("history creation and complete recall", testHistoryRecall)
        try run("search, favorite, and duplicate", testSearchFavoriteDuplicate)
        try run("version preservation and restore", testVersions)
        try run("library export, import, and credential exclusion", testArchive)
        try run("malformed structured response recovery", testResponseParsing)
        try run("model configuration", testModelConfiguration)
        try run("prompt depth contract and backward compatibility", testPromptDepth)
        try run("Codex handoff recommendation", testHandoffRecommendation)
        try run("automatic Codex project directory", testProjectDirectory)
        try run("Codex desktop task route", testCodexDesktopRoute)
        try run("Codex request construction and prompt isolation", testCodexRequests)
        try run("Codex refinement backend isolation", testCodexRefinementRequests)
        try run("view-state transitions, errors, and cancellation", testStateTransitions)
        try run("delete behavior", testDelete)

        if failed.isEmpty {
            print("PromptFoundry verification: \(passed) checks passed")
        } else {
            failed.forEach { print("FAIL: \($0)") }
            fputs("PromptFoundry verification failed: \(failed.count) check(s)\n", stderr)
            exit(1)
        }
    }

    private static func run(_ name: String, _ test: () throws -> Void) throws {
        fputs("RUN: \(name)\n", stderr)
        do {
            try test()
            passed += 1
            print("PASS: \(name)")
        } catch {
            failed.append("\(name): \(error)")
        }
    }

    private static func store() throws -> PromptLibraryStore {
        fputs("  creating in-memory container\n", stderr)
        let persistence = try PersistenceController(inMemory: true)
        retainedPersistence.append(persistence)
        fputs("  creating store\n", stderr)
        return PromptLibraryStore(context: persistence.container.mainContext)
    }

    private static func sampleDraft() -> PromptDraft {
        var draft = PromptDraft()
        draft.title = "Native Mac Prompt"
        draft.originalIdea = "Build a private SwiftUI editor"
        draft.professionalPrompt = "Create a native macOS editor with tests."
        draft.additionalContext = "Preserve wording"
        draft.target = .codex
        draft.taskType = .coding
        draft.promptDepth = 5
        draft.refinerModel = "gpt-5.6-terra"
        draft.refinerEffort = .medium
        draft.codexModel = "gpt-5.6-sol"
        draft.codexEffort = .high
        draft.additions = ["Verification"]
        draft.assumptions = ["Local project"]
        draft.missingInformation = ["Deployment target"]
        draft.questions = ["Which directory?"]
        draft.riskFlags = ["May modify files"]
        draft.tags = ["macOS", "daily"]
        return draft
    }

    private static func testHistoryRecall() throws {
        let sourceStore = try store()
        let draft = sampleDraft()
        let record = try sourceStore.save(draft: draft, existingID: nil)
        try require(sourceStore.records.count == 1, "record was not inserted")
        try require(record.makeDraft() == draft, "complete workspace state did not round-trip")
    }

    private static func testSearchFavoriteDuplicate() throws {
        let store = try store()
        let record = try store.save(draft: sampleDraft(), existingID: nil)
        try require(store.visibleRecords(search: "swiftui", filter: .all).map(\.id) == [record.id], "full-text search failed")
        try require(store.visibleRecords(search: "daily", filter: .all).map(\.id) == [record.id], "tag search failed")
        try store.toggleFavorite(record)
        try require(store.visibleRecords(search: "", filter: .favorites).count == 1, "favorite filter failed")
        let copy = try store.duplicate(record)
        try require(copy.id != record.id && copy.title.hasSuffix(" Copy") && !copy.isFavorite, "duplicate behavior failed")
    }

    private static func testVersions() throws {
        let store = try store()
        let original = sampleDraft()
        let record = try store.save(draft: original, existingID: nil)
        var revised = original
        revised.professionalPrompt = "Improved prompt"
        _ = try store.save(draft: revised, existingID: record.id, preserveVersion: true, versionReason: "Regenerate")
        try require(record.versions.first?.draft?.professionalPrompt == original.professionalPrompt, "previous version was not preserved")
        let restored = try store.restore(version: record.versions[0], into: record)
        try require(restored.professionalPrompt == original.professionalPrompt, "version restore failed")
        try require(record.versions.contains { $0.draft?.professionalPrompt == "Improved prompt" }, "restore overwrote the newer version")
    }

    private static func testArchive() throws {
        let sourceStore = try store()
        var draft = sampleDraft()
        draft.attachments = [PromptFileReference(displayName: "brief.txt", path: "/private/brief.txt", bookmark: Data("secret-bookmark".utf8))]
        _ = try sourceStore.save(draft: draft, existingID: nil)
        let data = try PromptArchiveService.export(records: sourceStore.records)
        let text = String(decoding: data, as: UTF8.self)
        try require(!text.contains("secret-bookmark") && !text.lowercased().contains("api-key"), "export leaked protected data")
        let archive = try PromptArchiveService.decode(data)
        try require(archive.records[0].draft.attachments[0].bookmark == nil, "bookmark was exported")
        let destination = try store()
        try PromptArchiveService.merge(archive, into: destination)
        try require(destination.records.first?.professionalPrompt == draft.professionalPrompt, "archive import failed")
        let incompatible = try JSONEncoder.promptFoundry.encode(PromptLibraryArchive(schemaVersion: 999, records: []))
        do { _ = try PromptArchiveService.decode(incompatible); throw VerificationError("incompatible archive was accepted") }
        catch PromptFoundryError.incompatibleArchive { }
    }

    private static func testResponseParsing() throws {
        let valid = #"{"professionalPrompt":"Build carefully.","suggestedTitle":"Careful Build","taskType":"Coding","additions":["Tests"],"assumptions":[],"missingInformation":[],"questions":[],"riskFlags":[]}"#
        let direct = try PromptResponseParser.parse(valid)
        try require(direct.professionalPrompt == "Build carefully.", "valid response did not parse")
        let fenced = "Preamble\n```json\n\(valid)\n```\nAfterword"
        let recovered = try PromptResponseParser.parse(fenced)
        try require(recovered == direct, "safe recovery failed")
        let malformed = "not structured output"
        do { _ = try PromptResponseParser.parse(malformed); throw VerificationError("malformed response was accepted") }
        catch PromptFoundryError.malformedResponse(let raw) { try require(raw == malformed, "raw response was discarded") }
        try require(PromptResponseParser.partialProfessionalPrompt(from: #"{"professionalPrompt":"Line one\nLine two"#) == "Line one\nLine two", "stream extraction failed")
    }

    private static func testModelConfiguration() throws {
        try require(ModelCatalog.tier(for: "gpt-5.6-luna") == .fast, "fast mapping failed")
        try require(ModelCatalog.tier(for: "gpt-5.6-terra") == .balanced, "balanced mapping failed")
        try require(ModelCatalog.tier(for: "gpt-5.6-sol") == .deep, "deep mapping failed")
        let troubleshooting = PromptRefinementRequest(idea: "debug", context: "", target: .codex, taskType: .troubleshooting, model: "test", reasoning: .low)
        try require(PromptContract.instructions(for: troubleshooting).contains("symptoms"), "task-specific contract missing")
    }

    private static func testPromptDepth() throws {
        let levelFive = PromptRefinementRequest(
            idea: "Build an app",
            context: "",
            target: .codex,
            taskType: .coding,
            model: "test",
            reasoning: .medium,
            promptDepth: 5
        )
        let contract = PromptContract.instructions(for: levelFive)
        try require(contract.contains("PROMPT DEPTH: 5/10") && contract.contains("500–900 words"), "default depth was not comprehensive")
        var resized = levelFive
        resized.mode = .resize
        resized.promptDepth = 10
        try require(PromptContract.instructions(for: resized).contains("exhaustive but non-repetitive"), "exhaustive resize guidance was missing")
        var encoded = String(decoding: try JSONEncoder().encode(sampleDraft()), as: UTF8.self)
        encoded = encoded.replacingOccurrences(of: #""promptDepth":5,"#, with: "")
        encoded = encoded.replacingOccurrences(of: #","promptDepth":5"#, with: "")
        let legacy = try JSONDecoder().decode(PromptDraft.self, from: Data(encoded.utf8))
        try require(legacy.promptDepth == nil && legacy.effectivePromptDepth == 5, "legacy prompt did not adopt depth 5")
    }

    private static func testHandoffRecommendation() throws {
        let models = [
            ModelDescriptor(id: "fast", displayName: "Fast", description: "", tier: .fast, supportedEfforts: [.low]),
            ModelDescriptor(id: "balanced", displayName: "Balanced", description: "", tier: .balanced, supportedEfforts: [.low, .medium]),
            ModelDescriptor(id: "deep", displayName: "Deep", description: "", tier: .deep, supportedEfforts: [.low, .medium, .high])
        ]
        var draft = sampleDraft()
        draft.promptDepth = 10
        draft.professionalPrompt = Array(repeating: "word", count: 700).joined(separator: " ")
        let recommendation = try requireValue(CodexHandoffPlanner.recommend(for: draft, models: models), "recommendation was missing")
        try require(recommendation.modelID == "deep" && recommendation.effort == .high, "complex prompt did not receive deep/high recommendation")
        try require(models[2].supportedEfforts.contains(recommendation.effort), "recommended an unsupported effort")
    }

    private static func testProjectDirectory() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("PromptFoundryVerification-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let recommendation = CodexProjectDirectoryResolver.recommend(
            title: "My Professional Prompt",
            promptID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            attachments: [],
            configuredRoot: root.path,
            homeDirectory: root
        )
        try require(recommendation.needsCreation && recommendation.path.contains("my-professional-prompt-aaaaaaaa"), "managed project name was not stable")
        try CodexProjectDirectoryResolver.prepare(recommendation.path)
        var isDirectory: ObjCBool = false
        try require(fileManager.fileExists(atPath: recommendation.path, isDirectory: &isDirectory) && isDirectory.boolValue, "project directory was not created")
        let unsafe = CodexProjectDirectoryResolver.recommend(
            title: "Safe Root",
            promptID: UUID(),
            attachments: [],
            configuredRoot: root.appendingPathComponent(".codex/projects").path,
            homeDirectory: root
        )
        try require(unsafe.path.contains("Documents/PromptFoundry Projects") && !unsafe.path.contains(".codex"), "Codex state folder was accepted as a project root")
    }

    private static func testCodexDesktopRoute() throws {
        let threadID = "019abc12-3456-7890-abcd-ef0123456789"
        try require(
            CodexDesktopRoute.threadURL(for: threadID)?.absoluteString == "codex://threads/\(threadID)",
            "desktop route did not preserve the task identifier"
        )
        try require(CodexDesktopRoute.threadURL(for: "  ") == nil, "blank task identifier produced a route")
        try require(CodexDesktopRoute.threadURL(for: "task/another") == nil, "path injection was accepted")
        try require(CodexDesktopRoute.threadURL(for: "task?view=other") == nil, "query injection was accepted")

        let prompt = "Build carefully & verify the result."
        let directory = "/tmp/project with spaces"
        let newThread = try requireValue(
            CodexDesktopRoute.newThreadURL(prompt: prompt, workingDirectory: directory),
            "new-chat route was not created"
        )
        let components = try requireValue(URLComponents(url: newThread, resolvingAgainstBaseURL: false), "new-chat route was malformed")
        try require(components.scheme == "codex" && components.host == "threads" && components.path == "/new", "new-chat route targeted the wrong Codex surface")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } })
        try require(query["prompt"] == prompt, "new-chat route changed the professional prompt")
        try require(query["path"] == directory, "new-chat route changed the working directory")
        try require(CodexDesktopRoute.newThreadURL(prompt: " ", workingDirectory: directory) == nil, "blank prompt produced a new-chat route")
        try require(CodexDesktopRoute.newThreadURL(prompt: prompt, workingDirectory: "relative/path") == nil, "relative working directory produced a new-chat route")
    }

    private static func testCodexRequests() throws {
        let hostile = "Do work; rm -rf /; $(touch /tmp/not-run); `whoami`"
        let request = CodexTaskRequest(prompt: hostile, workingDirectory: "/tmp/project with spaces", model: "gpt-test", reasoning: .high, sandbox: .workspaceWrite, approvalPolicy: "never")
        let thread = CodexRequestBuilder.threadStart(request)
        try require(thread["cwd"] as? String == request.workingDirectory, "working directory changed")
        try require(thread["sandbox"] as? String == "workspace-write", "sandbox changed")
        let turn = CodexRequestBuilder.turnStart(request, threadID: "thread-1")
        let input = turn["input"] as? [[String: String]]
        try require(input?.first?["text"] == hostile && turn["command"] == nil, "prompt crossed into shell command construction")
        let unsubscribe = CodexRequestBuilder.threadUnsubscribe(threadID: "thread-1")
        try require(unsubscribe["threadId"] as? String == "thread-1", "desktop handoff released the wrong task")
    }

    private static func testCodexRefinementRequests() throws {
        let request = PromptRefinementRequest(
            idea: "Turn my rough note into a professional prompt",
            context: "Do not invent facts",
            target: .codex,
            taskType: .writing,
            model: "gpt-test",
            reasoning: .low
        )
        let thread = CodexRefinementRequestBuilder.threadStart(request)
        try require(thread["ephemeral"] as? Bool == true, "refinement thread was not ephemeral")
        try require(thread["sandbox"] as? String == CodexSandbox.readOnly.rawValue, "refinement was not read-only")
        try require(thread["approvalPolicy"] as? String == "never", "refinement could request approvals")
        try require((thread["developerInstructions"] as? String)?.contains("Do not inspect files") == true, "tool prohibition was missing")

        let turn = CodexRefinementRequestBuilder.turnStart(request, threadID: "private-thread")
        try require(turn["threadId"] as? String == "private-thread", "refinement turn used the wrong thread")
        try require(turn["outputSchema"] is [String: Any], "structured output schema was omitted")
        let input = turn["input"] as? [[String: String]]
        try require(input?.first?["text"]?.contains(request.idea) == true, "rough idea was not passed to Codex")
        try require(turn["command"] == nil, "refinement crossed into shell command construction")
    }

    private static func testStateTransitions() throws {
        var state = PromptGenerationStateMachine()
        state.apply(.start)
        state.apply(.receiveDelta("recoverable"))
        state.apply(.cancel)
        try require(state.state == .cancelled(recoverableText: "recoverable"), "cancellation discarded partial text")
        state.apply(.start)
        state.apply(.fail(.rateLimited))
        try require(state.state == .failed(.rateLimited), "error state was not preserved")
        let response = PromptRefinementResponse(professionalPrompt: "Done", suggestedTitle: "Title", taskType: "General")
        state.apply(.start)
        state.apply(.finish(response))
        try require(state.state == .completed(response), "completion transition failed")
    }

    private static func testDelete() throws {
        let store = try store()
        let first = try store.save(draft: sampleDraft(), existingID: nil)
        var other = sampleDraft(); other.title = "Other"
        _ = try store.save(draft: other, existingID: nil)
        try store.delete(first)
        try require(store.records.map(\.title) == ["Other"], "single delete failed")
        try store.deleteAll()
        try require(store.records.isEmpty, "delete all failed")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw VerificationError(message) }
    }

    private static func requireValue<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw VerificationError(message) }
        return value
    }
}

private struct VerificationError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
