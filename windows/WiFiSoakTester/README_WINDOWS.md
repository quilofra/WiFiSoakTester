# WiFiSoakTester for Windows

## Quick start

1. Extract the ZIP anywhere on your PC.
2. Double-click `run_default.bat`.
3. Let the soak test run.
4. Type `stop` and press Enter to finish gracefully.

Exports are written to:

- `exports\stats_current.csv`
- `exports\report_current.html`

## Contents

- `WiFiSoakTester.exe`: CLI binary
- `run_default.bat`: double-click launcher
- `endpoints.txt`: endpoint list used by default
- `README_WINDOWS.md`: this file

## Manual usage

Open Command Prompt in the extracted folder and run:

```bat
WiFiSoakTester.exe --help
```

Example:

```bat
WiFiSoakTester.exe --duration 12h --concurrency 2 --endpoints-file endpoints.txt --csv-out soak_test.csv --html-out report.html
```
