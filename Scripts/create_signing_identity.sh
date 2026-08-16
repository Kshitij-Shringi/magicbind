#!/bin/zsh
# Creates a local self-signed code-signing certificate, so rebuilt copies of
# MagicBind keep their Accessibility permission.
#
# Why this exists: an ad-hoc signature (`codesign --sign -`) produces a cdhash
# derived from the binary, and macOS TCC keys the Accessibility grant on that
# hash. Every rebuild therefore looks like a brand-new app and silently loses
# the permission — gestures keep being recognized while every action does
# nothing, which is a genuinely confusing failure. Signing with a stable
# certificate gives the app a stable identity, and the grant survives rebuilds.
#
#   ./Scripts/create_signing_identity.sh   # once
#   ./Scripts/build_app.sh                 # picks it up automatically
set -e

NAME="MagicBind Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "==> '$NAME' already exists. Nothing to do."
  security find-identity -v -p codesigning | grep "$NAME"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Generating a self-signed code-signing certificate..."
cat > "$TMP/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no

[dn]
CN = $NAME

[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 3650 -config "$TMP/openssl.cnf" 2>/dev/null

openssl pkcs12 -export -legacy \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/identity.p12" -passout pass: 2>/dev/null \
  || openssl pkcs12 -export \
       -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
       -out "$TMP/identity.p12" -passout pass:

echo "==> Importing into the login keychain..."
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "" \
  -T /usr/bin/codesign -T /usr/bin/security

echo "==> Trusting it for code signing..."
echo "    (macOS will ask for your login password — this edits your keychain"
echo "     trust settings, nothing system-wide.)"
security add-trusted-cert -d -r trustAsRoot -p codeSign \
  -k "$KEYCHAIN" "$TMP/cert.pem" || {
    echo
    echo "!! Could not set trust automatically."
    echo "   Open Keychain Access, find '$NAME' under login > My Certificates,"
    echo "   double-click it, expand Trust, and set 'Code Signing' to 'Always Trust'."
  }

echo
echo "==> Done. Verify with:"
echo "     security find-identity -v -p codesigning"
echo
echo "   Then rebuild:  ./Scripts/build_app.sh"
echo "   Grant Accessibility once more, and it will stick across rebuilds."
