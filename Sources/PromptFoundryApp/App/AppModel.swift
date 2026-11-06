import Foundation
import PromptFoundryCore
import SwiftData

@MainActor
final class AppModel: ObservableObject {
    let persistence: PersistenceController
    let library: PromptLibraryStore
    let keychain: KeychainStore
    let apiRefiner: OpenAIRefinementService
    let codex: CodexAppServerService
    let workspace: WorkspaceViewModel
    let persistenceStartupError: String?

    init() {
        let controller: PersistenceController
        let startupError: String?
        do {
            controller = try PersistenceController()
            startupError = nil
        } catch {
            controller = try! PersistenceController(inMemory: true)
            startupError = "Local history could not be opened. PromptFoundry is using temporary storage for this session: \(error.localizedDescription)"
        }
        let keychain = KeychainStore()
        let library = PromptLibraryStore(context: controller.container.mainContext)
        let apiRefiner = OpenAIRefinementService(credentials: keychain)
        let codex = CodexAppServerService()
        self.persistence = controller
        self.library = library
        self.keychain = keychain
        self.apiRefiner = apiRefiner
        self.codex = codex
        self.persistenceStartupError = startupError
        self.workspace = WorkspaceViewModel(library: library, codexRefiner: codex, apiRefiner: apiRefiner, credentials: keychain, codex: codex)
        if let startupError { workspace.presentError(startupError) }
        if startupError == nil, !UserDefaults.standard.bool(forKey: "legacyLibraryCopiedV2") {
            do {
                let count = try LegacyLibraryImporter.copyLibrary(into: library)
                UserDefaults.standard.set(true, forKey: "legacyLibraryCopiedV2")
                if count > 0 { workspace.showFeedback(.imported(count)) }
            } catch {
                workspace.presentError("Your original library could not be copied automatically. It remains in PromptFoundry; use Export Library there and Import Library in V2. \(error.localizedDescription)")
            }
        }
    }
}
