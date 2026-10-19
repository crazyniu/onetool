#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
: "${RUNNER_TEMP:?Only use on an ephemeral CI runner}"
: "${DEVELOPER_ID_CERTIFICATE_BASE64:?Missing DEVELOPER_ID_CERTIFICATE_BASE64}"
: "${DEVELOPER_ID_CERTIFICATE_PASSWORD:?Missing DEVELOPER_ID_CERTIFICATE_PASSWORD}"
: "${NOTARY_API_KEY_BASE64:?Missing NOTARY_API_KEY_BASE64}"
: "${NOTARY_KEY_ID:?Missing NOTARY_KEY_ID}"
: "${NOTARY_ISSUER_ID:?Missing NOTARY_ISSUER_ID}"
umask 077
KEYCHAIN="$RUNNER_TEMP/onetool-signing.keychain-db"
P12="$RUNNER_TEMP/onetool-signing.p12"
NOTARY_KEY_PATH="$RUNNER_TEMP/onetool-notary.p8"
KEYCHAIN_PASSWORD=$(openssl rand -hex 32)
# The caller's always() cleanup also handles partially completed imports.
printf '%s' "$DEVELOPER_ID_CERTIFICATE_BASE64" | base64 --decode > "$P12"
printf '%s' "$NOTARY_API_KEY_BASE64" | base64 --decode > "$NOTARY_KEY_PATH"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$P12" -P "$DEVELOPER_ID_CERTIFICATE_PASSWORD" -k "$KEYCHAIN" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db"
IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN" | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)
[[ -n "$IDENTITY" ]] || { echo 'The P12 must contain a valid Developer ID Application certificate and its private key.' >&2; exit 1; }
rm -f "$P12"
printf 'CODE_SIGN_IDENTITY=%s\nNOTARY_KEY_PATH=%s\n' "$IDENTITY" "$NOTARY_KEY_PATH" >> "$GITHUB_ENV"
