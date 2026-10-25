#!/bin/zsh
set -e

cd "$(dirname "$0")"

ARCH=$(uname -m)
APP_NAME="XboxToolbarController"
APP_BUNDLE="${APP_NAME}.app"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
RESOURCES_DIR="${APP_BUNDLE}/Contents/Resources"

echo "[1/3] Compiling ${APP_NAME} (${ARCH}) with swiftc..."
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

swiftc -O \
    -target "${ARCH}-apple-macosx13.0" \
    Sources/XboxToolbarController/Localization.swift \
    Sources/XboxToolbarController/SmartGlassClient.swift \
    Sources/XboxToolbarController/ControllerView.swift \
    Sources/XboxToolbarController/AppDelegate.swift \
    Sources/XboxToolbarController/main.swift \
    -o "${MACOS_DIR}/${APP_NAME}"

echo "[2/3] Creating Info.plist for macOS Menu Bar app..."
cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.xboxmacoscontroller.toolbar</string>
    <key>CFBundleName</key>
    <string>Xbox Toolbar Controller</string>
    <key>CFBundleDisplayName</key>
    <string>Xbox Toolbar Controller</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2.0</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Local network access is required to discover and control your Xbox console over SmartGlass (UDP 5050) and Kodi EventServer (UDP 9777).</string>
</dict>
</plist>
EOF

codesign --force --deep --sign - "${APP_BUNDLE}"

echo "[3/3] Launching ${APP_BUNDLE}..."
killall "${APP_NAME}" 2>/dev/null || true
sleep 0.5
open "${APP_BUNDLE}"
echo "Done! ${APP_BUNDLE} is now running in the macOS Menu Bar."
