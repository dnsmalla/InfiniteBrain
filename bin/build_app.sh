#!/usr/bin/env bash
# Builds InfiniteBrain.app and (optionally) a distributable .dmg.
#
# Usage:
#   bin/build_app.sh                # produces InfiniteBrain.app + infb in .build/dist
#   bin/build_app.sh --dmg          # also produces InfiniteBrain.dmg
#   bin/build_app.sh --sign IDENTITY  # codesigns with the given identity
#                                   # (default is ad-hoc "-")
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="InfiniteBrain"
CLI_NAME="infb"
BUNDLE_ID="co.infinitebrain.app"
VERSION="$(cat VERSION)"
RELEASE_DIR=".build/release"
DIST_DIR=".build/dist"
RESOURCE_BUNDLE="InfiniteBrain_InfiniteBrainCore.bundle"
SIGN_IDENTITY="-"   # ad-hoc; pass --sign to override
MAKE_DMG=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dmg)  MAKE_DMG=1 ;;
        --sign) SIGN_IDENTITY="$2"; shift ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
    shift
done

echo "==> swift build -c release"
swift build -c release

# --- Lay out InfiniteBrain.app ----------------------------------------------
APP="${DIST_DIR}/${APP_NAME}.app"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

cp "${RELEASE_DIR}/${APP_NAME}" "${APP}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP}/Contents/MacOS/${APP_NAME}"

if [[ -d "${RELEASE_DIR}/${RESOURCE_BUNDLE}" ]]; then
    cp -R "${RELEASE_DIR}/${RESOURCE_BUNDLE}" "${APP}/Contents/Resources/"
fi

cat > "${APP}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>           <string>en</string>
    <key>CFBundleDisplayName</key>                  <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>                   <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>                   <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>        <string>6.0</string>
    <key>CFBundleName</key>                         <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>                  <string>APPL</string>
    <key>CFBundleShortVersionString</key>           <string>${VERSION}</string>
    <key>CFBundleVersion</key>                      <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>               <string>14.0</string>
    <key>NSHighResolutionCapable</key>              <true/>
    <key>NSHumanReadableCopyright</key>             <string>Copyright © 2026 Dinesh Malla. MIT.</string>
    <key>NSSupportsAutomaticTermination</key>       <true/>
    <key>NSSupportsSuddenTermination</key>          <true/>
</dict>
</plist>
EOF

printf 'APPL????' > "${APP}/Contents/PkgInfo"

echo "==> codesigning ${APP} with identity '${SIGN_IDENTITY}'"
codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP}"

# --- Copy CLI alongside the .app -------------------------------------------
cp "${RELEASE_DIR}/${CLI_NAME}" "${DIST_DIR}/${CLI_NAME}"
chmod +x "${DIST_DIR}/${CLI_NAME}"

echo "==> built ${APP} (version ${VERSION})"
echo "    + CLI binary at ${DIST_DIR}/${CLI_NAME}"

# --- Optional .dmg ----------------------------------------------------------
if [[ "${MAKE_DMG}" -eq 1 ]]; then
    DMG="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
    rm -f "${DMG}"
    echo "==> packaging ${DMG}"
    hdiutil create \
        -volname "${APP_NAME}" \
        -srcfolder "${APP}" \
        -ov -format UDZO \
        "${DMG}" >/dev/null
    echo "    written ${DMG}"
fi
