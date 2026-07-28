---
layout: default
title: FileMailer Privacy Policy
permalink: /privacy/
---

# FileMailer Privacy Policy

Last updated: July 28, 2026.

This policy explains how FileMailer, an open-source native macOS application,
accesses, uses, stores and shares Google user data. It applies to the official
FileMailer application distributed by its maintainers. Community builds use the
Google Cloud project and OAuth client configured by their own builder.

## Local processing

Recipient ranking, file metadata inspection, text extraction, PDF processing,
Vision OCR, archive manifests and Foundation Models generation happen on the
user’s Mac. Extracted file text is held in memory for the current composition
and is not written to FileMailer logs.

The optional on-device language model receives bounded metadata and extracted
text inside an explicitly untrusted-data section. File contents are not system
instructions. FileMailer has no developer-operated backend, analytics service
or third-party crash reporter.

## Google data FileMailer accesses and uses

When a user chooses **Continue with Google**, FileMailer requests `openid`,
`email`, `profile` and `https://www.googleapis.com/auth/gmail.send`. It uses
the resulting Google account identifier, verified email address and optional
display name to identify the selected sending account. It does not request or
use `gmail.metadata`, `gmail.readonly`, `gmail.modify`, `gmail.compose`, Gmail
history, existing Gmail messages or existing Gmail drafts.

Only after the user reviews a message and presses **Send**, FileMailer sends the
exact sender, recipients, subject, message body and direct attachments to Google
through the Gmail API. FileMailer does not initiate an email without a user’s
explicit action.

If a user selects Google Drive delivery for a file or archive, FileMailer asks
separately for `https://www.googleapis.com/auth/drive.file`. It uploads only the
selected file or archive to a `FileMailer` folder in that user’s Google Drive.
This scope is limited to Drive files FileMailer creates or that the user
explicitly opens through the app; it does not grant access to the user’s whole
Drive.

For each Drive-delivered file, FileMailer grants reader access only to the To,
Cc and Bcc recipients selected in the reviewed message. It does not create a
public or “anyone with the link” permission. When the user chooses an access
expiry, FileMailer sets that expiry on each recipient permission. The user can
also choose to trash or permanently delete the uploaded Drive file after the
selected period.

## Sharing, transfer and disclosure of Google user data

FileMailer does not sell, rent, transfer or disclose Google user data to
advertising networks, data brokers, analytics providers, or other third parties.
It discloses or transfers Google user data only in these limited situations:

- **Google:** to authenticate the user, to send the message that the user has
  reviewed and chosen to send through the Gmail API, and, when the user chooses
  Google Drive delivery, to upload the selected file to the user’s Drive.
- **Recipients selected by the user:** when Google Drive delivery is selected,
  the selected recipients receive reader access to that specific Drive file.
  No other person receives a public-link permission from FileMailer.
- **Legal or security requirements:** when disclosure is required by applicable
  law, or necessary to investigate security abuse or protect users and the
  service.

FileMailer does not allow its maintainers, employees or contractors to read a
user’s Gmail data. It has no server on which it receives or stores Gmail content.

FileMailer’s use of information received from Google APIs adheres to the
[Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy),
including its Limited Use requirements. FileMailer does not use, transfer or
retain data obtained through Google APIs to train or improve generalized AI or
machine-learning models.

## Storage, retention and deletion

FileMailer stores the following data on the user’s Mac:

- OAuth authorization state and refresh tokens in the macOS Keychain, one item
  per OpenID Connect subject. The keychain item is accessible only while the
  device is unlocked and is not migrated to another device.
- Account and recipient metadata in the local FileMailer SwiftData store.
- Optional locally saved pending drafts and security-scoped bookmarks to their
  original attachments. Attachments themselves are not copied into saved drafts.
- Temporary MIME and ZIP files in a directory with mode `0700`; individual
  temporary files use mode `0600` and are removed after a successful send or
  cleanup.
- Drive folder identifiers and cleanup metadata in local Application Support,
  without Drive content or OAuth tokens.

Extracted file text is memory-only. Successful sends remove their pending draft
and registered temporary files. Temporary files older than 24 hours are cleaned
at launch. If a Drive cleanup is due while the Mac is off or offline, FileMailer
performs it at the next scheduled maintenance opportunity or app launch.

Users can remove a connected account from FileMailer to delete its local OAuth
Keychain item and local account metadata. They can revoke FileMailer’s access
from [Google Account connections](https://myaccount.google.com/connections).
Users can remove recipients individually in FileMailer’s settings and can turn
off locally saved drafts in Settings; disabling that setting deletes every saved
local draft. Do not include message content,
credentials or OAuth tokens in a public support issue.

## Security measures

FileMailer uses the system browser for Google OAuth and protects the
authorization flow with PKCE S256, state and nonce checks. It communicates with
Google API endpoints over HTTPS and stores OAuth credentials only in the macOS
Keychain rather than in application preferences, logs or a developer server.

Temporary files use restrictive filesystem permissions. Diagnostics mask email
addresses, bearer values and user paths, and FileMailer does not log message
bodies, subjects, raw API responses, access tokens, refresh tokens or extracted
text. The Finder extension has no network entitlement and cannot access OAuth
tokens or message content.

Private Cloud Compute is not enabled in this release. A future opt-in cloud
feature would require separate consent and a policy update before it is enabled.

## Contact

For privacy questions, use the [FileMailer support process](https://github.com/Thomazlb/FileMailer/issues)
without including personal documents, message content, credentials or OAuth
tokens. Security vulnerabilities must use
[private vulnerability reporting](https://github.com/Thomazlb/FileMailer/security/advisories/new).
