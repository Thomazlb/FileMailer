---
layout: default
title: FileMailer Security Design
permalink: /security/
---

# Security Design

## Trust boundaries

Finder IPC, file names, metadata, extracted content, OAuth responses and Gmail
responses are untrusted. The model has no tools, network client or send action.
Only explicit UI code can start `GmailUploadCoordinator`.

## Controls

- Finder Sync uses public APIs only and keeps its menu snapshot in memory.
- IPC is versioned, checksummed, bounded, expiring and rate-limited.
- Recipient IDs are resolved locally; no extension-provided address is trusted.
- Every Finder action opens a review window and cannot send.
- OAuth uses the system browser, AppAuth PKCE S256, state, nonce and the
  registered application redirect scheme.
- Standard OAuth scopes are minimal and OAuth archives are Keychain-only. The
  keychain item is accessible only while the device is unlocked and is not
  migrated to another device.
- MIME rejects CR, LF and NUL in user-controlled headers.
- Attachment base64 uses bounded lines and file-backed streaming.
- ZIP readers allow expected entries only, reject traversal and flag suspicious
  expansion ratios. Folder symlinks are not followed outside their root.
- File excerpts are placed only in the user prompt and marked as untrusted.
- Logs and diagnostics mask email addresses, bearer values and user paths.
- Google API requests use HTTPS. FileMailer has no developer-operated backend
  that receives Gmail content or OAuth credentials.

## Prompt injection

The static model instructions never interpolate file content. Prompts delimit
untrusted file data and instruct the model not to obey it. Guided output is
validated for header-like prefixes, subject newlines, length and assertions of
sending. A deterministic fallback remains available after guardrail or context
errors.

## Local denial of service

The extension limits paths to 50 and each path to 4096 UTF-8 bytes. IPC has
message and table bounds. File analysis reads at most 256 KiB per text file and
1 MiB total prompt text, limits PDF/OCR pages and caps archive and folder
entries. Cancellation is checked in long operations.

## Logs

Do not add message bodies, subjects, raw API responses, access tokens, refresh
tokens, complete paths or extracted text to logs. Diagnostic events must pass
the app sanitizer before storage or export.
