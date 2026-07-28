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
                Button("Réglages…") {
                    appDelegate.windows?.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
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
        let windows = WindowCoordinator(model: model)
        self.windows = windows
        model.windows = windows
        menuBar = MenuBarController(model: model)
        ipc = AppIPCService(model: model)
        let actionURLs = pendingActionURLs
        pendingActionURLs.removeAll()
        actionURLs.forEach { ipc?.handleActionURL($0) }
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing-compose") {
            windows.showCompose(paths: [], recipient: nil)
        } else if arguments.contains("--ui-testing-onboarding")
                    || (model.accounts.isEmpty && model.recipients.isEmpty) {
            windows.showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { await model.temporaryFiles?.removeAllRegistered() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let ipc else {
            pendingActionURLs.append(contentsOf: urls)
            return
        }
        urls.forEach(ipc.handleActionURL)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        windows?.showSettings()
        return false
    }
}
