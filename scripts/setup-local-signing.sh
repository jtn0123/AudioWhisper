#!/bin/bash
# One machine-local signing key gives development builds a persistent identity.
# It grants no app permissions and changes no system certificate trust settings.
set -euo pipefail
umask 077

identity_name="AudioWhisper Rebuild Local Development"
existing_identity=$(security find-identity -p codesigning | awk -v name="$identity_name" 'index($0, "\"" name "\"") {print $2; exit}')
if [ -n "$existing_identity" ]; then
  echo "$existing_identity"
  exit 0
fi

signing_temp=$(mktemp -d "${TMPDIR:-/tmp}/audiowhisper-signing.XXXXXX")
trap 'rm -rf "$signing_temp"' EXIT
openssl rand -hex 32 > "$signing_temp/password"
cat > "$signing_temp/certificate.cnf" <<'EOF'
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
CN = AudioWhisper Rebuild Local Development
[extensions]
basicConstraints = critical,CA:true
keyUsage = critical,digitalSignature,keyCertSign
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF
openssl req -new -x509 -newkey rsa:3072 -nodes -days 1825 \
  -config "$signing_temp/certificate.cnf" -keyout "$signing_temp/key.pem" \
  -out "$signing_temp/certificate.pem" >/dev/null 2>&1
openssl pkcs12 -export -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -inkey "$signing_temp/key.pem" -in "$signing_temp/certificate.pem" \
  -out "$signing_temp/identity.p12" -passout "file:$signing_temp/password"
keychain_path=$(security default-keychain -d user | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')
security import "$signing_temp/identity.p12" -k "$keychain_path" \
  -P "$(cat "$signing_temp/password")" -T /usr/bin/codesign >/dev/null
identity_hash=$(security find-identity -p codesigning | awk -v name="$identity_name" 'index($0, "\"" name "\"") {print $2; exit}')
if [ -z "$identity_hash" ]; then
  echo "Local signing identity could not be installed in the user keychain." >&2
  exit 1
fi
echo "$identity_hash"
