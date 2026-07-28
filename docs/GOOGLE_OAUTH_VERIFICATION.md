---
layout: default
title: Google OAuth Verification Checklist
permalink: /google-oauth-verification/
---

# Google OAuth Verification Checklist

This checklist prepares the official FileMailer Google Cloud project for public
OAuth verification. It cannot verify a domain or submit a request on behalf of
the project owner: those actions require access to the domain’s DNS provider and
the Google Cloud project.

## 1. Verify the domain

1. In [Google Search Console](https://search.google.com/search-console), add a
   **Domain** property for `filemail.online`.
2. Create the TXT record that Search Console provides at the DNS provider for
   `filemail.online`.
3. Verify the property.
4. Ensure the Google account that is a verified Search Console owner is also an
   Owner or Editor of Google Cloud project `filemail-503408`.

The repository’s `docs/CNAME` file configures the intended GitHub Pages custom
domain. DNS still needs the GitHub Pages records and the Search Console TXT
record configured by the domain owner.

## 2. Publish the public site

Configure GitHub Pages to publish the `docs` directory (or the repository’s
chosen Pages deployment) and confirm these public, non-login URLs load over
HTTPS:

- `https://filemail.online/`
- `https://filemail.online/privacy/`
- `https://filemail.online/terms/`

The homepage explains FileMailer’s functionality and links to the same privacy
policy URL used in Cloud Console.

## 3. Configure Google Auth Platform

In the Branding section of project `filemail-503408`:

- use **FileMailer** consistently for the application name and public site;
- provide the public homepage, privacy policy and terms URLs above;
- add `filemail.online` as an authorized domain;
- set a real user-support email and developer-contact email;
- publish the verified branding once Google marks it ready.

In Audience, choose **External** for a public product. In Data Access, declare
only the scopes implemented by the official build:

- `openid`
- `email`
- `profile`
- `https://www.googleapis.com/auth/gmail.send`
- `https://www.googleapis.com/auth/drive.file` only if the Drive-link feature is
  included in the public release

Do not add Gmail read, modify, compose, metadata, SMTP/IMAP or full Drive scopes.

## 4. Scope justification

Use this description, adapting it only if the product changes:

> FileMailer is a native macOS productivity application that lets a user prepare
> and review an email from files selected in Finder. It uses `gmail.send` only
> after the user has reviewed all recipients, subject, body and attachments and
> explicitly pressed Send. It does not read, import, analyze or store Gmail
> inbox messages, Gmail history, existing Gmail drafts or mailbox metadata.
> FileMailer has no automatic or bulk-email sending feature. If the user chooses
> a Google Drive link for a selected file, FileMailer requests `drive.file` to
> upload only that file and grants reader access only to the reviewed message
> recipients; it does not create public links or access the user’s whole Drive.

## 5. Demo video and reviewer instructions

Record an unlisted YouTube video using a non-sensitive test account. Show:

1. the public FileMailer homepage and privacy policy;
2. the in-app privacy disclosure before Google authorization;
3. Google’s consent screen with the declared scopes;
4. a user editing and reviewing a message before pressing Send;
5. optionally, the Drive-link flow: separate consent, selected file, and the
   recipient-only sharing notice.

Never show real tokens, passwords, private files or personal email content.
Provide the reviewer with current installation and test instructions for the
signed release build. Do not provide the reviewer a shared production credential.

## 6. Resubmit and reply

After the public URLs, domain verification, branding and data-access details are
ready, submit the request from Google Cloud’s Verification Center. Then reply to
the Google verification email with the real URLs:

> Hello,\n\n>
> We have verified ownership of filemail.online and updated the FileMailer
> homepage and privacy policy. The policy now explicitly describes Google user
> data access, sharing, storage, security protections and Limited Use compliance.
> We have also resubmitted the verification request in Cloud Console.\n\n>
> Thank you.

Do not send this confirmation before the DNS verification and Cloud Console
resubmission actually succeed.
