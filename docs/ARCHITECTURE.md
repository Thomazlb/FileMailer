# Architecture

## Process boundaries

```text
Finder
  -> FinderExtension.appex
       sandbox: enabled
       network: none
       file reads: none
       state: bounded in-memory menu snapshot
  -> DistributedNotificationCenter
       versioned, chunked, checksummed, size-limited, unauthenticated
  -> FileMailer.app
       LSUIElement: true
       sandbox: disabled
       review window required
       file analysis, Foundation Models, Keychain, MIME, Gmail and Drive
```

The app is distributed outside the Mac App Store with Developer ID because its
core flow needs durable access to files explicitly handed over by Finder. The
main app is not sandboxed. The Finder extension is sandboxed, has no App Group,
no file entitlement and no network entitlement.

## Modules

- `FileMailerDomain`: immutable messages, accounts, recipients and protocols
- `FileMailerIPC`: chunk codec, SHA-256 checks, expiry, limits and deduplication
- `RecipientRanking`: pinned ordering and frequency/recency scoring
- `GmailAuth`: AppAuth browser flow, application redirect and Keychain archives
- `GmailAPI`: targeted REST uploads with typed errors
- `GoogleDrive`: per-user Drive uploads, recipient permissions and local cleanup scheduling
- `MIME`: streaming RFC 5322 message construction and temporary files
- `FileAnalysis`: bounded local analyzers and safe folder archiving
- `AIComposition`: deterministic and Foundation Models draft generation
- `Persistence`: SwiftData metadata, send events, settings and pending drafts

## Finder transport

The extension posts at most 50 paths, a random request ID, a local recipient ID,
selection context and timestamp. It cannot name a Gmail account or supply an
email address as trusted state. The app resolves identifiers in SwiftData and
always opens a visible compose window.

Payloads are split into at most 64 chunks. A chunk is at most 64 KiB, a snapshot
is at most 256 KiB and an action is at most 128 KiB. The reassembler expires
partial messages after five seconds and checks a SHA-256 digest before decode.
Actions older than 30 seconds and duplicate request IDs are rejected.

`DistributedNotificationCenter` is not an authentication mechanism. A local
process can forge a notification. This cannot cause sending because the only
result of a valid request is a review window.

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
