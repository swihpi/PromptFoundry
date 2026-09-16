import Foundation

public enum PromptContract {
    public static let jsonSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["professionalPrompt", "suggestedTitle", "taskType", "additions", "assumptions", "missingInformation", "questions", "riskFlags"],
        "properties": [
            "professionalPrompt": ["type": "string"],
            "suggestedTitle": ["type": "string"],
            "taskType": ["type": "string"],
            "additions": ["type": "array", "items": ["type": "string"]],
            "assumptions": ["type": "array", "items": ["type": "string"]],
            "missingInformation": ["type": "array", "items": ["type": "string"]],
            "questions": ["type": "array", "items": ["type": "string"]],
            "riskFlags": ["type": "array", "items": ["type": "string"]]
        ]
    ]

    public static func instructions(for request: PromptRefinementRequest) -> String {
        let taskGuidance: String
        switch request.taskType {
        case .coding:
            taskGuidance = "Consider the user-visible outcome, repository context, functional and non-functional requirements, compatibility, errors, tests, definition of done, and verification evidence. Add only items relevant to this request."
        case .research:
            taskGuidance = "Clarify the research question, currentness, source quality, comparison criteria, citations, uncertainty, desired depth, and output format where material."
        case .writing:
            taskGuidance = "Clarify audience, purpose, tone, length, format, facts to preserve, and claims that must not be invented."
        case .troubleshooting:
            taskGuidance = "Separate symptoms, environment, reproduction, available evidence, prior attempts, expected diagnosis, and whether a fix is authorized."
        default:
            taskGuidance = "Use the smallest amount of structure that makes this request complete and executable."
        }
        let modeGuidance: String
        switch request.mode {
        case .generate: modeGuidance = "Create a strong first professional prompt from the idea. It must already be complete at the requested depth; do not rely on a later Improve pass."
        case .regenerate: modeGuidance = "Create a fresh alternative without changing the underlying goal."
        case .improve: modeGuidance = "Improve the existing prompt's clarity, completeness, and executability."
        case .shorter: modeGuidance = "Make the existing prompt more concise without losing material requirements."
        case .detailed: modeGuidance = "Add useful implementation detail, success criteria, and boundaries without inventing facts."
        case .preserveWording: modeGuidance = "Preserve as much of the user's wording and tone as possible while fixing ambiguity and structure."
        case .resize: modeGuidance = "Rewrite the existing professional prompt to match the requested depth. Preserve all facts, intent, and material requirements while changing its breadth and detail."
        }
        let depthGuidance = PromptDepth.guidance(for: request.promptDepth)
        return """
        You are PromptFoundry, a careful prompt-development engine. Preserve the user's intent, tone, and meaningful personal wording. Correct grammar and ambiguity, but never invent facts, credentials, files, deadlines, authorization, or project details. Put uncertainties in assumptions or missingInformation instead of silently filling them in. Add requirements when they materially improve execution quality. Adapt to target \(request.target.rawValue) and task type \(request.taskType.rawValue). \(taskGuidance) \(modeGuidance)

        PROMPT DEPTH: \(request.promptDepth)/10 — \(PromptDepth.title(for: request.promptDepth)). \(depthGuidance)

        The professionalPrompt must be directly usable by another AI and proportionate to the requested depth. Prefer clear headings and executable instructions for substantive tasks. Keep every metadata list factual and concise.
        """
    }

    public static func inputText(for request: PromptRefinementRequest) -> String {
        var parts = ["ROUGH IDEA:\n\(request.idea)"]
        if !request.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append("ADDITIONAL CONTEXT:\n\(request.context)") }
        if let existing = request.existingPrompt, !existing.isEmpty { parts.append("EXISTING PROFESSIONAL PROMPT:\n\(existing)") }
        if !request.attachmentNames.isEmpty { parts.append("REFERENCED LOCAL FILES (names only; do not invent contents):\n" + request.attachmentNames.joined(separator: "\n")) }
        return parts.joined(separator: "\n\n")
    }
}
