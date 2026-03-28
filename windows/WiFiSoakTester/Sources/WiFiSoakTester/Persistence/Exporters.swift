import Foundation

enum ExportError: Error {
    case noSamples
    case invalidCSVRow(lineNumber: Int, line: String)
}

struct CSVExporter {
    static func export(samples: [SessionSample], to url: URL, onlyLastHours: Int?) throws {
        let filtered = filter(samples: samples, onlyLastHours: onlyLastHours)
        guard !filtered.isEmpty else {
            throw ExportError.noSamples
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines: [String] = ["timestamp,speed_Bps,total_bytes,url,errors,retries"]
        lines.reserveCapacity(filtered.count + 1)

        for sample in filtered {
            let timestamp = formatter.string(from: sample.timestamp)
            let speed = String(format: "%.4f", sample.speedBps)
            let row = [
                timestamp,
                speed,
                String(sample.totalBytes),
                csvEscaped(sample.primaryURL),
                String(sample.errors),
                String(sample.retries)
            ].joined(separator: ",")
            lines.append(row)
        }

        try validateCSV(lines: lines)
        let content = lines.joined(separator: "\n") + "\n"
        try AtomicFileWriter.write(content: content, to: url)
    }

    private static func csvEscaped(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    static func filter(samples: [SessionSample], onlyLastHours: Int?) -> [SessionSample] {
        guard let onlyLastHours, onlyLastHours > 0, let lastDate = samples.last?.timestamp else {
            return samples
        }

        let cutoff = lastDate.addingTimeInterval(-Double(onlyLastHours) * 3600)
        return samples.filter { $0.timestamp >= cutoff }
    }

    private static func validateCSV(lines: [String]) throws {
        for (index, line) in lines.enumerated() where index > 0 {
            if csvFieldCount(line) != 6 {
                throw ExportError.invalidCSVRow(lineNumber: index + 1, line: line)
            }
        }
    }

    private static func csvFieldCount(_ line: String) -> Int {
        var fields = 1
        var inQuotes = false
        var iterator = line.makeIterator()

        while let char = iterator.next() {
            if char == "\"" {
                if inQuotes {
                    if let peek = iterator.next() {
                        if peek != "\"" {
                            inQuotes = false
                            if peek == "," {
                                fields += 1
                            }
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
                continue
            }

            if char == "," && !inQuotes {
                fields += 1
            }
        }

        return fields
    }
}

struct HTMLReportGenerator {
    static func generate(title: String, samples: [SessionSample], generatedAt: Date = Date()) throws -> String {
        guard !samples.isEmpty else {
            throw ExportError.noSamples
        }

        let speeds = samples.map(\.speedBps)
        let p50 = Statistics.percentile(values: speeds, percentile: 50)
        let p95 = Statistics.percentile(values: speeds, percentile: 95)
        let maxSpeed = max(speeds.max() ?? 0, 1)
        let avgSpeed = speeds.reduce(0, +) / Double(speeds.count)
        let totalBytes = samples.last?.totalBytes ?? 0

        let width = 1200.0
        let height = 300.0

        let points: String
        if samples.count == 1 {
            let y = height - ((samples[0].speedBps / maxSpeed) * height)
            points = "0,\(y) \(width),\(y)"
        } else {
            points = samples.enumerated().map { index, sample in
                let x = (Double(index) / Double(samples.count - 1)) * width
                let normalized = sample.speedBps / maxSpeed
                let y = height - (normalized * height)
                return String(format: "%.2f,%.2f", x, y)
            }.joined(separator: " ")
        }

        let df = ISO8601DateFormatter()
        let generatedAtText = df.string(from: generatedAt)

        return """
<!doctype html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\" />
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
  <title>\(htmlEscaped(title))</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif; margin: 24px; color: #0a0a0a; background: #f7f8fb; }
    .card { background: white; border-radius: 12px; padding: 16px; box-shadow: 0 6px 20px rgba(0,0,0,0.08); margin-bottom: 16px; }
    .stats { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; }
    .label { color: #5f6470; font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; }
    .value { font-size: 18px; font-weight: 600; }
    svg { width: 100%; height: auto; background: #0d1321; border-radius: 10px; }
    .line { fill: none; stroke: #53d8fb; stroke-width: 2; }
    h1 { margin-top: 0; }
    .foot { color: #5f6470; font-size: 12px; margin-top: 10px; }
  </style>
</head>
<body>
  <div class=\"card\">
    <h1>\(htmlEscaped(title))</h1>
    <div class=\"stats\">
      <div>
        <div class=\"label\">Average speed</div>
        <div class=\"value\">\(formatSpeed(avgSpeed))</div>
      </div>
      <div>
        <div class=\"label\">p50 / p95</div>
        <div class=\"value\">\(formatSpeed(p50)) / \(formatSpeed(p95))</div>
      </div>
      <div>
        <div class=\"label\">Peak speed</div>
        <div class=\"value\">\(formatSpeed(maxSpeed))</div>
      </div>
      <div>
        <div class=\"label\">Total downloaded</div>
        <div class=\"value\">\(formatBytes(totalBytes))</div>
      </div>
    </div>
  </div>

  <div class=\"card\">
    <svg viewBox=\"0 0 \(Int(width)) \(Int(height))\" role=\"img\" aria-label=\"Speed over time\">
      <polyline class=\"line\" points=\"\(points)\" />
    </svg>
    <div class=\"foot\">Generated at \(generatedAtText). Report is self-contained (no external CDN).</div>
  </div>
</body>
</html>
"""
    }

    private static func formatSpeed(_ bps: Double) -> String {
        let mbps = bps * 8 / 1_000_000
        return String(format: "%.2f Mbps", mbps)
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }

    private static func htmlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

enum AtomicFileWriter {
    static func write(content: String, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let directory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporaryURL = directory.appendingPathComponent(".\(destinationURL.lastPathComponent).tmp.\(UUID().uuidString)")

        do {
            try content.write(to: temporaryURL, atomically: true, encoding: .utf8)

            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }
}
