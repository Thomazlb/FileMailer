# Foundation Models

FileMailer supports macOS 26 and later. It calls Foundation Models directly
only on macOS 27 or later. It does not invoke the Siri interface. Siri-facing
actions are outside the current release.

`SystemLanguageModel.default.availability` selects between:

- on-device guided generation when available;
- a deterministic draft in the selected application language on macOS 26;
- a deterministic draft in the selected application language when the device is not eligible,
  Apple Intelligence is disabled or the model is not ready;
- fully manual composition at all times.

The interface and deterministic templates cover 50 languages. An explicit drafting
language or a language instruction in the user purpose overrides the application
language. Unsupported on-device model locales use local templates.

The source prompts and model guides are written in English and explicitly require
the resolved output language. The session receives no tools. Its static instructions say that file content is
untrusted, facts must not be invented and sending must never be claimed. The
user prompt contains bounded metadata, summaries and excerpts inside explicit
untrusted-data delimiters.

Guided generation returns a subject and plain-text body. Validation trims the
subject, rejects CR/LF, caps it at 120 characters, removes technical header-like
body lines and caps the body. Account signatures are appended deterministically
after final model output.

The Golden Gate adapter uses the verified macOS 27 on-device text API. On macOS
26, FileMailer never calls the Apple Intelligence API and exposes the same
editable deterministic and manual drafting paths. Image analysis currently uses
local dimensions and Vision OCR. Multimodal direct image input and Private Cloud
Compute remain disabled until their SDK contracts and entitlements are stable
enough for release review.
