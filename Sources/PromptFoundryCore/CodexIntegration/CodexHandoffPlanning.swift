import Foundation

public struct CodexProjectDirectoryRecommendation: Equatable, Sendable {
    public var path: String
    public var rationale: String
    public var needsCreation: Bool

    public init(path: String, rationale: String, needsCreation: Bool) {
        self.path = path
        self.rationale = rationale
        self.needsCreation = needsCreation
    }
}

public enum CodexProjectDirectoryResolver {
    public static func recommend(
        title: String,
        promptID: UUID,
        attachments: [PromptFileReference],
        configuredRoot: String?,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> CodexProjectDirectoryRecommendation {
        if let commonParent = commonExistingParent(of: attachments, fileManager: fileManager) {
            return CodexProjectDirectoryRecommendation(
                path: commonParent.path,
                rationale: "Uses the folder containing the referenced files.",
                needsCreation: false
            )
        }

        let defaultRoot = homeDirectory.appendingPathComponent("Documents/PromptFoundry Projects", isDirectory: true)
        let requestedRoot = configuredRoot
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        let root = requestedRoot.map { isInsideCodexState($0, homeDirectory: homeDirectory) ? defaultRoot : $0 } ?? defaultRoot
        let suffix = promptID.uuidString.prefix(8).lowercased()
        let project = root.appendingPathComponent("\(slug(title))-\(suffix)", isDirectory: true)
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: project.path, isDirectory: &isDirectory) && isDirectory.boolValue
        let source = requestedRoot == nil || root == defaultRoot ? "PromptFoundry’s managed projects folder" : "your configured projects root"
        return CodexProjectDirectoryRecommendation(
            path: project.path,
            rationale: "Uses \(source). The project folder \(exists ? "already exists" : "will be created automatically").",
            needsCreation: !exists
        )
    }

    public static func prepare(_ path: String, fileManager: FileManager = .default) throws {
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw PromptFoundryError.projectDirectoryCreationFailed("A file already exists at \(url.path).") }
            return
        }
        do { try fileManager.createDirectory(at: url, withIntermediateDirectories: true) }
        catch { throw PromptFoundryError.projectDirectoryCreationFailed(error.localizedDescription) }
    }

    private static func commonExistingParent(of attachments: [PromptFileReference], fileManager: FileManager) -> URL? {
        let parents = attachments.map { URL(fileURLWithPath: $0.path).deletingLastPathComponent().standardizedFileURL }
        guard let first = parents.first, parents.allSatisfy({ $0 == first }) else { return nil }
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: first.path, isDirectory: &isDirectory) && isDirectory.boolValue ? first : nil
    }

    private static func isInsideCodexState(_ url: URL, homeDirectory: URL) -> Bool {
        let state = homeDirectory.appendingPathComponent(".codex", isDirectory: true).standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == state || path.hasPrefix(state + "/")
    }

    private static func slug(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let words = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let joined = words.joined(separator: "-").lowercased()
        return String((joined.isEmpty ? "prompt-project" : joined).prefix(52))
    }
}
