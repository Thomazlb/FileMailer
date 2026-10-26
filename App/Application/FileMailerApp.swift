import AppKit
import SwiftUI

@main
struct FileMailerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsCommand(model: appDelegate.model)
            }
        }
    }
}

private struct SettingsCommand: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Button(model.localizedString("Settings…")) { model.windows?.showSettings() }
            .keyboardShortcut(",", modifiers: .command)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    var windows: WindowCoordinator?
    private var menuBar: MenuBarController?
    private var ipc: AppIPCService?
    private var pendingActionURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(where: { $0.hasPrefix("--ui-testing-") }) {
            NSApp.setActivationPolicy(.regular)
        }
        #endif
        NativeMenuLocalizer.shared.start()
        let windows = WindowCoordinator(model: model)
        self.windows = windows
        model.windows = windows
        menuBar = MenuBarController(model: model)
        ipc = AppIPCService(model: model)
        let actionURLs = pendingActionURLs
        pendingActionURLs.removeAll()
        handleOpenedURLs(actionURLs)
        #if DEBUG
        if arguments.contains("--ui-testing-settings") {
            windows.showSettings()
        } else if arguments.contains("--ui-testing-compose") {
            windows.showCompose(urls: [], recipient: nil)
        } else if arguments.contains("--ui-testing-onboarding")
                    || (model.accounts.isEmpty && model.recipients.isEmpty) {
            windows.showOnboarding()
        }
        #else
        if model.accounts.isEmpty && model.recipients.isEmpty { windows.showOnboarding() }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { await model.temporaryFiles?.removeAllRegistered() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard ipc != nil else {
            pendingActionURLs.append(contentsOf: urls)
            return
        }
        handleOpenedURLs(urls)
    }

    private func handleOpenedURLs(_ urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty { model.openUserSelectedFiles(files) }
        urls.filter { !$0.isFileURL }.forEach { ipc?.handleActionURL($0) }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        windows?.showSettings()
        return false
    }
}
