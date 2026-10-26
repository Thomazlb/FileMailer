import AppKit
import FileMailerCore

/// AppKit builds these menus in the launch language. Keep their visible titles
/// in step with FileMailer's language without replacing their native actions.
@MainActor
final class NativeMenuLocalizer {
    static let shared = NativeMenuLocalizer()
    private var observers: [NSObjectProtocol] = []
    private var refreshScheduled = false
    private var isRefreshing = false

    private static let titles: [String: String] = [
        "Show Tab Bar": "Show Tab Bar",
        "Hide Tab Bar": "Hide Tab Bar",
        "Show All Tabs": "Show All Tabs",
        "Exit Tab Overview": "Exit Tab Overview",
        "Show Previous Tab": "Show Previous Tab",
        "Show Next Tab": "Show Next Tab",
        "Move Tab to New Window": "Move Tab to New Window",
        "Merge All Windows": "Merge All Windows",
        "Left of Screen": "Left of Screen",
        "Right of Screen": "Right of Screen",
        "Edit": "Edit menu",
        "View": "View",
        "Window": "Window",
        "Help": "Help",
        "About FileMailer": "About FileMailer",
        "Services": "Services",
        "Hide FileMailer": "Hide FileMailer",
        "Hide Others": "Hide Others",
        "Show All": "Show All",
        "Quit FileMailer": "Exit FileMailer",
        "Undo": "Undo",
        "Redo": "Redo",
        "Cut": "Cut",
        "Copy": "Copy",
        "Paste": "Paste",
        "Delete": "Delete",
        "Select All": "Select All",
        "AutoFill": "AutoFill",
        "Contact…": "Contact…",
        "Passwords…": "Passwords…",
        "Credit Card…": "Credit Card…",
        "Start Dictation": "Start Dictation",
        "Emoji & Symbols": "Emoji & Symbols",
        "Enter Full Screen": "Enter Full Screen",
        "Exit Full Screen": "Exit Full Screen",
        "Close": "Close",
        "Close All": "Close All",
        "Minimize": "Minimize",
        "Minimize All": "Minimize All",
        "Zoom": "Zoom",
        "Zoom All": "Zoom All",
        "Fill": "Fill",
        "Center": "Center",
        "Move & Resize": "Move & Resize",
        "Halves": "Halves",
        "Left": "Left",
        "Right": "Right",
        "Top": "Top",
        "Bottom": "Bottom",
        "Quarters": "Quarters",
        "Top Left": "Top Left",
        "Top Right": "Top Right",
        "Bottom Left": "Bottom Left",
        "Bottom Right": "Bottom Right",
        "Arrange": "Arrange",
        "Left & Right": "Left & Right",
        "Left & Quarters": "Left & Quarters",
        "Right & Left": "Right & Left",
        "Right & Quarters": "Right & Quarters",
        "Top & Bottom": "Top & Bottom",
        "Top & Quarters": "Top & Quarters",
        "Bottom & Top": "Bottom & Top",
        "Bottom & Quarters": "Bottom & Quarters",
        "Return to Previous Size": "Return to Previous Size",
        "Full Screen Tile": "Full Screen Tile",
        "Bring All to Front": "Bring All to Front",
        "Arrange in Front": "Arrange in Front",
        "Remove Window from Set": "Remove Window from Set",
        "Send FileMailer Feedback to Apple": "Send FileMailer Feedback to Apple",
        "FileMailer Help": "FileMailer Help",
    ]

    private lazy var aliases: [String: String] = {
        var values = Self.titles
        let systemMenus = Bundle(for: NSMenu.self)
        for (source, key) in Self.titles {
            values[systemMenus.localizedString(forKey: source, value: source, table: "MenuCommands")] = key
        }
        for identifier in FileMailerLocalization.supportedIdentifiers {
            let localization = FileMailerLocalization(languageIdentifier: identifier)
            for key in Self.titles.values {
                values[localization.string(key)] = key
            }
        }
        return values
    }()

    func start() {
        guard observers.isEmpty else { return }
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification,
                     NSMenu.didBeginTrackingNotification, NSApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] notification in
                // NotificationCenter delivers this Objective-C object synchronously
                // on the main queue; it never crosses an executor here.
                nonisolated(unsafe) let changedMenu = notification.object as? NSMenu
                MainActor.assumeIsolated {
                    if name == NSMenu.didChangeItemNotification || name == NSMenu.didBeginTrackingNotification {
                        self?.refresh(menu: changedMenu)
                    } else {
                        self?.scheduleRefresh()
                    }
                }
            })
        }
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.refreshScheduled = false
            self?.refresh()
        }
    }

    func refresh(menu: NSMenu? = nil) {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let localization = FileMailerLocalization.current
        if let menu { localize(menu, using: localization) }
        if let main = NSApp.mainMenu, main !== menu { localize(main, using: localization) }
    }

    private func localize(_ menu: NSMenu, using localization: FileMailerLocalization) {
        // Service and window names belong to their providers or to the user.
        guard menu !== NSApp.servicesMenu else { return }
        guard !menu.items.contains(where: { $0.action.map(NSStringFromSelector) == "_aboutThisMacRequested:" })
        else { return }
        for item in menu.items where !item.isSeparatorItem {
            let action = item.action.map(NSStringFromSelector)
            if action == "makeKeyAndOrderFront:" { continue }
            let key: String?
            switch action {
            case "undo:": key = "Undo"
            case "redo:": key = "Redo"
            case "cut:": key = "Cut"
            case "copy:": key = "Copy"
            case "paste:": key = "Paste"
            case "delete:": key = "Delete"
            case "selectAll:": key = "Select All"
            case "orderFrontStandardAboutPanel:": key = "About FileMailer"
            case "hide:": key = "Hide FileMailer"
            case "hideOtherApplications:": key = "Hide Others"
            case "unhideAllApplications:": key = "Show All"
            case "terminate:": key = "Exit FileMailer"
            case "performMiniaturize:": key = "Minimize"
            case "arrangeInFront:": key = "Bring All to Front"
            default: key = aliases[item.title]
            }
            if let key {
                let title = localization.string(key)
                if item.title != title { item.title = title }
                if let attributed = item.attributedTitle, attributed.string != title {
                    let attributes = attributed.length > 0 ? attributed.attributes(at: 0, effectiveRange: nil) : [:]
                    item.attributedTitle = NSAttributedString(string: title, attributes: attributes)
                }
                item.setAccessibilityTitle(title)
                item.setAccessibilityLabel(title)
                if let submenu = item.submenu, submenu.title != title { submenu.title = title }
            }
            if let submenu = item.submenu { localize(submenu, using: localization) }
        }
    }
}
