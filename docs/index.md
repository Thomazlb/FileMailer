---
layout: default
title: FileMailer
permalink: /
---

# FileMailer

FileMailer is an open-source native macOS application that prepares an editable
email from files selected in Finder. It is a productivity tool for
user-initiated correspondence: every sender, recipient, subject, message body
and attachment remains visible for review, and FileMailer sends nothing until
the user presses **Send**.

FileMailer is maintained as an open-source project by
[Thomazlb](https://github.com/Thomazlb).

## What FileMailer does

- Analyzes selected files locally on the Mac and can propose an editable draft.
- Connects a Google account only when the user chooses to do so.
- Uses the Gmail API only to send the message the user has reviewed.
- Offers an optional Google Drive link for large files or file types Gmail does
  not accept. Those files are uploaded only when the user selects that option.

FileMailer does **not** read the user’s Gmail inbox, existing messages, Gmail
drafts or Gmail history. It does not send automatically, provide bulk-mailing
features, operate a developer backend, use analytics, or include a third-party
crash reporter.

## How Google data is used

FileMailer requests the minimum scopes needed for its visible features:

- `openid`, `email` and `profile` identify the Google account selected by the
  user;
- `gmail.send` sends only the message explicitly reviewed and sent by the user;
- `drive.file` is requested separately and only if the user chooses a Google
  Drive link.

For a Drive link, FileMailer creates or uses a file in the user’s Google Drive
and grants reader access only to the message’s To, Cc and Bcc recipients. It
does not create a public link or request access to the user’s whole Drive.

Read the complete [Privacy Policy](https://filemail.online/privacy/) and
[Terms of Use](https://filemail.online/terms/) before using FileMailer.

## Project links

- [Source code](https://github.com/Thomazlb/FileMailer)
- [Releases](https://github.com/Thomazlb/FileMailer/releases)
- [Support](https://github.com/Thomazlb/FileMailer/issues)
- [Security design](https://filemail.online/security/)
- [OAuth setup for community builds](https://filemail.online/google-oauth-setup/)
