import SwiftUI

struct ClarificationAnswersView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    private var questions: [String] {
        var seen = Set<String>()
        return (viewModel.draft.questions + viewModel.draft.missingInformation).filter { seen.insert($0).inserted }
    }
    var body: some View {
        DisclosureGroup("Answer & Refine") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Optional answers become Additional Context and are saved with this prompt.").font(.caption).foregroundStyle(.secondary)
                ForEach(questions, id: \.self) { question in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(question).font(.callout)
                        TextField("Your answer", text: Binding(
                            get: { viewModel.clarificationAnswers[question] ?? "" },
                            set: { viewModel.clarificationAnswers[question] = $0 }
                        ), axis: .vertical).textFieldStyle(.roundedBorder)
                    }
                }
                Button("Apply Answers & Improve") { viewModel.applyClarificationAnswers() }
                    .disabled(viewModel.generationState == .generating || !viewModel.clarificationAnswers.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            }.padding(.vertical, 10)
        }
    }
}
