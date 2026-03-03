#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$ROOT_DIR/BuildLinux"
BINARY_PATH=""

cd "$ROOT_DIR"

mkdir -p "$OUTPUT_DIR"

echo "[1/3] Building Linux CLI in Release mode..."
swift build -c release --product WiFiSoakTesterLinux

if [[ -x "$ROOT_DIR/.build/release/WiFiSoakTesterLinux" ]]; then
  BINARY_PATH="$ROOT_DIR/.build/release/WiFiSoakTesterLinux"
else
  BINARY_PATH="$(find "$ROOT_DIR/.build" -type f -path '*/release/WiFiSoakTesterLinux' | head -n 1 || true)"
fi

if [[ -z "$BINARY_PATH" || ! -x "$BINARY_PATH" ]]; then
  echo "Error: Linux binary not found after build."
  exit 1
fi

echo "[2/3] Copying binary..."
cp "$BINARY_PATH" "$OUTPUT_DIR/wifi-soak-linux"
chmod +x "$OUTPUT_DIR/wifi-soak-linux"

echo "[3/3] Done"
echo "Binary available at: $OUTPUT_DIR/wifi-soak-linux"
