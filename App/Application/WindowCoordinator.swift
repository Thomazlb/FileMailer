import AppKit
import FileMailerCore
import FinderSync
import SwiftUI

@MainActor
final class WindowCoordinator: NSObject {
    private static let composeContentSize = NSSize(width: 820, height: 680)
    private static let composeMinimumContentSize = NSSize(width: 760, height: 620)
    private static let settingsContentSize = NSSize(width: 760, height: 560)
    private static let onboardingContentSize = NSSize(width: 700, height: 520)

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general
        case recipients
        case accounts
        case diagnostics
        case about

        var id: Self { self }
    }

    private unowned let model: AppModel
    private var composeWindows: [UUID: NSWindowController] = [:]
    private var composeWindowDelegates: [UUID: ComposeWindowDelegate] = [:]
    private var settingsWindow: NSWindowController?
    private var onboardingWindow: NSWindowController?

    init(model: AppModel) {
        self.model = model
    }

    func showCompose(
        urls: [URL], recipient: RecipientProfile?, leases: [SecurityScopedFileAccess] = []
    ) {
        let viewModel = ComposeViewModel(
            model: model,
            urls: urls,
            recipient: recipient,
            leases: leases
        )
        presentCompose(viewModel)
    }

    func showCompose(draft: ComposeDraft) {
        presentCompose(ComposeViewModel(model: model, draft: draft))
    }

    private func presentCompose(_ viewModel: ComposeViewModel) {
        let root = ComposeView(viewModel: viewModel)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.composeContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = model.localizedString("New message")
        window.contentMinSize = Self.composeMinimumContentSize
        configureWindow(window, transparentTitlebar: false)
        window.contentViewController = NSHostingController(rootView: root)
        window.center()
        window.isReleasedWhenClosed = false
        let controller = NSWindowController(window: window)
        let id = viewModel.id
        let delegate = ComposeWindowDelegate { [weak self, weak viewModel] in
            viewModel?.handleWindowClose()
            self?.composeWindowDelegates.removeValue(forKey: id)
            self?.composeWindows.removeValue(forKey: id)
        }
        window.delegate = delegate
        viewModel.onClose = { [weak window] in
            window?.close()
        }
        composeWindowDelegates[id] = delegate
        composeWindows[id] = controller
        bringToFront(controller)
    }

    func showSettings(section: SettingsSection = .general) {
        if let settingsWindow {
            settingsWindow.contentViewController = NSHostingController(
                rootView: SettingsRootView(model: model, initialSection: section)
            )
            ensureContentSize(
                settingsWindow.window,
                minimum: Self.settingsContentSize
            )
            bringToFront(settingsWindow)
            return
        }
        let root = SettingsRootView(model: model, initialSection: section)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.settingsContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = model.localizedString("Settings")
        window.contentMinSize = Self.settingsContentSize
        configureWindow(window)
        window.contentViewController = NSHostingController(rootView: root)
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = NSWindowController(window: window)
        if let settingsWindow {
            bringToFront(settingsWindow)
        }
    }

    func showOnboarding() {
        if let onboardingWindow {
            bringToFront(onboardingWindow)
            return
        }
        let root = OnboardingView(model: model) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.onboardingContentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = model.localizedString("Welcome to FileMailer")
        window.contentMinSize = Self.onboardingContentSize
        configureWindow(window)
        window.contentViewController = NSHostingController(rootView: root)
        window.center()
        window.isReleasedWhenClosed = false
        onboardingWindow = NSWindowController(window: window)
        if let onboardingWindow {
            bringToFront(onboardingWindow)
        }
    }

    func showExtensionManagement() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    func refreshLocalizedTitles() {
        onboardingWindow?.window?.title = model.localizedString("Welcome to FileMailer")
        for controller in composeWindows.values {
            controller.window?.title = model.localizedString("New message")
        }
    }

    func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func bringToFront(_ controller: NSWindowController) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FILEMAILER_TEST_SCREENSHOT"] == "1",
           ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-testing-") }),
           let window = controller.window {
            window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 1280, height: 800)), display: true)
            window.center()
        }
        #endif
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        controller.window?.orderFrontRegardless()
    }

    private func configureWindow(
        _ window: NSWindow,
        transparentTitlebar: Bool = true
    ) {
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = true
        window.backgroundColor = .black
        window.titlebarAppearsTransparent = transparentTitlebar
        window.hasShadow = true
        window.isRestorable = false
    }

    private func ensureContentSize(
        _ window: NSWindow?,
        minimum: NSSize
    ) {
        guard let window else { return }
        let current = window.contentLayoutRect.size
        guard current.width < minimum.width || current.height < minimum.height else {
            return
        }
        window.setContentSize(
            NSSize(
                width: max(current.width, minimum.width),
                height: max(current.height, minimum.height)
            )
        )
    }
}

@MainActor
private final class ComposeWindowDelegate: NSObject, NSWindowDelegate {
    private let onWindowClose: () -> Void

    init(onWindowClose: @escaping () -> Void) {
        self.onWindowClose = onWindowClose
    }

    func windowWillClose(_ notification: Notification) {
        onWindowClose()
    }
}
