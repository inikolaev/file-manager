#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

bash scripts/build-app.sh --universal
APP="dist/universal/Commander.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
NAME="Commander-$VERSION"
ARCHIVE="$PWD/dist/$NAME-macOS-universal.zip"
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/commander-package.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
mkdir "$STAGING/$NAME"
ditto "$APP" "$STAGING/$NAME/Commander.app"
cp LICENSE "$STAGING/$NAME/LICENSE"
cat > "$STAGING/$NAME/Read Me.txt" <<'TEXT'
Commander — macOS preview

Requires macOS 13 or later. Supports Apple silicon and Intel Macs.
No Xcode, Swift installation, or terminal is needed.

Drag Commander.app to Applications and open it.
This preview is ad-hoc signed, but not Developer ID signed or notarized.
If macOS blocks it, and you trust the sender, attempt to open it once,
then go to System Settings > Privacy & Security > Open Anyway.
Apple's instructions: https://support.apple.com/102445

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

This is an early preview. Folder copying and editing are not implemented.
macOS may ask permission to access your folders.
TEXT
codesign --verify --deep --strict "$STAGING/$NAME/Commander.app"
ditto -c -k --sequesterRsrc --keepParent "$STAGING/$NAME" "$ARCHIVE"
printf 'Packaged %s\n' "$ARCHIVE"
