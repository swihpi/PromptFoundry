import Foundation
import SwiftData

public final class PersistenceController {
    public let container: ModelContainer
    public let storeURL: URL?

    public init(inMemory: Bool = false) throws {
        let schema = Schema([PromptRecord.self, PromptVersion.self])
        let configuration = ModelConfiguration("PromptFoundry", schema: schema, isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: schema, configurations: [configuration])
        storeURL = inMemory ? nil : configuration.url
    }
}
