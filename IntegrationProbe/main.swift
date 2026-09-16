import Foundation
import PromptFoundryCore

@main
struct PromptFoundryCodexProbe {
    static func main() async {
        let service = CodexAppServerService()
        let status = await service.connectionStatus()
        switch status {
        case .connected(let version): print("CONNECTED \(version)")
        case .checking: print("CHECKING")
        case .unavailable(let message):
            fputs("UNAVAILABLE \(message)\n", stderr)
            exit(2)
        }

        do {
            let models = try await service.availableModels()
            print("MODELS \(models.count)")
            guard CommandLine.arguments.contains("--create") || CommandLine.arguments.contains("--run") || CommandLine.arguments.contains("--refine") else { return }
            let chosen = models.first(where: { $0.tier == .balanced && $0.available })
                ?? models.first(where: { $0.available }) ?? models.first
            guard let chosen else { throw PromptFoundryError.codexUnavailable("No models were advertised.") }
            if CommandLine.arguments.contains("--refine") {
                let refinement = PromptRefinementRequest(
                    idea: "Build a native macOS app that imports meeting notes, produces accurate summaries, lets the user review every claim, saves work locally, and exports Markdown. Make the implementation polished and production-ready.",
                    context: "Use SwiftUI and SwiftData, support light and dark mode, never invent facts from the notes, include useful error handling and accessibility, and provide tests plus visible verification evidence.",
                    target: .codex,
                    taskType: .coding,
                    model: chosen.id,
                    reasoning: chosen.supportedEfforts.contains(.medium) ? .medium : (chosen.supportedEfforts.first ?? .low),
                    promptDepth: 5
                )
                for try await event in service.refine(refinement) {
                    if case .completed(let result, let raw) = event {
                        let wordCount = result.professionalPrompt.split(whereSeparator: \.isWhitespace).count
                        guard wordCount >= 350, !result.suggestedTitle.isEmpty, !raw.isEmpty else {
                            throw PromptFoundryError.malformedResponse(raw: raw)
                        }
                        print("REFINED title=\(result.suggestedTitle) words=\(wordCount) characters=\(result.professionalPrompt.count)")
                    }
                }
                return
            }
            let request = CodexTaskRequest(
                prompt: "PromptFoundry integration verification. Do not modify files. Reply only with: PromptFoundry handoff verified.",
                workingDirectory: FileManager.default.currentDirectoryPath,
                model: chosen.id,
                reasoning: chosen.supportedEfforts.contains(.low) ? .low : (chosen.supportedEfforts.first ?? .medium),
                sandbox: .readOnly,
                approvalPolicy: "never"
            )
            if CommandLine.arguments.contains("--run") {
                let result = try await service.runTask(request)
                print("RUN thread=\(result.threadID) turn=\(result.turnID ?? "missing")")
            } else {
                let result = try await service.createTask(request)
                print("CREATED thread=\(result.threadID)")
            }
        } catch {
            fputs("FAILED \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
