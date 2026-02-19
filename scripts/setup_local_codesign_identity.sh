#!/bin/zsh
set -euo pipefail

# Creates and imports a self-signed code signing identity into the login keychain.
# This helps keep macOS TCC permissions (eg. Accessibility) stable across rebuilds.

NAME="CopyToAsk Local Dev"
WORKDIR="$(mktemp -d)"

cleanup() {
  rm -rf "$WORKDIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Working in: $WORKDIR"

cat >"$WORKDIR/openssl.cnf" <<'EOF'
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
distinguished_name = dn
x509_extensions    = v3

[ dn ]
CN = CopyToAsk Local Dev
O  = CopyToAsk

[ v3 ]
basicConstraints = critical,CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
  -days 3650 \
  -config "$WORKDIR/openssl.cnf" \
  -keyout "$WORKDIR/key.pem" \
  -out "$WORKDIR/cert.pem" \
  >/dev/null 2>&1

openssl pkcs12 -export \
  -inkey "$WORKDIR/key.pem" \
  -in "$WORKDIR/cert.pem" \
  -name "$NAME" \
  -passout pass: \
  -out "$WORKDIR/codesign.p12" \
  >/dev/null 2>&1

echo "Importing identity into login keychain (no password)…"
security import "$WORKDIR/codesign.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "" -T /usr/bin/codesign >/dev/null

echo "Done. Available identities:"
security find-identity -v -p codesigning | sed -n '1,20p'

echo
echo "Next:"
echo "  export COPYTOASK_CODESIGN_IDENTITY=\"$NAME\""
echo "  ./build.sh"
