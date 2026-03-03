# WiFiSoakTester (macOS 13+, SwiftUI)

App nativa macOS para soak test de descarga (12h/24h/custom/infinite), con UI glassy, rotación de endpoints, métricas en vivo, gráfica y export/auto-export con rotación.

## Nota ética
Usa solo endpoints estáticos permitidos explícitamente para testing.

## Endpoints por defecto (sin placeholders)
La app arranca con estos 6 endpoints:
- https://proof.ovh.net/files/10Gb.dat
- https://proof.ovh.net/files/1Gb.dat
- https://proof.ovh.net/files/100Mb.dat
- https://download.thinkbroadband.com/2GB.zip
- https://download.thinkbroadband.com/1GB.zip
- https://download.thinkbroadband.com/512MB.zip

También están en `endpoints.txt`.

## Funcionalidad implementada
- `NavigationSplitView` con secciones: Dashboard, Endpoints, Configuration, Export.
- UI macOS glassy con cards material, sombras suaves y animaciones.
- `Configuration > Appearance`:
  - `Aspecto`: `Ahora (Color)` o `Antes (Sin color)`.
  - `Palette`: `Ocean` / `Sunset` / `Studio` (solo en modo `Ahora`).
- Descarga streaming con `URLSession.bytes(for:)`.
- Máquina de estados de sesión (`Idle/Starting/Running/Stopping/Stopped/Error`) para Start/Stop robusto.
- Preflight de endpoints al iniciar (range request) para evitar arrancar con lista completamente caída.
- Concurrency configurable `1..4` workers.
- Rotación round-robin + retry/backoff + cooldown + switch por bajo rendimiento (`minRate`/`switchAfter`).
- Modos:
  - `Saturate maximum` (sin limitador)
  - `Stable` (rate cap en Mbps)
- Sink:
  - `Discard` (default)
  - `Disk Ring Buffer` (cache/segment/folder)
- Métricas live (refresh 1s): current, moving avg, global avg, total, elapsed, endpoints activos, switches, errors, retries, p50/p95, `% below threshold`.
- Gráfica Swift Charts: velocidad + total acumulado normalizado (opcional), ventana `1h/6h/all`, downsampling para limitar carga.
- Optimización de métricas de largo plazo: p50/p95 sobre ventana reciente y recálculo menos frecuente para bajar CPU.
- MenuBarExtra: estado, velocidad, total, errors/retries, Start/Stop y Open Window; título dinámico (velocidad).
- Export manual:
  - CSV: `timestamp,speed_Bps,total_bytes,url,errors,retries`
  - `report.html` autocontenido
- Escritura de export atómica (tmp + replace) para evitar archivos parciales/corruptos.
- Validación de consistencia CSV antes de escribir (detección de filas inválidas).
- Auto-export:
  - intervalo configurable
  - `stats_current.csv` + snapshots `stats_YYYYMMDD_HHMMSS.csv`
  - `report_current.html` opcional
  - rotación por `maxFiles` y `maxTotalMB`
- Validaciones UX:
  - Start bloqueado si hay URL inválida o placeholder (`example.com`)
  - mensaje claro de validación
  - `Last error` visible para diagnóstico

## ATS para endpoints HTTP opcionales
Los defaults son HTTPS, pero `build_app.sh` mantiene excepciones ATS explícitas para estos hosts HTTP opcionales:
- `ipv4.rbx.proof.ovh.net`
- `ipv4.sbg.proof.ovh.net`
- `ipv4.bhs.proof.ovh.net`

## Ejecutar en Xcode
1. Abre `Package.swift` en Xcode.
2. Selecciona esquema `WiFiSoakTester`.
3. Run (`⌘R`).

## Linux (CLI)
La versión Linux es de consola (`WiFiSoakTesterLinux`) porque SwiftUI no está disponible en Linux.

Build:
```bash
./build_linux.sh
```

Salida:
- `./BuildLinux/wifi-soak-linux`

Ejemplo de uso:
```bash
./BuildLinux/wifi-soak-linux \
  --duration 12h \
  --concurrency 2 \
  --endpoints-file endpoints.txt \
  --csv-out soak_test.csv \
  --html-out report.html
```

Opcional auto-export:
```bash
./BuildLinux/wifi-soak-linux \
  --duration infinite \
  --auto-export-dir ./exports \
  --auto-export-interval-min 5 \
  --auto-export-max-files 48 \
  --auto-export-max-mb 200
```

Para parar en modo interactivo: escribe `stop` + Enter.

## Verificación rápida (automática)
Puedes ejecutar un chequeo corto end-to-end (build + descarga real + validación de CSV):

```bash
./quick_sanity_check.sh
```

Salida esperada:
- genera `BuildLinux/sanity_check.csv`
- genera `BuildLinux/sanity_check.log`
- valida cabecera CSV, número de columnas y crecimiento monotónico de `total_bytes`

## Generar .app en la carpeta del proyecto
Script en raíz:
```bash
./build_app.sh
```
Salida:
- `./Build/WiFiSoakTester.app`

No copia nada a `/Applications`.

## Tests
Incluidos:
- `StatisticsTests`
- `URLRotatorTests`
- `DiskRingBufferTests`
- `AutoExportRotationTests`

En este entorno CLI, `swift test` puede fallar por falta de XCTest completo en CommandLineTools.
