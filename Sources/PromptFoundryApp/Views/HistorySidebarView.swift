import PromptFoundryCore
import SwiftUI

struct HistorySidebarView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @ObservedObject private var library: PromptLibraryStore
    @State private var renameRecord: PromptRecord?
    @State private var renameText = ""
    @State private var deleteRecord: PromptRecord?

    init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
        _library = ObservedObject(wrappedValue: viewModel.library)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search prompt library", text: $viewModel.historySearch)
                .textFieldStyle(.roundedBorder).padding(12)
            Button { viewModel.newPrompt() } label: {
                Label("New Prompt", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(12)

            List(selection: selection) {
                Section("Library") {
                    ForEach(HistoryFilter.allCases) { filter in
                        Button { viewModel.historyFilter = filter; viewModel.selectedTag = nil } label: {
                            Label(filter.rawValue, systemImage: filter.systemImage)
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !library.allTags.isEmpty {
                    Section("Tags") {
                        ForEach(library.allTags, id: \.self) { tag in
                            Button { viewModel.selectedTag = tag } label: {
                                Label(tag, systemImage: "tag")
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    if viewModel.filteredRecords.isEmpty {
                        ContentUnavailableView(
                            viewModel.historySearch.isEmpty ? "No Prompts Yet" : "No Matches",
                            systemImage: viewModel.historySearch.isEmpty ? "doc.text" : "magnifyingglass",
                            description: Text(viewModel.historySearch.isEmpty ? "Create a prompt and successful generations will appear here." : "Try another search or library filter.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(viewModel.filteredRecords) { record in
                            HistoryRow(record: record)
                                .tag(record.id)
                                .contextMenu { contextMenu(for: record) }
                        }
                    }
                } header: {
                    HStack {
                        Text(viewModel.selectedTag ?? viewModel.historyFilter.rawValue)
                        Spacer()
                        Menu {
                            Picker("Sort", selection: $viewModel.sort) {
                                ForEach(PromptSort.allCases) { sort in Text(sort.rawValue).tag(sort) }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .menuStyle(.borderlessButton)
                        .help("Sort prompt history")
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .alert("Rename Prompt", isPresented: Binding(get: { renameRecord != nil }, set: { if !$0 { renameRecord = nil } })) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renameRecord = nil }
            Button("Rename") {
                if let record = renameRecord { viewModel.rename(record, title: renameText) }
                renameRecord = nil
            }
        }
        .alert("Delete Prompt?", isPresented: Binding(get: { deleteRecord != nil }, set: { if !$0 { deleteRecord = nil } })) {
            Button("Cancel", role: .cancel) { deleteRecord = nil }
            Button("Delete", role: .destructive) {
                if let record = deleteRecord { viewModel.delete(record) }
                deleteRecord = nil
            }
        } message: { Text("This removes the prompt and its saved versions from local history.") }
    }

    private var selection: Binding<UUID?> {
        Binding(get: { viewModel.selectedID }, set: { id in
            guard let id, let record = library.records.first(where: { $0.id == id }) else { return }
            viewModel.select(record)
        })
    }

    @ViewBuilder
    private func contextMenu(for record: PromptRecord) -> some View {
        Button("Rename") { renameText = record.title; renameRecord = record }
        Button("Duplicate") { viewModel.duplicate(record) }
        Button(record.isFavorite ? "Remove from Favorites" : "Add to Favorites") { viewModel.toggleFavorite(record) }
        Button("Export as Markdown") { export(record, markdown: true) }
        Divider()
        Button("Delete", role: .destructive) { deleteRecord = record }
    }

    private func export(_ record: PromptRecord, markdown: Bool) {
        let draft = record.makeDraft()
        let text = markdown ? PromptArchiveService.markdown(for: draft) : draft.professionalPrompt
        do {
            try DesktopPanels.export(data: Data(text.utf8), suggestedName: safeFilename(record.title), extension: markdown ? "md" : "txt")
            viewModel.showFeedback(.exported)
        } catch { viewModel.presentError(error.localizedDescription) }
    }

    private func safeFilename(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\")
        return value.components(separatedBy: forbidden).joined(separator: "-").prefix(80).description
    }
}

private struct HistoryRow: View {
    let record: PromptRecord
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: record.isFavorite ? "star.fill" : record.taskType.systemImage)
                .foregroundStyle(record.isFavorite ? Color.accentColor : .secondary)
                .frame(width: 17)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title).font(.body.weight(.medium)).lineLimit(1)
                Text(preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 5) {
                    Text(record.taskType.rawValue)
                    Text("•")
                    Text(record.modifiedAt, format: .relative(presentation: .named))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.title), \(record.taskType.rawValue), modified \(record.modifiedAt.formatted())")
    }

    private var preview: String {
        let source = record.originalIdea.isEmpty ? record.professionalPrompt : record.originalIdea
        return source.replacingOccurrences(of: "\n", with: " ")
    }
}
