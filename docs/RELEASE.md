# Release

## Mac App Store preparation

The main app and Finder extension use App Sandbox. The main app has outgoing
network access, user-selected read-only file access and app-scoped bookmarks.
The extension has only sandbox and App Group entitlements. A Finder path is a
request, never a grant: the app resolves an existing bookmark or asks the user
for read-only access in a native file picker.

Both targets share `$(DEVELOPMENT_TEAM).$(BASE_BUNDLE_ID).shared`. This is a
team-prefixed macOS App Group. Enable App Groups for both bundle identifiers
and regenerate both provisioning profiles. Apple documents this namespace and
profile authorization in its [App Groups guidance](https://developer.apple.com/forums/thread/721701).
The shared container carries menu metadata and expiring action files. Distributed
notifications have no `userInfo`, and launch URLs contain only a request UUID.

The `AppStore` configuration uses Apple Distribution signing and separate profiles
for the main app and Finder extension. Developer ID distribution uses `Release`
and its own profiles. All four profile names belong in the ignored
`Config/Local.xcconfig`; see the public template. Configure a maintainer-owned,
verified Google OAuth client matching the final bundle ID there as well.

Requirements: Xcode 27, macOS 27 SDK, macOS 26 deployment target, active Apple
Developer Program membership, signing certificates with their private keys and
matching profiles. Apple Intelligence is optional and guarded at macOS 27;
manual editing and deterministic drafting support macOS 26.

## Checks and signed store archive

```bash
make generate
make audit-public
make test
make check-app-store
make export-app-store CODE_SIGNING_ALLOWED=YES
```

`export-app-store` creates a signed universal archive in
`build/FileMailer-AppStore.xcarchive` and a signed installer in
`build/AppStore/FileMailer.pkg`. It derives export profile names from the embedded
profiles and writes export options under the ignored build directory. Install
both an Apple Distribution certificate and a Mac Installer Distribution
certificate with their private keys before export. This command does not upload,
submit or publish the app.

Inspect an existing archive independently:

```bash
python3 Scripts/check_app_store.py --archive build/FileMailer-AppStore.xcarchive
```

This checks both signatures, universal architectures, read-only sandbox
entitlements, group authorization in the embedded profiles, matching versions
and bundled privacy manifests. It does not replace installed-app testing,
Transporter validation, App Store Connect validation or App Review.

Complete the [manual test plan](MANUAL_TEST_PLAN.md), including file access after
relaunch, revoked access, a folder, multiple files, Finder-to-app handoff and
actual Gmail/Drive delivery. Test migration from a previous direct-download
installation: sandbox containers change local database and credential access.
Do not claim upgrade compatibility until this has been checked.

## App Store Connect

Reusable English metadata and review instructions are in `AppStore/`. The store
name is **FileMailer: Send from Anywhere** (30 characters); the subtitle is
**Send any file from Finder**. The app and repository remain named FileMailer.
Finder files and folders are supported; arbitrary selections in other apps are
not promised.

Before submission, verify:

- Current developer agreements are accepted by the account holder.
- The correct version and build are uploaded, processed and selected.
- The review contact has valid private name, email and telephone fields.
- Real macOS screenshots use an accepted App Store size and show the final UI.
- Pricing, country availability, category, age rating, support and privacy URLs
  match the intended release.
- The App Privacy answers match both the privacy policy and the shipped code.
  Account identifiers, names, email addresses and user-selected message/file
  contents go to Google for app functionality; they are linked to the account
  and are not used for tracking. The Finder extension does not collect data.
- Google OAuth verification and public-user access are complete. Signing an
  archive does not establish that new users can authorize Google successfully.
- All 50 languages have resource coverage; fluent-speaker review is still needed
  beyond the languages inspected. Test both interface and drafting behavior.

Using the [App Store Connect CLI](https://github.com/rorkai/App-Store-Connect-CLI):

```bash
asc validate --app "$APP_ID" --version 1.0.0 --platform MAC_OS --output json
```

CLI versions support different flags; inspect local help before using examples
from a newer release. App Privacy publication is verified in the authenticated
web interface because the public API cannot establish its published state.
Keep release type manual until the account holder explicitly chooses release.

A locally exported installer, a processed build, a clean metadata validation and
Apple review acceptance are separate outcomes. Report each one with evidence.

## Direct download

```bash
make archive CODE_SIGNING_ALLOWED=YES
make package CODE_SIGNING_ALLOWED=YES
```

`Release` uses Developer ID Application signing and separate main/extension
profiles with App Groups enabled. Both targets remain sandboxed. Xcode signs
nested code in the correct order; do not use `codesign --deep` for signing.

Store notarization credentials once in a Keychain profile:

```bash
xcrun notarytool store-credentials FileMailerNotary
NOTARY_KEYCHAIN_PROFILE=FileMailerNotary make notarize CODE_SIGNING_ALLOWED=YES
make verify-release
```

The package target creates a ZIP, a DMG containing the app and Applications
shortcut, and portable SHA-256 manifests. Notarization staples the app, rebuilds
the containers, then notarizes and staples the DMG. Verify Gatekeeper on a clean
Mac and distribute the dependency notices and SBOM with the release.

The native Icon Composer source is `App/Resources/FileMail.icon`; the GitHub PNG
and SVG exports are under `Design/`. The same artwork is used for application
and disk image branding.
