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

## App and drafting languages

1. On an English-language Mac, select French in General. Keep Settings and a
   compose window open: check their titles, sidebar, fields, menus, progress,
   attachment summaries, accessibility labels and Google disclosures in French.
2. Switch to English in the same window and repeat. Existing user text, names,
   filenames and saved signatures must remain unchanged.
3. Select Japanese and Arabic. Check line wrapping, the full draft-language
   picker value and right-to-left layout, including recipient editor sheets.
4. For each of the 50 app languages, generate a draft with “Application language”
   selected. Check subject, greeting, body and closing in the selected language.
5. With the app in French, request “Write in English”, then use a saved recipient
   preference and an explicit draft-language choice. The current writing request
   takes priority, then the recipient preference, then the draft-language picker,
   then the app language. File content must not override the language.
6. Repeat with Apple Intelligence unavailable or with an unsupported model
   language. The local template must still use the selected drafting language.
7. Re-enable the rebuilt Finder extension, switch app language and verify its
   submenu; quit the app and verify the cached language on the fallback menu.
8. Select the system language option and verify regional and Norwegian/Chinese
   resolution on a fresh launch.
9. Have fluent speakers review translations outside French and
   English before release. Resource completeness does not establish linguistic
   quality in every language.

Run `python3 Scripts/check_localizations.py` and `make test` before review. On an
eligible Mac, `FILEMAILER_TEST_ON_DEVICE_MODEL=1 swift test --package-path
Packages/FileMailerCore` also exercises actual French/English model output and an
explicit English override. UI tests isolate storage using `--ui-testing-*`.

## Release

Verify signatures, entitlements, notarization acceptance, stapling and
Gatekeeper assessment. Install on a clean user account and repeat onboarding,
Finder activation and one reviewed Gmail send.

## Sandboxed file access and Finder transport

- Use a signed archive with matching profiles, not only an unsigned debug build.
- Select an external test file using Add Attachment. Confirm analysis and preview
  work while the compose window remains open. Cancel the picker and confirm no
  attachment or permission is added.
- Quit and relaunch. Request the same path from Finder; confirm the remembered
  read-only bookmark allows analysis. Test a folder grant with a child file,
  multiple selected files, a moved file and a revoked or unavailable bookmark.
- Deny access to a new path. Confirm the app asks for read-only access and keeps
  the request visible rather than silently losing an attachment.
- Save a pending draft, relaunch, reopen it and verify every attachment is still
  accessible. Test a missing file and confirm an actionable error.
- Enable the Finder extension in System Settings. Test the right-click action
  while the app is running and while it is closed. Verify pinned recipients,
  the Other Recipient action and cancellation of the access picker.
- Change the app language with Finder open. Confirm refreshed menu labels and
  the language of a new draft. Check recipient and attachment remove buttons
  with VoiceOver in French and English.
- Confirm shared request files expire and are consumed once; notifications must
  have no userInfo and launch URLs must contain only a request UUID.
- Check a fresh installation and migration from an older direct-download build
  separately. Never infer account, credential or database migration from a build.
