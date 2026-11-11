#!/bin/bash
# Builds a release: bumps the version, builds a signed-for-Sparkle zip, writes the
# appcast (the update feed), and updates the Homebrew cask.
#
# Usage:
#   scripts/release.sh 1.1.0             # build everything into build/release/ and show next steps
#   scripts/release.sh 1.1.0 --publish   # ...and create the GitHub release with `gh`
#
# One-time setup: create the update-signing key (stored in your login keychain):
#   .build/artifacts/sparkle/Sparkle/bin/generate_keys
# Keep it safe. Every future update must be signed with the same key.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version> [--publish]}"
PUBLISH="${2:-}"
REPO="${GITHUB_REPO:-isjl/even-dimmer}"
PLIST=Resources/Info.plist
CASK=packaging/homebrew/even-dimmer.rb

swift package resolve >/dev/null
TOOLS="$(dirname "$(find .build/artifacts -path '*Sparkle/bin/generate_keys' -maxdepth 5 | head -1)")"
PUBLIC_KEY="$("$TOOLS/generate_keys" -p 2>/dev/null)" || {
  echo "No Sparkle signing key found in your keychain. Create one once with:"
  echo "  $TOOLS/generate_keys"
  exit 1
}

# 1. Version: marketing version from the argument, build number +1.
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST") + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
echo "Version $VERSION (build $BUILD)"

# 2. Build with the update key baked in.
SPARKLE_PUBLIC_KEY="$PUBLIC_KEY" scripts/build-app.sh

# 3. Release folder: the zip and an appcast that points at this release's download.
OUT=build/release
rm -rf "$OUT" && mkdir -p "$OUT"
ZIP="EvenDimmer-$VERSION.zip"
cp build/EvenDimmer.zip "$OUT/$ZIP"
"$TOOLS/generate_appcast" \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  -o "$OUT/appcast.xml" "$OUT"

# 4. Homebrew cask: new version and checksum.
SHA="$(shasum -a 256 "$OUT/$ZIP" | cut -d' ' -f1)"
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 .*/  sha256 \"$SHA\"/" "$CASK"

echo
echo "Release files are in $OUT/:"
ls -1 "$OUT"

if [ "$PUBLISH" = "--publish" ]; then
  gh release create "v$VERSION" "$OUT/$ZIP" "$OUT/appcast.xml" \
    --repo "$REPO" --title "Even Dimmer $VERSION" --generate-notes
  echo "Published https://github.com/$REPO/releases/tag/v$VERSION"
else
  echo
  echo "Next steps:"
  echo "  1. Commit the version bump and cask update, then push."
  echo "  2. Publish:  gh release create v$VERSION $OUT/$ZIP $OUT/appcast.xml --repo $REPO --generate-notes"
fi
echo "  3. Copy $CASK into your tap repo (github.com/${REPO%%/*}/homebrew-tap, folder Casks/) and push."
