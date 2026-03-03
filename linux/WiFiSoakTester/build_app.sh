#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_OUTPUT_DIR="$ROOT_DIR/Build"
APP_DIR="$BUILD_OUTPUT_DIR/WiFiSoakTester.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE_DIR="$ROOT_DIR/.build/module-cache"

cd "$ROOT_DIR"

# Prefer full Xcode toolchain over CommandLineTools when available.
if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

# Keep module caches inside the workspace to avoid permission issues.
mkdir -p "$MODULE_CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_DIR"

echo "[1/4] Building Release binary..."
swift build -c release --product WiFiSoakTester

BIN_PATH=""
if [[ -x "$ROOT_DIR/.build/release/WiFiSoakTester" ]]; then
  BIN_PATH="$ROOT_DIR/.build/release/WiFiSoakTester"
else
  BIN_PATH="$(find "$ROOT_DIR/.build" -type f -path '*/release/WiFiSoakTester' | head -n 1 || true)"
fi

if [[ -z "$BIN_PATH" || ! -x "$BIN_PATH" ]]; then
  echo "Error: Release executable not found."
  exit 1
fi

echo "[2/4] Creating .app bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/WiFiSoakTester"
chmod +x "$MACOS_DIR/WiFiSoakTester"

echo "[3/4] Copying resources/bundles..."
find "$ROOT_DIR/.build" -type d -path '*/release/*.bundle' -name '*.bundle' -exec cp -R {} "$RESOURCES_DIR" \; || true

ICON_PATH="$ROOT_DIR/Sources/WiFiSoakTester/Resources/AppIcon.icns"
if [[ -f "$ICON_PATH" ]]; then
  cp "$ICON_PATH" "$RESOURCES_DIR/AppIcon.icns"
  ICON_ENTRY=$'    <key>CFBundleIconFile</key>\n    <string>AppIcon</string>'
else
  ICON_ENTRY=''
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>WiFiSoakTester</string>
    <key>CFBundleIdentifier</key>
    <string>local.wifisoaktester.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>WiFiSoakTester</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSExceptionDomains</key>
        <dict>
            <key>ipv4.rbx.proof.ovh.net</key>
            <dict>
                <key>NSExceptionAllowsInsecureHTTPLoads</key>
                <true/>
                <key>NSIncludesSubdomains</key>
                <false/>
            </dict>
            <key>ipv4.sbg.proof.ovh.net</key>
            <dict>
                <key>NSExceptionAllowsInsecureHTTPLoads</key>
                <true/>
                <key>NSIncludesSubdomains</key>
                <false/>
            </dict>
            <key>ipv4.bhs.proof.ovh.net</key>
            <dict>
                <key>NSExceptionAllowsInsecureHTTPLoads</key>
                <true/>
                <key>NSIncludesSubdomains</key>
                <false/>
            </dict>
        </dict>
    </dict>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
${ICON_ENTRY}
</dict>
</plist>
PLIST

echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

echo "[4/4] Done"
echo "App generated at: $APP_DIR"
