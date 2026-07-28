# Manual test plan

Automated tests do not prove Finder placement, OAuth service configuration,
model quality or Gmail delivery. Record OS, hardware, account type, build ID and
result for every manual run.

| Area | macOS 26 or 27 Apple silicon | macOS 26 or 27 Intel if supported |
| --- | --- | --- |
| App launch and LSUIElement status item | Required | Best effort |
| Left popover and right status menu | Required | Best effort |
| Finder local file and folder | Required | Best effort |
| External volume | Required | Best effort |
| iCloud Drive downloaded item | Required | Best effort |
| File Provider item | Required | Best effort |
| Gmail personal | Required | Best effort |
| Google Workspace | Required when available | Best effort |
| Foundation Models available | Required on eligible macOS 27 hardware | Not eligible |
| Deterministic fallback | Required | Required |

## Finder and compose

1. Enable and disable the extension and verify diagnostics follow the real state.
2. Select one file, multiple files, a container and a folder.
3. Confirm the submenu limit, pinned order and app-absent fallback.
4. Confirm each action opens a visible review window and never sends.
5. Add, remove, preview and reveal attachments.
6. Compress a folder and inspect displayed exclusions and sensitive warnings.
7. Move, edit and delete attachments before Send and verify blocking messages.
8. Exercise keyboard navigation, VoiceOver labels, dark mode and Reduce Motion.

## OAuth and Gmail

1. Add two Google accounts and verify separate Keychain items by OIDC subject.
2. Reconnect an expired account, change default account and remove one account.
3. Confirm the in-app disclosure and privacy-policy link appear immediately
   before the Google consent screen for Gmail and Drive.
4. Confirm the standard four scopes are requested at Gmail sign-in and
   `drive.file` is requested only after choosing private Drive delivery.
5. Send plain text, Unicode, small attachment and resumable-size messages.
6. Confirm recipients, visible edits, attachment names and body in Gmail.
7. Exercise 401, policy block, quota, offline and ambiguous timeout paths with a
   synthetic network configuration before production credentials.

## Google Drive delivery

1. Choose Drive delivery for a file above 18 MiB and verify background upload
   to the sender's `FileMailer` Drive folder while the compose window remains
   editable.
2. Send to To, Cc and Bcc recipients and verify each recipient receives private
   reader access without a public link.
3. Verify that a person who is not a To, Cc or Bcc recipient cannot open the
   Drive file, even when they receive the URL.
4. Test no expiry, preset expiry and a custom expiry date within one year. Verify
   that expired access is revoked.
5. Test keep, trash and permanent-delete cleanup choices. Confirm that cleanup
   can be delayed until FileMailer next runs after the due date.

## Model behavior

1. Test available, disabled, model-not-ready and ineligible states.
2. Edit subject and body while generation streams and verify no late overwrite.
3. Use the prompt-injection fixture and confirm no extra recipient or send claim.
4. Compare French, English and automatic language plus all tone choices.

## Release

Verify signatures, entitlements, notarization acceptance, stapling and
Gatekeeper assessment. Install on a clean user account and repeat onboarding,
Finder activation and one reviewed Gmail send.
