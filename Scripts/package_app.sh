#!/usr/bin/env bash
set -euo pipefail

CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP_NAME="ScribeFlowPro"
BUNDLE_ID="com.scribeflowpro.app"
MACOS_MIN_VERSION="15.0"

source "$ROOT/version.env"

echo "==> Building $APP_NAME ($CONF) with xcodebuild..."
DERIVED_DATA="$ROOT/.build/xcode"
xcodebuild -scheme "$APP_NAME" -configuration Release -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" 2>&1 | tail -5

XCODE_BIN="$DERIVED_DATA/Build/Products/Release/$APP_NAME"
if [[ ! -f "$XCODE_BIN" ]]; then
    echo "ERROR: xcodebuild binary not found at $XCODE_BIN"
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
    <key>NSLocalNetworkUsageDescription</key><string>ScribeFlow Pro downloads ML models from Hugging Face.</string>
    <key>BuildTimestamp</key><string>${BUILD_TIMESTAMP}</string>
    <key>GitCommit</key><string>${GIT_COMMIT}</string>
</dict>
</plist>
PLIST

# Copy xcodebuild binary
cp "$XCODE_BIN" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

# Copy icon
if [[ -f "$ROOT/Icon.icns" ]]; then
    cp "$ROOT/Icon.icns" "$APP/Contents/Resources/Icon.icns"
fi

# Copy entitlements
ENTITLEMENTS="$ROOT/ScribeFlowPro/ScribeFlowPro.entitlements"

# Copy resource bundles from xcodebuild output (includes metallib for MLX)
XCODE_PRODUCTS="$DERIVED_DATA/Build/Products/Release"
shopt -s nullglob
XCODE_BUNDLES=("${XCODE_PRODUCTS}/"*.bundle)
shopt -u nullglob
if [[ ${#XCODE_BUNDLES[@]} -gt 0 ]]; then
    for bundle in "${XCODE_BUNDLES[@]}"; do
        echo "    Bundling: $(basename "$bundle")"
        cp -R "$bundle" "$APP/Contents/Resources/"
    done
fi

# Also copy from SwiftPM build dir if any (fallback)
HOST_ARCH=$(uname -m)
SWIFTPM_DIR=".build/${HOST_ARCH}-apple-macosx/$CONF"
if [[ -d "$SWIFTPM_DIR" ]]; then
    shopt -s nullglob
    SWIFTPM_BUNDLES=("${SWIFTPM_DIR}/"*.bundle)
    shopt -u nullglob
    for bundle in "${SWIFTPM_BUNDLES[@]}"; do
        BNAME=$(basename "$bundle")
        if [[ ! -d "$APP/Contents/Resources/$BNAME" ]]; then
            echo "    Bundling (SwiftPM): $BNAME"
            cp -R "$bundle" "$APP/Contents/Resources/"
        fi
    done
fi

# Copy frameworks if any
FRAMEWORK_DIRS=("$XCODE_PRODUCTS" ".build/${HOST_ARCH}-apple-macosx/$CONF")
for dir in "${FRAMEWORK_DIRS[@]}"; do
    if compgen -G "${dir}/"*.framework >/dev/null 2>&1; then
        cp -R "${dir}/"*.framework "$APP/Contents/Frameworks/"
        chmod -R a+rX "$APP/Contents/Frameworks"
        install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true
        break
    fi
done

# Clean and sign
chmod -R u+w "$APP"
xattr -cr "$APP"
find "$APP" -name '._*' -delete

if [[ -f "$ENTITLEMENTS" ]]; then
    codesign --force --sign "-" --entitlements "$ENTITLEMENTS" "$APP"
else
    codesign --force --sign "-" "$APP"
fi

echo "==> Created $APP"
echo "    Version: $MARKETING_VERSION ($BUILD_NUMBER)"
echo "    Size: $(du -sh "$APP" | cut -f1)"
