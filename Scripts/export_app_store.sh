#!/bin/zsh
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root"
archive_path="${1:-build/FileMailer-AppStore.xcarchive}"
export_path="${2:-build/AppStore}"
python3 Scripts/check_app_store.py --archive "$archive_path"
mkdir -p "$export_path"
options_path="$export_path/ExportOptions.plist"

python3 - "$archive_path" "$options_path" <<'PY'
import plistlib
import subprocess
import sys
from pathlib import Path

app = Path(sys.argv[1]) / 'Products/Applications/FileMailer.app'
targets = [app, app / 'Contents/PlugIns/FileMailer Finder Extension.appex']
profiles = {}
for target in targets:
    info = plistlib.loads((target / 'Contents/Info.plist').read_bytes())
    profile = plistlib.loads(subprocess.check_output([
        'security', 'cms', '-D', '-i', str(target / 'Contents/embedded.provisionprofile')
    ], stderr=subprocess.DEVNULL))
    profiles[info['CFBundleIdentifier']] = profile['Name']
    team = profile['TeamIdentifier'][0]
options = {
    'method': 'app-store-connect', 'destination': 'export', 'teamID': team,
    'signingStyle': 'manual', 'signingCertificate': 'Apple Distribution',
    'installerSigningCertificate': '3rd Party Mac Developer Installer',
    'provisioningProfiles': profiles,
}
Path(sys.argv[2]).write_bytes(plistlib.dumps(options))
PY

DEVELOPER_DIR="${XCODE_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
    xcodebuild -exportArchive -archivePath "$archive_path" \
    -exportPath "$export_path" -exportOptionsPlist "$options_path"
pkgutil --check-signature "$export_path/FileMailer.pkg"
(cd "$export_path" && shasum -a 256 FileMailer.pkg > FileMailer.pkg.sha256)
