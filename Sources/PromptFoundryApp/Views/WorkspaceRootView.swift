import AppKit
import PromptFoundryCore
import SwiftUI

struct WorkspaceRootView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @ObservedObject private var library: PromptLibraryStore
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showLibrary = false
    @SceneStorage("historySidebarVisible") private var historySidebarVisible = true
    @AppStorage(SettingsKeys.onboardingCompleted) private var onboardingCompleted = false

    init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
        _library = ObservedObject(wrappedValue: viewModel.library)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Text("PromptFoundry").font(.system(size: 24, weight: .bold, design: .rounded))
                Text("V2").font(.caption.weight(.bold)).foregroundStyle(FoundryStyle.accent)
                Divider().frame(height: 24)
                Text(viewModel.draft.title).font(.title3).lineLimit(1)
                Spacer()
                connectionIndicator
                SettingsLink { Image(systemName: "gearshape") }.help("Settings")
            }.padding(.horizontal, 28).padding(.vertical, 16)
            Divider()
            HStack(spacing: 16) {
                TextField("Search prompt library", text: $viewModel.historySearch)
                    .textFieldStyle(.roundedBorder).frame(width: 220)
                    .onChange(of: viewModel.historySearch) { showLibrary = true }
                ForEach(HistoryFilter.allCases) { filter in
                    Button(filter.rawValue) { viewModel.historyFilter = filter; viewModel.selectedTag = nil; showLibrary = true }
                        .foregroundStyle(viewModel.historyFilter == filter ? FoundryStyle.accent : .secondary)
                        .buttonStyle(.plain)
                }
                Button("Library", systemImage: "rectangle.grid.1x2") { showLibrary.toggle() }
                    .popover(isPresented: $showLibrary) {
                        HistorySidebarView(viewModel: viewModel).frame(width: 460, height: 550)
                    }
                Spacer()
                Button("New Prompt", systemImage: "square.and.pencil") { viewModel.newPrompt() }
                    .buttonStyle(.borderedProminent)
            }.padding(.horizontal, 28).padding(.vertical, 14)
            if !viewModel.filteredRecords.isEmpty {
                HStack(spacing: 20) {
                    ForEach(Array(viewModel.filteredRecords.prefix(3))) { record in
                        Button { viewModel.select(record) } label: {
                            Text(record.title).lineLimit(1).font(.callout.weight(.medium))
                                .foregroundStyle(viewModel.selectedID == record.id ? FoundryStyle.accent : .secondary)
                        }.buttonStyle(.plain)
                        Divider().frame(height: 16)
                    }
                    Spacer()
                    Menu {
                        Picker("Sort", selection: $viewModel.sort) {
                            ForEach(PromptSort.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }.fixedSize()
                }.padding(.horizontal, 28).padding(.bottom, 14)
            }
            Divider()
            HSplitView {
                RoughIdeaView(viewModel: viewModel).frame(minWidth: 470)
                ProfessionalPromptView(viewModel: viewModel).frame(minWidth: 530)
            }
        }
        .background(Color(red: 0.035, green: 0.043, blue: 0.052))
        .navigationTitle(viewModel.draft.title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { toggleSidebar() } label: { Label("Toggle History", systemImage: "sidebar.left") }
                    .help("Show or hide prompt history")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.generationState == .generating {
                    Button(role: .cancel) { viewModel.stopGeneration() } label: { Label("Stop", systemImage: "stop.fill") }
                        .help("Stop generation (Esc)")
                } else {
                    Button { viewModel.generate() } label: { Label("Generate", systemImage: "wand.and.stars") }
                        .disabled(!viewModel.canGenerate)
                        .help("Generate professional prompt (Command-Return)")
                }
            }
        }
        .overlay(alignment: .top) {
            if let feedback = viewModel.feedback {
                FeedbackBanner(message: feedback.message)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 12)
            }
        }
        .animation(.snappy(duration: 0.25), value: viewModel.feedback)
        .onAppear {
            columnVisibility = historySidebarVisible ? .all : .doubleColumn
        }
        .onChange(of: columnVisibility) { _, value in historySidebarVisible = value == .all }
        .sheet(isPresented: $viewModel.showCodexReview) { CodexReviewSheet(viewModel: viewModel) }
        .onChange(of: viewModel.selectedID) { showLibrary = false }
        .sheet(isPresented: $viewModel.showVersionBrowser) { VersionBrowserView(viewModel: viewModel) }
        .sheet(isPresented: Binding(get: { !onboardingCompleted }, set: { _ in })) {
            FirstLaunchSetupView(isCompleted: $onboardingCompleted)
        }
        .alert("PromptFoundry", isPresented: errorPresented) {
            if viewModel.rawFailedResponse != nil {
                Button("Copy Raw Response") { copyRawResponse() }
            }
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
        .task { await viewModel.refreshConnections() }
        .tint(FoundryStyle.accent)
    }

    @ViewBuilder private var connectionIndicator: some View {
        switch viewModel.codexStatus {
        case .connected: Label("Codex connected", systemImage: "circle.fill").foregroundStyle(.green).font(.caption)
        case .checking: ProgressView().controlSize(.small)
        case .unavailable: Button("Reconnect Codex") { Task { await viewModel.refreshConnections() } }.foregroundStyle(.orange)
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })
    }

    private func toggleSidebar() {
        showLibrary.toggle()
    }

    private func copyRawResponse() {
        guard let raw = viewModel.rawFailedResponse else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(raw, forType: .string)
    }

}

private struct FeedbackBanner: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
            .accessibilityAddTraits(.isStaticText)
    }
}
