import Foundation

actor MetricsStore {
    private var samples: CircularBuffer<SessionSample>
    private var speedSamples: CircularBuffer<Double>
    // Keep percentile calculations bounded to a recent window to reduce CPU over long sessions.
    private var percentileSamples: CircularBuffer<Double>
    private var totalBytes: Int64 = 0
    private var intervalBytes: Int64 = 0
    private var intervalBytesByWorker: [Int: Int64] = [:]
    private var totalBytesByWorker: [Int: Int64] = [:]
    private var workerCurrentBps: [Int: Double] = [:]
    private var startTime: Date?
    private var lastTick: Date?
    private var activeURLs: [Int: String] = [:]
    private var switches: Int = 0
    private var errors: Int = 0
    private var retries: Int = 0
    private var belowThresholdSeconds: TimeInterval = 0
    private var observedSeconds: TimeInterval = 0
    private var cachedP50: Double = 0
    private var cachedP95: Double = 0
    private var tickCount: Int = 0
    private let percentileRecalcIntervalTicks = 15
    private let movingAverageSampleCapacity = 600

    init(sampleCapacity: Int) {
        let capacity = max(sampleCapacity, 60)
        self.samples = CircularBuffer<SessionSample>(capacity: capacity)
        self.speedSamples = CircularBuffer<Double>(capacity: min(capacity, movingAverageSampleCapacity))
        self.percentileSamples = CircularBuffer<Double>(capacity: min(capacity, 3_600))
        let now = Date()
        self.startTime = now
        self.lastTick = now
    }

    func reset(sampleCapacity: Int, startedAt: Date = Date()) {
        let capacity = max(sampleCapacity, 60)
        samples = CircularBuffer<SessionSample>(capacity: capacity)
        speedSamples = CircularBuffer<Double>(capacity: min(capacity, movingAverageSampleCapacity))
        percentileSamples = CircularBuffer<Double>(capacity: min(capacity, 3_600))
        totalBytes = 0
        intervalBytes = 0
        intervalBytesByWorker = [:]
        totalBytesByWorker = [:]
        workerCurrentBps = [:]
        startTime = startedAt
        lastTick = startedAt
        activeURLs = [:]
        switches = 0
        errors = 0
        retries = 0
        belowThresholdSeconds = 0
        observedSeconds = 0
        cachedP50 = 0
        cachedP95 = 0
        tickCount = 0
    }

    func recordBytes(workerID: Int, bytes: Int64, url: URL) {
        guard bytes > 0 else { return }
        totalBytes += bytes
        intervalBytes += bytes
        intervalBytesByWorker[workerID, default: 0] += bytes
        totalBytesByWorker[workerID, default: 0] += bytes
        activeURLs[workerID] = url.absoluteString
    }

    func setActiveURL(workerID: Int, url: URL) {
        let newURL = url.absoluteString
        if let previous = activeURLs[workerID], previous != newURL {
            switches += 1
        }
        activeURLs[workerID] = newURL
    }

    func recordError() {
        errors += 1
    }

    func recordRetry() {
        retries += 1
    }

    func tick(now: Date, minRateBps: Double, movingAverageWindowSeconds: Int) -> MetricsSnapshot {
        if startTime == nil {
            startTime = now
            lastTick = now
        }

        let previousTick = lastTick ?? now
        let elapsedInterval = max(now.timeIntervalSince(previousTick), 0.001)
        let speedBps = Double(intervalBytes) / elapsedInterval
        intervalBytes = 0

        // Compute per-worker rates from this tick window.
        workerCurrentBps = [:]
        let workerIDs = Set(activeURLs.keys).union(intervalBytesByWorker.keys)
        for workerID in workerIDs {
            let bytes = intervalBytesByWorker[workerID, default: 0]
            workerCurrentBps[workerID] = Double(bytes) / elapsedInterval
        }
        intervalBytesByWorker = [:]
        lastTick = now

        let start = startTime ?? now
        let elapsed = max(now.timeIntervalSince(start), 0.001)
        let globalAverage = Double(totalBytes) / elapsed

        tickCount += 1
        speedSamples.append(speedBps)
        percentileSamples.append(speedBps)
        let allSpeeds = speedSamples.values()
        let percentileSpeeds = percentileSamples.values()

        if tickCount % percentileRecalcIntervalTicks == 0 || tickCount <= 3 {
            cachedP50 = Statistics.percentile(values: percentileSpeeds, percentile: 50)
            cachedP95 = Statistics.percentile(values: percentileSpeeds, percentile: 95)
        }

        if minRateBps > 0 {
            observedSeconds += elapsedInterval
            if speedBps < minRateBps {
                belowThresholdSeconds += elapsedInterval
            }
        }

        let belowThresholdPercent: Double
        if observedSeconds > 0 {
            belowThresholdPercent = (belowThresholdSeconds / observedSeconds) * 100
        } else {
            belowThresholdPercent = 0
        }

        let primaryURL: String
        if let firstWorker = activeURLs.keys.min(), let url = activeURLs[firstWorker] {
            primaryURL = url
        } else {
            primaryURL = "-"
        }
        let sample = SessionSample(
            timestamp: now,
            speedBps: speedBps,
            totalBytes: totalBytes,
            primaryURL: primaryURL,
            errors: errors,
            retries: retries
        )
        samples.append(sample)

        return MetricsSnapshot(
            latestSample: sample,
            currentSpeedBps: speedBps,
            movingAverageBps: Statistics.movingAverage(values: allSpeeds, window: movingAverageWindowSeconds),
            globalAverageBps: globalAverage,
            totalBytes: totalBytes,
            elapsedSeconds: elapsed,
            activeURLs: activeURLs,
            workerCurrentBps: workerCurrentBps,
            workerTotalBytes: totalBytesByWorker,
            switches: switches,
            errors: errors,
            retries: retries,
            p50Bps: cachedP50,
            p95Bps: cachedP95,
            belowThresholdPercent: belowThresholdPercent
        )
    }

    func allSamples() -> [SessionSample] {
        samples.values()
    }
}
