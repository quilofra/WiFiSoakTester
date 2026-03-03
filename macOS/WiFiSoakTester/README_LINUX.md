# WiFiSoakTesterLinux

Linux CLI variant of WiFiSoakTester (no GUI).

Includes:
- Endpoint preflight before running (fast check, avoids starting with all endpoints down).
- Session state flow (`Starting/Running/Stopping/Finished/Error`).
- Atomic CSV/HTML writes to reduce partial/corrupted exports.
- Optimized percentile computation for long runs (lower CPU in extended soak tests).

## Build

```bash
./build_linux.sh
```

Binary output:
- `./BuildLinux/wifi-soak-linux`

## Quick Start

```bash
./BuildLinux/wifi-soak-linux \
  --duration 12h \
  --concurrency 2 \
  --endpoints-file endpoints.txt \
  --csv-out soak_test.csv
```

## Endpoints

By default it uses `endpoints.txt` (ignores empty lines and comments starting with `#` or `//`).
If the file does not exist, built-in defaults are used.

## Useful options

- `--duration <12h|24h|infinite|N>` (N = custom hours)
- `--concurrency <1..4>`
- `--min-rate-mBps <value>`
- `--switch-after <seconds>`
- `--stable-rate-mbps <value>`
- `--sink <discard|ring>`
- `--ring-dir <path>`
- `--csv-out <path>`
- `--html-out <path>`
- `--auto-export-dir <path>`

Help:

```bash
./BuildLinux/wifi-soak-linux --help
```

## Stop

Type `stop` + Enter for graceful stop.

## Quick Sanity Check

Run an automated short verification (build + real download + CSV consistency checks):

```bash
./quick_sanity_check.sh
```

Outputs:
- `BuildLinux/sanity_check.csv`
- `BuildLinux/sanity_check.log`
