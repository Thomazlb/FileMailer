import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private unowned let model: AppModel
    private let statusItem: NSStatusItem
    private let panel: MenuBarPanel
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let hostingController = NSHostingController(
            rootView: MenuBarPanelView(model: model)
        )
        hostingController.sizingOptions = [.preferredContentSize]
        panel = MenuBarPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        super.init()
        statusItem.autosaveName = "org.filemailer.status-item"
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.image = Self.menuBarImage()
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.setAccessibilityLabel(String(localized: "FileMailer"))
            button.toolTip = String(localized: "FileMailer")
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        configurePanel()
    }

    private static func menuBarImage() -> NSImage? {
        guard
            let source = NSImage(named: "MenuBarIcon"),
            let image = source.copy() as? NSImage
        else {
            return nil
        }

        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu(relativeTo: sender)
        } else {
            togglePopover(relativeTo: sender)
        }
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        if panel.isVisible {
            closePanel()
        } else {
            showPanel(relativeTo: button)
        }
    }

    private func configurePanel() {
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient
        ]
    }

    private func showPanel(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let fittingSize = panel.contentViewController?.view.fittingSize
            ?? NSSize(width: 320, height: 300)
        panel.setContentSize(fittingSize)

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = buttonWindow.convertToScreen(buttonRectInWindow)
        let screenFrame = buttonWindow.screen?.frame
            ?? NSScreen.main?.frame
            ?? .zero
        let horizontalMargin: CGFloat = 8
        let proposedX = buttonRectOnScreen.midX - fittingSize.width / 2
        let clampedX = min(
            max(proposedX, screenFrame.minX + horizontalMargin),
            screenFrame.maxX - fittingSize.width - horizontalMargin
        )
        panel.setFrameTopLeftPoint(
            NSPoint(x: clampedX, y: buttonRectOnScreen.minY + 1)
        )
        panel.orderFrontRegardless()
        panel.makeKey()
        installDismissMonitors()
    }

    private func closePanel() {
        panel.orderOut(nil)
        removeDismissMonitors()
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            let statusWindow = self.statusItem.button?.window
            if event.window !== self.panel, event.window !== statusWindow {
                self.closePanel()
            }
            return event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closePanel()
            }
        }
    }

    private func removeDismissMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func showContextMenu(relativeTo button: NSStatusBarButton) {
        closePanel()
        let menu = NSMenu(title: AppConfiguration.appName)
        menu.addItem(item("Modifier les destinataires…", action: #selector(editRecipients)))
        menu.addItem(item("Comptes Gmail…", action: #selector(editAccounts)))
        menu.addItem(item("Préférences…", action: #selector(openPreferences)))
        menu.addItem(item("Diagnostic de l’extension…", action: #selector(openDiagnostics)))
        menu.addItem(item("À propos de FileMailer", action: #selector(openAbout)))
        menu.addItem(item("Quitter FileMailer", action: #selector(quit)))
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 4),
            in: button
        )
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func editRecipients() {
        model.windows?.showSettings(section: .recipients)
    }

    @objc private func editAccounts() {
        model.windows?.showSettings(section: .accounts)
    }

    @objc private func openPreferences() {
        model.windows?.showSettings(section: .general)
    }

    @objc private func openDiagnostics() {
        model.windows?.showSettings(section: .diagnostics)
    }

    @objc private func openAbout() {
        model.windows?.showSettings(section: .about)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private final class MenuBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
