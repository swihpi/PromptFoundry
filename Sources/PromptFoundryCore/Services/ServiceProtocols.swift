import Foundation

public protocol PromptRefining {
    func refine(_ request: PromptRefinementRequest) -> AsyncThrowingStream<PromptRefinementEvent, Error>
}

public protocol CredentialStoring {
    func set(_ value: String, account: String) throws
    func get(account: String) throws -> String?
    func delete(account: String) throws
}

public protocol CodexServicing {
    func connectionStatus() async -> CodexConnectionStatus
    func availableModels() async throws -> [ModelDescriptor]
    func createTask(_ request: CodexTaskRequest) async throws -> CodexTaskResult
    func runTask(_ request: CodexTaskRequest) async throws -> CodexTaskResult
}

public enum CodexConnectionStatus: Equatable, Sendable {
    case checking
    case connected(version: String)
    case unavailable(message: String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
