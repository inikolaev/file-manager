#!/bin/bash
set -euo pipefail
# Secrets are passed through the environment, never interpolated into workflow code.
for name in APPLE_CERTIFICATE_P12_BASE64 APPLE_CERTIFICATE_PASSWORD APPLE_ID APPLE_TEAM_ID APPLE_APP_SPECIFIC_PASSWORD RUNNER_TEMP GITHUB_ENV; do
    if [[ -z "${!name:-}" ]]; then
        printf 'Missing required setting: %s\n' "$name" >&2
        exit 1
    fi
done
KEYCHAIN_PATH="$RUNNER_TEMP/commander-signing.keychain-db"
CERTIFICATE_PATH="$RUNNER_TEMP/commander-certificate.p12"
KEYCHAIN_PASSWORD=$(openssl rand -hex 32)
echo "::add-mask::$KEYCHAIN_PASSWORD"
umask 077
trap 'rm -f "$CERTIFICATE_PATH"' EXIT
printf '%s' "$APPLE_CERTIFICATE_P12_BASE64" | base64 --decode > "$CERTIFICATE_PATH"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERTIFICATE_PATH" -P "$APPLE_CERTIFICATE_PASSWORD" -t cert -f pkcs12 -k "$KEYCHAIN_PATH" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" > /dev/null
security list-keychains -d user -s "$KEYCHAIN_PATH" "$HOME/Library/Keychains/login.keychain-db"
# Select exactly one Developer ID Application identity from the imported keychain.
identity=$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | awk '/"Developer ID Application:/ {print $2}')
if [[ ! "$identity" =~ ^[A-Fa-f0-9]{40}$ ]]; then
    echo 'Expected exactly one valid Developer ID Application certificate with its private key.' >&2
    exit 1
fi
xcrun notarytool store-credentials commander-notary --keychain "$KEYCHAIN_PATH" \
    --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD"
printf 'SIGNING_IDENTITY=%s\nNOTARY_KEYCHAIN=%s\n' "$identity" "$KEYCHAIN_PATH" >> "$GITHUB_ENV"
