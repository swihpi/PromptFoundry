import Foundation

public enum PromptTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex = "Codex"
    case chatGPT = "ChatGPT"
    case generalAI = "General AI"
    case writing = "Writing"
    case research = "Research"
    case coding = "Coding"
    case troubleshooting = "Troubleshooting"
    case custom = "Custom"

    public var id: String { rawValue }
    public var systemImage: String {
        switch self {
        case .codex: return "hammer"
        case .chatGPT: return "bubble.left.and.bubble.right"
        case .generalAI: return "sparkles"
        case .writing: return "pencil.line"
        case .research: return "books.vertical"
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .troubleshooting: return "stethoscope"
        case .custom: return "slider.horizontal.3"
        }
    }
}

public enum PromptTaskType: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic = "Automatic"
    case coding = "Coding"
    case research = "Research"
    case writing = "Writing"
    case troubleshooting = "Troubleshooting"
    case planning = "Planning"
    case analysis = "Analysis"
    case general = "General"

    public var id: String { rawValue }
    public var systemImage: String {
        switch self {
        case .automatic: return "wand.and.stars"
        case .coding: return "terminal"
        case .research: return "magnifyingglass"
        case .writing: return "doc.text"
        case .troubleshooting: return "wrench.and.screwdriver"
        case .planning: return "list.bullet.clipboard"
        case .analysis: return "chart.xyaxis.line"
        case .general: return "square.grid.2x2"
        }
    }
}

public enum ReasoningEffort: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, minimal, low, medium, high, xhigh, max, ultra
    public var id: String { rawValue }
    public var displayName: String { rawValue == "xhigh" ? "Extra High" : rawValue.capitalized }
}

public enum ModelTier: String, Codable, CaseIterable, Identifiable, Sendable {
    case fast = "Fast"
    case balanced = "Balanced"
    case deep = "Deep"
    case custom = "Custom"
    public var id: String { rawValue }
    public var systemImage: String {
        switch self {
        case .fast: return "bolt.fill"
        case .balanced: return "scale.3d"
        case .deep: return "brain.head.profile"
        case .custom: return "gearshape.2"
        }
    }
}

public enum CodexSandbox: String, Codable, CaseIterable, Identifiable, Sendable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case fullAccess = "danger-full-access"
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .readOnly: return "Read Only"
        case .workspaceWrite: return "Workspace Write"
        case .fullAccess: return "Full Access"
        }
    }
    public var allowsModification: Bool { self != .readOnly }
}

public enum HistoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Prompts"
    case favorites = "Favorites"
    case recent = "Recently Used"
    public var id: String { rawValue }
    public var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .favorites: return "star"
        case .recent: return "clock"
        }
    }
}

public enum PromptSort: String, Codable, CaseIterable, Identifiable, Sendable {
    case modified = "Last Modified"
    case created = "Date Created"
    case title = "Title"
    case model = "Model"
    case taskType = "Task Type"
    public var id: String { rawValue }
}

public struct ModelDescriptor: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var description: String
    public var tier: ModelTier
    public var supportedEfforts: [ReasoningEffort]
    public var available: Bool

    public init(id: String, displayName: String, description: String, tier: ModelTier, supportedEfforts: [ReasoningEffort], available: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.tier = tier
        self.supportedEfforts = supportedEfforts
        self.available = available
    }
}

public struct PromptFileReference: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var displayName: String
    public var path: String
    public var bookmark: Data?

    public init(id: UUID = UUID(), displayName: String, path: String, bookmark: Data? = nil) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.bookmark = bookmark
    }
}

public struct PromptDraft: Codable, Equatable, Sendable {
    public var title = "Untitled Prompt"
    public var originalIdea = ""
    public var professionalPrompt = ""
    public var additionalContext = ""
    public var target = PromptTarget.codex
    public var taskType = PromptTaskType.automatic
    public var promptDepth: Int?
    public var refinerModel = "gpt-5.6-terra"
    public var refinerTier = ModelTier.balanced
    public var refinerEffort = ReasoningEffort.medium
    public var codexModel = "gpt-5.6-terra"
    public var codexTier = ModelTier.balanced
    public var codexEffort = ReasoningEffort.medium
    public var codexSandbox = CodexSandbox.workspaceWrite
    public var additions: [String] = []
    public var assumptions: [String] = []
    public var missingInformation: [String] = []
    public var questions: [String] = []
    public var riskFlags: [String] = []
    public var tags: [String] = []
    public var attachments: [PromptFileReference] = []

    public init() {}

    public var effectivePromptDepth: Int {
        get { PromptDepth.clamp(promptDepth ?? PromptDepth.defaultValue) }
        set { promptDepth = PromptDepth.clamp(newValue) }
    }
}

public struct PromptRefinementRequest: Equatable, Sendable {
    public var idea: String
    public var context: String
    public var target: PromptTarget
    public var taskType: PromptTaskType
    public var model: String
    public var reasoning: ReasoningEffort
    public var mode: RefinementMode
    public var existingPrompt: String?
    public var attachmentNames: [String]
    public var promptDepth: Int

    public init(idea: String, context: String, target: PromptTarget, taskType: PromptTaskType, model: String, reasoning: ReasoningEffort, mode: RefinementMode = .generate, existingPrompt: String? = nil, attachmentNames: [String] = [], promptDepth: Int = PromptDepth.defaultValue) {
        self.idea = idea
        self.context = context
        self.target = target
        self.taskType = taskType
        self.model = model
        self.reasoning = reasoning
        self.mode = mode
        self.existingPrompt = existingPrompt
        self.attachmentNames = attachmentNames
        self.promptDepth = PromptDepth.clamp(promptDepth)
    }
}

public enum RefinementMode: String, Codable, Sendable {
    case generate, regenerate, improve, shorter, detailed, preserveWording, resize
}

public enum PromptDepth {
    public static let defaultValue = 5

    public static func clamp(_ value: Int) -> Int { min(10, max(1, value)) }

    public static func title(for value: Int) -> String {
        switch clamp(value) {
        case 1...2: return "Essential"
        case 3...4: return "Focused"
        case 5...6: return "Comprehensive"
        case 7...8: return "Detailed"
        default: return "Exhaustive"
        }
    }

    public static func guidance(for value: Int) -> String {
        switch clamp(value) {
        case 1:
            return "Be concise: retain only the objective, essential context, critical constraints, and requested output."
        case 2:
            return "Produce a compact but complete prompt with the essential requirements and success condition."
        case 3...4:
            return "Produce a focused professional prompt with clear scope, requirements, output, and verification where relevant."
        case 5:
            return "Produce a comprehensive, self-contained professional prompt. Cover the objective, context, deliverables, material functional and non-functional requirements, constraints, scope boundaries, assumptions, risks, output format, verification, and definition of done wherever relevant. For a substantive task, aim for roughly 500–900 words; never pad a simple task, but do not omit execution-critical detail."
        case 6:
            return "Produce a comprehensive prompt with extra operational detail, explicit acceptance criteria, edge cases, and verification evidence."
        case 7...8:
            return "Produce a highly detailed execution brief with dependencies, alternatives, edge cases, failure handling, quality criteria, and staged verification wherever relevant."
        default:
            return "Produce an exhaustive but non-repetitive specification: include full context, requirements, constraints, dependencies, edge cases, failure modes, non-goals, deliverables, acceptance criteria, and end-to-end verification."
        }
    }
}

public enum RefinementProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex = "Codex account"
    case openAIAPI = "OpenAI API key"

    public var id: String { rawValue }
}

public struct PromptRefinementResponse: Codable, Equatable, Sendable {
    public var professionalPrompt: String
    public var suggestedTitle: String
    public var taskType: String
    public var additions: [String]
    public var assumptions: [String]
    public var missingInformation: [String]
    public var questions: [String]
    public var riskFlags: [String]

    public init(professionalPrompt: String, suggestedTitle: String, taskType: String, additions: [String] = [], assumptions: [String] = [], missingInformation: [String] = [], questions: [String] = [], riskFlags: [String] = []) {
        self.professionalPrompt = professionalPrompt
        self.suggestedTitle = suggestedTitle
        self.taskType = taskType
        self.additions = additions
        self.assumptions = assumptions
        self.missingInformation = missingInformation
        self.questions = questions
        self.riskFlags = riskFlags
    }
}

public enum PromptRefinementEvent: Sendable {
    case started
    case delta(String)
    case completed(PromptRefinementResponse, rawResponse: String)
}

public struct CodexTaskRequest: Equatable, Sendable {
    public var prompt: String
    public var workingDirectory: String
    public var model: String
    public var reasoning: ReasoningEffort
    public var sandbox: CodexSandbox
    public var approvalPolicy: String

    public init(prompt: String, workingDirectory: String, model: String, reasoning: ReasoningEffort, sandbox: CodexSandbox, approvalPolicy: String = "on-request") {
        self.prompt = prompt
        self.workingDirectory = workingDirectory
        self.model = model
        self.reasoning = reasoning
        self.sandbox = sandbox
        self.approvalPolicy = approvalPolicy
    }
}

public struct CodexTaskResult: Equatable, Sendable {
    public var threadID: String
    public var turnID: String?
    public init(threadID: String, turnID: String? = nil) {
        self.threadID = threadID
        self.turnID = turnID
    }
}

public struct CodexHandoffRecommendation: Equatable, Sendable {
    public var modelID: String
    public var tier: ModelTier
    public var effort: ReasoningEffort
    public var rationale: String

    public init(modelID: String, tier: ModelTier, effort: ReasoningEffort, rationale: String) {
        self.modelID = modelID
        self.tier = tier
        self.effort = effort
        self.rationale = rationale
    }
}

public enum CodexHandoffPlanner {
    public static func recommend(for draft: PromptDraft, models: [ModelDescriptor]) -> CodexHandoffRecommendation? {
        let available = models.filter(\.available)
        guard !available.isEmpty else { return nil }
        let words = draft.professionalPrompt.split(whereSeparator: \.isWhitespace).count
        var score = 0
        switch draft.taskType {
        case .coding, .troubleshooting: score += 2
        case .research, .planning, .analysis: score += 1
        default: break
        }
        if words >= 700 { score += 3 } else if words >= 350 { score += 2 } else if words >= 150 { score += 1 }
        if draft.effectivePromptDepth >= 8 { score += 2 } else if draft.effectivePromptDepth >= 6 { score += 1 }
        if !draft.attachments.isEmpty { score += 1 }
        if draft.riskFlags.count + draft.missingInformation.count >= 3 { score += 1 }

        let preferredTier: ModelTier = score >= 5 ? .deep : (score >= 2 ? .balanced : .fast)
        let model = available.first(where: { $0.tier == preferredTier })
            ?? available.first(where: { $0.tier == .balanced })
            ?? available[0]
        let preferredEffort: ReasoningEffort = score >= 7 ? .high : (score >= 4 ? .medium : (score >= 2 ? .low : .minimal))
        let effortOrder = [preferredEffort, .medium, .low, .high, .minimal, .none, .xhigh, .max, .ultra]
        let effort = effortOrder.first(where: { model.supportedEfforts.contains($0) })
            ?? model.supportedEfforts.first ?? .medium
        let rationale = "\(preferredTier.rawValue) model with \(effort.displayName) reasoning is recommended for a \(draft.taskType.rawValue.lowercased()) prompt at depth \(draft.effectivePromptDepth), containing \(words) words\(draft.attachments.isEmpty ? "" : " and referenced files")."
        return CodexHandoffRecommendation(modelID: model.id, tier: model.tier, effort: effort, rationale: rationale)
    }
}
