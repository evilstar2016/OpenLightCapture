#!/bin/bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")/.." && pwd)"
package_app="${1:-$package_root/build/DerivedData/Build/Products/Release/OpenLightCapture.app}"
package_plist="$package_app/Contents/Info.plist"
package_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$package_plist")"
package_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$package_plist")"
package_output="${2:-$package_root/build/OpenLightCapture-$package_version-macOS-universal.dmg}"

if [[ "$package_identifier" != "io.github.evilstar2016.openlightcapture" ]]; then
    printf 'Expected the OpenLightCapture application identity.\n' >&2
    exit 1
fi
if [[ -e "$package_output" ]]; then
    printf 'Output already exists: %s\n' "$package_output" >&2
    exit 1
fi
codesign --verify --deep --strict "$package_app"
lipo "$package_app/Contents/MacOS/OpenLightCapture" -verify_arch arm64
lipo "$package_app/Contents/MacOS/OpenLightCapture" -verify_arch x86_64
python3 "$package_root/scripts/verify-localizations.py" --app "$package_app"

mkdir -p "$package_root/build" "$(dirname "$package_output")"
package_stage="$(mktemp -d "$package_root/build/dmg-stage.XXXXXX")"
trap 'rm -rf "$package_stage"' EXIT
mkdir "$package_stage/contents"
ditto "$package_app" "$package_stage/contents/OpenLightCapture.app"
ln -s /Applications "$package_stage/contents/Applications"
cp "$package_root/LICENSE" "$package_root/THIRD_PARTY_NOTICES.md" "$package_root/PRIVACY.md" "$package_stage/contents/"
git -C "$package_root" rev-parse HEAD > "$package_stage/contents/SOURCE-COMMIT.txt"

hdiutil create -volname "OpenLightCapture $package_version" \
    -srcfolder "$package_stage/contents" -fs HFS+ -format UDZO "$package_stage/package.dmg"
hdiutil verify "$package_stage/package.dmg"
mv "$package_stage/package.dmg" "$package_output"
(
    cd "$(dirname "$package_output")"
    shasum -a 256 "$(basename "$package_output")" > "$(basename "$package_output").sha256"
)
printf 'DMG: %s\nChecksum: %s.sha256\n' "$package_output" "$package_output"
