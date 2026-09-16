import PromptFoundryCore
import SwiftUI

struct CodexReviewSheet: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 18) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        recommendationCard
                        executionSettings
                        directoryCard
                    }
                    .padding(2)
                }
                .frame(width: 330)

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Label("Complete Prompt", systemImage: "doc.text").font(.headline)
                        Spacer()
                        Text("\(promptWordCount) words")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text("This is the exact prompt Codex will receive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ReadOnlyPromptTextView(text: viewModel.draft.professionalPrompt)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.separator.opacity(0.45)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(20)
            Divider()
            footer
        }
        .frame(width: 930, height: 720)
        .background {
            LinearGradient(
                colors: [FoundryStyle.accent.opacity(0.06), .clear, FoundryStyle.warmAccent.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .background(.background)
        }
        .interactiveDismissDisabled(isSubmitting)
        .onAppear {
            if viewModel.codexRecommendation == nil { viewModel.recommendCodexConfiguration(apply: true) }
            viewModel.refreshDirectoryRecommendation()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(FoundryStyle.accent.gradient)
                Image(systemName: "terminal.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("Review Codex Handoff").font(.title2.weight(.semibold))
                Text("Run opens a new Codex-owned chat with this prompt and working directory.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            DepthBadge(depth: viewModel.promptDepth)
        }
        .padding(20)
    }

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Recommended", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(FoundryStyle.warmAccent)
                Spacer()
                Button("Use Again") { viewModel.recommendCodexConfiguration(apply: true) }
                    .controlSize(.small)
            }
            if let recommendation = viewModel.codexRecommendation {
                Text("\(modelName(recommendation.modelID)) · \(recommendation.effort.displayName)")
                    .font(.subheadline.weight(.semibold))
                Text(recommendation.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("The current saved configuration will be used.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .foundrySurface(emphasized: true)
    }

    private var executionSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Execution", systemImage: "cpu").font(.headline)
            Picker("Model", selection: modelBinding) {
                ForEach(viewModel.codexModels.filter(\.available)) { model in
                    Text("\(model.displayName) — \(model.id)").tag(model.id)
                }
            }
            .pickerStyle(.menu)
            Picker("Reasoning", selection: $viewModel.draft.codexEffort) {
                ForEach(ReasoningEffort.allCases) { effort in
                    Text(effort.displayName)
                        .tag(effort)
                        .disabled(!viewModel.supportedCodexEfforts.contains(effort))
                }
            }
            .pickerStyle(.menu)
            Picker("File access", selection: $viewModel.draft.codexSandbox) {
                ForEach(CodexSandbox.allCases) { sandbox in
                    Text(sandbox.displayName).tag(sandbox)
                }
            }
            .pickerStyle(.segmented)
            Text("Every reasoning option is shown; unsupported levels are unavailable for the selected live model.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("These settings apply to Create Task. A new desktop chat uses the execution settings selected in Codex.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .foundrySurface()
    }

    private var directoryCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Working Directory", systemImage: "folder.fill").font(.headline)
                Spacer()
                Button("Auto") { viewModel.refreshDirectoryRecommendation(resetToAutomatic: true) }
                    .controlSize(.small)
            }
            TextField("Codex working directory", text: $viewModel.codexWorkingDirectory)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Choose…") {
                    if let url = DesktopPanels.chooseDirectory() { viewModel.codexWorkingDirectory = url.path }
                }
                .controlSize(.small)
                Spacer()
                if viewModel.directoryRecommendation?.needsCreation == true {
                    Label("Created on launch", systemImage: "plus.circle")
                        .font(.caption).foregroundStyle(.green)
                }
            }
            if let recommendation = viewModel.directoryRecommendation {
                Text(recommendation.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .foundrySurface()
    }

    private var footer: some View {
        HStack {
            codexConnectionLabel
            Spacer()
            if isSubmitting { ProgressView().controlSize(.small) }
            Button("Cancel") { viewModel.showCodexReview = false }
                .keyboardShortcut(.cancelAction)
            Button("Create Task") { submit(run: false) }
                .disabled(isSubmitting)
            Button("Run in Codex") { submit(run: true) }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    @ViewBuilder
    private var codexConnectionLabel: some View {
        switch viewModel.codexStatus {
        case .checking:
            Label("Checking Codex…", systemImage: "ellipsis.circle").foregroundStyle(.secondary)
        case .connected(let version):
            Label(version, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .unavailable(let message):
            Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.orange).lineLimit(2)
        }
    }

    private var modelBinding: Binding<String> {
        Binding(get: { viewModel.draft.codexModel }, set: { viewModel.selectCodexModel($0) })
    }

    private var promptWordCount: Int {
        viewModel.draft.professionalPrompt.split(whereSeparator: \.isWhitespace).count
    }

    private func modelName(_ id: String) -> String {
        viewModel.codexModels.first(where: { $0.id == id })?.displayName ?? id
    }

    private func submit(run: Bool) {
        isSubmitting = true
        Task {
            await viewModel.createCodexTask(run: run)
            isSubmitting = false
        }
    }
}
