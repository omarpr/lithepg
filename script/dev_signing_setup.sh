#!/bin/bash
# Creates a persistent self-signed code-signing identity ("LithePG Local Dev")
# so local dev builds keep a stable code signature across rebuilds.
#
# Why: ad-hoc signed builds get a new signature every rebuild, so macOS treats
# each build as a different app and re-prompts for Keychain access to saved
# passwords. With a stable identity, one "Always Allow" per item sticks.
#
# Run once, interactively (it may ask for your login password to trust the
# certificate and unlock the signing key):
#   ./script/dev_signing_setup.sh
#
# Afterwards ./script/build_and_run.sh --package picks the identity up
# automatically. This is for LOCAL builds only; public releases still require
# the Apple Developer identity path in script/sign_and_notarize.sh.
set -euo pipefail

IDENTITY_NAME="LithePG Local Dev"
SECURITY=/usr/bin/security
OPENSSL=/usr/bin/openssl

if "$SECURITY" find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY_NAME"; then
  echo "Identity \"$IDENTITY_NAME\" already exists. Nothing to do."
  exit 0
fi

workdir="$(mktemp -d "${TMPDIR:-/tmp}/lithepg-dev-signing.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

echo "Generating self-signed code-signing certificate..."
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$workdir/key.pem" -out "$workdir/cert.pem" \
  -subj "/CN=$IDENTITY_NAME" \
  -addext "keyUsage=digitalSignature" \
  -addext "extendedKeyUsage=codeSigning" >/dev/null 2>&1

"$OPENSSL" pkcs12 -export -passout pass:lithepg-dev \
  -inkey "$workdir/key.pem" -in "$workdir/cert.pem" -out "$workdir/dev.p12"

echo "Importing into the login keychain..."
"$SECURITY" import "$workdir/dev.p12" -P lithepg-dev -T /usr/bin/codesign

echo "Marking the certificate trusted for code signing (may prompt)..."
"$SECURITY" add-trusted-cert -p codeSign "$workdir/cert.pem"

cat <<'DONE'

Done. Next steps:
  1. Rebuild the app: ./script/build_and_run.sh --package
  2. Open dist/LithePG.app and connect to a saved connection.
  3. When the Keychain prompt appears, click "Always Allow" once per saved
     password. Because the signature is now stable, that choice persists
     across rebuilds.

If codesign reports it cannot use the key, allow it once with:
  security set-key-partition-list -S apple-tool:,apple: -s ~/Library/Keychains/login.keychain-db
DONE
