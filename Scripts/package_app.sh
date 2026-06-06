#!/usr/bin/env bash
set -euo pipefail

CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP_NAME="ScribeFlowPro"
BUNDLE_ID="com.nodaysidle.scribeflowpro"
MACOS_MIN_VERSION="15.0"

source "$ROOT/version.env"

echo "==> Building $APP_NAME ($CONF) with SwiftPM..."
swift build -c "$CONF"

HOST_ARCH=$(uname -m)
SWIFTPM_DIR="$ROOT/.build/${HOST_ARCH}-apple-macosx/$CONF"
SWIFTPM_BIN="$SWIFTPM_DIR/$APP_NAME"
if [[ ! -f "$SWIFTPM_BIN" ]]; then
    echo "ERROR: SwiftPM binary not found at $SWIFTPM_BIN"
    exit 1
fi

APP="$ROOT/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>ScribeFlow Pro</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>${MACOS_MIN_VERSION}</string>
    <key>CFBundleIconFile</key><string>Icon</string>
    <key>NSMicrophoneUsageDescription</key><string>ScribeFlow Pro needs microphone access to record and transcribe meetings.</string>
    <key>NSLocalNetworkUsageDescription</key><string>ScribeFlow Pro downloads ML models from Hugging Face only when you explicitly use Model Manager.</string>
    <key>BuildTimestamp</key><string>${BUILD_TIMESTAMP}</string>
    <key>GitCommit</key><string>${GIT_COMMIT}</string>
</dict>
</plist>
PLIST

cp "$SWIFTPM_BIN" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

if [[ -f "$ROOT/Icon.icns" ]]; then
    cp "$ROOT/Icon.icns" "$APP/Contents/Resources/Icon.icns"
fi

if [[ -d "$ROOT/Scripts" ]]; then
    mkdir -p "$APP/Contents/Resources/Scripts"
    cp "$ROOT/Scripts/mlx_whisper_transcribe.py" "$APP/Contents/Resources/Scripts/" 2>/dev/null || true
    cp "$ROOT/Scripts/mlx_lm_generate.py" "$APP/Contents/Resources/Scripts/" 2>/dev/null || true
    cp "$ROOT/Scripts/setup_mlx_runtime.sh" "$APP/Contents/Resources/Scripts/" 2>/dev/null || true
    chmod +x "$APP/Contents/Resources/Scripts/"* 2>/dev/null || true
fi

ENTITLEMENTS="$ROOT/ScribeFlowPro/ScribeFlowPro.entitlements"

shopt -s nullglob
for bundle in "$SWIFTPM_DIR"/*.bundle; do
    echo "    Bundling: $(basename "$bundle")"
    cp -R "$bundle" "$APP/Contents/Resources/"
done

for framework in "$SWIFTPM_DIR"/*.framework; do
    echo "    Framework: $(basename "$framework")"
    cp -R "$framework" "$APP/Contents/Frameworks/"
done
shopt -u nullglob

if [[ -d "$APP/Contents/Frameworks" ]]; then
    chmod -R a+rX "$APP/Contents/Frameworks"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true
fi

chmod -R u+w "$APP"
xattr -cr "$APP"
find "$APP" -name '._*' -delete

if [[ -f "$ENTITLEMENTS" ]]; then
    codesign --force --sign "-" --entitlements "$ENTITLEMENTS" "$APP"
else
    codesign --force --sign "-" "$APP"
fi

codesign --verify --deep --strict "$APP"

echo "==> Created $APP"
echo "    Version: $MARKETING_VERSION ($BUILD_NUMBER)"
echo "    Size: $(du -sh "$APP" | cut -f1)"
