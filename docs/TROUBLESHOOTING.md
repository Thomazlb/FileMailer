# Troubleshooting

## Finder menu is absent

Open FileMailer Settings > Diagnostic, open extension management and confirm
that FileMailer is enabled. Start FileMailer, wait for the heartbeat indicator,
then reopen the context menu. Finder can require a restart after extension
changes. iCloud Drive and File Provider locations can behave differently from
local folders.

## A file is inaccessible

Move or download the item locally, then add it again with the file picker.
FileMailer does not request Full Disk Access automatically. iCloud placeholders,
TCC-protected folders and detached external volumes can lose access before
send. The app rechecks every attachment just before MIME creation.

## Google sign-in is blocked

Confirm the iOS client ID, reversed client ID redirect scheme, bundle ID, Gmail
API state and consent-screen test users. A Testing project with Gmail scopes can
issue refresh tokens that expire after seven days. Workspace administrators can
block unverified clients or Gmail scopes.

## Google Drive link cannot be prepared

Confirm that the Google Drive API is enabled for the same Cloud project and
authorize the Drive request for the selected sender account. FileMailer asks for
the narrow `drive.file` scope only when the private Drive delivery option is
used. Workspace administrators can block Drive sharing or Drive API access.

## Apple Intelligence is unavailable

Apple Intelligence drafting requires macOS 27, an eligible Mac, an enabled
Apple Intelligence setting and a downloaded local model. FileMailer reports
each state and continues with deterministic or manual drafting. On macOS 26,
the deterministic and manual paths are used by design.

## Gmail rejects the message

The default source-attachment budget is 18 MiB because MIME encoding increases
size. Remove attachments if Gmail or an administrator applies a smaller limit.
On an upload timeout after data transfer starts, check Gmail Sent before trying
again because FileMailer intentionally avoids a blind retry.
