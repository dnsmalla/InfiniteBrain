#!/usr/bin/env bash
# Builds InfiniteBrain.app and packages a .dmg.
# Mirrors the pattern used in ucp-demo/build_app.sh.
set -euo pipefail

APP_NAME="InfiniteBrain"
VERSION="$(cat VERSION)"
BUILD_DIR=".build/release"

swift build -c release
mkdir -p "${APP_NAME}.app/Contents/MacOS"
cp "${BUILD_DIR}/${APP_NAME}" "${APP_NAME}.app/Contents/MacOS/${APP_NAME}"

# TODO: Info.plist, code-signing, dmg packaging via create-dmg
echo "built ${APP_NAME}.app (version ${VERSION})"
