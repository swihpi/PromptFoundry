import Foundation
import SwiftData

@MainActor
public enum LegacyLibraryImporter {
    /// Opens the original store without saving; V2 writes only to its own store.
    public static func copyLibrary(into destination: PromptLibraryStore) throws -> Int {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PromptFoundry.store")
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let schema = Schema([PromptRecord.self, PromptVersion.self])
        let configuration = ModelConfiguration("PromptFoundry", schema: schema, url: url, allowsSave: false)
        let legacy = try ModelContainer(for: schema, configurations: [configuration])
        let records = try legacy.mainContext.fetch(FetchDescriptor<PromptRecord>())
        let archive = try PromptArchiveService.decode(PromptArchiveService.export(records: records))
        try PromptArchiveService.merge(archive, into: destination)
        return records.count
    }
}
