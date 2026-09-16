import AppKit
import PromptFoundryCore

@MainActor
enum CodexDesktopNavigator {
    /// Opens a new composer inside Codex Desktop. The desktop app creates and
    /// owns the resulting task, preventing the cross-app writer-lock warning.
    static func openNewChat(prompt: String, workingDirectory: String) -> Bool {
        guard let url = CodexDesktopRoute.newThreadURL(
            prompt: prompt,
            workingDirectory: workingDirectory
        ) else { return false }
        return NSWorkspace.shared.open(url)
    }

    /// Codex desktop discovers sessions created by another app-server process
    /// asynchronously. Opening the route before that discovery finishes is
    /// silently ignored, so allow its local task index to catch up first.
    static func openWhenIndexed(threadID: String) async -> Bool {
        guard let url = CodexDesktopRoute.threadURL(for: threadID) else { return false }
        try? await Task.sleep(for: .seconds(2.5))
        guard !Task.isCancelled else { return false }
        return NSWorkspace.shared.open(url)
    }
}
