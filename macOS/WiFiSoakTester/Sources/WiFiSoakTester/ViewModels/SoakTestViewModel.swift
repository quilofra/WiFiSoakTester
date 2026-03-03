import Foundation
import SwiftUI

@MainActor
final class SoakTestViewModel: ObservableObject {
    static let defaultEndpointStrings: [String] = [
        "https://proof.ovh.net/files/10Gb.dat",
        "https://proof.ovh.net/files/1Gb.dat",
        "https://proof.ovh.net/files/100Mb.dat",
        "https://download.thinkbroadband.com/2GB.zip",
        "https://download.thinkbroadband.com/1GB.zip",
        "https://download.thinkbroadband.com/512MB.zip"
    ]

    private static let placeholderHosts: Set<String> = [
        "example.com",
        "www.example.com"
    ]

    enum ChartWindow: String, CaseIterable, Identifiable {
        case oneHour = "1h"
        case sixHours = "6h"
        case all = "All"

        var id: String { rawValue }

        var seconds: TimeInterval? {
            switch self {
            case .oneHour: return 3_600
            case .sixHours: return 21_600
            case .all: return nil
            }
        }
    }

    enum SessionState: String {
        case idle
        case starting
        case running
        case stopping
        case finished
        case failed

        var statusText: String {
            switch self {
            case .idle: return "Idle"
            case .starting: return "Starting"
            case .running: return "Running"
            case .stopping: return "Stopping"
            case .finished: return "Stopped"
            case .failed: return "Error"
            }
        }

        var behavesAsRunning: Bool {
            switch self {
            case .starting, .running, .stopping:
                return true
            case .idle, .finished, .failed:
                return false
            }
        }
    }

    @Published var endpointRows: [EndpointRow] = SoakTestViewModel.defaultEndpointStrings.map { EndpointRow(value: $0) }

    @Published var durationPreset: DurationPreset = .twelveHours
    @Published var customDurationHours: Double = 12

    @Published var saturateMaximum: Bool = true
    @Published var stableMode: Bool = false
    @Published var maxRateMbps: Double = 100

    @Published var sinkMode: SinkMode = .discard
    @Published var ringCacheGiB: Double = 2
    @Published var ringSegmentMiB: Int = 64
    @Published var ringDirectoryPath: String = ""

    @Published var timeoutSeconds: Double = 15
    @Published var maxRetries: Int = 5
    @Published var backoffSeconds: Double = 1.5

    @Published var minRateMBps: Double = 1
    @Published var switchAfterSeconds: Double = 20
    @Published var concurrency: Int = 1
    @Published var movingAverageWindowSeconds: Int = 10

    @Published var useMbps: Bool = true
    @Published var showTotalSeries: Bool = true
    @Published var chartWindow: ChartWindow = .oneHour
    @Published var appearanceMode: AppearanceMode = .enhanced
    @Published var themePreset: ThemePreset = .ocean

    @Published var exportOnlyLast24h: Bool = true

    @Published var autoExportEnabled: Bool = false
    @Published var autoExportIntervalMinutes: Int = 5
    @Published var autoExportDirectoryPath: String = ""
    @Published var autoExportMaxFiles: Int = 48
    @Published var autoExportMaxTotalMB: Int = 200
    @Published var autoExportIncludeHTML: Bool = true
    @Published private(set) var autoExportStatus: String = "Disabled"

    @Published private(set) var sessionState: SessionState = .idle
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var preventingSleep: Bool = false
    @Published private(set) var statusMessage: String = SessionState.idle.statusText

    @Published private(set) var currentSpeedBps: Double = 0
    @Published private(set) var movingAverageBps: Double = 0
    @Published private(set) var globalAverageBps: Double = 0
    @Published private(set) var totalBytes: Int64 = 0
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var activeURLText: String = "-"
    @Published private(set) var workerStatusText: String = "-"
    @Published private(set) var switchCount: Int = 0
    @Published private(set) var errors: Int = 0
    @Published private(set) var retries: Int = 0
    @Published private(set) var p50Bps: Double = 0
    @Published private(set) var p95Bps: Double = 0
    @Published private(set) var belowThresholdPercent: Double = 0
    @Published private(set) var lastEngineEvent: String = "-"
    @Published private(set) var lastErrorMessage: String = "-"
    @Published private(set) var recentEvents: [String] = []

    @Published private(set) var samples: [SessionSample] = []
    @Published var userError: String?

    private let maxStoredSamples = 172_800
    private let maxRecentEvents = 200
    private var coordinator: DownloadCoordinator?
    private var startTask: Task<Void, Never>?
    private var autoExportTask: Task<Void, Never>?
    private let sleepAssertionManager = SleepAssertionManager()

    var startValidationError: String? {
        do {
            _ = try parseURLs(rejectPlaceholders: true)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var canStart: Bool {
        startValidationError == nil
    }

    var menuBarTitle: String {
        if isRunning {
            return useMbps ? ValueFormatting.speedMbps(currentSpeedBps) : ValueFormatting.speedMBps(currentSpeedBps)
        }
        return "Soak"
    }

    var menuBarStateText: String {
        sessionState.statusText
    }

    var themePalette: ThemePalette {
        VisualTheme.palette(for: themePreset)
    }

    func addEndpoint() {
        endpointRows.append(EndpointRow(value: ""))
    }

    func removeEndpoint(id: UUID) {
        endpointRows.removeAll { $0.id == id }
    }

    func removeEndpoints(at offsets: IndexSet) {
        endpointRows.remove(atOffsets: offsets)
    }

    func chooseRingDirectory() {
        if let folder = FileDialogs.chooseDirectory() {
            ringDirectoryPath = folder.path
        }
    }

    func chooseAutoExportDirectory() {
        if let folder = FileDialogs.chooseDirectory() {
            autoExportDirectoryPath = folder.path
        }
    }

    func importURLList() {
        guard let fileURL = FileDialogs.chooseTextFile() else { return }

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("//") }

            endpointRows = lines.map { EndpointRow(value: $0) }
        } catch {
            userError = "No se pudo importar el archivo de URLs: \(error.localizedDescription)"
        }
    }

    func exportURLList() {
        guard let fileURL = FileDialogs.saveFile(defaultName: "endpoints.txt", allowedExtension: "txt") else {
            return
        }

        let lines = endpointRows.map(\.value)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        do {
            try AtomicFileWriter.write(content: lines.joined(separator: "\n") + "\n", to: fileURL)
        } catch {
            userError = "No se pudo exportar la lista: \(error.localizedDescription)"
        }
    }

    func start() {
        guard !isRunning else { return }
        if let validation = startValidationError {
            userError = validation
            return
        }

        startTask?.cancel()
        transition(to: .starting)
        appendRecentEvent("Session starting")

        startTask = Task { [weak self] in
            guard let self else { return }
            await self.startInternal()
        }
    }

    func stop() {
        guard sessionState.behavesAsRunning else { return }

        transition(to: .stopping)
        appendRecentEvent("Session stopping")
        startTask?.cancel()
        startTask = nil

        Task { [weak self] in
            guard let self else { return }
            if let coordinator = self.coordinator {
                await coordinator.stop()
            } else {
                self.finish(with: self.samples)
            }
        }
    }

    private func startInternal() async {
        do {
            var configuration = try makeConfiguration()
            let preflight = await preflightEndpoints(
                configuration.urls,
                timeoutSeconds: min(max(configuration.timeoutSeconds, 3), 10)
            )

            guard !preflight.healthy.isEmpty else {
                let details = preflight.failed.prefix(3).joined(separator: " | ")
                throw NSError(
                    domain: "SoakTest",
                    code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "Ningún endpoint respondió en el preflight. \(details)"]
                )
            }

            configuration.urls = preflight.healthy
            let sink = try makeSink(from: configuration)
            try validateAutoExportConfigurationIfNeeded()

            withAnimation(.easeInOut(duration: 0.25)) {
                resetRuntimeMetrics()
                userError = nil
                preventingSleep = sleepAssertionManager.begin()
                transition(to: .running)
                if !preflight.failed.isEmpty {
                    lastEngineEvent = "Preflight: \(preflight.healthy.count) OK / \(preflight.failed.count) failed"
                    appendRecentEvent(lastEngineEvent)
                }
            }

            let coordinator = DownloadCoordinator(
                configuration: configuration,
                sink: sink,
                onSnapshot: { snapshot in
                    Task { @MainActor [weak self, snapshot] in
                        self?.apply(snapshot: snapshot)
                    }
                },
                onFinished: { allSamples in
                    Task { @MainActor [weak self, allSamples] in
                        self?.finish(with: allSamples)
                    }
                },
                onEvent: { event in
                    Task { @MainActor [weak self, event] in
                        self?.lastEngineEvent = event
                        self?.appendRecentEvent(event)
                    }
                },
                onError: { message in
                    Task { @MainActor [weak self, message] in
                        self?.lastErrorMessage = message
                        self?.appendRecentEvent("ERROR: \(message)")
                    }
                }
            )
            self.coordinator = coordinator
            coordinator.start()
            startAutoExportLoopIfNeeded()
            startTask = nil
        } catch is CancellationError {
            startTask = nil
        } catch {
            withAnimation(.easeInOut(duration: 0.2)) {
                transition(to: .failed)
                userError = error.localizedDescription
                lastErrorMessage = error.localizedDescription
                appendRecentEvent("ERROR: \(error.localizedDescription)")
                preventingSleep = false
            }
            startTask = nil
            sleepAssertionManager.end()
        }
    }

    func exportCSV() {
        guard !samples.isEmpty else {
            userError = "No hay muestras para exportar."
            return
        }

        guard let fileURL = FileDialogs.saveFile(defaultName: "soak_test.csv", allowedExtension: "csv") else {
            return
        }

        do {
            let hours = exportOnlyLast24h ? 24 : nil
            try CSVExporter.export(samples: samples, to: fileURL, onlyLastHours: hours)
            statusMessage = "CSV exportado"
        } catch {
            userError = "No se pudo exportar CSV: \(error.localizedDescription)"
        }
    }

    func generateHTMLReport() {
        guard !samples.isEmpty else {
            userError = "No hay muestras para generar el reporte."
            return
        }

        guard let fileURL = FileDialogs.saveFile(defaultName: "report.html", allowedExtension: "html") else {
            return
        }

        do {
            let report = try HTMLReportGenerator.generate(title: "Wi-Fi Soak Test Report", samples: samples)
            try AtomicFileWriter.write(content: report, to: fileURL)
            statusMessage = "Reporte HTML generado"
        } catch {
            userError = "No se pudo generar el reporte HTML: \(error.localizedDescription)"
        }
    }

    var chartSamples: [SessionSample] {
        downsample(samples: filterByWindow(samples: samples), maxPoints: 2_000)
    }

    private func filterByWindow(samples: [SessionSample]) -> [SessionSample] {
        guard let window = chartWindow.seconds, let latest = samples.last?.timestamp else {
            return samples
        }

        let cutoff = latest.addingTimeInterval(-window)
        return samples.filter { $0.timestamp >= cutoff }
    }

    private func downsample(samples: [SessionSample], maxPoints: Int) -> [SessionSample] {
        guard samples.count > maxPoints, maxPoints > 1 else {
            return samples
        }

        let step = Double(samples.count - 1) / Double(maxPoints - 1)
        var output: [SessionSample] = []
        output.reserveCapacity(maxPoints)

        for index in 0..<maxPoints {
            let source = Int(round(Double(index) * step))
            output.append(samples[min(source, samples.count - 1)])
        }

        return output
    }

    private func apply(snapshot: MetricsSnapshot) {
        currentSpeedBps = snapshot.currentSpeedBps
        movingAverageBps = snapshot.movingAverageBps
        globalAverageBps = snapshot.globalAverageBps
        totalBytes = snapshot.totalBytes
        elapsedSeconds = snapshot.elapsedSeconds
        switchCount = snapshot.switches
        errors = snapshot.errors
        retries = snapshot.retries
        p50Bps = snapshot.p50Bps
        p95Bps = snapshot.p95Bps
        belowThresholdPercent = snapshot.belowThresholdPercent

        let workerLines = snapshot.activeURLs
            .sorted { $0.key < $1.key }
            .map { workerID, url in
                let workerRate = snapshot.workerCurrentBps[workerID] ?? 0
                let speed = useMbps ? ValueFormatting.speedMbps(workerRate) : ValueFormatting.speedMBps(workerRate)
                return "W\(workerID + 1): \(speed) @ \(url)"
            }
        activeURLText = workerLines.joined(separator: " | ")
        workerStatusText = workerLines.joined(separator: "\n")

        append(sample: snapshot.latestSample)
    }

    private func append(sample: SessionSample) {
        if samples.count >= maxStoredSamples {
            samples.removeFirst(samples.count - maxStoredSamples + 1)
        }
        samples.append(sample)
    }

    private func finish(with allSamples: [SessionSample]) {
        if !allSamples.isEmpty {
            samples = allSamples
        }

        startTask?.cancel()
        startTask = nil
        autoExportTask?.cancel()
        autoExportTask = nil
        autoExportStatus = autoExportEnabled ? "Stopped" : "Disabled"

        withAnimation(.easeInOut(duration: 0.25)) {
            transition(to: .finished)
            appendRecentEvent("Session stopped")
            preventingSleep = false
        }

        sleepAssertionManager.end()
        coordinator = nil
    }

    private func resetRuntimeMetrics() {
        currentSpeedBps = 0
        movingAverageBps = 0
        globalAverageBps = 0
        totalBytes = 0
        elapsedSeconds = 0
        activeURLText = "-"
        workerStatusText = "-"
        switchCount = 0
        errors = 0
        retries = 0
        p50Bps = 0
        p95Bps = 0
        belowThresholdPercent = 0
        lastEngineEvent = "-"
        lastErrorMessage = "-"
        recentEvents = []
        samples = []
    }

    private func transition(to newState: SessionState, status: String? = nil) {
        sessionState = newState
        isRunning = newState.behavesAsRunning
        statusMessage = status ?? newState.statusText
    }

    private func appendRecentEvent(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        recentEvents.append("[\(timestamp)] \(trimmed)")

        if recentEvents.count > maxRecentEvents {
            recentEvents.removeFirst(recentEvents.count - maxRecentEvents)
        }
    }

    private func makeConfiguration() throws -> DownloadConfiguration {
        let parsedURLs = try parseURLs(rejectPlaceholders: true)

        let ring = RingBufferConfiguration(
            cacheSizeGiB: max(ringCacheGiB, 0.1),
            segmentSizeMiB: max(ringSegmentMiB, 1),
            directoryPath: ringDirectoryPath
        )

        return DownloadConfiguration(
            urls: parsedURLs,
            durationPreset: durationPreset,
            customDurationHours: customDurationHours,
            saturateMaximum: saturateMaximum,
            stableMode: stableMode,
            maxRateMbps: maxRateMbps,
            sinkMode: sinkMode,
            ringBuffer: ring,
            timeoutSeconds: timeoutSeconds,
            maxRetries: maxRetries,
            backoffSeconds: backoffSeconds,
            minRateMBps: minRateMBps,
            switchAfterSeconds: switchAfterSeconds,
            concurrency: min(max(concurrency, 1), 4),
            movingAverageWindowSeconds: min(max(movingAverageWindowSeconds, 5), 60),
            sampleCapacity: maxStoredSamples
        )
    }

    private func parseURLs(rejectPlaceholders: Bool) throws -> [URL] {
        let raw = endpointRows.map(\.value)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !raw.isEmpty else {
            throw NSError(domain: "SoakTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Debes indicar al menos una URL válida."])
        }

        let urls: [URL] = try raw.map { value in
            guard
                let url = URL(string: value),
                let scheme = url.scheme?.lowercased(),
                scheme == "http" || scheme == "https"
            else {
                throw NSError(domain: "SoakTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "URL inválida: \(value)"])
            }
            return url
        }

        if rejectPlaceholders {
            if let bad = urls.first(where: { url in
                guard let host = url.host?.lowercased() else { return false }
                return SoakTestViewModel.placeholderHosts.contains(host)
            }) {
                throw NSError(
                    domain: "SoakTest",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "URL placeholder detectada: \(bad.absoluteString). Sustitúyela por un endpoint permitido antes de iniciar."]
                )
            }
        }

        return urls
    }

    private func preflightEndpoints(_ urls: [URL], timeoutSeconds: Double) async -> (healthy: [URL], failed: [String]) {
        guard !urls.isEmpty else {
            return ([], [])
        }

        let timeout = max(timeoutSeconds, 2)

        let results = await withTaskGroup(of: (URL, Bool, String).self) { group in
            for url in urls {
                group.addTask {
                    let config = URLSessionConfiguration.ephemeral
                    config.timeoutIntervalForRequest = timeout
                    config.timeoutIntervalForResource = timeout
                    config.waitsForConnectivity = false
                    let session = URLSession(configuration: config)
                    defer { session.invalidateAndCancel() }

                    func probeByHead() async -> (Bool, String)? {
                        var head = URLRequest(url: url)
                        head.httpMethod = "HEAD"
                        head.timeoutInterval = timeout
                        head.cachePolicy = .reloadIgnoringLocalCacheData

                        do {
                            let (_, response) = try await session.data(for: head)
                            if let http = response as? HTTPURLResponse {
                                if (200...299).contains(http.statusCode) {
                                    return (true, "OK \(http.statusCode) \(url.absoluteString)")
                                }
                                if http.statusCode == 405 || http.statusCode == 501 {
                                    return nil
                                }
                                return (false, "HTTP \(http.statusCode) \(url.absoluteString)")
                            }
                            return (true, "OK \(url.absoluteString)")
                        } catch {
                            return nil
                        }
                    }

                    func probeByStreamingRange() async -> (Bool, String) {
                        var ranged = URLRequest(url: url)
                        ranged.httpMethod = "GET"
                        ranged.timeoutInterval = timeout
                        ranged.cachePolicy = .reloadIgnoringLocalCacheData
                        ranged.setValue("bytes=0-1023", forHTTPHeaderField: "Range")

                        do {
                            let (bytes, response) = try await session.bytes(for: ranged)
                            if let http = response as? HTTPURLResponse {
                                if !(200...299).contains(http.statusCode) && http.statusCode != 206 {
                                    return (false, "HTTP \(http.statusCode) \(url.absoluteString)")
                                }
                            }

                            var iterator = bytes.makeAsyncIterator()
                            _ = try await iterator.next()
                            return (true, "OK \(url.absoluteString)")
                        } catch {
                            return (false, "\(ErrorPolicy.describe(error: error)) \(url.absoluteString)")
                        }
                    }

                    if let headResult = await probeByHead() {
                        return (url, headResult.0, headResult.1)
                    }
                    let fallback = await probeByStreamingRange()
                    return (url, fallback.0, fallback.1)
                }
            }

            var gathered: [(URL, Bool, String)] = []
            for await result in group {
                gathered.append(result)
            }
            return gathered
        }

        let healthySet = Set(results.compactMap { $0.1 ? $0.0 : nil })
        let orderedHealthy = urls.filter { healthySet.contains($0) }
        let failed = results.filter { !$0.1 }.map { $0.2 }
        return (orderedHealthy, failed)
    }

    private func makeSink(from configuration: DownloadConfiguration) throws -> any ByteSink {
        switch configuration.sinkMode {
        case .discard:
            return DiscardSink()

        case .ringBuffer:
            guard let directory = configuration.ringBuffer.directoryURL else {
                throw NSError(domain: "SoakTest", code: 3, userInfo: [NSLocalizedDescriptionKey: "Selecciona carpeta destino para el ring buffer."])
            }

            return try DiskRingBuffer(
                directoryURL: directory,
                cacheSizeBytes: configuration.ringBuffer.cacheSizeBytes,
                segmentSizeBytes: configuration.ringBuffer.segmentSizeBytes
            )
        }
    }

    private func validateAutoExportConfigurationIfNeeded() throws {
        guard autoExportEnabled else {
            autoExportStatus = "Disabled"
            return
        }

        let trimmed = autoExportDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "SoakTest", code: 4, userInfo: [NSLocalizedDescriptionKey: "Activa Auto-export solo después de elegir carpeta de destino."])
        }

        autoExportStatus = "Ready"
    }

    private func startAutoExportLoopIfNeeded() {
        autoExportTask?.cancel()
        autoExportTask = nil

        guard autoExportEnabled else {
            autoExportStatus = "Disabled"
            return
        }

        let directoryPath = autoExportDirectoryPath
        let intervalMinutes = max(autoExportIntervalMinutes, 1)
        let maxFiles = max(autoExportMaxFiles, 1)
        let maxTotalMB = max(autoExportMaxTotalMB, 1)
        let includeHTML = autoExportIncludeHTML

        autoExportStatus = "Running (\(intervalMinutes)m)"

        autoExportTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let sleepNanos = UInt64(intervalMinutes) * 60 * 1_000_000_000
                try? await Task.sleep(nanoseconds: sleepNanos)
                if Task.isCancelled { return }

                let samplesToExport = await MainActor.run { self.samples }
                guard !samplesToExport.isEmpty else { continue }

                let config = AutoExportConfiguration(
                    directoryURL: URL(fileURLWithPath: directoryPath),
                    intervalMinutes: intervalMinutes,
                    maxFiles: maxFiles,
                    maxTotalMB: maxTotalMB,
                    includeHTML: includeHTML
                )

                do {
                    _ = try AutoExportManager.exportSnapshot(samples: samplesToExport, configuration: config)
                    await MainActor.run {
                        self.autoExportStatus = "Last export: \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))"
                    }
                } catch {
                    await MainActor.run {
                        self.autoExportStatus = "Auto-export error"
                        self.lastErrorMessage = "Auto-export: \(error.localizedDescription)"
                        self.userError = "Auto-export falló: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
