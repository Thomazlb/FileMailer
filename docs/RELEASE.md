# Release

## Prerequisites

- Apple Developer Program membership
- Developer ID Application certificate and private key
- Xcode 27 and macOS 27 SDK
- Deployment target macOS 26, with Apple Intelligence guarded at macOS 27
- App-specific notarization credentials stored in a Keychain profile
- Maintainer-owned verified Google OAuth iOS client matching the macOS bundle ID

Set release values in a non-committed `Config/Local.xcconfig` or CI environment.
Never place a certificate, private key, Keychain password or notarization token
in the repository.

Run the public-source audit before generating release artifacts:

```bash
make audit-public
```

## Build and package

```bash
make generate
make test
make build CODE_SIGNING_ALLOWED=NO
make archive CODE_SIGNING_ALLOWED=YES
make package CODE_SIGNING_ALLOWED=YES
```

Release archives default to manual `Developer ID Application` signing. Override
`RELEASE_CODE_SIGN_IDENTITY` only when using a differently named Developer ID
identity.

Inspect the app and embedded extension separately:

```bash
codesign -d --entitlements :- build/FileMailer.xcarchive/Products/Applications/FileMailer.app
codesign -d --entitlements :- build/FileMailer.xcarchive/Products/Applications/FileMailer.app/Contents/PlugIns/FileMailer\ Finder\ Extension.appex
```

The main app must have Hardened Runtime, no app sandbox and no App Group. The
extension must have app sandbox, no network entitlement, no file entitlement
and no App Group. Do not use `codesign --deep`; Xcode signs nested code in the
correct order.

## Notarize and verify

Store credentials once:

```bash
xcrun notarytool store-credentials FileMailerNotary
```

Then:

```bash
NOTARY_KEYCHAIN_PROFILE=FileMailerNotary make notarize CODE_SIGNING_ALLOWED=YES
make verify-release
```

The `package` target creates both a ZIP and a compressed DMG. The DMG contains
`FileMailer.app` and an `Applications` shortcut. The `notarize` target first
notarizes and staples the application, recreates the DMG with that stapled app,
then notarizes and staples the DMG itself. It also recreates the downloadable
ZIP after stapling so both distributed containers include the same final
application. Checksum manifests use portable filenames and can be verified from
the directory containing the downloaded artifacts.

Publish the DMG, ZIP, their SHA-256 files, release notes and a simple dependency
list from `Package.resolved`. Confirm Gatekeeper assessment on a clean Mac
before announcing a release.

Archive creation, notarization submission, Apple acceptance and stapling are
separate outcomes and must be reported separately.
