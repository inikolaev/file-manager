#!/bin/bash
set -euo pipefail
APP="${1:?Usage: notarize-app.sh path/to/App.app}"
: "${SIGNING_IDENTITY:?Developer ID signing identity is required}"
: "${NOTARY_KEYCHAIN:?Notarization credential keychain is required}"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/commander-notarize.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/submission.zip"
# Capture the submission ID immediately so even a timeout leaves a traceable request.
xcrun notarytool submit "$WORK/submission.zip" --keychain-profile commander-notary \
    --keychain "$NOTARY_KEYCHAIN" --output-format json > "$WORK/submission.json"
submission=$(jq -er .id "$WORK/submission.json")
printf 'Apple notarization submission: %s\n' "$submission"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf 'Apple notarization submission: `%s`\n' "$submission" >> "$GITHUB_STEP_SUMMARY"
fi
if ! xcrun notarytool wait "$submission" --keychain-profile commander-notary \
    --keychain "$NOTARY_KEYCHAIN" --timeout 40m --output-format json > "$WORK/result.json"; then
    echo "Notarization did not complete successfully; submission $submission remains available in Apple's history." >&2
    xcrun notarytool log "$submission" --keychain-profile commander-notary --keychain "$NOTARY_KEYCHAIN" || true
    exit 1
fi
status=$(jq -r .status "$WORK/result.json")
if [[ "$status" != Accepted ]]; then
    echo "Notarization was not accepted: $status" >&2
    xcrun notarytool log "$submission" --keychain-profile commander-notary --keychain "$NOTARY_KEYCHAIN" || true
    exit 1
fi
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict "$APP"
spctl --assess --type execute --verbose=2 "$APP"
