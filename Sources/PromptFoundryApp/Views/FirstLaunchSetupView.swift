import AppKit
import PromptFoundryCore
import SwiftUI

struct FirstLaunchSetupView: View {
    @EnvironmentObject private var appModel: AppModel
    @Binding var isCompleted: Bool
    @AppStorage(SettingsKeys.codexExecutablePath) private var codexExecutablePath = ""
    @AppStorage(SettingsKeys.defaultProjectDirectory) private var projectDirectory = ""
    @State private var step = 0
    @State private var connectionStatus = CodexConnectionStatus.checking
    @State private var loginProcess: Process?
    @State private var setupError: String?

    private let steps = ["Welcome", "Find Codex", "Sign In", "Projects", "Ready"]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(30)
            Divider()
            footer
        }
        .frame(width: 720, height: 540)
        .interactiveDismissDisabled()
        .task { detectCodex() }
        .alert("Setup could not continue", isPresented: Binding(get: { setupError != nil }, set: { if !$0 { setupError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(setupError ?? "Unknown error") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "hammer.circle.fill")
                    .font(.system(size: 34)).foregroundStyle(FoundryStyle.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set Up PromptFoundry").font(.title2.bold())
                    Text("Connect this Mac to the user’s own Codex installation.").foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule().fill(index <= step ? FoundryStyle.accent : Color.secondary.opacity(0.2)).frame(height: 5)
                }
            }
            Text("Step \(step + 1) of \(steps.count) · \(steps[step])")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(24)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0: welcome
        case 1: findCodex
        case 2: signIn
        case 3: projects
        default: ready
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your account stays yours").font(.title.bold())
            Text("PromptFoundry contains no developer API key, Codex token, account, or computer-specific folder. It uses the Codex CLI installed on this Mac and the authentication managed by Codex.")
                .font(.title3).fixedSize(horizontal: false, vertical: true)
            SetupPoint(icon: "lock.shield", title: "Credentials remain with Codex", detail: "PromptFoundry checks connection status but never reads or copies Codex authentication files.")
            SetupPoint(icon: "internaldrive", title: "Prompt history is local", detail: "Prompts and versions are stored on this Mac unless the user explicitly exports them.")
            SetupPoint(icon: "checkmark.rectangle", title: "Execution is reviewed", detail: "The complete prompt, working directory, model, reasoning, and file permissions are shown before handoff.")
        }
    }

    private var findCodex: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Find the Codex CLI").font(.title.bold())
            Text("PromptFoundry checks the standard ChatGPT/Codex application locations and common command-line installation paths.")
                .foregroundStyle(.secondary)
            GroupBox {
                LabeledContent("Detected executable") {
                    Text(codexExecutablePath.isEmpty ? "Not found" : codexExecutablePath)
                        .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                }
                .padding(8)
            }
            HStack {
                Button("Detect Automatically") { detectCodex() }
                Button("Locate Codex…") { chooseCodex() }
            }
            Label("Only the executable path is saved. No Codex credential or configuration file is imported.", systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Verify the user’s Codex account").font(.title.bold())
            Text("Codex owns the sign-in flow. PromptFoundry only asks the CLI whether it is ready.")
                .foregroundStyle(.secondary)
            GroupBox { connectionLabel.padding(10).frame(maxWidth: .infinity, alignment: .leading) }
            HStack {
                Button("Check Connection") { Task { await checkConnection() } }
                Button("Start Codex Sign-In") { startLogin() }.disabled(codexExecutablePath.isEmpty)
                Button("Open ChatGPT") { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/ChatGPT.app"), configuration: .init()) }
            }
            Text("Sign-in may open a browser. Credentials are entered into and stored by Codex—not PromptFoundry.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var projects: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose where Codex may work").font(.title.bold())
            Text("This becomes the default projects root. Every Codex handoff still displays its exact working directory before execution.")
                .foregroundStyle(.secondary)
            GroupBox {
                HStack {
                    Image(systemName: "folder.fill").foregroundStyle(FoundryStyle.accent)
                    Text(displayPath(projectDirectory.isEmpty ? defaultProjectsDirectory.path : projectDirectory))
                        .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                }.padding(8)
            }
            HStack {
                Button("Use PromptFoundry Projects") { projectDirectory = defaultProjectsDirectory.path }
                Button("Choose Existing Folder…") {
                    if let selected = DesktopPanels.chooseDirectory() { projectDirectory = selected.path }
                }
            }
            Label("The folder is created only when setup finishes. PromptFoundry never uses the Codex configuration directory as a project workspace.", systemImage: "folder.badge.gearshape")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ready to use PromptFoundry").font(.title.bold())
            SetupSummary(label: "Codex CLI", value: codexExecutablePath.isEmpty ? "Not configured" : codexExecutablePath)
            SetupSummary(label: "Authentication", value: connectionStatus.isConnected ? "Connected through Codex" : "Not yet connected")
            SetupSummary(label: "Projects folder", value: displayPath(projectDirectory.isEmpty ? defaultProjectsDirectory.path : projectDirectory))
            SetupSummary(label: "Prompt storage", value: "Local on this Mac")
            Label("You can change these choices later in PromptFoundry Settings.", systemImage: "gearshape")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var connectionLabel: some View {
        switch connectionStatus {
        case .checking: Label("Checking Codex…", systemImage: "arrow.triangle.2.circlepath")
        case .connected(let version): Label("Connected · \(version)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .unavailable(let message): Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var footer: some View {
        HStack {
            Button("Back") { step -= 1 }.disabled(step == 0)
            Spacer()
            if step < steps.count - 1 {
                Button("Continue") { step += 1; if step == 2 { Task { await checkConnection() } } }
                    .buttonStyle(.borderedProminent)
                    .disabled(step == 1 && codexExecutablePath.isEmpty)
            } else {
                Button("Finish Setup") { finish() }
                    .buttonStyle(.borderedProminent)
                    .disabled(codexExecutablePath.isEmpty)
            }
        }.padding(20)
    }

    private var defaultProjectsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("PromptFoundry Projects", isDirectory: true)
    }

    private func displayPath(_ path: String) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == homePath || path.hasPrefix(homePath + "/") else { return path }
        return "~" + path.dropFirst(homePath.count)
    }

    private func detectCodex() {
        if let url = DefaultCodexExecutableLocator().locate() { codexExecutablePath = url.path }
    }

    private func chooseCodex() {
        guard let url = DesktopPanels.chooseCodexExecutable() else { return }
        guard FileManager.default.isExecutableFile(atPath: url.path), url.lastPathComponent == "codex" else {
            setupError = "Choose an executable file named codex."
            return
        }
        codexExecutablePath = url.path
    }

    @MainActor private func checkConnection() async {
        connectionStatus = .checking
        connectionStatus = await appModel.codex.connectionStatus()
    }

    private func startLogin() {
        guard !codexExecutablePath.isEmpty else { return }
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: codexExecutablePath)
            process.arguments = ["login"]
            try process.run()
            loginProcess = process
            connectionStatus = .unavailable(message: "Complete the Codex sign-in in the browser, then check the connection again.")
        } catch { setupError = error.localizedDescription }
    }

    private func finish() {
        let target = projectDirectory.isEmpty ? defaultProjectsDirectory : URL(fileURLWithPath: projectDirectory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            projectDirectory = target.path
            isCompleted = true
        } catch { setupError = "The projects folder could not be created: \(error.localizedDescription)" }
    }
}

private struct SetupPoint: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(FoundryStyle.accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SetupSummary: View {
    let label: String
    let value: String
    var body: some View {
        LabeledContent(label) { Text(value).lineLimit(2).truncationMode(.middle).textSelection(.enabled) }
            .padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
