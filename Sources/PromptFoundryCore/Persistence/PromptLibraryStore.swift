import Combine
import Foundation
import SwiftData

@MainActor
public final class PromptLibraryStore: ObservableObject {
    @Published public private(set) var records: [PromptRecord] = []
    @Published public private(set) var lastError: PromptFoundryError?

    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
        reload()
    }

    public func reload() {
        do {
            let descriptor = FetchDescriptor<PromptRecord>(sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)])
            records = try context.fetch(descriptor)
            lastError = nil
        } catch {
            lastError = .persistence(error.localizedDescription)
        }
    }

    public func visibleRecords(search: String, filter: HistoryFilter, tag: String? = nil, sort: PromptSort = .modified, now: Date = Date()) -> [PromptRecord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var output = records.filter { record in
            let filterMatches: Bool
            switch filter {
            case .all: filterMatches = true
            case .favorites: filterMatches = record.isFavorite
            case .recent: filterMatches = now.timeIntervalSince(record.lastUsedAt) <= 60 * 60 * 24 * 30
            }
            let tagMatches = tag.map { record.tags.contains($0) } ?? true
            let searchMatches = query.isEmpty || [record.title, record.originalIdea, record.professionalPrompt]
                .joined(separator: "\n").lowercased().contains(query) || record.tags.contains { $0.lowercased().contains(query) }
            return filterMatches && tagMatches && searchMatches
        }
        switch sort {
        case .modified: output.sort { $0.modifiedAt > $1.modifiedAt }
        case .created: output.sort { $0.createdAt > $1.createdAt }
        case .title: output.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .model: output.sort { $0.refinerModel.localizedStandardCompare($1.refinerModel) == .orderedAscending }
        case .taskType: output.sort { $0.taskTypeRaw.localizedStandardCompare($1.taskTypeRaw) == .orderedAscending }
        }
        return output
    }

    public var allTags: [String] {
        Array(Set(records.flatMap(\.tags))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    @discardableResult
    public func save(draft: PromptDraft, existingID: UUID?, preserveVersion: Bool = false, versionReason: String = "Previous result", now: Date = Date()) throws -> PromptRecord {
        let record: PromptRecord
        if let existingID, let existing = records.first(where: { $0.id == existingID }) {
            if preserveVersion, !existing.professionalPrompt.isEmpty, existing.professionalPrompt != draft.professionalPrompt {
                existing.versions.append(PromptVersion(draft: existing.makeDraft(), reason: versionReason, createdAt: now))
            }
            existing.apply(draft, now: now)
            record = existing
        } else {
            record = PromptRecord(draft: draft, now: now)
            context.insert(record)
        }
        try persist()
        reload()
        return record
    }

    public func markUsed(_ record: PromptRecord, now: Date = Date()) throws {
        record.lastUsedAt = now
        try persist()
        reload()
    }

    public func rename(_ record: PromptRecord, to title: String) throws {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        record.title = cleaned
        record.modifiedAt = Date()
        try persist()
        reload()
    }

    @discardableResult
    public func duplicate(_ record: PromptRecord, now: Date = Date()) throws -> PromptRecord {
        var draft = record.makeDraft()
        draft.title = record.title + " Copy"
        let copy = PromptRecord(draft: draft, now: now)
        copy.isFavorite = false
        copy.versions = record.versions.compactMap { version in
            version.draft.map { PromptVersion(draft: $0, reason: version.reason, createdAt: version.createdAt) }
        }
        context.insert(copy)
        try persist()
        reload()
        return copy
    }

    public func toggleFavorite(_ record: PromptRecord) throws {
        record.isFavorite.toggle()
        record.modifiedAt = Date()
        try persist()
        reload()
    }

    public func delete(_ record: PromptRecord) throws {
        context.delete(record)
        try persist()
        reload()
    }

    public func deleteAll() throws {
        try context.delete(model: PromptRecord.self)
        try persist()
        reload()
    }

    public func restore(version: PromptVersion, into record: PromptRecord) throws -> PromptDraft {
        guard let draft = version.draft else { throw PromptFoundryError.corruptedArchive("The selected version is unreadable.") }
        record.versions.append(PromptVersion(draft: record.makeDraft(), reason: "Before version restore"))
        record.apply(draft)
        try persist()
        reload()
        return draft
    }

    private func persist() throws {
        do {
            try context.save()
            lastError = nil
        } catch {
            let mapped = PromptFoundryError.persistence(error.localizedDescription)
            lastError = mapped
            throw mapped
        }
    }
}
