# Architecture

## Process boundaries

```text
Finder
  -> FinderExtension.appex
       sandbox: enabled
       network and attachment reads: none
  -> App Group container
       bounded menu snapshot and expiring action requests
  -> FileMailer.app
       sandbox: enabled
       user-selected read-only access and scoped bookmarks
       local analysis, drafting, Keychain, MIME, Gmail and Drive
```

The main app and Finder extension share a team-prefixed macOS App Group, authorized
by provisioning profiles with the App Groups capability. Only the main app has
outgoing network and user-selected-file entitlements. Both Developer ID and
App Store configurations use the sandbox.

## Modules

- `FileMailerDomain`: immutable messages, accounts, recipients and protocols
- `FileMailerIPC`: bounded shared state, request references, expiry, limits and deduplication
- `RecipientRanking`: pinned ordering and frequency/recency scoring
- `GmailAuth`: AppAuth browser flow, application redirect and Keychain archives
- `GmailAPI`: targeted REST uploads with typed errors
- `GoogleDrive`: per-user Drive uploads, recipient permissions and local cleanup scheduling
- `MIME`: streaming RFC 5322 message construction and temporary files
- `FileAnalysis`: bounded local analyzers and safe folder archiving
- `AIComposition`: deterministic and Foundation Models draft generation
- `Persistence`: SwiftData metadata, send events, settings and pending drafts

## Finder transport

The extension writes at most 50 absolute paths, a random request ID, a local
recipient ID, selection context and timestamp to the shared container. It opens
the containing app explicitly using a URL with only that request ID. A request
cannot supply a Gmail account or email address as trusted state. The app resolves
recipient IDs locally and always opens a visible compose window.

Distributed notifications carry signals only, with `userInfo: nil`, as required
for sandboxed senders. Snapshots are read from atomic files, not notifications.
Acknowledgements carry only a request UUID in the notification's string object.
Actions expire after 30 seconds, are consumed once, and pass rate and duplicate
checks. Payloads are capped at 128 KiB for actions and 256 KiB for snapshots.
Symlink payload files and invalid menu counts are rejected. Abandoned actions
are pruned and the queue is bounded to 100 entries. The legacy URL codec remains
for compatibility with earlier Developer ID installations.

A path alone grants no file access. The app resolves remembered read-only
security-scoped bookmarks. If a requested file is still inaccessible, the native
file picker asks the user to select it or its containing folder. Successful scope
leases remain alive through analysis, compression, upload and sending, and are
balanced when the compose operation ends. Pending drafts store scoped bookmarks
and surface bookmark failures instead of silently dropping attachments.

The App Group contains no OAuth tokens, attachments or message bodies. A forged
notification cannot supply a request payload or send an email.

## Send data flow

1. The main actor captures an immutable `OutboundMessage` from the visible UI.
2. It rechecks readability, size and modification date for every attachment.
3. `MIMEWriter` streams a temporary mode-0600 RFC 5322 file.
4. `GmailUploadCoordinator` obtains a valid token from the account actor.
5. `GmailMailSender` uploads the file directly up to 5 MiB or uses a resumable
   session above that size.
6. SwiftData records a sanitized success event only after Gmail returns 2xx.
7. Temporary resources and the local pending draft are deleted.

An ambiguous upload timeout is never retried automatically.

## Large-file Drive flow

1. A file above the direct-attachment budget, or a file explicitly switched to
   Drive delivery, is uploaded in the background to the sender's `FileMailer`
   Drive folder.
2. The compose window remains editable while upload progress is visible.
3. At Send, FileMailer grants reader access only to the To, Cc and Bcc
   recipients, optionally with a Drive-enforced expiry.
4. The message body receives the private Drive link. The file is not added to
   the RFC 5322 MIME attachment list.
5. An optional trash or permanent-delete action is recorded locally and retried
   when FileMailer next has an opportunity to perform due cleanup.

## Data model

SwiftData stores account metadata without tokens, recipients, aggregate send
events, settings and optional pending drafts. Pending drafts contain addresses,
plain text and file bookmarks, not copied attachments. OAuth archives are
separate Keychain items keyed by the OIDC `sub` claim.
