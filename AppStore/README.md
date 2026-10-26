# App Store metadata

`metadata.json` contains the English store identity and public URLs. `en-US/`
contains version text. `review-notes.txt` describes offline review, Google
authorization, read-only file grants and Finder activation. Private review
contact details belong only in App Store Connect.

The requested phrase “FileMailer: Everything from Anywhere” exceeds Apple’s
30-character name limit. The store name is “FileMailer: Send from Anywhere”;
the subtitle specifies the supported Finder workflow. Files and folders can be
selected in Finder, added with the native picker or dropped into a draft.
Selections of arbitrary content in every macOS app are not supported.

The app includes 50 interface and deterministic drafting languages. Store text
is currently supplied in English; resource coverage does not replace
fluent-speaker review. See [release checks](../docs/RELEASE.md).

The main app privacy manifest declares Google account identifiers, name and
email, message contents and selected file contents, linked to the account for
app functionality without tracking. Match these categories in App Store
Connect; publication of privacy answers requires the account holder’s approval.
The Finder extension declares no collection. Google authorization, sending and
optional Drive uploads are the only account-backed network features.

Use real interface captures in an accepted APP_DESKTOP size. Do not include
private accounts, personal files, credentials, desktop background or test-run
logs in uploaded screenshots. Test captures use example.com and a synthetic
project brief. Uploading metadata and screenshots does not publish the app.
