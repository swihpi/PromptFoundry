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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    selectors.frame(height: 40)
                    ideaEditor
                    depthControl
                    Divider()
                    contextSection
                    attachmentsSection
                    tagsSection
                    refinerSection
                }
                .padding(18)
            }
        }
        .onAppear { if viewModel.draft.originalIdea.isEmpty { ideaFocused = true } }
        .disabled(viewModel.generationState == .generating)
        .onChange(of: viewModel.selectedID) {
            if viewModel.selectedID == nil { DispatchQueue.main.async { ideaFocused = true } }
        }
    }

    private var paneHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Rough Idea")
                    .font(.system(size: 36, weight: .bold))
                Spacer()
                Text("\(viewModel.wordCount) words · \(viewModel.characterCount) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("Prompt title", text: $viewModel.draft.title)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .accessibilityLabel("Prompt title")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(height: 116, alignment: .top)
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
                Button { viewModel.generate() } label: { Label("Generate Prompt", systemImage: "wand.and.stars") }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(!viewModel.canGenerate)
            }
        }
        .padding(14)
        .help(depthDescription)
    }

    private var ideaEditor: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("What do you want to accomplish?").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Paste") { viewModel.pasteIdea() }.buttonStyle(.plain).foregroundStyle(FoundryStyle.accent)
                Button("Clear") { viewModel.clearIdea() }.buttonStyle(.plain).foregroundStyle(FoundryStyle.accent)
                    .disabled(viewModel.draft.originalIdea.isEmpty)
            }
            .frame(height: 20)
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
                    .font(.system(size: 16))
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .focused($ideaFocused)
                    .accessibilityLabel("Rough idea")
            }
            .frame(height: 280)
            .disabled(viewModel.generationState == .generating)
        }
        .padding(14)
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
                        Toggle("Use contents", isOn: Binding(
                            get: { viewModel.contextFileIDs.contains(reference.id) },
                            set: { if $0 { viewModel.contextFileIDs.insert(reference.id) } else { viewModel.contextFileIDs.remove(reference.id) } }
                        )).toggleStyle(.checkbox).help("Include UTF-8 text contents in the next AI request; up to 64 KB per file.")
                        Button { viewModel.removeAttachment(reference) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless)
                            .help("Remove file reference")
                    }
                }
                Button("Reference Files…", systemImage: "paperclip") {
                    viewModel.addAttachments(DesktopPanels.chooseFiles())
                }
                Text("References send filenames only. Select Use contents to send supported text to your refinement provider. Selection resets when you switch prompts.")
                    .font(.caption).foregroundStyle(.secondary)
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
