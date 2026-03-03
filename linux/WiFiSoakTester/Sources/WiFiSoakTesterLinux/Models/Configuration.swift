import Foundation

enum DurationPreset: String, CaseIterable, Identifiable, Codable {
    case twelveHours = "12h"
    case twentyFourHours = "24h"
    case custom = "Custom"
    case infinite = "Infinite"

    var id: String { rawValue }
}

enum SinkMode: String, CaseIterable, Identifiable, Codable {
    case discard = "Discard"
    case ringBuffer = "Ring Buffer"

    var id: String { rawValue }
}

struct RingBufferConfiguration: Sendable, Codable {
    var cacheSizeGiB: Double = 2.0
    var segmentSizeMiB: Int = 64
    var directoryPath: String = ""

    var cacheSizeBytes: Int64 {
        Int64(cacheSizeGiB * 1_073_741_824)
    }

    var segmentSizeBytes: Int64 {
        Int64(segmentSizeMiB) * 1_048_576
    }

    var directoryURL: URL? {
        guard !directoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: directoryPath)
    }
}

struct DownloadConfiguration: Sendable {
    var urls: [URL]
    var durationPreset: DurationPreset
    var customDurationHours: Double
    var saturateMaximum: Bool
    var stableMode: Bool
    var maxRateMbps: Double
    var sinkMode: SinkMode
    var ringBuffer: RingBufferConfiguration
    var timeoutSeconds: Double
    var maxRetries: Int
    var backoffSeconds: Double
    var minRateMBps: Double
    var switchAfterSeconds: Double
    var concurrency: Int
    var movingAverageWindowSeconds: Int
    var sampleCapacity: Int

    var minRateBps: Double {
        max(minRateMBps, 0) * 1_048_576
    }

    var maxRateBps: Double {
        max(maxRateMbps, 0) * 125_000
    }

    var durationSeconds: TimeInterval? {
        switch durationPreset {
        case .twelveHours:
            return 12 * 3600
        case .twentyFourHours:
            return 24 * 3600
        case .custom:
            return max(customDurationHours, 0) * 3600
        case .infinite:
            return nil
        }
    }

    static func makeDefault(urls: [URL]) -> DownloadConfiguration {
        DownloadConfiguration(
            urls: urls,
            durationPreset: .twelveHours,
            customDurationHours: 12,
            saturateMaximum: true,
            stableMode: false,
            maxRateMbps: 100,
            sinkMode: .discard,
            ringBuffer: RingBufferConfiguration(),
            timeoutSeconds: 15,
            maxRetries: 5,
            backoffSeconds: 1.5,
            minRateMBps: 1,
            switchAfterSeconds: 20,
            concurrency: 1,
            movingAverageWindowSeconds: 10,
            sampleCapacity: 86_400
        )
    }
}

struct EndpointRow: Identifiable, Codable, Hashable {
    let id: UUID
    var value: String

    init(id: UUID = UUID(), value: String) {
        self.id = id
        self.value = value
    }
}
