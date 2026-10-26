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

    @Environment(\.locale) private var locale
    private var localization: FileMailerLocalization { FileMailerLocalization(languageIdentifier: locale.identifier) }

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
                    Text(analysis?.localizedSummary(using: localization) ?? localization.string("Analysis in progress…"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Button(
                            LocalizedStringKey(attachment.contentType == "inode/directory"
                                ? "Compress" : "Preview"),
                            action: attachment.contentType == "inode/directory"
                                ? onCompress
                                : onPreview
                        )
                        Button("Reveal", action: onReveal)
                    }
                    .buttonStyle(.link)
                }
                Spacer(minLength: 2)
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: localization.format("Remove %@", attachment.displayName)))
            }

            if attachment.contentType != "inode/directory" {
                Divider()
                if attachment.usesGoogleDrive {
                    driveDeliveryControls
                    driveControls
                } else if requiresGoogleDrive {
                    Label(
                        "Gmail blocks this file type. A Google Drive link is required.",
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
                        "Use Google Drive for files larger than 18 MB.",
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
            Text("Only recipients of this message will be able to download.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if attachment.driveAccessExpiry == .custom {
                DatePicker(
                    "Expiry",
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
                    Button("Import") { onPrepareDrive() }
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
                Label("Gmail attachment", systemImage: "paperclip")
            }

            Button {
                onDeliveryModeChange(.googleDrive)
            } label: {
                Label("Google Drive link", systemImage: "link")
            }
        } label: {
            Label(
                LocalizedStringKey(attachment.usesGoogleDrive ? "Google Drive link" : "Gmail attachment"),
                systemImage: attachment.usesGoogleDrive ? "link" : "paperclip"
            )
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .menuStyle(.borderedButton)
        .controlSize(.small)
        .help("Delivery method")
        .accessibilityLabel("Delivery method")
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
            Button("Keep without automatic deletion") {
                onDriveAccessExpiryChange(.never)
            }
            Button("Delete after 1 day") {
                onDriveAccessExpiryChange(.oneDay)
            }
            Button("Delete after 7 days") {
                onDriveAccessExpiryChange(.sevenDays)
            }
            Button("Delete after 30 days") {
                onDriveAccessExpiryChange(.thirtyDays)
            }
            Button("Delete after 90 days") {
                onDriveAccessExpiryChange(.ninetyDays)
            }
            Divider()
            Button("Custom deletion date") {
                onDriveAccessExpiryChange(.custom)
            }
        } label: {
            Label(driveExpiryControlTitle, systemImage: "clock.arrow.circlepath")
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .menuStyle(.borderedButton)
        .controlSize(.small)
        .help("Access expiry")
        .accessibilityLabel("Access expiry")
    }

    private var driveCleanupMenu: some View {
        Menu {
            Button {
                onDriveCleanupActionChange(.keep)
            } label: {
                Label("Store in Drive", systemImage: "archivebox")
            }
            Button {
                onDriveCleanupActionChange(.trash)
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            Button(role: .destructive) {
                onDriveCleanupActionChange(.delete)
            } label: {
                Label("Permanently delete", systemImage: "trash.fill")
            }
        } label: {
            driveCleanupMenuLabel
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .menuStyle(.borderedButton)
        .controlSize(.small)
        .help("Action after expiration")
        .accessibilityLabel("Action after expiration")
    }

    @ViewBuilder
    private var driveCleanupMenuLabel: some View {
        switch attachment.driveCleanupAction {
        case .keep:
            Label("Keep", systemImage: "trash")
        case .trash:
            Label("Trash", systemImage: "trash")
        case .delete:
            Label("Permanent", systemImage: "trash.fill")
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
            localization.string("1 day")
        case .sevenDays:
            localization.string("7 days")
        case .thirtyDays:
            localization.string("30 days")
        case .ninetyDays:
            localization.string("90 days")
        case .custom:
            attachment.customDriveAccessExpiry?
                .formatted(.dateTime.day().month(.abbreviated).locale(locale))
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
            localization.string("Ready to upload to your FileMailer folder")
        case .needsAuthorization:
            localization.string("Authorize Google Drive for this account")
        case .uploading:
            localization.string("Import to Google Drive…")
        case .ready:
            localization.string("Private link ready for recipients of this message.")
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
