import Foundation

/// Builds links that open an existing task in the Codex desktop app.
public enum CodexDesktopRoute {
    public static func threadURL(for threadID: String) -> URL? {
        let id = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty,
              id.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
              })
        else { return nil }

        return URL(string: "codex://threads/\(id)")
    }

    /// Opens Codex Desktop's own new-chat composer. Codex then remains the sole
    /// owner of the task instead of competing with PromptFoundry's app-server.
    public static func newThreadURL(prompt: String, workingDirectory: String) -> URL? {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDirectory = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, trimmedDirectory.hasPrefix("/") else { return nil }

        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/new"
        components.queryItems = [
            URLQueryItem(name: "prompt", value: prompt),
            URLQueryItem(name: "path", value: trimmedDirectory)
        ]
        return components.url
    }
}
