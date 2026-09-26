#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# CI supplies a calendar version; local builds retain a development default.
APP_VERSION="${APP_VERSION:-0.1.0}"
APP_BUILD_NUMBER="${APP_BUILD_NUMBER:-2}"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! "$APP_BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    printf 'APP_VERSION must contain three integers; APP_BUILD_NUMBER must be an integer.\n' >&2
    exit 2
fi
BUILD_ARGS=(-c release)
APP="dist/Commander.app"
if [[ "${1:-}" == "--universal" && $# == 1 ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
    APP="dist/universal/Commander.app"
elif [[ $# != 0 ]]; then
    printf 'Usage: %s [--universal]\n' "$0" >&2
    exit 2
fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp Assets/Commander.icns "$APP/Contents/Resources/Commander.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp THIRD-PARTY-NOTICES.txt "$APP/Contents/Resources/THIRD-PARTY-NOTICES.txt"
cp "$BIN_DIR/Commander" "$APP/Contents/MacOS/Commander"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>Commander</string>
    <key>CFBundleIdentifier</key><string>local.commander.filemanager</string>
    <key>CFBundleName</key><string>Commander</string>
    <key>CFBundleDisplayName</key><string>Commander</string>
    <key>CFBundleIconFile</key><string>Commander.icns</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
    <key>CFBundleVersion</key><string>$APP_BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf 'Built %s/%s\n' "$PWD" "$APP"
