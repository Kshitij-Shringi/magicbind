#!/bin/zsh
# Builds a universal MagicBind.app and packages it as a zip for testers, with a
# SHA-256 checksum so they can verify what they downloaded is what you built.
#
#   ./Scripts/package_release.sh
#
# The result is ad-hoc signed, NOT notarized, so Gatekeeper will reject it on
# the tester's machine and they'll have to clear the quarantine flag by hand.
# docs/TESTING.md walks them through it. If you get an Apple Developer Program
# membership, replace the ad-hoc signing in build_app.sh with a Developer ID
# signature plus `xcrun notarytool submit` and this friction disappears.
set -e

cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"

if ! git diff --quiet HEAD 2>/dev/null; then
  echo "!! Working tree is dirty. Testers will report against a build you"
  echo "   cannot reconstruct from a commit. Commit or stash first."
  echo
  printf "   Continue anyway? [y/N] "
  read -r reply
  [[ "$reply" == "y" || "$reply" == "Y" ]] || exit 1
fi

./Scripts/build_app.sh --universal

DIST="dist"
NAME="MagicBind-${VERSION}"
ARCHIVE="${DIST}/${NAME}.zip"

rm -rf "$DIST"
mkdir -p "$DIST"

echo "==> Packaging $ARCHIVE..."
# ditto rather than `zip` so the bundle's symlinks, resource forks, and code
# signature survive the round trip. A zip made with `zip -r` can invalidate the
# signature.
ditto -c -k --sequesterRsrc --keepParent "build/MagicBind.app" "$ARCHIVE"

echo "==> Checksum..."
shasum -a 256 "$ARCHIVE" | tee "${ARCHIVE}.sha256"

SIZE="$(du -h "$ARCHIVE" | cut -f1)"

cat <<EOF

==> Done.

  $ARCHIVE  ($SIZE)
  ${ARCHIVE}.sha256

Share it, e.g. as a GitHub pre-release:

  gh release create v${VERSION} \\
    --prerelease \\
    --title "MagicBind ${VERSION} (test build)" \\
    --notes-file docs/TESTING.md \\
    "$ARCHIVE" "${ARCHIVE}.sha256"

Point testers at docs/TESTING.md. They MUST clear the quarantine flag:

  xattr -dr com.apple.quarantine /Applications/MagicBind.app

EOF
