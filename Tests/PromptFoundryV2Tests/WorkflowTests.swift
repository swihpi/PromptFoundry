import AppKit
import Foundation
import SwiftData
import PromptFoundryCore

@MainActor
final class WorkflowTests {
    private var persistenceControllers: [PersistenceController] = []
    func makeVM(_ refiner: ControlledRefiner) throws -> WorkspaceViewModel {
        let persistence = try PersistenceController(inMemory: true)
        persistenceControllers.append(persistence)
        let library = PromptLibraryStore(context: persistence.container.mainContext)
        let vm = WorkspaceViewModel(library: library, codexRefiner: refiner, apiRefiner: refiner, credentials: EmptyCredentials(), codex: CodexAppServerService())
        vm.draft.originalIdea = "Make a useful app"
        vm.draft.professionalPrompt = "Previous trusted prompt"
        return vm
    }

    func waitForRequest(_ refiner: ControlledRefiner) async throws {
        for _ in 0..<100 {
            if refiner.continuation != nil { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Request did not start")
    }

    func settle() async throws { try await Task.sleep(nanoseconds: 100_000_000) }

    func testFailurePreservesOriginalAndPersistedPrompt() async throws {
        let refiner = ControlledRefiner(), vm = try makeVM(refiner)
        vm.generate(mode: .regenerate)
        try await waitForRequest(refiner)
        refiner.continuation?.yield(.delta("Partial replacement"))
        try await settle()
        XCTAssertEqual(vm.draft.professionalPrompt, "Previous trusted prompt")
        XCTAssertEqual(vm.pendingPrompt, "Partial replacement")
        refiner.continuation?.finish(throwing: PromptFoundryError.offline)
        try await settle()
        XCTAssertEqual(vm.generationState, .failed)
        XCTAssertEqual(vm.draft.professionalPrompt, "Previous trusted prompt")
        XCTAssertEqual(vm.library.records.first?.professionalPrompt, "Previous trusted prompt")
    }

    func testCancellationCannotOverwriteNewWorkspace() async throws {
        let refiner = ControlledRefiner(), vm = try makeVM(refiner)
        vm.generate(mode: .improve)
        try await waitForRequest(refiner)
        vm.newPrompt()
        refiner.continuation?.yield(.delta("Late result"))
        refiner.continuation?.finish(throwing: PromptFoundryError.offline)
        try await settle()
        XCTAssertEqual(vm.draft.professionalPrompt, "")
        XCTAssertEqual(vm.generationState, .idle)
        XCTAssertNil(vm.errorMessage)
    }

    func testSuccessfulReplacementKeepsVersionAndClarifications() async throws {
        let refiner = ControlledRefiner(), vm = try makeVM(refiner)
        vm.clarificationAnswers = ["Supported platform?": "macOS 14 or later"]
        vm.applyClarificationAnswers()
        try await waitForRequest(refiner)
        XCTAssertTrue(refiner.request?.context.contains("macOS 14 or later") == true)
        let response = PromptRefinementResponse(professionalPrompt: "Completed replacement", suggestedTitle: "Improved", taskType: "Coding")
        refiner.continuation?.yield(.completed(response, rawResponse: "{}"))
        refiner.continuation?.finish()
        try await settle()
        XCTAssertEqual(vm.draft.professionalPrompt, "Completed replacement")
        XCTAssertTrue(vm.selectedRecord?.versions.contains { $0.draft?.professionalPrompt == "Previous trusted prompt" } == true)
        XCTAssertTrue(vm.selectedRecord?.additionalContext.contains("macOS 14 or later") == true)
        vm.prepareCodexReview(desktop: false)
        XCTAssertFalse(vm.desktopHandoff)
        vm.prepareCodexReview()
        XCTAssertTrue(vm.desktopHandoff)
    }

    func testFileContextIsOptInAndBounded() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("Unique reference requirement".utf8).write(to: url)
        let refiner = ControlledRefiner(), vm = try makeVM(refiner)
        vm.addAttachments([url])
        vm.generate()
        try await waitForRequest(refiner)
        XCTAssertFalse(refiner.request!.context.contains("Unique reference requirement"))
        vm.stopGeneration()
        refiner.continuation = nil
        vm.contextFileIDs.insert(vm.draft.attachments[0].id)
        vm.generate()
        try await waitForRequest(refiner)
        XCTAssertTrue(refiner.request!.context.contains("Unique reference requirement"))
        vm.stopGeneration()
        try Data(repeating: 65, count: 64_001).write(to: url)
        XCTAssertThrowsError(try FileContextReader.read(url))
    }

    func testComparisonRepresentsBothDocuments() {
        let lines = PromptComparison.lines(before: "A\nB\nC", after: "A\nD\nC\nE")
        XCTAssertEqual(lines.filter { $0.kind != .added }.map { String($0.text.dropFirst(2)) }.joined(separator: "\n"), "A\nB\nC")
        XCTAssertEqual(lines.filter { $0.kind != .removed }.map { String($0.text.dropFirst(2)) }.joined(separator: "\n"), "A\nD\nC\nE")
    }
}

@main
enum WorkflowVerification {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let tests = WorkflowTests()
        try await tests.testFailurePreservesOriginalAndPersistedPrompt()
        print("PASS failure preserves active and persisted prompt")
        try await tests.testCancellationCannotOverwriteNewWorkspace()
        print("PASS cancellation and workspace isolation")
        try await tests.testSuccessfulReplacementKeepsVersionAndClarifications()
        print("PASS replacement versions, clarification persistence and handoff modes")
        try await tests.testFileContextIsOptInAndBounded()
        print("PASS file context opt-in and size limits")
        tests.testComparisonRepresentsBothDocuments()
        print("PASS comparison reconstructs both documents")
    }
}

func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T) { precondition(actual == expected, "Expected \(expected); got \(actual)") }
func XCTAssertTrue(_ value: Bool) { precondition(value) }
func XCTAssertFalse(_ value: Bool) { precondition(!value) }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
func XCTFail(_ message: String) { fatalError(message) }
func XCTAssertThrowsError<T>(_ operation: @autoclosure () throws -> T) {
    do { _ = try operation(); fatalError("Expected an error") } catch { }
}

final class ControlledRefiner: PromptRefining {
    var request: PromptRefinementRequest?
    var continuation: AsyncThrowingStream<PromptRefinementEvent, Error>.Continuation?
    func refine(_ request: PromptRefinementRequest) -> AsyncThrowingStream<PromptRefinementEvent, Error> {
        self.request = request
        return AsyncThrowingStream { continuation = $0 }
    }
}
struct EmptyCredentials: CredentialStoring {
    func get(account: String) throws -> String? { nil }
    func set(_ value: String, account: String) throws {}
    func delete(account: String) throws {}
}
