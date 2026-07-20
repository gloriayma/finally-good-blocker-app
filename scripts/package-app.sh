#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
configuration="${1:-release}"
binary_name="FinallyGoodBlockerMac"
app_dir="$project_dir/build/finally-good-blocker.app"
contents_dir="$app_dir/Contents"
icon_work_dir="$(mktemp -d)"

cleanup() {
    rm -rf "$icon_work_dir"
}
trap cleanup EXIT

cd "$project_dir"
swift build -c "$configuration" --product "$binary_name"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$binary_dir/$binary_name" "$contents_dir/MacOS/$binary_name"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"

qlmanage -t -s 1024 -o "$icon_work_dir" "$project_dir/Resources/AppIcon.svg" >/dev/null 2>&1
source_png="$icon_work_dir/AppIcon.svg.png"
iconset_dir="$icon_work_dir/AppIcon.iconset"
mkdir -p "$iconset_dir"

sips -z 16 16 "$source_png" --out "$iconset_dir/icon_16x16.png" >/dev/null
sips -z 32 32 "$source_png" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$source_png" --out "$iconset_dir/icon_32x32.png" >/dev/null
sips -z 64 64 "$source_png" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$source_png" --out "$iconset_dir/icon_128x128.png" >/dev/null
sips -z 256 256 "$source_png" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$source_png" --out "$iconset_dir/icon_256x256.png" >/dev/null
sips -z 512 512 "$source_png" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$source_png" --out "$iconset_dir/icon_512x512.png" >/dev/null
cp "$source_png" "$iconset_dir/icon_512x512@2x.png"
iconutil -c icns "$iconset_dir" -o "$contents_dir/Resources/AppIcon.icns"

codesign --force --sign - --timestamp=none "$app_dir"

echo "$app_dir"
