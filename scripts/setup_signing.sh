#!/usr/bin/env bash
# One-time: import the stable self-signed code-signing identity into the login
# keychain so GroqFlow rebuilds keep the same signature and macOS does not reset
# Microphone / Input Monitoring / Accessibility grants on every rebuild.
#
# Signing only needs the private key, not a trust setting, so this runs without
# an admin prompt. The p12 password is "groqflow" (local dev cert, not a secret).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P12="${SCRIPT_DIR}/signing/groqflow-identity.p12"
NAME="GroqFlow Local Dev"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if [ ! -f "$P12" ]; then
	echo "error: identity not found at $P12" >&2
	exit 1
fi

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
	echo "Identity '${NAME}' already imported. Nothing to do."
	exit 0
fi

echo "==> Importing '${NAME}' into login keychain"
security import "$P12" -k "$KEYCHAIN" -P groqflow -T /usr/bin/codesign -A

echo "Done. Rebuild with scripts/build_app.sh; grants now persist across rebuilds."
