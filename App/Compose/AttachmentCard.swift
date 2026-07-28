import AppKit
import FileMailerCore
import QuickLookThumbnailing
import SwiftUI

@MainActor
struct AttachmentCard: View {
    private enum Layout {
        static let directCardWidth: CGFloat = 292
        static let driveCardWidth: CGFloat = 360
        static let directCardHeight: CGFloat = 102
        static let driveCardHeight: CGFloat = 142
        static let driveCardWithCustomDateHeight: CGFloat = 174
    }

    let attachment: ComposeAttachment
    let analysis: AttachmentAnalysis?
    let driveUploadState: ComposeViewModel.DriveUploadState
    let onRemove: () -> Void
    let onPreview: () -> Void
    let onReveal: () -> Void
    let onCompress: () -> Void
    let onDeliveryModeChange: @MainActor @Sendable (AttachmentDeliveryMode) -> Void
    let onDriveAccessExpiryChange: @MainActor @Sendable (DriveAccessExpiry) -> Void
    let onCustomDriveAccessExpiryChange: @MainActor @Sendable (Date) -> Void
    let onDriveCleanupActionChange: @MainActor @Sendable (DriveCleanupAction) -> Void
    let onPrepareDrive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                QuickLookThumbnail(url: attachment.url)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.displayName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(analysis?.deterministicSummary ?? "Analyse en cours…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Button(
                            attachment.contentType == "inode/directory"
                                ? "Compresser"
                                : "Aperçu",
                            action: attachment.contentType == "inode/directory"
                                ? onCompress
                                : onPreview
                        )
                        Button("Révéler", action: onReveal)
                    }
                    .buttonStyle(.link)
                }
                Spacer(minLength: 2)
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retirer \(attachment.displayName)")
            }

            if attachment.contentType != "inode/directory" {
                Divider()
                if attachment.usesGoogleDrive {
                    driveDeliveryControls
                    driveControls
                } else if requiresGoogleDrive {
                    Label(
                        "Gmail bloque ce type de fichier. Un lien Google Drive est requis.",
                        systemImage: "link.badge.plus"
                    )
                    .font(.caption2)
                    .foregroundStyle(.orange)
                } else {
                    deliveryModeMenu
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !attachment.usesGoogleDrive,
                   attachment.size > AttachmentDeliveryPolicy.directAttachmentLimit {
                    Label(
                        "Utilisez Google Drive pour les fichiers de plus de 18 Mo.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption2)
                    .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(
            width: usesDrivePresentation ? Layout.driveCardWidth : Layout.directCardWidth,
            alignment: .topLeading
        )
        .frame(
            minHeight: minimumCardHeight,
            alignment: .topLeading
        )
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.black)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.7)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var driveControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Seuls les destinataires de ce message pourront télécharger.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if attachment.driveAccessExpiry == .custom {
                DatePicker(
                    "Expiration",
                    selection: Binding(
                        get: {
                            attachment.customDriveAccessExpiry
                                ?? Calendar.current.date(byAdding: .day, value: 7, to: Date())!
                        },
                        set: onCustomDriveAccessExpiryChange
                    ),
                    in: Date()...Calendar.current.date(byAdding: .year, value: 1, to: Date())!,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(.caption)
            }

            HStack(spacing: 6) {
                Image(systemName: driveStatusSymbol)
                    .foregroundStyle(driveStatusColor)
                Text(driveStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if driveUploadState == .notRequested || isFailed {
                    Button("Importer") { onPrepareDrive() }
                        .buttonStyle(.link)
                }
            }
        }
    }

    private var deliveryModeMenu: some View {
        Menu {
            Button {
                onDeliveryModeChange(.attachment)
            } label: {
                Label("Pièce jointe Gmail", systemImage: "paperclip")
            }

            Button {
                onDeliveryModeChange(.googleDrive)
            } label: {
                Label("Lien Google Drive", systemImage: "link")
            }
        } label: {
            Label(
                attachment.usesGoogleDrive ? "Lien Google Drive" : "Pièce jointe Gmail",
                systemImage: attachment.usesGoogleDrive ? "link" : "paperclip"
            )
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .menuStyle(.borderedButton)
        .controlSize(.small)
        .help("Mode de livraison")
        .accessibilityLabel("Mode de livraison")
    }

    private var driveDeliveryControls: some View {
        HStack(spacing: 8) {
            deliveryModeMenu
                .fixedSize(horizontal: true, vertical: false)

            driveExpiryMenu
                .fixedSize(horizontal: true, vertical: false)
            driveCleanupMenu
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var driveExpiryMenu: some View {
        Menu {
            Button("Conserver sans suppression automatique") {
                onDriveAccessExpiryChange(.never)
            }
            Button("Supprimer après 1 jour") {
                onDriveAccessExpiryChange(.oneDay)
            }
            Button("Supprimer après 7 jours") {
                onDriveAccessExpiryChange(.sevenDays)
            }
            Button("Supprimer après 30 jours") {
                onDriveAccessExpiryChange(.thirtyDays)
            }
            Button("Supprimer après 90 jours") {
                onDriveAccessExpiryChange(.ninetyDays)
            }
            Divider()
            Button("Date de suppression personnalisée") {
                onDriveAccessExpiryChange(.custom)
            }
        } label: {
            Label(driveExpiryControlTitle, systemImage: "clock.arrow.circlepath")
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .menuStyle(.borderedButton)
        .controlSize(.small)
        .help("Expiration de l’accès")
        .accessibilityLabel("Expiration de l’accès")
    }

    private var driveCleanupMenu: some View {
        Menu {
            Button {
                onDriveCleanupActionChange(.keep)
            } label: {
                Label("Conserver dans Drive", systemImage: "archivebox")
            }
            Button {
                onDriveCleanupActionChange(.trash)
            } label: {
                Label("Mettre à la corbeille", systemImage: "trash")
            }
            Button(role: .destructive) {
                onDriveCleanupActionChange(.delete)
            } label: {
                Label("Supprimer définitivement", systemImage: "trash.fill")
            }
        } label: {
            driveCleanupMenuLabel
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .menuStyle(.borderedButton)
        .controlSize(.small)
        .help("Action après expiration")
        .accessibilityLabel("Action après expiration")
    }

    @ViewBuilder
    private var driveCleanupMenuLabel: some View {
        switch attachment.driveCleanupAction {
        case .keep:
            Label("Garder", systemImage: "trash")
        case .trash:
            Label("Corbeille", systemImage: "trash")
        case .delete:
            Label("Définitif", systemImage: "trash.fill")
        }
    }

    private var isFailed: Bool {
        if case .failed = driveUploadState { return true }
        return false
    }

    private var requiresGoogleDrive: Bool {
        AttachmentDeliveryPolicy.requiresLinkDelivery(for: attachment)
    }

    private var usesDrivePresentation: Bool {
        attachment.usesGoogleDrive || requiresGoogleDrive
    }

    private var minimumCardHeight: CGFloat {
        guard attachment.usesGoogleDrive else {
            return Layout.directCardHeight
        }
        return attachment.driveAccessExpiry == .custom
            ? Layout.driveCardWithCustomDateHeight
            : Layout.driveCardHeight
    }

    private var driveExpiryControlTitle: String {
        switch attachment.driveAccessExpiry {
        case .never:
            "∞"
        case .oneDay:
            "1 j"
        case .sevenDays:
            "7 j"
        case .thirtyDays:
            "30 j"
        case .ninetyDays:
            "90 j"
        case .custom:
            attachment.customDriveAccessExpiry?
                .formatted(.dateTime.day().month(.abbreviated))
                ?? "…"
        }
    }

    private var driveStatusSymbol: String {
        switch driveUploadState {
        case .notRequested: "icloud.and.arrow.up"
        case .needsAuthorization: "lock.fill"
        case .uploading: "arrow.up.circle"
        case .ready: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var driveStatusColor: Color {
        switch driveUploadState {
        case .ready: .green
        case .failed: .orange
        case .needsAuthorization: .yellow
        case .notRequested, .uploading: .accentColor
        }
    }

    private var driveStatusText: String {
        switch driveUploadState {
        case .notRequested:
            "Prêt à importer dans votre dossier FileMailer"
        case .needsAuthorization:
            "Autorisez Google Drive pour ce compte"
        case .uploading:
            "Importation vers Google Drive…"
        case .ready:
            "Lien privé prêt pour les destinataires de ce message."
        case let .failed(message):
            message
        }
    }
}

private struct QuickLookThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "doc")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 80, height: 80),
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                representationTypes: .thumbnail
            )
            image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(
                for: request
            ).nsImage
        }
    }
}
