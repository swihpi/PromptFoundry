import PromptFoundryCore
import SwiftUI

struct ProfessionalPromptView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    promptEditor
                    primaryActions
                    refinementActions
                    metadataSections
                    codexConfiguration
                }
                .padding(18)
            }
        }
        .background {
            LinearGradient(colors: [FoundryStyle.warmAccent.opacity(0.025), .clear, FoundryStyle.accent.opacity(0.045)], startPoint: .topTrailing, endPoint: .bottomLeading)
                .background(.background)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Professional Prompt", systemImage: "checkmark.seal")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            Spacer()
            if viewModel.generationState == .generating {
                ProgressView().controlSize(.small).accessibilityLabel("Generating professional prompt")
            }
            DepthBadge(depth: viewModel.promptDepth)
            Button { viewModel.showVersionBrowser = true } label: { Label("Versions", systemImage: "clock.arrow.circlepath") }
                .disabled(viewModel.selectedRecord?.versions.isEmpty != false)
                .help("Browse previous prompt versions")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    private var promptEditor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background.secondary)
                .strokeBorder(promptFocused ? Color.accentColor : Color.secondary.opacity(0.22), lineWidth: promptFocused ? 1.5 : 1)
            if viewModel.draft.professionalPrompt.isEmpty && viewModel.generationState != .generating {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "wand.and.rays").font(.title2).foregroundStyle(.tertiary)
                    Text("Your professional prompt will appear here.").font(.headline).foregroundStyle(.secondary)
                    Text("It remains fully editable after generation.").font(.callout).foregroundStyle(.tertiary)
                }
                .padding(18)
                .allowsHitTesting(false)
            }
            TextEditor(text: $viewModel.draft.professionalPrompt)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(8)
                .focused($promptFocused)
                .accessibilityLabel("Professional prompt editor")
        }
        .frame(minHeight: 330)
        .shadow(color: .black.opacity(0.045), radius: 10, y: 4)
    }

    private var primaryActions: some View {
        HStack(spacing: 9) {
            Button { viewModel.copyPrompt() } label: { Label("Copy", systemImage: "doc.on.doc") }
                .disabled(!viewModel.canUsePrompt)
            Button { viewModel.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                .disabled(!viewModel.canUsePrompt)
            Menu {
                Button("Markdown") { export(markdown: true) }
                Button("Plain Text") { export(markdown: false) }
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
            .disabled(!viewModel.canUsePrompt)
            Spacer()
            Button { viewModel.prepareCodexReview() } label: { Label("Create Codex Task", systemImage: "plus.square.on.square") }
                .disabled(!viewModel.canUsePrompt)
            Button { viewModel.prepareCodexReview() } label: { Label("Run in Codex", systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canUsePrompt)
        }
        .controlSize(.regular)
        .padding(12)
        .foundrySurface()
    }

    private var refinementActions: some View {
        GroupBox("Shape the Prompt") {
            HStack(spacing: 8) {
                refinementButton("Regenerate", icon: "arrow.clockwise", mode: .regenerate)
                refinementButton("Improve", icon: "sparkles", mode: .improve)
                refinementButton("Shorter", icon: "text.badge.minus", mode: .shorter)
                refinementButton("More Detail", icon: "text.badge.plus", mode: .detailed)
                refinementButton("Keep My Voice", icon: "quote.bubble", mode: .preserveWording)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var metadataSections: some View {
        VStack(spacing: 8) {
            MetadataDisclosure(title: "What Was Added", icon: "plus.circle", values: viewModel.draft.additions)
            MetadataDisclosure(title: "Assumptions Made", icon: "questionmark.diamond", values: viewModel.draft.assumptions)
            MetadataDisclosure(title: "Missing Information", icon: "ellipsis.bubble", values: viewModel.draft.missingInformation)
            MetadataDisclosure(title: "Questions Worth Answering", icon: "questionmark.bubble", values: viewModel.draft.questions)
            MetadataDisclosure(title: "Potential Risks or Ambiguities", icon: "exclamationmark.triangle", values: viewModel.draft.riskFlags, isRisk: true)
        }
    }

    private var codexConfiguration: some View {
        DisclosureGroup {
            VStack(spacing: 12) {
                ModelConfigurationView(
                    title: "Codex execution model",
                    model: $viewModel.draft.codexModel,
                    tier: $viewModel.draft.codexTier,
                    effort: $viewModel.draft.codexEffort,
                    models: viewModel.codexModels
                )
                Picker("File access", selection: $viewModel.draft.codexSandbox) {
                    ForEach(CodexSandbox.allCases) { sandbox in Text(sandbox.displayName).tag(sandbox) }
                }
                .pickerStyle(.segmented)
            }
            .padding(.top, 8)
        } label: {
            Label("Codex Execution", systemImage: "terminal")
                .font(.subheadline.weight(.medium))
        }
    }

    private func refinementButton(_ title: String, icon: String, mode: RefinementMode) -> some View {
        Button { viewModel.generate(mode: mode) } label: { Label(title, systemImage: icon) }
            .disabled(!viewModel.canUsePrompt || viewModel.generationState == .generating)
            .controlSize(.small)
    }

    private var statusText: String {
        switch viewModel.generationState {
        case .idle: return viewModel.canUsePrompt ? "Editable draft" : "Ready when you are"
        case .generating: return "Generating securely…"
        case .completed: return "Generated and saved locally"
        case .failed: return "Generation needs attention"
        }
    }

    private var statusColor: Color {
        switch viewModel.generationState {
        case .failed: return .orange
        case .completed: return .green
        default: return .secondary
        }
    }

    private func export(markdown: Bool) {
        let text = markdown ? PromptArchiveService.markdown(for: viewModel.draft) : viewModel.draft.professionalPrompt
        do {
            try DesktopPanels.export(data: Data(text.utf8), suggestedName: viewModel.draft.title, extension: markdown ? "md" : "txt")
            viewModel.showFeedback(.exported)
        } catch { viewModel.presentError(error.localizedDescription) }
    }
}

private struct MetadataDisclosure: View {
    let title: String
    let icon: String
    let values: [String]
    var isRisk = false

    var body: some View {
        DisclosureGroup {
            if values.isEmpty {
                Text("Nothing to report.").font(.callout).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(values, id: \.self) { value in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: isRisk ? "exclamationmark.circle" : "circle.fill")
                                .font(isRisk ? .caption : .system(size: 5))
                                .foregroundStyle(isRisk ? Color.orange : Color.secondary)
                                .frame(width: 13, height: 18)
                            Text(value).font(.callout).textSelection(.enabled)
                        }
                    }
                }
                .padding(.vertical, 7)
            }
        } label: {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                if !values.isEmpty {
                    Text("\(values.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.weight(.medium))
        }
        .padding(11)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
