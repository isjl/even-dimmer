#!/bin/bash
# Builds "Even Dimmer.app" (universal: Apple Silicon + Intel) and a zip.
#
# Usage:
#   scripts/build-app.sh
#
# Environment (all optional):
#   SIGN_ID             Code-signing identity. Default "-" (ad-hoc). A stable identity,
#                       even a self-signed one, keeps macOS permissions across updates.
#   HARDENED_RUNTIME=1  Sign with the hardened runtime (needed for notarization).
#   SPARKLE_PUBLIC_KEY  EdDSA public key for auto-updates (scripts/release.sh sets it).
#                       Without it the build has updates switched off.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Even Dimmer.app"
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/EvenDimmer"
SPARKLE="$(find .build/artifacts -path '*macos-arm64_x86_64/Sparkle.framework' -maxdepth 6 | head -1)"
[ -d "$SPARKLE" ] || { echo "Sparkle.framework not found; run 'swift package resolve'"; exit 1; }

rm -rf "$APP" build/EvenDimmer.zip
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/EvenDimmer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/" || true
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"

if [ -n "${SPARKLE_PUBLIC_KEY:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_KEY" "$APP/Contents/Info.plist"
else
  echo "note: SPARKLE_PUBLIC_KEY not set, so this build has auto-updates switched off"
fi

# Sign inside-out: Sparkle's helpers, the framework, then the app.
# The hardened runtime is only needed for notarization (HARDENED_RUNTIME=1, with a
# Developer ID in SIGN_ID). Without a team ID it would refuse to load Sparkle.
SIGN=(codesign --force --timestamp=none --sign "${SIGN_ID:--}")
[ "${HARDENED_RUNTIME:-0}" = "1" ] && SIGN+=(--options runtime)
FW="$APP/Contents/Frameworks/Sparkle.framework"
for item in "$FW/Versions/B/XPCServices/Installer.xpc" "$FW/Versions/B/XPCServices/Downloader.xpc" \
            "$FW/Versions/B/Autoupdate" "$FW/Versions/B/Updater.app"; do
  [ -e "$item" ] && "${SIGN[@]}" "$item"
done
"${SIGN[@]}" "$FW"
"${SIGN[@]}" "$APP"

(cd build && ditto -c -k --keepParent "Even Dimmer.app" "EvenDimmer.zip")
echo "Built $APP and build/EvenDimmer.zip"
