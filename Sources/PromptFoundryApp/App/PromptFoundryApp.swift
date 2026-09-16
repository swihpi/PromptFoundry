import AppKit
import PromptFoundryCore
import SwiftUI

final class PromptFoundryAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct PromptFoundryApp: App {
    @NSApplicationDelegateAdaptor(PromptFoundryAppDelegate.self) private var appDelegate
    @StateObject private var appModel: AppModel
    @AppStorage(SettingsKeys.appearance) private var appearance = "system"

    init() {
        UserDefaults.standard.register(defaults: [
            SettingsKeys.defaultRefinerModel: "gpt-5.6-terra",
            SettingsKeys.defaultRefinerEffort: ReasoningEffort.medium.rawValue,
            SettingsKeys.refinementProvider: RefinementProvider.codex.rawValue,
            SettingsKeys.defaultCodexModel: "gpt-5.6-terra",
            SettingsKeys.defaultCodexEffort: ReasoningEffort.medium.rawValue,
            SettingsKeys.defaultTarget: PromptTarget.codex.rawValue,
            SettingsKeys.automaticSave: true,
            SettingsKeys.appearance: "system",
            SettingsKeys.codexNeverAsk: false,
            SettingsKeys.onboardingCompleted: false
        ])
        _appModel = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        WindowGroup("PromptFoundry", id: "main") {
            WorkspaceRootView(viewModel: appModel.workspace)
                .environmentObject(appModel)
                .frame(minWidth: 1_100, minHeight: 680)
                .preferredColorScheme(preferredColorScheme)
        }
        .defaultSize(width: 1_520, height: 900)
        .commands { PromptFoundryCommands(viewModel: appModel.workspace) }

        Settings {
            SettingsView()
                .environmentObject(appModel)
                .preferredColorScheme(preferredColorScheme)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

private struct PromptFoundryCommands: Commands {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Prompt") { viewModel.newPrompt() }
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandGroup(after: .saveItem) {
            Button("Save Prompt") { viewModel.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(viewModel.draft.originalIdea.isEmpty && viewModel.draft.professionalPrompt.isEmpty)
        }
        CommandMenu("Prompt") {
            Button("Generate Professional Prompt") { viewModel.generate() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!viewModel.canGenerate)
            Button("Stop Generation") { viewModel.stopGeneration() }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(viewModel.generationState != .generating)
            Divider()
            Button("Copy Professional Prompt") { viewModel.copyPrompt() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!viewModel.canUsePrompt)
            Button("Run in Codex") { viewModel.prepareCodexReview() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(!viewModel.canUsePrompt)
        }
    }
}
