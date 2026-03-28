import Foundation
import Dispatch

#if os(Windows)
import ucrt
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

private enum PlatformConsole {
    static func writeLine(_ line: String = "") {
        Swift.print(line)
        flushStandardOutput()
    }

    static func writeErrorLine(_ line: String) {
        guard let data = "\(line)\n".data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }

    private static func flushStandardOutput() {
        _ = fflush(stdout)
    }
}

private enum PlatformProcess {
    static func terminate(with code: Int32) -> Never {
        exit(code)
    }
}

private enum CLIError: LocalizedError {
    case missingValue(String)
    case invalidValue(flag: String, value: String)
    case unknownFlag(String)
    case noValidEndpoints
    case placeholderEndpoint(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .invalidValue(let flag, let value):
            return "Invalid value '\(value)' for \(flag)."
        case .unknownFlag(let flag):
            return "Unknown option: \(flag). Use --help."
        case .noValidEndpoints:
            return "No valid endpoints available."
        case .placeholderEndpoint(let endpoint):
            return "Placeholder endpoint is not allowed: \(endpoint)"
        }
    }
}

private struct CLIOptions {
    var showHelp = false
    var endpointsFile = "endpoints.txt"
    var urls: [String] = []
    var duration = "12h"
    var concurrency = 1
    var timeoutSeconds = 15.0
    var maxRetries = 5
    var backoffSeconds = 1.5
    var minRateMBps = 1.0
    var switchAfterSeconds = 20.0
    var movingAverageWindow = 10

    var saturateMaximum = true
    var stableMode = false
    var maxRateMbps = 100.0

    var sinkMode: SinkMode = .discard
    var ringDirectory = "./ring-buffer"
    var ringCacheGiB = 2.0
    var ringSegmentMiB = 64

    var csvOut: String?
    var htmlOut: String?
    var exportOnlyLastHours: Int?

    var autoExportDirectory: String?
    var autoExportIntervalMinutes = 5
    var autoExportMaxFiles = 48
    var autoExportMaxTotalMB = 200
    var autoExportIncludeHTML = true
}

private enum CLIParser {
    static func parse(arguments: [String]) throws -> CLIOptions {
        var options = CLIOptions()
        var index = 1

        func requireValue(for flag: String) throws -> String {
            guard index + 1 < arguments.count else {
                throw CLIError.missingValue(flag)
            }
            index += 1
            return arguments[index]
        }

        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--help", "-h":
                options.showHelp = true

            case "--url":
                options.urls.append(try requireValue(for: argument))

            case "--endpoints-file":
                options.endpointsFile = try requireValue(for: argument)

            case "--duration":
                options.duration = try requireValue(for: argument)

            case "--concurrency":
                let raw = try requireValue(for: argument)
                guard let value = Int(raw), (1...4).contains(value) else {
                    throw CLIError.invalidValue(flag: argument, value: raw)
                }
                options.concurrency = value

            case "--timeout":
                let raw = try requireValue(for: argument)
                guard let value = Double(raw), value > 0 else {
                    throw CLIError.invalidValue(flag: argument, value: raw)
                }
                options.timeoutSeconds = value

            case "--max-retries":
                let raw = try requireValue(for: argument)
                guard let value = Int(raw), value >= 0 else {
                    throw CLIError.invalidValue(flag: argument, value: raw)
                }
                options.maxRetries = value

            case "--backoff":
                let raw = try requireValue(for: argument)
                guard let value = Double(raw), value > 0 else {
                    throw CLIError.invalidValue(flag: argument, value: raw)
                }
                options.backoffSeconds = value

            case "--min-rate-mBps":
                let raw = try requireValue(for: argument)
                guard let value = Double(raw), value >= 0 else {
                    throw CLIError.invalidValue(flag: argument, value: raw)
                }
                options.minRateMBps = value

            case "--switch-after":
                let raw = try requireValue(for: argument)
                guard let value = Double(raw), value > 0 else {
                    throw CLIError.invalidValue(flag: argument, value: raw)
                }
                options.switchAfterSeconds = value

            case "--moving-average-window":
                let raw = try requireValue(for: argument)
                guard let value = Int(raw), value >= 2 else {
                    throw CLIError.invalidValue(flag: argument, value: raw)
                }
                options.movingAverageWindow = value

            case "--stable-rate-mbps":
                let raw = try requireValue(for: argument)
                guard let value = Double(raw), value > 0 else {
                    throw CLIError.invalidValue(flag: argument, value: raw)
                }
                options.stableMode = true
                options.saturateMaximum = false
                options.maxRateMbps = value

            case "--sink":
                let raw = try requireValue(for: argument).lowercased()
                guard let sink = SinkMode(rawValue: raw == "ring" ? "Ring Buffer" : (raw == "discard" ? "Discard" : "")) else {
                    throw CLIError.invalidValue(flag: argument, value: raw)
                }
                options.sinkMode = sink

            case "--ring-dir":
                options.ringDirectory = try requireValue(for: argument)

            case "--ring-cache-gib":
                let raw = try requireValue(for: argument)
                guard let value = Double(raw), value > 0 else {
                    throw CLIError.invalidValue(flag: argument, value: raw)
                }
                options.ringCacheGiB = value

            case "--ring-segment-mib":
                let raw = try requireValue(for: argument)
                guard let value = Int(raw), value > 0 else {
                    throw CLIError.invalidValue(flag: argument, value: raw)
                }
                options.ringSegmentMiB = value

            case "--csv-out":
                options.csvOut = try requireValue(for: argument)

            case "--html-out":
                options.htmlOut = try requireValue(for: argument)

            case "--export-last-hours":
                let raw = try requireValue(for: argument)
                guard let value = Int(raw), value > 0 else {
                    throw CLIError.invalidValue(flag: argument, value: raw)
                }
                options.exportOnlyLastHours = value

            case "--auto-export-dir":
                options.autoExportDirectory = try requireValue(for: argument)

            case "--auto-export-interval-min":
                let raw = try requireValue(for: argument)
                guard let value = Int(raw), value > 0 else {
                    throw CLIError.invalidValue(flag: argument, value: raw)
                }
                options.autoExportIntervalMinutes = value

            case "--auto-export-max-files":
                let raw = try requireValue(for: argument)
                guard let value = Int(raw), value > 0 else {
                    throw CLIError.invalidValue(flag: argument, value: raw)
                }
                options.autoExportMaxFiles = value

            case "--auto-export-max-mb":
                let raw = try requireValue(for: argument)
                guard let value = Int(raw), value > 0 else {
                    throw CLIError.invalidValue(flag: argument, value: raw)
                }
                options.autoExportMaxTotalMB = value

            case "--auto-export-html":
                let raw = try requireValue(for: argument)
                guard let value = parseBoolean(raw) else {
                    throw CLIError.invalidValue(flag: argument, value: raw)
                }
                options.autoExportIncludeHTML = value

            default:
                throw CLIError.unknownFlag(argument)
            }

            index += 1
        }

        return options
    }

    private static func parseBoolean(_ raw: String) -> Bool? {
        switch raw.lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }
}

private actor SampleCollector {
    private var buffer: CircularBuffer<SessionSample>

    init(capacity: Int) {
        self.buffer = CircularBuffer(capacity: max(capacity, 60))
    }

    func append(_ sample: SessionSample) {
        buffer.append(sample)
    }

    func replace(with samples: [SessionSample]) {
        buffer.removeAll(keepingCapacity: true)
        for sample in samples {
            buffer.append(sample)
        }
    }

    func allSamples() -> [SessionSample] {
        buffer.values()
    }
}

private final class CoordinatorHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var coordinator: DownloadCoordinator?

    func set(_ coordinator: DownloadCoordinator) {
        lock.lock()
        self.coordinator = coordinator
        lock.unlock()
    }

    func get() -> DownloadCoordinator? {
        lock.lock()
        let value = coordinator
        lock.unlock()
        return value
    }
}

private actor ConsoleReporter {
    private var lastErrorPrinted = ""

    func printStart(configuration: DownloadConfiguration, urls: [URL]) {
        PlatformConsole.writeLine("WiFiSoakTester started")
        PlatformConsole.writeLine("Endpoints: \(urls.count) | Concurrency: \(configuration.concurrency) | Sink: \(configuration.sinkMode.rawValue)")
        PlatformConsole.writeLine("Duration: \(durationText(configuration)) | Timeout: \(configuration.timeoutSeconds)s | Retries: \(configuration.maxRetries)")
        PlatformConsole.writeLine("Type 'stop' + Enter to finish gracefully.")
        PlatformConsole.writeLine()
    }

    func printSnapshot(_ snapshot: MetricsSnapshot) {
        let active = snapshot.activeURLs.keys.sorted().compactMap { key in
            snapshot.activeURLs[key].map { "W\(key + 1):\($0)" }
        }.joined(separator: " | ")

        let line = [
            "[\(isoTimestamp(snapshot.latestSample.timestamp))]",
            "cur \(ValueFormatting.speedMbps(snapshot.currentSpeedBps))",
            "mov \(ValueFormatting.speedMbps(snapshot.movingAverageBps))",
            "avg \(ValueFormatting.speedMbps(snapshot.globalAverageBps))",
            "tot \(ValueFormatting.bytes(snapshot.totalBytes))",
            "err/retry \(snapshot.errors)/\(snapshot.retries)",
            "sw \(snapshot.switches)",
            "p50/p95 \(ValueFormatting.speedMbps(snapshot.p50Bps))/\(ValueFormatting.speedMbps(snapshot.p95Bps))",
            "below \(String(format: "%.2f", snapshot.belowThresholdPercent))%",
            active.isEmpty ? "-" : active
        ].joined(separator: " | ")

        PlatformConsole.writeLine(line)
    }

    func printError(_ message: String) {
        guard message != lastErrorPrinted else { return }
        lastErrorPrinted = message
        PlatformConsole.writeLine("ERROR: \(message)")
    }

    func printInfo(_ message: String) {
        PlatformConsole.writeLine("INFO: \(message)")
    }

    func printSummary(samples: [SessionSample]) {
        guard !samples.isEmpty else {
            PlatformConsole.writeLine("Finished without samples.")
            return
        }
        let speeds = samples.map(\.speedBps)
        let average = speeds.reduce(0, +) / Double(max(speeds.count, 1))
        let p50 = Statistics.percentile(values: speeds, percentile: 50)
        let p95 = Statistics.percentile(values: speeds, percentile: 95)
        let total = samples.last?.totalBytes ?? 0
        PlatformConsole.writeLine()
        PlatformConsole.writeLine("Finished")
        PlatformConsole.writeLine("Samples: \(samples.count)")
        PlatformConsole.writeLine("Total: \(ValueFormatting.bytes(total))")
        PlatformConsole.writeLine("Average: \(ValueFormatting.speedMbps(average))")
        PlatformConsole.writeLine("p50/p95: \(ValueFormatting.speedMbps(p50)) / \(ValueFormatting.speedMbps(p95))")
    }

    private func durationText(_ configuration: DownloadConfiguration) -> String {
        if let seconds = configuration.durationSeconds {
            return ValueFormatting.elapsed(seconds)
        }
        return "Infinite"
    }

    private func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

@main
struct WiFiSoakTester {
    private static let defaultEndpoints: [String] = [
        "https://proof.ovh.net/files/10Gb.dat",
        "https://proof.ovh.net/files/1Gb.dat",
        "https://proof.ovh.net/files/100Mb.dat",
        "https://download.thinkbroadband.com/2GB.zip",
        "https://download.thinkbroadband.com/1GB.zip",
        "https://download.thinkbroadband.com/512MB.zip"
    ]

    static func main() async {
        do {
            let options = try CLIParser.parse(arguments: CommandLine.arguments)
            if options.showHelp {
                printHelp()
                return
            }

            let urls = try loadURLs(options: options)
            var configuration = DownloadConfiguration.makeDefault(urls: urls)
            apply(options: options, to: &configuration)

            let sink = try makeSink(configuration: configuration)
            let reporter = ConsoleReporter()
            let collector = SampleCollector(capacity: configuration.sampleCapacity)
            let coordinatorHolder = CoordinatorHolder()

            let completion = AsyncStream<[SessionSample]> { continuation in
                let coordinator = DownloadCoordinator(
                    configuration: configuration,
                    sink: sink,
                    onSnapshot: { snapshot in
                        Task {
                            await collector.append(snapshot.latestSample)
                            await reporter.printSnapshot(snapshot)
                        }
                    },
                    onFinished: { samples in
                        continuation.yield(samples)
                        continuation.finish()
                    },
                    onEvent: { message in
                        Task { await reporter.printInfo(message) }
                    },
                    onError: { message in
                        Task { await reporter.printError(message) }
                    }
                )

                coordinatorHolder.set(coordinator)
                coordinator.start()

                Task.detached(priority: .utility) {
                    while let line = readLine(strippingNewline: true) {
                        if line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "stop" {
                            await reporter.printInfo("Stop requested from stdin")
                            if let running = coordinatorHolder.get() {
                                await running.stop()
                            }
                            break
                        }
                    }
                }
            }

            await reporter.printStart(configuration: configuration, urls: urls)

            let autoExportTask = startAutoExportTaskIfNeeded(options: options, collector: collector, reporter: reporter)

            var finalSamples: [SessionSample] = []
            for await samples in completion {
                finalSamples = samples
            }

            autoExportTask?.cancel()
            await collector.replace(with: finalSamples)
            try exportIfRequested(options: options, samples: finalSamples)
            await reporter.printSummary(samples: finalSamples)
        } catch {
            PlatformConsole.writeErrorLine("Error: \(error.localizedDescription)")
            PlatformProcess.terminate(with: 1)
        }
    }

    private static func loadURLs(options: CLIOptions) throws -> [URL] {
        let endpointStrings: [String]
        if !options.urls.isEmpty {
            endpointStrings = options.urls
        } else {
            let fileURL = URL(fileURLWithPath: options.endpointsFile)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                let parsed = content
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("//") }
                endpointStrings = parsed.isEmpty ? defaultEndpoints : parsed
            } else {
                endpointStrings = defaultEndpoints
            }
        }

        let placeholders: Set<String> = ["example.com", "www.example.com"]
        var urls: [URL] = []

        for endpoint in endpointStrings {
            guard let url = URL(string: endpoint),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = url.host?.lowercased() else {
                continue
            }

            if placeholders.contains(host) {
                throw CLIError.placeholderEndpoint(endpoint)
            }

            urls.append(url)
        }

        guard !urls.isEmpty else {
            throw CLIError.noValidEndpoints
        }

        return urls
    }

    private static func apply(options: CLIOptions, to configuration: inout DownloadConfiguration) {
        configuration.durationPreset = durationPreset(from: options.duration)
        if configuration.durationPreset == .custom {
            configuration.customDurationHours = customHours(from: options.duration)
        }

        configuration.concurrency = options.concurrency
        configuration.timeoutSeconds = options.timeoutSeconds
        configuration.maxRetries = options.maxRetries
        configuration.backoffSeconds = options.backoffSeconds
        configuration.minRateMBps = options.minRateMBps
        configuration.switchAfterSeconds = options.switchAfterSeconds
        configuration.movingAverageWindowSeconds = options.movingAverageWindow

        configuration.saturateMaximum = options.saturateMaximum
        configuration.stableMode = options.stableMode
        configuration.maxRateMbps = options.maxRateMbps

        configuration.sinkMode = options.sinkMode
        configuration.ringBuffer = RingBufferConfiguration(
            cacheSizeGiB: options.ringCacheGiB,
            segmentSizeMiB: options.ringSegmentMiB,
            directoryPath: options.ringDirectory
        )
    }

    private static func durationPreset(from raw: String) -> DurationPreset {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "12", "12h":
            return .twelveHours
        case "24", "24h":
            return .twentyFourHours
        case "infinite", "inf", "forever":
            return .infinite
        default:
            return .custom
        }
    }

    private static func customHours(from raw: String) -> Double {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasSuffix("h") {
            let trimmed = String(normalized.dropLast())
            return max(Double(trimmed) ?? 12, 0.001)
        }
        return max(Double(normalized) ?? 12, 0.001)
    }

    private static func makeSink(configuration: DownloadConfiguration) throws -> any ByteSink {
        switch configuration.sinkMode {
        case .discard:
            return DiscardSink()

        case .ringBuffer:
            let directoryPath = configuration.ringBuffer.directoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedPath = directoryPath.isEmpty ? "./ring-buffer" : directoryPath
            let directoryURL = URL(fileURLWithPath: resolvedPath)
            return try DiskRingBuffer(
                directoryURL: directoryURL,
                cacheSizeBytes: configuration.ringBuffer.cacheSizeBytes,
                segmentSizeBytes: configuration.ringBuffer.segmentSizeBytes
            )
        }
    }

    private static func startAutoExportTaskIfNeeded(
        options: CLIOptions,
        collector: SampleCollector,
        reporter: ConsoleReporter
    ) -> Task<Void, Never>? {
        guard let path = options.autoExportDirectory,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let exportConfiguration = AutoExportConfiguration(
            directoryURL: URL(fileURLWithPath: path),
            intervalMinutes: options.autoExportIntervalMinutes,
            maxFiles: options.autoExportMaxFiles,
            maxTotalMB: options.autoExportMaxTotalMB,
            includeHTML: options.autoExportIncludeHTML
        )

        return Task.detached(priority: .utility) {
            while !Task.isCancelled {
                let interval = UInt64(max(exportConfiguration.intervalMinutes, 1)) * 60 * 1_000_000_000
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled {
                    return
                }

                let samples = await collector.allSamples()
                guard !samples.isEmpty else { continue }

                do {
                    _ = try AutoExportManager.exportSnapshot(samples: samples, configuration: exportConfiguration)
                    await reporter.printInfo("Auto-export snapshot written at \(exportConfiguration.directoryURL.path)")
                } catch {
                    await reporter.printError("Auto-export failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private static func exportIfRequested(
        options: CLIOptions,
        samples: [SessionSample]
    ) throws {
        guard !samples.isEmpty else { return }

        if let csvPath = options.csvOut, !csvPath.isEmpty {
            let csvURL = URL(fileURLWithPath: csvPath)
            try CSVExporter.export(samples: samples, to: csvURL, onlyLastHours: options.exportOnlyLastHours)
            PlatformConsole.writeLine("INFO: CSV exported to \(csvURL.path)")
        }

        if let htmlPath = options.htmlOut, !htmlPath.isEmpty {
            let htmlURL = URL(fileURLWithPath: htmlPath)
            let report = try HTMLReportGenerator.generate(title: "Wi-Fi Soak Test Report", samples: samples)
            try AtomicFileWriter.write(content: report, to: htmlURL)
            PlatformConsole.writeLine("INFO: HTML report exported to \(htmlURL.path)")
        }
    }

    private static func printHelp() {
        PlatformConsole.writeLine("""
WiFiSoakTester (CLI)

Usage:
  WiFiSoakTester [options]

Options:
  --help, -h                      Show help
  --url <URL>                     Add endpoint (repeatable)
  --endpoints-file <path>         Endpoints file (default: endpoints.txt)
  --duration <12h|24h|infinite|N> Duration (N = custom hours)
  --concurrency <1..4>            Worker count (default: 1)
  --timeout <seconds>             Request timeout (default: 15)
  --max-retries <n>               Retries per endpoint (default: 5)
  --backoff <seconds>             Base backoff (default: 1.5)
  --min-rate-mBps <value>         Low-performance threshold in MB/s (default: 1)
  --switch-after <seconds>        Rotate when under threshold for this long (default: 20)
  --moving-average-window <sec>   Moving average window (default: 10)
  --stable-rate-mbps <value>      Enable stable mode with rate cap (Mbps)

  --sink <discard|ring>           Byte sink mode (default: discard)
  --ring-dir <path>               Ring buffer directory
  --ring-cache-gib <n>            Ring cache size (default: 2)
  --ring-segment-mib <n>          Ring segment size (default: 64)

  --csv-out <path>                Export final CSV on finish
  --html-out <path>               Export final HTML report on finish
  --export-last-hours <n>         Filter CSV to last N hours

  --auto-export-dir <path>        Enable periodic auto-export
  --auto-export-interval-min <n>  Auto-export interval in minutes (default: 5)
  --auto-export-max-files <n>     Max snapshot files kept (default: 48)
  --auto-export-max-mb <n>        Max total MB for snapshots (default: 200)
  --auto-export-html <true|false> Include report_current.html (default: true)

Runtime:
  Type 'stop' + Enter to stop gracefully.
""")
    }
}
