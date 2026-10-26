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
        "Show Tab Bar": "Afficher la barre d’onglets",
        "Hide Tab Bar": "Masquer la barre d’onglets",
        "Show All Tabs": "Afficher tous les onglets",
        "Exit Tab Overview": "Quitter l’aperçu des onglets",
        "Show Previous Tab": "Afficher l’onglet précédent",
        "Show Next Tab": "Afficher l’onglet suivant",
        "Move Tab to New Window": "Déplacer l’onglet vers une nouvelle fenêtre",
        "Merge All Windows": "Fusionner toutes les fenêtres",
        "Left of Screen": "À gauche de l’écran",
        "Right of Screen": "À droite de l’écran",
        "Edit": "Édition",
        "View": "Présentation",
        "Window": "Fenêtre",
        "Help": "Aide",
        "About FileMailer": "À propos de FileMailer",
        "Services": "Services",
        "Hide FileMailer": "Masquer FileMailer",
        "Hide Others": "Masquer les autres",
        "Show All": "Tout afficher",
        "Quit FileMailer": "Quitter FileMailer",
        "Undo": "Annuler la dernière action",
        "Redo": "Rétablir",
        "Cut": "Couper",
        "Copy": "Copier",
        "Paste": "Coller",
        "Delete": "Supprimer",
        "Select All": "Tout sélectionner",
        "AutoFill": "Remplissage automatique",
        "Contact…": "Contact…",
        "Passwords…": "Mots de passe…",
        "Credit Card…": "Carte bancaire…",
        "Start Dictation": "Démarrer la dictée",
        "Emoji & Symbols": "Emoji et symboles",
        "Enter Full Screen": "Activer le plein écran",
        "Exit Full Screen": "Quitter le plein écran",
        "Close": "Fermer",
        "Close All": "Tout fermer",
        "Minimize": "Réduire",
        "Minimize All": "Tout réduire",
        "Zoom": "Zoom",
        "Zoom All": "Tout agrandir",
        "Fill": "Remplir",
        "Center": "Centrer",
        "Move & Resize": "Déplacer et redimensionner",
        "Halves": "Moitiés",
        "Left": "Gauche",
        "Right": "Droite",
        "Top": "Haut",
        "Bottom": "Bas",
        "Quarters": "Quarts",
        "Top Left": "En haut à gauche",
        "Top Right": "En haut à droite",
        "Bottom Left": "En bas à gauche",
        "Bottom Right": "En bas à droite",
        "Arrange": "Disposer",
        "Left & Right": "Gauche et droite",
        "Left & Quarters": "Gauche et quarts",
        "Right & Left": "Droite et gauche",
        "Right & Quarters": "Droite et quarts",
        "Top & Bottom": "Haut et bas",
        "Top & Quarters": "Haut et quarts",
        "Bottom & Top": "Bas et haut",
        "Bottom & Quarters": "Bas et quarts",
        "Return to Previous Size": "Rétablir la taille précédente",
        "Full Screen Tile": "Mosaïque plein écran",
        "Bring All to Front": "Tout ramener au premier plan",
        "Arrange in Front": "Disposer au premier plan",
        "Remove Window from Set": "Retirer la fenêtre du groupe",
        "Send FileMailer Feedback to Apple": "Envoyer des commentaires sur FileMailer à Apple",
        "FileMailer Help": "Aide FileMailer",
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
            case "undo:": key = "Annuler la dernière action"
            case "redo:": key = "Rétablir"
            case "cut:": key = "Couper"
            case "copy:": key = "Copier"
            case "paste:": key = "Coller"
            case "delete:": key = "Supprimer"
            case "selectAll:": key = "Tout sélectionner"
            case "orderFrontStandardAboutPanel:": key = "À propos de FileMailer"
            case "hide:": key = "Masquer FileMailer"
            case "hideOtherApplications:": key = "Masquer les autres"
            case "unhideAllApplications:": key = "Tout afficher"
            case "terminate:": key = "Quitter FileMailer"
            case "performMiniaturize:": key = "Réduire"
            case "arrangeInFront:": key = "Tout ramener au premier plan"
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
