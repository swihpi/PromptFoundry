import AppKit
import Foundation
import PromptFoundryCore

@MainActor
enum DesktopPanels {
    static func chooseFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Reference Local Files"
        panel.prompt = "Reference"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Codex Working Directory"
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseCodexExecutable() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Locate the Codex CLI"
        panel.message = "Choose the executable named codex. PromptFoundry stores only its path and never reads or copies Codex credentials."
        panel.prompt = "Use Codex"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func export(data: Data, suggestedName: String, extension fileExtension: String) throws {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName + "." + fileExtension
        panel.allowedContentTypes = fileExtension == "json" ? [.json] : (fileExtension == "md" ? [.plainText] : [.plainText])
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url, options: .atomic) }
        catch { throw PromptFoundryError.exportFailed(error.localizedDescription) }
    }

    static func importJSON() throws -> Data? {
        let panel = NSOpenPanel()
        panel.title = "Import Prompt Library"
        panel.prompt = "Import"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do { return try Data(contentsOf: url, options: .mappedIfSafe) }
        catch { throw PromptFoundryError.corruptedArchive(error.localizedDescription) }
    }
}
