#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

bash scripts/build-app.sh --universal
APP="dist/universal/Commander.app"
if [[ "${NOTARIZE:-0}" == 1 ]]; then
    bash scripts/notarize-app.sh "$APP"
fi
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
NAME="Commander-$VERSION"
ARCHIVE="$PWD/dist/$NAME-macOS-universal.zip"
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/commander-package.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
mkdir "$STAGING/$NAME"
ditto "$APP" "$STAGING/$NAME/Commander.app"
cp LICENSE "$STAGING/$NAME/LICENSE"
if [[ "${NOTARIZE:-0}" == 1 ]]; then
    SIGNING_NOTICE="This app is Developer ID signed and notarized by Apple."
else
    SIGNING_NOTICE="This preview is not notarized. macOS may require System Settings > Privacy & Security > Open Anyway on first launch."
fi
cat > "$STAGING/$NAME/Read Me.txt" <<TEXT
Commander — macOS preview

Requires macOS 13 or later. Supports Apple silicon and Intel Macs.
No Xcode, Swift installation, or terminal is needed.

Drag Commander.app to Applications and open it.
$SIGNING_NOTICE

Controls
Tab: switch pane. Arrows: select. Enter: open folder. Backspace: parent.
Space: toggle selection. Shift+arrows: extend or shrink selection.
F3: view file. In viewer, F4 toggles hex; Escape returns to panes.
F5: copy selected files with confirmation. Existing files are never overwritten.
F6: move selected entries (or the current entry) to another location.
F7: create a directory in the active pane.
F8: move selected files or folders to Trash with confirmation.
With no selection, F5/F8 act on the current entry. Successful operations clear
selection. Changing directories also clears selection.
F10: quit. On some keyboards, hold Fn to use function keys.
The numbered footer buttons are clickable too.

This is an early preview. Folder copying is not implemented.
macOS may ask permission to access your folders.
TEXT
codesign --verify --deep --strict "$STAGING/$NAME/Commander.app"
ditto -c -k --sequesterRsrc --keepParent "$STAGING/$NAME" "$ARCHIVE"
# Use a relative filename so recipients can run shasum -a 256 -c beside the ZIP.
(cd dist && shasum -a 256 "$NAME-macOS-universal.zip" > "$NAME-macOS-universal.zip.sha256")
printf 'Packaged %s\n' "$ARCHIVE"
