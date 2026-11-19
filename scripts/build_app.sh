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
HOST_ARCH="$(uname -m)"
if [[ "$HOST_ARCH" == "x86_64" ]] && [[ "$(sysctl -in hw.optional.arm64 2>/dev/null || echo 0)" == "1" ]]; then
    HOST_ARCH="arm64"
fi
TARGET_ARCH="${2:-$HOST_ARCH}"

case "$TARGET_ARCH" in
    native)
        TARGET_ARCH="$HOST_ARCH"
        ARCH_LIST=("$TARGET_ARCH")
        ARCH_LABEL="$TARGET_ARCH"
        ;;
    arm64|x86_64)
        ARCH_LIST=("$TARGET_ARCH")
        ARCH_LABEL="$TARGET_ARCH"
        ;;
    universal)
        ARCH_LIST=(arm64 x86_64)
        ARCH_LABEL="universal (arm64 + x86_64)"
        ;;
    *)
        echo "Unsupported arch '$TARGET_ARCH'. Use: native, universal, arm64, or x86_64." >&2
        exit 1
        ;;
esac

echo "Building NotchNest ($CONFIGURATION, $ARCH_LABEL)..."
BUILT_BINS=()
for arch in "${ARCH_LIST[@]}"; do
    swift build --package-path "$ROOT_DIR" --disable-sandbox -c "$CONFIGURATION" --arch "$arch"
    BIN_PATH="$(swift build --package-path "$ROOT_DIR" --disable-sandbox -c "$CONFIGURATION" --arch "$arch" --show-bin-path)/NotchNest"
    if [[ ! -f "$BIN_PATH" ]]; then
        echo "Error: Binary not found at $BIN_PATH" >&2
        exit 1
    fi
    BUILT_BINS+=("$BIN_PATH")
done

rm -rf "$APP_BUNDLE" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

if [[ ${#BUILT_BINS[@]} -gt 1 ]]; then
    lipo -create "${BUILT_BINS[@]}" -output "$MACOS_DIR/NotchNest"
else
    cp "${BUILT_BINS[1]}" "$MACOS_DIR/NotchNest"
fi
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

resolve_codesign_identity() {
    if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
        printf '%s\n' "$CODESIGN_IDENTITY"
        return 0
    fi
    local identities preferred match_hash
    identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    for preferred in "NotchNest Local" "NotchNest Dev" "Developer ID Application" "Apple Development"; do
        match_hash="$(printf '%s\n' "$identities" | grep -m1 "$preferred" | awk '{print $2}' || true)"
        if [[ -n "$match_hash" ]]; then
            printf '%s\n' "$match_hash"
            return 0
        fi
    done
    printf '%s\n' "-"
}

SIGN_IDENTITY="$(resolve_codesign_identity)"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "Signing ad-hoc (-); TCC permissions may re-prompt across rebuilds."
else
    echo "Signing with Keychain identity: $SIGN_IDENTITY"
fi
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
file "$MACOS_DIR/NotchNest"
lipo -info "$MACOS_DIR/NotchNest"
codesign -dv "$APP_BUNDLE" 2>&1 | grep -E "Identifier|Format|Signature|Authority|TeamIdentifier" || true
