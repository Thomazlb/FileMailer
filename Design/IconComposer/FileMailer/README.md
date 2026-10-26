# FileMailer icon

The source document used by Xcode and the app distributed in the DMG is
[`App/Resources/FileMail.icon`](../../../App/Resources/FileMail.icon).
Open the package in Icon Composer to edit it. The icon selected in `project.yml`
is `FileMail`.

[`Design/FileMailerIcon.png`](../../FileMailerIcon.png) is a direct Icon Composer
export for iOS/macOS, Default appearance, 1024 pt at 1x. It preserves the native
rendering and is the GitHub README logo. After replacing that export, run:

```sh
zsh Scripts/generate_app_icon.sh
```

The script updates the PNGs in the legacy `AppIcon.appiconset` to match. The
`.icon` document remains the source of the compiled app icon.

[`Design/FileMailerIcon.svg`](../../FileMailerIcon.svg) and
[`FileMailerIcon.svg`](FileMailerIcon.svg) are static vector previews with the
same paths, layer order and translation. Native Icon Composer lighting and glass
effects are preserved in the `.icon` document and PNG export.

The white layer sits above the blue layer. Both use a translation of
`(-13.659437189567257, 3.4607383646631433)` points. Layer colors are white
`#FFFFFF` and blue `#0A84FF`; the Icon Composer background is `system-dark`.
