import PromptFoundryCore
import SwiftUI

struct VersionBrowserView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @State private var selectedVersionID: UUID?
    @State private var compare = true

    var body: some View {
        NavigationSplitView {
            List(versions, selection: $selectedVersionID) { version in
                VStack(alignment: .leading, spacing: 3) {
                    Text(version.reason).font(.body.weight(.medium))
                    Text(version.createdAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
                .tag(version.id)
            }
            .navigationTitle("Versions")
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            if let version = selectedVersion {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(version.draft?.title ?? "Unreadable Version").font(.title2.weight(.semibold))
                            Text(version.createdAt.formatted()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore This Version") { viewModel.restore(version) }
                            .buttonStyle(.borderedProminent)
                            .disabled(version.draft == nil)
                    }
                    Divider()
                    Toggle("Compare with current prompt", isOn: $compare)
                    if compare {
                        Text("Red − removed from the selected version · Blue + added in the current prompt").font(.caption).foregroundStyle(.secondary)
                    }
                    ScrollView {
                        if compare, let prior = version.draft?.professionalPrompt {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(PromptComparison.lines(before: prior, after: viewModel.draft.professionalPrompt).enumerated()), id: \.offset) { _, line in
                                    Text(line.text).foregroundStyle(line.kind == .removed ? Color.red : line.kind == .added ? Color.cyan : Color.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                                }
                            }.font(.system(size: 14, design: .monospaced))
                        } else {
                            Text(version.draft?.professionalPrompt ?? "This saved version could not be decoded.")
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(20)
            } else {
                ContentUnavailableView("Choose a Version", systemImage: "clock.arrow.circlepath", description: Text("Select a previous result to preview or restore it."))
            }
        }
        .frame(width: 820, height: 560)
        .toolbar { Button("Done") { viewModel.showVersionBrowser = false } }
        .onAppear { selectedVersionID = versions.first?.id }
    }

    private var versions: [PromptVersion] {
        (viewModel.selectedRecord?.versions ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    private var selectedVersion: PromptVersion? {
        selectedVersionID.flatMap { id in versions.first(where: { $0.id == id }) }
    }
}
