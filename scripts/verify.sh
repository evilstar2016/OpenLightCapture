#!/bin/bash
set -euo pipefail

verification_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$verification_root"
for verification_tool in xcodegen swiftformat xcodebuild xcrun codesign lipo plutil; do
    if ! command -v "$verification_tool" >/dev/null 2>&1; then
        printf 'Missing required tool: %s\n' "$verification_tool" >&2
        exit 1
    fi
done

verification_output="$verification_root/build/verification/$(date +%Y%m%d-%H%M%S)-$$"
verification_derived="$verification_root/build/verification/DerivedData"
verification_result="$verification_output/Tests.xcresult"
verification_app="$verification_root/build/DerivedData/Build/Products/Release/OpenLightCapture.app"
mkdir -p "$verification_output"

run_check() {
    local verification_phase="$1"
    shift
    printf '%s...\n' "$verification_phase"
    if ! "$@" >"$verification_output/$verification_phase.log" 2>&1; then
        tail -n 60 "$verification_output/$verification_phase.log" >&2
        printf 'Verification failed. Logs: %s\n' "$verification_output" >&2
        exit 1
    fi
}

run_check project xcodegen generate
run_check format swiftformat LightCapture LightCaptureTests --lint --swiftversion 6 --cache "$verification_output/swiftformat.cache"
run_check whitespace git diff --check
run_check localization-source python3 scripts/verify-localizations.py
run_check tests xcodebuild -project OpenLightCapture.xcodeproj -scheme OpenLightCapture \
    -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath "$verification_derived" -resultBundlePath "$verification_result" \
    -enableCodeCoverage YES test
run_check coverage xcrun xccov view --report "$verification_result"
run_check release xcodebuild -project OpenLightCapture.xcodeproj -scheme OpenLightCapture \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$verification_root/build/DerivedData" \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
run_check architecture-arm64 lipo "$verification_app/Contents/MacOS/OpenLightCapture" -verify_arch arm64
run_check architecture-x86_64 lipo "$verification_app/Contents/MacOS/OpenLightCapture" -verify_arch x86_64
run_check signature codesign --verify --deep --strict "$verification_app"
run_check metadata plutil -lint "$verification_app/Contents/Info.plist"
run_check localization-package python3 scripts/verify-localizations.py --app "$verification_app"
printf 'Verification passed. Results: %s\nRelease app: %s\n' "$verification_output" "$verification_app"
