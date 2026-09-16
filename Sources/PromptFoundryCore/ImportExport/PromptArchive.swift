import Foundation

public struct PromptArchiveRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var draft: PromptDraft
    public var isFavorite: Bool
    public var createdAt: Date
    public var modifiedAt: Date
    public var lastUsedAt: Date
    public var versions: [PromptArchiveVersion]
}

public struct PromptArchiveVersion: Codable, Equatable, Sendable {
    public var id: UUID
    public var draft: PromptDraft
    public var reason: String
    public var createdAt: Date
}

public struct PromptLibraryArchive: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var schemaVersion: Int
    public var exportedAt: Date
    public var records: [PromptArchiveRecord]

    public init(schemaVersion: Int = currentVersion, exportedAt: Date = Date(), records: [PromptArchiveRecord]) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.records = records
    }
}

public enum PromptArchiveService {
    public static let maximumArchiveBytes = 25 * 1_024 * 1_024
    public static let maximumRecords = 50_000

    public static func export(records: [PromptRecord], exportedAt: Date = Date()) throws -> Data {
        let archiveRecords = records.map { record in
            var exportDraft = record.makeDraft()
            exportDraft.attachments = exportDraft.attachments.map {
                PromptFileReference(id: $0.id, displayName: $0.displayName, path: $0.path, bookmark: nil)
            }
            return PromptArchiveRecord(
                id: record.id,
                draft: exportDraft,
                isFavorite: record.isFavorite,
                createdAt: record.createdAt,
                modifiedAt: record.modifiedAt,
                lastUsedAt: record.lastUsedAt,
                versions: record.versions.compactMap { version in
                    guard var draft = version.draft else { return nil }
                    draft.attachments = draft.attachments.map {
                        PromptFileReference(id: $0.id, displayName: $0.displayName, path: $0.path, bookmark: nil)
                    }
                    return PromptArchiveVersion(id: version.id, draft: draft, reason: version.reason, createdAt: version.createdAt)
                }
            )
        }
        return try JSONEncoder.promptFoundry.encode(PromptLibraryArchive(exportedAt: exportedAt, records: archiveRecords))
    }

    public static func decode(_ data: Data) throws -> PromptLibraryArchive {
        guard data.count <= maximumArchiveBytes else { throw PromptFoundryError.corruptedArchive("The file is larger than 25 MB.") }
        let archive: PromptLibraryArchive
        do { archive = try JSONDecoder.promptFoundry.decode(PromptLibraryArchive.self, from: data) }
        catch { throw PromptFoundryError.corruptedArchive(error.localizedDescription) }
        guard archive.schemaVersion == PromptLibraryArchive.currentVersion else { throw PromptFoundryError.incompatibleArchive }
        guard archive.records.count <= maximumRecords else { throw PromptFoundryError.corruptedArchive("The file contains too many prompts.") }
        guard archive.records.allSatisfy({ !$0.draft.title.isEmpty && $0.draft.title.count <= 10_000 }) else {
            throw PromptFoundryError.corruptedArchive("One or more records contain invalid titles.")
        }
        return archive
    }

    @MainActor
    public static func merge(_ archive: PromptLibraryArchive, into store: PromptLibraryStore) throws {
        let existingIDs = Set(store.records.map(\.id))
        for item in archive.records {
            let id = existingIDs.contains(item.id) ? UUID() : item.id
            let record = PromptRecord(id: id, draft: item.draft, now: item.createdAt)
            record.isFavorite = item.isFavorite
            record.modifiedAt = item.modifiedAt
            record.lastUsedAt = item.lastUsedAt
            record.versions = item.versions.map { PromptVersion(id: $0.id, draft: $0.draft, reason: $0.reason, createdAt: $0.createdAt) }
            store.context.insert(record)
        }
        do { try store.context.save(); store.reload() }
        catch { throw PromptFoundryError.persistence(error.localizedDescription) }
    }

    public static func markdown(for draft: PromptDraft) -> String {
        var output = "# \(draft.title)\n\n## Professional Prompt\n\n\(draft.professionalPrompt)\n"
        if !draft.originalIdea.isEmpty { output += "\n## Original Idea\n\n\(draft.originalIdea)\n" }
        appendSection("Additions", values: draft.additions, to: &output)
        appendSection("Assumptions", values: draft.assumptions, to: &output)
        appendSection("Missing Information", values: draft.missingInformation, to: &output)
        appendSection("Questions", values: draft.questions, to: &output)
        appendSection("Risks and Ambiguities", values: draft.riskFlags, to: &output)
        return output
    }

    private static func appendSection(_ title: String, values: [String], to output: inout String) {
        guard !values.isEmpty else { return }
        output += "\n## \(title)\n\n" + values.map { "- \($0)" }.joined(separator: "\n") + "\n"
    }
}
