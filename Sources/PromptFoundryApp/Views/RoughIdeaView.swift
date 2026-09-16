import PromptFoundryCore
import SwiftUI

struct RoughIdeaView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @FocusState private var ideaFocused: Bool
    @State private var tagText = ""
    @AppStorage(SettingsKeys.refinementProvider) private var refinementProviderRaw = RefinementProvider.codex.rawValue

    var body: some View {
        VStack(spacing: 0) {
            paneHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    selectors
                    depthControl
                    ideaEditor
                    contextSection
                    attachmentsSection
                    tagsSection
                    refinerSection
                }
                .padding(18)
            }
        }
        .background {
            LinearGradient(colors: [FoundryStyle.accent.opacity(0.045), .clear, FoundryStyle.warmAccent.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .background(.background)
        }
        .onAppear { if viewModel.draft.originalIdea.isEmpty { ideaFocused = true } }
        .onChange(of: viewModel.selectedID) {
            if viewModel.selectedID == nil { DispatchQueue.main.async { ideaFocused = true } }
        }
    }

    private var paneHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Rough Idea", systemImage: "lightbulb")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.wordCount) words · \(viewModel.characterCount) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("Prompt title", text: $viewModel.draft.title)
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .accessibilityLabel("Prompt title")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    private var selectors: some View {
        HStack(spacing: 12) {
            LabeledContent("Target") {
                Picker("Target", selection: $viewModel.draft.target) {
                    ForEach(PromptTarget.allCases) { target in Label(target.rawValue, systemImage: target.systemImage).tag(target) }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            }
            LabeledContent("Task") {
                Picker("Task Type", selection: $viewModel.draft.taskType) {
                    ForEach(PromptTaskType.allCases) { type in Label(type.rawValue, systemImage: type.systemImage).tag(type) }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            }
        }
        .font(.callout)
    }

    private var depthControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prompt Depth").font(.subheadline.weight(.semibold))
                    Text("Control completeness, not just length.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                DepthBadge(depth: viewModel.promptDepth)
            }
            Slider(
                value: Binding(
                    get: { Double(viewModel.promptDepth) },
                    set: { viewModel.promptDepth = Int($0.rounded()) }
                ),
                in: 1...10,
                step: 1
            ) {
                Text("Prompt depth")
            } minimumValueLabel: {
                Text("1").font(.caption.monospacedDigit())
            } maximumValueLabel: {
                Text("10").font(.caption.monospacedDigit())
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Essential").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                if viewModel.canUsePrompt {
                    Button("Apply to Prompt", systemImage: "arrow.triangle.2.circlepath") {
                        viewModel.generate(mode: .resize)
                    }
                    .controlSize(.small)
                    .disabled(viewModel.generationState == .generating)
                }
                Spacer()
                Text("Exhaustive").font(.caption2).foregroundStyle(.tertiary)
            }
            Text(depthDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .foundrySurface()
    }

    private var ideaEditor: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("What do you want to accomplish?")
                .font(.subheadline.weight(.semibold))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.background.secondary)
                    .strokeBorder(ideaFocused ? Color.accentColor : Color.secondary.opacity(0.22), lineWidth: ideaFocused ? 1.5 : 1)
                if viewModel.draft.originalIdea.isEmpty {
                    Text("Write naturally. Include the outcome you want, anything that must be preserved, and any limits you already know.")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $viewModel.draft.originalIdea)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .focused($ideaFocused)
                    .accessibilityLabel("Rough idea")
            }
            .frame(minHeight: 330)
            HStack {
                Button("Paste", systemImage: "doc.on.clipboard") { viewModel.pasteIdea() }
                Button("Clear", systemImage: "xmark.circle") { viewModel.clearIdea() }
                    .disabled(viewModel.draft.originalIdea.isEmpty)
                Spacer()
                Button { viewModel.generate() } label: { Label("Generate Prompt", systemImage: "wand.and.stars") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!viewModel.canGenerate)
            }
        }
        .padding(14)
        .foundrySurface(emphasized: true)
    }

    private var contextSection: some View {
        DisclosureGroup {
            TextEditor(text: $viewModel.draft.additionalContext)
                .font(.callout)
                .frame(minHeight: 90)
                .padding(7)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.separator.opacity(0.5)))
                .accessibilityLabel("Additional context")
        } label: {
            Label("Additional Context", systemImage: "text.append")
                .font(.subheadline.weight(.medium))
        }
    }

    private var attachmentsSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(viewModel.draft.attachments) { reference in
                    HStack {
                        Image(systemName: "doc")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(reference.displayName).lineLimit(1)
                            Text(reference.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button { viewModel.removeAttachment(reference) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless)
                            .help("Remove file reference")
                    }
                }
                Button("Reference Files…", systemImage: "paperclip") {
                    viewModel.addAttachments(DesktopPanels.chooseFiles())
                }
            }
            .padding(.top, 6)
        } label: {
            Label("Files\(viewModel.draft.attachments.isEmpty ? "" : " (\(viewModel.draft.attachments.count))")", systemImage: "paperclip")
                .font(.subheadline.weight(.medium))
        }
    }

    private var tagsSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                FlowTags(tags: viewModel.draft.tags, onRemove: viewModel.removeTag)
                HStack {
                    TextField("Add a tag", text: $tagText)
                        .onSubmit { addTag() }
                    Button("Add") { addTag() }.disabled(tagText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.top, 6)
        } label: {
            Label("Tags", systemImage: "tag")
                .font(.subheadline.weight(.medium))
        }
    }

    private var refinerSection: some View {
        DisclosureGroup {
            ModelConfigurationView(
                title: "Refiner model",
                model: $viewModel.draft.refinerModel,
                tier: $viewModel.draft.refinerTier,
                effort: $viewModel.draft.refinerEffort,
                models: viewModel.refinerModels
            )
            Label(
                refinementProviderRaw == RefinementProvider.codex.rawValue
                    ? "Signed-in Codex account · no API key required"
                    : "OpenAI API key from Keychain",
                systemImage: refinementProviderRaw == RefinementProvider.codex.rawValue ? "checkmark.shield" : "key"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 7)
        } label: {
            Label("Refinement Model", systemImage: "cpu")
                .font(.subheadline.weight(.medium))
        }
    }

    private func addTag() {
        viewModel.addTag(tagText)
        tagText = ""
    }

    private var depthDescription: String {
        switch viewModel.promptDepth {
        case 1...2: return "A compact prompt containing only the execution essentials."
        case 3...4: return "Focused structure, requirements, output, and relevant checks."
        case 5...6: return "Comprehensive by default: scope, constraints, deliverables, risks, and definition of done where relevant."
        case 7...8: return "Detailed execution guidance, edge cases, failure handling, and stronger verification."
        default: return "An exhaustive, non-repetitive specification for complex or high-stakes work."
        }
    }
}

struct FlowTags: View {
    let tags: [String]
    let onRemove: (String) -> Void
    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag).lineLimit(1)
                    Button { onRemove(tag) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(tag) tag")
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
            }
        }
    }
}

struct ModelConfigurationView: View {
    let title: String
    @Binding var model: String
    @Binding var tier: ModelTier
    @Binding var effort: ReasoningEffort
    let models: [ModelDescriptor]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Quality", selection: tierBinding) {
                ForEach(ModelTier.allCases) { tier in Label(tier.rawValue, systemImage: tier.systemImage).tag(tier) }
            }
            .pickerStyle(.segmented)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    TextField("Model identifier", text: $model)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityHint("The underlying model name")
                }
                Picker("Reasoning", selection: $effort) {
                    ForEach(supportedEfforts) { effort in Text(effort.displayName).tag(effort) }
                }
                .frame(width: 130)
            }
            if let descriptor = models.first(where: { $0.id == model }) {
                Text(descriptor.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tierBinding: Binding<ModelTier> {
        Binding(get: { tier }, set: { newTier in
            tier = newTier
            if newTier != .custom, let candidate = models.first(where: { $0.tier == newTier }) {
                model = candidate.id
                if !candidate.supportedEfforts.contains(effort) { effort = candidate.supportedEfforts.first ?? .medium }
            }
        })
    }

    private var supportedEfforts: [ReasoningEffort] {
        models.first(where: { $0.id == model })?.supportedEfforts ?? ReasoningEffort.allCases
    }
}
