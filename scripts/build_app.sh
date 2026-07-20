#!/usr/bin/env bash
# Builds GroqFlow.app from the SwiftPM release binary.
set -euo pipefail

# Resolve repo root from this script's location so it works from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="GroqFlow"
APP_DIR="dist/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RES_DIR="${CONTENTS}/Resources"
BIN_PATH=".build/release/${APP_NAME}"

echo "==> Building release binary"
swift build -c release

if [ ! -f "$BIN_PATH" ]; then
	echo "error: release binary not found at $BIN_PATH" >&2
	exit 1
fi

echo "==> Assembling ${APP_DIR}"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

cp "$BIN_PATH" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"
cp "${SCRIPT_DIR}/Info.plist" "${CONTENTS}/Info.plist"

# Sign with a stable self-signed identity so TCC permission grants (Microphone,
# Input Monitoring, Accessibility) persist across rebuilds. The designated
# requirement is pinned to this certificate's leaf, which does not change
# between builds. Falls back to ad-hoc if the identity is missing.
SIGN_IDENTITY="GroqFlow Local Dev"
if security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
	echo "==> Code signing with '${SIGN_IDENTITY}' (stable identity)"
	HASH="$(security find-certificate -c "$SIGN_IDENTITY" -Z 2>/dev/null | awk '/SHA-1/{print $3; exit}')"
	codesign -s "$HASH" --force --deep "$APP_DIR"
	echo ""
	echo "Done. App bundle: ${ROOT_DIR}/${APP_DIR}"
	echo ""
	echo "Signed with the stable '${SIGN_IDENTITY}' certificate. Permission grants"
	echo "persist across rebuilds; you only grant Microphone / Input Monitoring /"
	echo "Accessibility once."
else
	echo "==> Code signing (ad-hoc fallback; run scripts/setup_signing.sh for stable grants)"
	codesign -s - --force --deep "$APP_DIR"
	echo ""
	echo "Done. App bundle: ${ROOT_DIR}/${APP_DIR}"
	echo ""
	echo "WARNING: ad-hoc signed. Rebuilds reset TCC permission grants. Run"
	echo "scripts/setup_signing.sh once to create a stable signing identity."
fi
