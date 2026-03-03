#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
CSV_PATH="${1:-$ROOT_DIR/BuildLinux/sanity_check.csv}"
LOG_PATH="${2:-$ROOT_DIR/BuildLinux/sanity_check.log}"
DURATION="${DURATION:-0.005h}"

mkdir -p "$(dirname "$CSV_PATH")"
mkdir -p "$(dirname "$LOG_PATH")"

echo "[1/4] Building Linux binary"
"$ROOT_DIR/build_linux.sh" >/dev/null

echo "[2/4] Running short soak test (duration=$DURATION)"
"$ROOT_DIR/BuildLinux/wifi-soak-linux" \
  --duration "$DURATION" \
  --concurrency 1 \
  --timeout 10 \
  --max-retries 2 \
  --backoff 0.8 \
  --csv-out "$CSV_PATH" >"$LOG_PATH" 2>&1

echo "[3/4] Validating CSV consistency"
awk -F',' '
BEGIN {
  expectedHeader = "timestamp,speed_Bps,total_bytes,url,errors,retries";
  rows = 0;
  prevTotal = -1;
}
NR == 1 {
  if ($0 != expectedHeader) {
    printf("Invalid header: %s\n", $0) > "/dev/stderr";
    exit 2;
  }
  next;
}
NR > 1 {
  if (NF != 6) {
    printf("Invalid field count at line %d: %s\n", NR, $0) > "/dev/stderr";
    exit 3;
  }

  speed = $2 + 0;
  total = $3 + 0;
  url = $4;

  if (speed < 0) {
    printf("Negative speed at line %d\n", NR) > "/dev/stderr";
    exit 4;
  }

  if (prevTotal >= 0 && total < prevTotal) {
    printf("Non-monotonic total_bytes at line %d\n", NR) > "/dev/stderr";
    exit 5;
  }

  if (url !~ /^https?:\/\//) {
    printf("Invalid URL field at line %d: %s\n", NR, url) > "/dev/stderr";
    exit 6;
  }

  prevTotal = total;
  rows++;
}
END {
  if (rows < 3) {
    printf("Too few data rows: %d\n", rows) > "/dev/stderr";
    exit 7;
  }
}
' "$CSV_PATH"

echo "[4/4] OK"
echo "CSV: $CSV_PATH"
echo "Log: $LOG_PATH"
