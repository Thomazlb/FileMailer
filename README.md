# FileMailer

[Privacy](docs/PRIVACY.md) |
[Security](SECURITY.md) |
[Support](docs/SUPPORT.md) |
[Releases](https://github.com/Thomazlb/FileMailer/releases)

FileMailer is a native macOS menu-bar application that prepares a reviewable
Gmail message from files selected in Finder. It analyzes files locally,
suggests a subject and plain-text body with Apple Foundation Models on eligible
macOS 27 systems, and always keeps a deterministic and fully manual path
available.

```text
Finder selection
      |
Finder Sync extension, sandboxed and network-free
      |
bounded DistributedNotificationCenter messages
      |
FileMailer, editable compose window
      |
Keychain OAuth + streaming MIME + Gmail and Drive REST
```

## Features

- Native Finder submenu backed by `FIFinderSync`
- Different left-click popover and right-click status-item menu
- Pinned and ranked recipients with a configurable visible count
- Multi-account Google OAuth through the system browser and Keychain storage
- Editable To, Cc, Bcc, subject, body and attachment list
- Local TXT, PDF, image OCR, Office Open XML, ZIP and folder analysis
- On-device Foundation Models guided generation on eligible macOS 27 systems
- Deterministic French and English fallback
- Streaming RFC 5322 MIME writer and direct or resumable Gmail uploads
- Optional private Google Drive links for files or ZIP archives above 18 MiB
- Per-recipient Drive access, optional expiry and best-effort local cleanup
- Optional local draft autosave using file bookmarks, never copied attachments
- No backend, analytics, third-party crash reporter or automatic sending

## Requirements

- macOS 26 or later
- Xcode 27 with the macOS 27 SDK
- XcodeGen 2.42 or later
- A Google Cloud iOS OAuth client matching the macOS bundle ID
- Apple Developer Program membership for Developer ID distribution

Apple Intelligence drafting is enabled only on macOS 27 when the device and
system model are eligible. macOS 26 retains the same editable compose flow with
deterministic drafting and manual composition.

## Build

```bash
cp Config/Local.xcconfig.template Config/Local.xcconfig
# Edit DEVELOPMENT_TEAM, GOOGLE_CLIENT_ID, GOOGLE_REDIRECT_SCHEME and BASE_BUNDLE_ID.
make bootstrap
make generate
make test
make build
```

`Config/Local.xcconfig` is ignored. A no-signing CI build uses:

```bash
make build CODE_SIGNING_ALLOWED=NO
```

Before the first commit or any public release, run:

```bash
make audit-public
```

The audit checks the complete publishable file set for credentials, personal
email addresses, private macOS paths and local signing material.

The working app is written to `build/DerivedData/Build/Products/Debug/FileMailer.app`.
`make run` opens it, but build and test targets do not launch it.

## First use

1. Start FileMailer and complete or skip each onboarding step.
2. Open the Finder extension management interface from onboarding or
   Settings > Diagnostic and enable FileMailer.
3. Add a Gmail account. Google authorization opens in the system browser.
4. Add and optionally pin recipients.
5. Right-click one or more files in Finder and choose the FileMailer submenu.
6. For a large file, choose a private Google Drive link and authorize Drive for
   that account when requested.
7. Review every visible field and press Send only when ready.

Finder chooses the exact position of extension menu items. A folder is
inspected and converted to ZIP before it can be sent or uploaded to Drive.

## Privacy and security

File contents remain local during deterministic analysis and on-device model
generation. At Send, the reviewed message and direct attachments are uploaded
to Google's Gmail API. When the user chooses a Drive link, the selected file or
ZIP archive is uploaded to a `FileMailer` folder in that user's Google Drive,
then shared only with the message recipients. OAuth states containing tokens
live only in Keychain.
The extension receives neither tokens nor message content and has no network
entitlement. See [Privacy](docs/PRIVACY.md) and
[Security](docs/SECURITY.md).

## Known limits

- The user must enable the Finder extension.
- Finder Sync behavior can vary in iCloud Drive and File Provider locations.
- Public Gmail distribution requires Google's OAuth verification for
  `gmail.send`; Workspace administrators can block the client.
- Drive links use the narrow `drive.file` scope and only cover files created or
  selected through FileMailer. They are not public links.
- Drive cleanup is scheduled locally. If the Mac is off at expiry, cleanup runs
  the next time FileMailer or macOS can run its scheduled maintenance.
- Gmail history import and Private Cloud Compute are disabled.
- The Golden Gate adapter currently uses the verified on-device text model.
  Multimodal image input remains isolated for a later SDK-stable iteration.
- FileMailer is not intended for bulk or automated mail.

Further design details are in [Architecture](docs/ARCHITECTURE.md), Google
setup in [OAuth setup](docs/GOOGLE_OAUTH_SETUP.md), and release operations in
[Release](docs/RELEASE.md).

## Official releases and community builds

An official GitHub release is signed and notarized by the maintainer and uses
the verified production OAuth client injected during the private release
build. Its users only authorize their own Google account.

A source checkout never receives maintainer credentials. Contributors copy
`Config/Local.xcconfig.template`, create their own Google Cloud iOS OAuth
client and keep that local configuration uncommitted. Missing OAuth
configuration disables real Gmail authorization without preventing a
no-signing source build.

## Contributing and license

Read [CONTRIBUTING.md](CONTRIBUTING.md) and the
[manual test plan](docs/MANUAL_TEST_PLAN.md). FileMailer is available under
the [MIT License](LICENSE).
