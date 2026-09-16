import Foundation

public enum PromptGenerationState: Equatable, Sendable {
    case idle
    case generating(partial: String)
    case completed(PromptRefinementResponse)
    case failed(PromptFoundryError)
    case cancelled(recoverableText: String)
}

public enum PromptGenerationAction: Sendable {
    case start
    case receiveDelta(String)
    case finish(PromptRefinementResponse)
    case fail(PromptFoundryError)
    case cancel
}

public struct PromptGenerationStateMachine: Sendable {
    public private(set) var state: PromptGenerationState = .idle

    public init() {}

    public mutating func apply(_ action: PromptGenerationAction) {
        switch action {
        case .start:
            state = .generating(partial: "")
        case .receiveDelta(let delta):
            let prior: String
            if case .generating(let partial) = state { prior = partial } else { prior = "" }
            state = .generating(partial: prior + delta)
        case .finish(let response):
            state = .completed(response)
        case .fail(let error):
            state = .failed(error)
        case .cancel:
            let text: String
            if case .generating(let partial) = state { text = partial } else { text = "" }
            state = .cancelled(recoverableText: text)
        }
    }
}
