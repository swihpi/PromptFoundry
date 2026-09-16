import Foundation
import SwiftData

@Model
public final class PromptRecord {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var originalIdea: String
    public var professionalPrompt: String
    public var additionalContext: String
    public var targetRaw: String
    public var taskTypeRaw: String
    public var promptDepth: Int?
    public var refinerModel: String
    public var refinerTierRaw: String
    public var refinerEffortRaw: String
    public var codexModel: String
    public var codexTierRaw: String
    public var codexEffortRaw: String
    public var codexSandboxRaw: String
    public var additionsData: Data
    public var assumptionsData: Data
    public var missingInformationData: Data
    public var questionsData: Data
    public var riskFlagsData: Data
    public var tagsData: Data
    public var attachmentsData: Data
    public var isFavorite: Bool
    public var createdAt: Date
    public var modifiedAt: Date
    public var lastUsedAt: Date
    @Relationship(deleteRule: .cascade) public var versions: [PromptVersion]

    public init(id: UUID = UUID(), draft: PromptDraft, now: Date = Date()) {
        self.id = id
        title = draft.title
        originalIdea = draft.originalIdea
        professionalPrompt = draft.professionalPrompt
        additionalContext = draft.additionalContext
        targetRaw = draft.target.rawValue
        taskTypeRaw = draft.taskType.rawValue
        promptDepth = draft.promptDepth
        refinerModel = draft.refinerModel
        refinerTierRaw = draft.refinerTier.rawValue
        refinerEffortRaw = draft.refinerEffort.rawValue
        codexModel = draft.codexModel
        codexTierRaw = draft.codexTier.rawValue
        codexEffortRaw = draft.codexEffort.rawValue
        codexSandboxRaw = draft.codexSandbox.rawValue
        additionsData = CodableStore.encode(draft.additions)
        assumptionsData = CodableStore.encode(draft.assumptions)
        missingInformationData = CodableStore.encode(draft.missingInformation)
        questionsData = CodableStore.encode(draft.questions)
        riskFlagsData = CodableStore.encode(draft.riskFlags)
        tagsData = CodableStore.encode(draft.tags)
        attachmentsData = CodableStore.encode(draft.attachments)
        isFavorite = false
        createdAt = now
        modifiedAt = now
        lastUsedAt = now
        versions = []
    }

    public var target: PromptTarget { PromptTarget(rawValue: targetRaw) ?? .custom }
    public var taskType: PromptTaskType { PromptTaskType(rawValue: taskTypeRaw) ?? .general }
    public var additions: [String] { CodableStore.decode([String].self, from: additionsData) ?? [] }
    public var assumptions: [String] { CodableStore.decode([String].self, from: assumptionsData) ?? [] }
    public var missingInformation: [String] { CodableStore.decode([String].self, from: missingInformationData) ?? [] }
    public var questions: [String] { CodableStore.decode([String].self, from: questionsData) ?? [] }
    public var riskFlags: [String] { CodableStore.decode([String].self, from: riskFlagsData) ?? [] }
    public var tags: [String] { CodableStore.decode([String].self, from: tagsData) ?? [] }
    public var attachments: [PromptFileReference] { CodableStore.decode([PromptFileReference].self, from: attachmentsData) ?? [] }

    public func makeDraft() -> PromptDraft {
        var draft = PromptDraft()
        draft.title = title
        draft.originalIdea = originalIdea
        draft.professionalPrompt = professionalPrompt
        draft.additionalContext = additionalContext
        draft.target = target
        draft.taskType = taskType
        draft.promptDepth = promptDepth
        draft.refinerModel = refinerModel
        draft.refinerTier = ModelTier(rawValue: refinerTierRaw) ?? .custom
        draft.refinerEffort = ReasoningEffort(rawValue: refinerEffortRaw) ?? .medium
        draft.codexModel = codexModel
        draft.codexTier = ModelTier(rawValue: codexTierRaw) ?? .custom
        draft.codexEffort = ReasoningEffort(rawValue: codexEffortRaw) ?? .medium
        draft.codexSandbox = CodexSandbox(rawValue: codexSandboxRaw) ?? .workspaceWrite
        draft.additions = additions
        draft.assumptions = assumptions
        draft.missingInformation = missingInformation
        draft.questions = questions
        draft.riskFlags = riskFlags
        draft.tags = tags
        draft.attachments = attachments
        return draft
    }

    public func apply(_ draft: PromptDraft, now: Date = Date()) {
        title = draft.title
        originalIdea = draft.originalIdea
        professionalPrompt = draft.professionalPrompt
        additionalContext = draft.additionalContext
        targetRaw = draft.target.rawValue
        taskTypeRaw = draft.taskType.rawValue
        promptDepth = draft.promptDepth
        refinerModel = draft.refinerModel
        refinerTierRaw = draft.refinerTier.rawValue
        refinerEffortRaw = draft.refinerEffort.rawValue
        codexModel = draft.codexModel
        codexTierRaw = draft.codexTier.rawValue
        codexEffortRaw = draft.codexEffort.rawValue
        codexSandboxRaw = draft.codexSandbox.rawValue
        additionsData = CodableStore.encode(draft.additions)
        assumptionsData = CodableStore.encode(draft.assumptions)
        missingInformationData = CodableStore.encode(draft.missingInformation)
        questionsData = CodableStore.encode(draft.questions)
        riskFlagsData = CodableStore.encode(draft.riskFlags)
        tagsData = CodableStore.encode(draft.tags)
        attachmentsData = CodableStore.encode(draft.attachments)
        modifiedAt = now
    }
}

@Model
public final class PromptVersion {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var reason: String
    public var draftData: Data

    public init(id: UUID = UUID(), draft: PromptDraft, reason: String, createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
        self.reason = reason
        draftData = CodableStore.encode(draft)
    }

    public var draft: PromptDraft? { CodableStore.decode(PromptDraft.self, from: draftData) }
}

public enum CodableStore {
    public static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder.promptFoundry.encode(value)) ?? Data()
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder.promptFoundry.decode(type, from: data)
    }
}

public extension JSONEncoder {
    static var promptFoundry: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var promptFoundry: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
