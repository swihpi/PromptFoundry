import AppKit
import PromptFoundryCore
import SwiftUI

struct WorkspaceRootView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @ObservedObject private var library: PromptLibraryStore
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @SceneStorage("historySidebarVisible") private var historySidebarVisible = true
    @AppStorage(SettingsKeys.onboardingCompleted) private var onboardingCompleted = false

    init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
        _library = ObservedObject(wrappedValue: viewModel.library)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            HistorySidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 340)
        } content: {
            RoughIdeaView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 420, ideal: 560, max: 620)
        } detail: {
            ProfessionalPromptView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 420, ideal: 560, max: 620)
        }
        .navigationTitle(viewModel.draft.title)
        .searchable(text: $viewModel.historySearch, placement: .sidebar, prompt: "Search prompt library")
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

    private var errorPresented: Binding<Bool> {
        Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })
    }

    private func toggleSidebar() {
        columnVisibility = columnVisibility == .all ? .doubleColumn : .all
        historySidebarVisible = columnVisibility == .all
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
