import Foundation

struct SessionSample: Identifiable, Sendable, Codable {
    let id: UUID
    let timestamp: Date
    let speedBps: Double
    let totalBytes: Int64
    let primaryURL: String
    let errors: Int
    let retries: Int

    init(
        id: UUID = UUID(),
        timestamp: Date,
        speedBps: Double,
        totalBytes: Int64,
        primaryURL: String,
        errors: Int,
        retries: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.speedBps = speedBps
        self.totalBytes = totalBytes
        self.primaryURL = primaryURL
        self.errors = errors
        self.retries = retries
    }
}

struct MetricsSnapshot: Sendable {
    let latestSample: SessionSample
    let currentSpeedBps: Double
    let movingAverageBps: Double
    let globalAverageBps: Double
    let totalBytes: Int64
    let elapsedSeconds: TimeInterval
    let activeURLs: [Int: String]
    let workerCurrentBps: [Int: Double]
    let workerTotalBytes: [Int: Int64]
    let switches: Int
    let errors: Int
    let retries: Int
    let p50Bps: Double
    let p95Bps: Double
    let belowThresholdPercent: Double
}

struct CircularBuffer<Element: Sendable>: Sendable {
    private(set) var capacity: Int
    private var storage: [Element?]
    private var startIndex: Int
    private(set) var count: Int

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
        self.storage = Array(repeating: nil, count: max(capacity, 1))
        self.startIndex = 0
        self.count = 0
    }

    mutating func append(_ value: Element) {
        if count < capacity {
            storage[(startIndex + count) % capacity] = value
            count += 1
            return
        }

        storage[startIndex] = value
        startIndex = (startIndex + 1) % capacity
    }

    func values() -> [Element] {
        guard count > 0 else { return [] }
        var result: [Element] = []
        result.reserveCapacity(count)

        for offset in 0..<count {
            let index = (startIndex + offset) % capacity
            if let value = storage[index] {
                result.append(value)
            }
        }

        return result
    }

    mutating func removeAll(keepingCapacity: Bool = true) {
        if keepingCapacity {
            storage = Array(repeating: nil, count: capacity)
        } else {
            capacity = 1
            storage = [nil]
        }
        startIndex = 0
        count = 0
    }
}

enum Statistics {
    static func movingAverage(values: [Double], window: Int) -> Double {
        guard !values.isEmpty else { return 0 }
        let count = min(max(window, 1), values.count)
        let slice = values.suffix(count)
        let sum = slice.reduce(0, +)
        return sum / Double(count)
    }

    static func percentile(values: [Double], percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let p = min(max(percentile, 0), 100)
        let sorted = values.sorted()
        if sorted.count == 1 { return sorted[0] }

        let rank = (p / 100) * Double(sorted.count - 1)
        let lower = Int(floor(rank))
        let upper = Int(ceil(rank))
        if lower == upper { return sorted[lower] }

        let weight = rank - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }
}
