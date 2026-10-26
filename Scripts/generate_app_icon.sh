#!/bin/zsh
set -euo pipefail

source_png="${1:-Design/FileMailerIcon.png}"
destination="${2:-App/Resources/Assets.xcassets/AppIcon.appiconset}"

if [[ ! -f "$source_png" ]]; then
  print -u2 "Icon export not found: $source_png"
  print -u2 "Export FileMail.icon from Icon Composer as a 1024pt default image first."
  exit 66
fi

mkdir -p "$destination"

for size in 16 32 64 128 256 512 1024; do
  case "$size" in
    16|128|256|512)
      output="$destination/icon_${size}x${size}.png"
      ;;
    32)
      output="$destination/icon_16x16@2x.png"
      ;;
    64)
      output="$destination/icon_32x32@2x.png"
      ;;
    1024)
      output="$destination/icon_512x512@2x.png"
      ;;
  esac
  /usr/bin/sips -z "$size" "$size" "$source_png" --out "$output" >/dev/null
done

/bin/cp "$destination/icon_16x16@2x.png" "$destination/icon_32x32.png"
/bin/cp "$destination/icon_256x256.png" "$destination/icon_128x128@2x.png"
/bin/cp "$destination/icon_512x512.png" "$destination/icon_256x256@2x.png"
