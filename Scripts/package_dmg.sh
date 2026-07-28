#!/bin/zsh

set -euo pipefail

if [[ "$#" -ne 2 ]]; then
    print -u2 "Usage: $0 /path/to/FileMailer.app /path/to/FileMailer.dmg"
    exit 64
fi

app_path="$1"
output_path="$2"

if [[ ! -d "$app_path" ]]; then
    print -u2 "Application bundle not found: $app_path"
    exit 66
fi

staging_dir="$(mktemp -d /private/tmp/FileMailerDMG.XXXXXX)"
output_dir="$(mktemp -d /private/tmp/FileMailerDMGOutput.XXXXXX)"

cleanup() {
    rm -rf "$staging_dir" "$output_dir"
}
trap cleanup EXIT

ditto "$app_path" "$staging_dir/FileMailer.app"
ln -s /Applications "$staging_dir/Applications"

diskutil image create from \
    --volumeName FileMailer \
    --format UDZO \
    "$staging_dir" \
    "$output_dir/FileMailer.dmg"

mkdir -p "${output_path:h}"
mv -f "$output_dir/FileMailer.dmg" "$output_path"
