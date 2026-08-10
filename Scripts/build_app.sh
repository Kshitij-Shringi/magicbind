#!/bin/zsh
# Builds the SwiftPM executable and wraps it into a proper MagicBind.app
# bundle (needed so macOS TCC can grant Accessibility permission reliably,
# and so the menu-bar-only / no-Dock-icon behavior from Info.plist applies).
set -e

cd "$(dirname "$0")/.."

echo "==> Building (release)..."
swift build -c release

APP="build/MagicBind.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp ".build/release/MagicBind" "$APP/Contents/MacOS/MagicBind"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

echo "==> Ad-hoc signing (fine for local use; use a Developer ID cert to distribute to others)..."
codesign --force --deep --sign - "$APP"

echo "==> Done: $APP"
echo "Open it once from Finder, then grant Accessibility access when prompted"
echo "(System Settings -> Privacy & Security -> Accessibility)."
