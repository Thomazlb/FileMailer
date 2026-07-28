---
layout: default
title: Google OAuth Setup
permalink: /google-oauth-setup/
---

# Google OAuth Setup

Direct console links:

- [Create a Google Cloud project](https://console.cloud.google.com/projectcreate)
- [Enable Gmail API](https://console.cloud.google.com/apis/library/gmail.googleapis.com)
- [Enable Google Drive API](https://console.cloud.google.com/apis/library/drive.googleapis.com)
- [Google Auth Platform overview](https://console.cloud.google.com/auth/overview)
- [Branding](https://console.cloud.google.com/auth/branding)
- [Audience](https://console.cloud.google.com/auth/audience)
- [Data access](https://console.cloud.google.com/auth/scopes)
- [OAuth clients](https://console.cloud.google.com/auth/clients)

## Community build

1. Create a Google Cloud project owned by you.
2. Enable the Gmail API and, if you want private large-file links, the Google
   Drive API.
3. Configure the OAuth consent screen, support email, homepage and privacy URL.
4. Create an OAuth client of type iOS for the macOS application.
5. Set its bundle ID to the same value as `BASE_BUNDLE_ID`.
6. Download its configuration and copy the public client ID and reversed client ID.
7. Copy `Config/Local.xcconfig.template` to `Config/Local.xcconfig`.
8. Set `GOOGLE_CLIENT_ID` to the client ID.
9. Set `GOOGLE_REDIRECT_SCHEME` to the reversed client ID, without `:/oauth2redirect`.
10. Set a unique `BASE_BUNDLE_ID` and your `DEVELOPMENT_TEAM`.
11. Generate and build the project.

The native client ID and reversed client ID are public configuration. FileMailer
does not embed or request a client secret because a distributed native
application cannot keep one confidential.

FileMailer discovers Google OpenID configuration, opens the system browser and
uses AppAuth with PKCE, state, nonce and the registered custom redirect scheme.
The standard scopes are:

```text
openid
email
profile
https://www.googleapis.com/auth/gmail.send
```

The request uses offline access and account selection. Consent can be required
again when Google does not return a refresh token.

FileMailer asks for this additional scope only when the user selects a private
Google Drive link for a file or folder archive:

```text
https://www.googleapis.com/auth/drive.file
```

`drive.file` limits Drive access to files FileMailer creates or that a user
explicitly opens through the app. FileMailer creates a `FileMailer` folder in
the signed-in user's Drive, uploads the selected file there and creates
recipient-specific reader permissions for the reviewed To, Cc and Bcc fields.
It does not create a public link.

## Testing and production

Add individual test users while the consent screen is in Testing. For external
apps using Gmail scopes, refresh tokens can expire after seven days while the
project remains in Testing. Move the project to Production and complete
Google's verification for public distribution of the sensitive `gmail.send`
scope. The narrower `drive.file` scope is non-sensitive, but public users still
need the same verified consent configuration because FileMailer requests
`gmail.send`.

The official release client belongs to a maintainer-controlled, verified Google
Cloud project and is injected at build time. It must not share contributor
development configuration. Google Workspace administrators can block the
client or OAuth scopes independently of FileMailer.

The release environment requires these configuration values:

```text
DEVELOPMENT_TEAM
GOOGLE_CLIENT_ID
GOOGLE_REDIRECT_SCHEME
BASE_BUNDLE_ID
```

Gmail sent-history import is off. If it is developed later, it requires separate
consent for `gmail.metadata`, no subject or body reads, local aggregation and
restricted-scope verification.

## Official public release

The public release must use a maintainer-owned Google Cloud project and OAuth
client. Community builders must create their own project and client; they must
not reuse the official production client. Before a public release, configure
the official project as External, provide the public homepage and privacy-policy
URLs on `https://filemail.online`, and submit the exact requested scopes for
verification.

See the [OAuth verification checklist](https://filemail.online/google-oauth-verification/)
for the Search Console, Cloud Console, demo-video and resubmission steps.
