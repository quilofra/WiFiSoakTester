import Foundation

struct AutoExportConfiguration: Sendable {
    var directoryURL: URL
    var intervalMinutes: Int
    var maxFiles: Int
    var maxTotalMB: Int
    var includeHTML: Bool

    var maxTotalBytes: Int64 {
        Int64(max(maxTotalMB, 1)) * 1_048_576
    }
}

struct RotationPolicy: Sendable {
    var maxFiles: Int
    var maxTotalBytes: Int64

    init(maxFiles: Int, maxTotalBytes: Int64) {
        self.maxFiles = max(maxFiles, 1)
        self.maxTotalBytes = max(maxTotalBytes, 1)
    }
}

enum AutoExportManager {
    static func exportSnapshot(
        samples: [SessionSample],
        configuration: AutoExportConfiguration,
        now: Date = Date()
    ) throws -> [URL] {
        guard !samples.isEmpty else {
            throw ExportError.noSamples
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: configuration.directoryURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmss"

        let stamp = formatter.string(from: now)
        let snapshotCSV = configuration.directoryURL.appendingPathComponent("stats_\(stamp).csv")
        let currentCSV = configuration.directoryURL.appendingPathComponent("stats_current.csv")

        try CSVExporter.export(samples: samples, to: snapshotCSV, onlyLastHours: nil)
        try CSVExporter.export(samples: samples, to: currentCSV, onlyLastHours: nil)

        var written: [URL] = [snapshotCSV, currentCSV]

        if configuration.includeHTML {
            let html = try HTMLReportGenerator.generate(title: "Wi-Fi Soak Test Report", samples: samples, generatedAt: now)
            let htmlURL = configuration.directoryURL.appendingPathComponent("report_current.html")
            try AtomicFileWriter.write(content: html, to: htmlURL)
            written.append(htmlURL)
        }

        let policy = RotationPolicy(maxFiles: configuration.maxFiles, maxTotalBytes: configuration.maxTotalBytes)
        _ = try rotateSnapshots(directoryURL: configuration.directoryURL, policy: policy)

        return written
    }

    @discardableResult
    static func rotateSnapshots(directoryURL: URL, policy: RotationPolicy) throws -> [URL] {
        let fileManager = FileManager.default
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var snapshots = urls.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix("stats_") && name != "stats_current.csv" && url.pathExtension.lowercased() == "csv"
        }

        snapshots.sort { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }

        func totalSize(of urls: [URL]) -> Int64 {
            urls.reduce(0) { partial, url in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey])
                return partial + Int64(values?.fileSize ?? 0)
            }
        }

        var working = snapshots
        var total = totalSize(of: working)

        while working.count > policy.maxFiles || total > policy.maxTotalBytes {
            guard let oldest = working.first else { break }
            let size = Int64((try? oldest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            try? fileManager.removeItem(at: oldest)
            working.removeFirst()
            total = max(total - size, 0)
        }

        return working
    }
}
