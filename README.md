# WiFiSoakTester Repository

Professional, sanitized repository for WiFi soak testing on:
- `macOS` (SwiftUI desktop app)
- `Linux` (CLI binary)
- `Windows` (CLI ZIP artifact from GitHub Actions)

The project is split into two ready-to-build copies so each platform can be packaged and used independently.

## Highlights

- Long-run download soak tests (`12h`, `24h`, custom, `infinite`)
- Endpoint rotation with retries, backoff, and fallback behavior
- Live metrics and export support (CSV + HTML)
- Auto-export with retention/rotation controls
- Defensive output writes (atomic export to reduce corruption risk)

## Repository Layout

```text
.
|-- macOS/
|   `-- WiFiSoakTester/      # Swift package + app build script
|-- linux/
|   `-- WiFiSoakTester/      # Swift package + Linux CLI build script
|-- windows/
|   `-- WiFiSoakTester/      # Swift package + Windows packaging script
|-- .github/                 # CI workflow + issue/PR templates
|-- Makefile                # Common local commands
|-- CONTRIBUTING.md
|-- SECURITY.md
`-- README.md
```

## Quick Start

You can run common tasks from repo root:

```bash
make help
```

### 1) Build macOS app bundle

```bash
cd macOS/WiFiSoakTester
./build_app.sh
```

Output:
- `Build/WiFiSoakTester.app`

### 2) Build Linux CLI binary

```bash
cd linux/WiFiSoakTester
./build_linux.sh
```

Output:
- `BuildLinux/wifi-soak-linux`

### 3) Run tests

```bash
cd macOS/WiFiSoakTester
swift test

cd ../../linux/WiFiSoakTester
swift test

cd ../../windows/WiFiSoakTester
swift test
```

### 4) Build Windows portable ZIP

The Windows package is produced from GitHub Actions:

- workflow: `.github/workflows/windows-package.yml`
- artifact: `wifisoaktester-windows-x64.zip`

## CI

GitHub Actions workflow is included at:
- `.github/workflows/ci.yml`
- `.github/workflows/windows-package.yml`

`ci.yml` validates the macOS and Linux copies. `windows-package.yml` builds, smoke-tests and uploads the Windows ZIP artifact.

## Security and Privacy

- This repository is prepared to avoid personal local data and machine-specific paths.
- Do not commit secrets (tokens, private keys, `.env`, credentials files).
- Report vulnerabilities following [`SECURITY.md`](SECURITY.md).

## Contributing

Contribution process and quality checks are documented in [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

No open-source license file is currently included. Add one before publishing for external reuse.
