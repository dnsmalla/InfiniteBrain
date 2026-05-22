#!/usr/bin/env bash
set -e

LOGO_PATH="/Users/dinsmallade/InfiniteBrain/app_logo.png"
ICONSET_DIR="AppIcon.iconset"
OUTPUT_ICNS="AppIcon.icns"

rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

# Generate all required sizes
sips -z 16 16     "${LOGO_PATH}" --out "${ICONSET_DIR}/icon_16x16.png"
sips -z 32 32     "${LOGO_PATH}" --out "${ICONSET_DIR}/icon_16x16@2x.png"
sips -z 32 32     "${LOGO_PATH}" --out "${ICONSET_DIR}/icon_32x32.png"
sips -z 64 64     "${LOGO_PATH}" --out "${ICONSET_DIR}/icon_32x32@2x.png"
sips -z 128 128   "${LOGO_PATH}" --out "${ICONSET_DIR}/icon_128x128.png"
sips -z 256 256   "${LOGO_PATH}" --out "${ICONSET_DIR}/icon_128x128@2x.png"
sips -z 256 256   "${LOGO_PATH}" --out "${ICONSET_DIR}/icon_256x256.png"
sips -z 512 512   "${LOGO_PATH}" --out "${ICONSET_DIR}/icon_256x256@2x.png"
sips -z 512 512   "${LOGO_PATH}" --out "${ICONSET_DIR}/icon_512x512.png"
sips -z 1024 1024 "${LOGO_PATH}" --out "${ICONSET_DIR}/icon_512x512@2x.png"

# Convert iconset to icns
iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_ICNS}"

# Clean up
rm -rf "${ICONSET_DIR}"

echo "Created ${OUTPUT_ICNS}"
