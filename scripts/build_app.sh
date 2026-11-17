#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/NotchNest.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"

CONFIGURATION="${1:-release}"

echo "Building NotchNest ($CONFIGURATION, x86_64)..."
swift build --package-path "$ROOT_DIR" --disable-sandbox -c "$CONFIGURATION" --arch x86_64

BIN_PATH="$(swift build --package-path "$ROOT_DIR" --disable-sandbox -c "$CONFIGURATION" --arch x86_64 --show-bin-path)/NotchNest"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "Error: Binary not found at $BIN_PATH" >&2
    exit 1
fi

rm -rf "$APP_BUNDLE" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/NotchNest"
chmod +x "$MACOS_DIR/NotchNest"

# Generate original app icon (.icns) directly
swift "$ROOT_DIR/scripts/generate_icon.swift" "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>NotchNest</string>
    <key>CFBundleExecutable</key>
    <string>NotchNest</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>app.notchnest.mac</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>NotchNest</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>NotchNest displays your upcoming calendar events and meeting join links inside the notch drawer.</string>
    <key>NSCameraUsageDescription</key>
    <string>NotchNest shows your camera only while the Mirror tab is open so you can check framing before a call.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>NotchNest watches your screenshot folder so new screenshots appear in Clips for quick drag-and-drop.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>NotchNest optionally reads Now Playing state from Apple Music or Spotify and applies system quick toggles.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>NotchNest estimates travel time and when to leave for upcoming calendar meetings with locations.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>NotchNest captures your voice only while you dictate a quick task into the notch.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>NotchNest optionally syncs tasks with a NotchNest list in Apple Reminders.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>NotchNest transcribes spoken tasks locally into your Today planner.</string>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS/Info.plist" >/dev/null
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
file "$MACOS_DIR/NotchNest"
lipo -info "$MACOS_DIR/NotchNest"
codesign -dv "$APP_BUNDLE" 2>&1 | grep -E "Identifier|Format|Signature" || true
