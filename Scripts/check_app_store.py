#!/usr/bin/env python3
"""Check store configuration and, optionally, a locally signed archive."""

import argparse
import fnmatch
import json
import plistlib
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GROUP_KEY = "com.apple.security.application-groups"
SANDBOX = "com.apple.security.app-sandbox"
DATA_TYPES = {
    "Name", "EmailAddress", "UserID", "EmailsOrTextMessages",
    "PhotosorVideos", "AudioData", "OtherUserContent",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def plist(path):
    return plistlib.loads(path.read_bytes())


def check_entitlements(main, extension, group):
    require(main.get(SANDBOX) is True, "The main app must be sandboxed")
    require(extension.get(SANDBOX) is True, "Finder must be sandboxed")
    for key in ("network.client", "files.user-selected.read-only", "files.bookmarks.app-scope"):
        require(main.get("com.apple.security." + key) is True, "Missing main entitlement: " + key)
    for values in (main, extension):
        require(values.get(GROUP_KEY) == [group], "App Groups must match the configured identifier")
        require(not values.get("get-task-allow"), "Distribution must not permit debugging")
        for key in values:
            require(not key.startswith("com.apple.security.temporary-exception"), "Temporary sandbox exception: " + key)
            require(key not in {
                "com.apple.security.network.server", "com.apple.security.files.user-selected.read-write",
                "com.apple.security.files.all", "com.apple.security.device.camera", "com.apple.security.device.audio-input",
            }, "Unexpected permission: " + key)
    extension_permissions = {k for k in extension if k.startswith("com.apple.security.")}
    require(extension_permissions == {SANDBOX, GROUP_KEY}, "Finder must have no network or attachment access entitlement")


def check_privacy(main_path, extension_path):
    main, extension = plist(main_path), plist(extension_path)
    require(main.get("NSPrivacyTracking") is False, "Tracking must remain disabled")
    entries = main.get("NSPrivacyCollectedDataTypes", [])
    require({e["NSPrivacyCollectedDataType"] for e in entries}
            == {"NSPrivacyCollectedDataType" + name for name in DATA_TYPES}, "Unexpected privacy data categories")
    for entry in entries:
        require(entry.get("NSPrivacyCollectedDataTypeLinked") is True, "Account data is linked to identity")
        require(entry.get("NSPrivacyCollectedDataTypeTracking") is False, "Data must not be used for tracking")
        require(entry.get("NSPrivacyCollectedDataTypePurposes") == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"],
                "Only app functionality is declared")
    require(extension.get("NSPrivacyTracking") is False
            and not extension.get("NSPrivacyCollectedDataTypes"), "Finder must not collect data")
    for manifest in (main, extension):
        reasons = {e["NSPrivacyAccessedAPIType"]: e["NSPrivacyAccessedAPITypeReasons"]
                   for e in manifest.get("NSPrivacyAccessedAPITypes", [])}
        require(reasons.get("NSPrivacyAccessedAPICategoryUserDefaults") == ["CA92.1"], "Check preferences API reason")
        require("C617.1" in reasons.get("NSPrivacyAccessedAPICategoryFileTimestamp", []), "Check file timestamp API reason")


def run(*args):
    result = subprocess.run(args, capture_output=True, check=True)
    return result.stdout


def signed_entitlements(path):
    return plistlib.loads(run("codesign", "-d", "--entitlements", ":-", str(path)))


def check_archive(archive):
    app = archive / "Products/Applications/FileMailer.app"
    extension = app / "Contents/PlugIns/FileMailer Finder Extension.appex"
    info, extension_info = plist(app / "Contents/Info.plist"), plist(extension / "Contents/Info.plist")
    group = info["FileMailerApplicationGroupIdentifier"]
    require("$(" not in group, "Unexpanded group identifier")
    require(extension_info.get("FileMailerApplicationGroupIdentifier") == group, "Finder Info.plist group mismatch")
    main_entitlements, extension_entitlements = signed_entitlements(app), signed_entitlements(extension)
    check_entitlements(main_entitlements, extension_entitlements, group)
    require(group == main_entitlements["com.apple.developer.team-identifier"] + "."
            + info["CFBundleIdentifier"] + ".shared", "Unexpected group namespace")
    for target, target_info, entitlements in (
        (app, info, main_entitlements), (extension, extension_info, extension_entitlements)
    ):
        run("codesign", "--verify", "--strict", str(target))
        architectures = run("lipo", "-archs", str(target / "Contents/MacOS" / target_info["CFBundleExecutable"])).decode().split()
        require(set(architectures) == {"arm64", "x86_64"}, "Store binaries must be universal")
        profile = plistlib.loads(run("security", "cms", "-D", "-i", str(target / "Contents/embedded.provisionprofile")))
        allowed = profile["Entitlements"].get(GROUP_KEY, [])
        require(any(fnmatch.fnmatchcase(group, pattern) for pattern in allowed), "Provisioning profile does not authorize App Groups")
        require(not profile["Entitlements"].get("get-task-allow"), "Development provisioning profile in archive")
        require(target_info["CFBundleVersion"] == info["CFBundleVersion"]
                and target_info["CFBundleShortVersionString"] == info["CFBundleShortVersionString"], "Extension version mismatch")
    check_privacy(app / "Contents/Resources/PrivacyInfo.xcprivacy", extension / "Contents/Resources/PrivacyInfo.xcprivacy")
    print("PASS: signed universal archive, profiles, sandbox, groups and privacy manifests")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    check_entitlements(plist(ROOT / "App/Resources/FileMailer.entitlements"),
                       plist(ROOT / "FinderExtension/FinderExtension.entitlements"), "$(FILEMAILER_APP_GROUP)")
    check_privacy(ROOT / "App/Resources/PrivacyInfo.xcprivacy", ROOT / "FinderExtension/Resources/PrivacyInfo.xcprivacy")
    catalog = json.loads((ROOT / "App/Resources/Localizable.xcstrings").read_text())
    require(catalog["sourceLanguage"] == "en", "Source localization must be English")
    for path in ("App/Resources/Info.plist", "FinderExtension/Info.plist"):
        require(plist(ROOT / path).get("FileMailerApplicationGroupIdentifier") == "$(FILEMAILER_APP_GROUP)", "Missing Info.plist group")
    print("PASS: store source configuration and privacy declarations")
    if args.archive:
        check_archive(args.archive.resolve())


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit("FAIL: " + str(error))
