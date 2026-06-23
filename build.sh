#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

APP_NAME="AI.Mon"          # Display / bundle name
EXEC_NAME="AIMon"          # Mach-O executable name (no dot, for safety)
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# Clean previous build artifacts (old and new names)
echo "Cleaning previous builds..."
rm -rf "AIMon.app" "${APP_DIR}"

echo "Creating App Bundle structure..."
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Build Icon if app_icon.png exists
if [ -f "app_icon.png" ]; then
    echo "Generating app icon (.icns)..."
    ICONSET_DIR="AppIcon.iconset"
    mkdir -p "${ICONSET_DIR}"

    # Create required resolutions
    sips -z 16 16     app_icon.png --out "${ICONSET_DIR}/icon_16x16.png" > /dev/null
    sips -z 32 32     app_icon.png --out "${ICONSET_DIR}/icon_16x16@2x.png" > /dev/null
    sips -z 32 32     app_icon.png --out "${ICONSET_DIR}/icon_32x32.png" > /dev/null
    sips -z 64 64     app_icon.png --out "${ICONSET_DIR}/icon_32x32@2x.png" > /dev/null
    sips -z 128 128   app_icon.png --out "${ICONSET_DIR}/icon_128x128.png" > /dev/null
    sips -z 256 256   app_icon.png --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null
    sips -z 256 256   app_icon.png --out "${ICONSET_DIR}/icon_256x256.png" > /dev/null
    sips -z 512 512   app_icon.png --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null
    sips -z 512 512   app_icon.png --out "${ICONSET_DIR}/icon_512x512.png" > /dev/null
    sips -z 1024 1024 app_icon.png --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null

    # Compile into .icns
    iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns"
    rm -rf "${ICONSET_DIR}"

    # Copy app_icon.png as a raw resource for UI usage
    cp app_icon.png "${RESOURCES_DIR}/app_icon.png"
    echo "Icon generation and copy complete."
fi

# Create Info.plist
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.seanyoon.AIMon</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${EXEC_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.5</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>MinimumOSVersion</key>
    <string>14.0</string>
</dict>
</plist>
EOF

echo "Compiling Swift source files..."
SDK_PATH=$(xcrun --show-sdk-path --sdk macosx)

swiftc Sources/*.swift \
    -sdk "${SDK_PATH}" \
    -target arm64-apple-macos14.0 \
    -O \
    -o "${MACOS_DIR}/${EXEC_NAME}"

# Ad-hoc code signature (helps WKWebView / keychain behave on local builds)
echo "Code signing (ad-hoc)..."
codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || echo "  (codesign skipped)"

echo "Build successful! Application packaged at ${APP_DIR}."
echo "You can run the app using: open \"${APP_DIR}\""
