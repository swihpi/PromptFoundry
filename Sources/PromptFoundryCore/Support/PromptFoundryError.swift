import Foundation

public enum PromptFoundryError: LocalizedError, Equatable, Sendable {
    case missingCredential
    case invalidCredential
    case offline
    case rateLimited
    case requestTimedOut
    case modelUnavailable(String)
    case cancelled
    case malformedResponse(raw: String)
    case persistence(String)
    case incompatibleArchive
    case corruptedArchive(String)
    case invalidWorkingDirectory
    case projectDirectoryCreationFailed(String)
    case codexNotInstalled
    case codexNotAuthenticated
    case codexUnavailable(String)
    case codexRefinementUnavailable(String)
    case exportFailed(String)
    case clipboardFailed

    public var errorDescription: String? {
        switch self {
        case .missingCredential: return "Add an OpenAI API key in Settings before refining a prompt."
        case .invalidCredential: return "The API key was rejected. Check it in Settings and try again."
        case .offline: return "PromptFoundry could not reach the AI service. Check your connection and try again."
        case .rateLimited: return "The AI service is receiving too many requests. Wait briefly and try again."
        case .requestTimedOut: return "The request took too long. Your text is safe; try again when ready."
        case .modelUnavailable(let model): return "The model “\(model)” is unavailable. Choose another model in Settings."
        case .cancelled: return "Generation stopped. Your existing text was preserved."
        case .malformedResponse: return "The AI response could not be validated. The raw response is available for recovery."
        case .persistence(let detail): return "Prompt history could not be saved: \(detail)"
        case .incompatibleArchive: return "This library backup was created by an incompatible PromptFoundry version."
        case .corruptedArchive(let detail): return "The library backup could not be read: \(detail)"
        case .invalidWorkingDirectory: return "Choose an existing project or working directory before creating a Codex task."
        case .projectDirectoryCreationFailed(let detail): return "PromptFoundry could not prepare the Codex project directory: \(detail)"
        case .codexNotInstalled: return "Codex is not installed. You can still copy the professional prompt."
        case .codexNotAuthenticated: return "Codex is installed but not signed in. Sign in with Codex, then check the connection again."
        case .codexUnavailable(let detail): return "Codex could not create the task: \(detail)"
        case .codexRefinementUnavailable(let detail): return "Codex could not refine the prompt: \(detail)"
        case .exportFailed(let detail): return "The export could not be completed: \(detail)"
        case .clipboardFailed: return "The prompt could not be copied to the clipboard."
        }
    }
}
