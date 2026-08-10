#!/bin/zsh
# Builds the SwiftPM executable and wraps it into a proper MagicBind.app
# bundle (needed so macOS TCC can grant Accessibility permission reliably,
# and so the menu-bar-only / no-Dock-icon behavior from Info.plist applies).
#
# Usage:
#   ./Scripts/build_app.sh              # native arch, fast — for local work
#   ./Scripts/build_app.sh --universal  # arm64 + x86_64 — for sharing with testers
set -e

cd "$(dirname "$0")/.."

UNIVERSAL=0
[[ "${1:-}" == "--universal" ]] && UNIVERSAL=1

VERSION="$(tr -d '[:space:]' < VERSION)"
# CFBundleVersion has to increase monotonically, and the commit count does that
# for free. The short SHA goes in a custom key so a tester's bug report can name
# the exact build.
if git rev-parse --git-dir >/dev/null 2>&1; then
  BUILD_NUMBER="$(git rev-list --count HEAD)"
  GIT_SHA="$(git rev-parse --short HEAD)"
  git diff --quiet HEAD 2>/dev/null || GIT_SHA="${GIT_SHA}-dirty"
else
  BUILD_NUMBER="0"
  GIT_SHA="unknown"
fi

APP="build/MagicBind.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

if [[ $UNIVERSAL -eq 1 ]]; then
  # `swift build --arch arm64 --arch x86_64` needs xcbuild, which only ships
  # with full Xcode. Building each slice and lipo-ing them works with Command
  # Line Tools alone.
  echo "==> Building universal (arm64 + x86_64)..."
  swift build -c release --triple arm64-apple-macosx13.0
  swift build -c release --triple x86_64-apple-macosx13.0
  lipo -create -output "$APP/Contents/MacOS/MagicBind" \
    ".build/arm64-apple-macosx/release/MagicBind" \
    ".build/x86_64-apple-macosx/release/MagicBind"
else
  echo "==> Building (release, native arch)..."
  swift build -c release
  cp ".build/release/MagicBind" "$APP/Contents/MacOS/MagicBind"
fi

cp "Resources/Info.plist" "$APP/Contents/Info.plist"

echo "==> Stamping version $VERSION ($BUILD_NUMBER, $GIT_SHA)..."
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :MagicBindGitSHA string $GIT_SHA" "$PLIST"

echo "==> Ad-hoc signing..."
# Ad-hoc is fine for a build you run yourself. It is NOT fine for handing to
# someone else: Gatekeeper rejects it on download and they have to override it
# manually. See docs/TESTING.md and SECURITY.md.
codesign --force --deep --sign - "$APP"

echo "==> Done: $APP"
echo "    version $VERSION ($GIT_SHA), arch: $(lipo -archs "$APP/Contents/MacOS/MagicBind")"
echo
echo "Open it once from Finder, then grant Accessibility access when prompted"
echo "(System Settings -> Privacy & Security -> Accessibility)."
