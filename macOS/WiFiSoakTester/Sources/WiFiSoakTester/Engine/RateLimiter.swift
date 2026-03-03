import Foundation

actor RateLimiter {
    private let enabled: Bool
    private let maxBytesPerSecond: Int64
    private var windowStart: Date
    private var consumedInWindow: Int64

    init(enabled: Bool, maxBytesPerSecond: Double) {
        self.enabled = enabled
        self.maxBytesPerSecond = Int64(max(maxBytesPerSecond, 0))
        self.windowStart = Date()
        self.consumedInWindow = 0
    }

    func acquire(bytes: Int64) async {
        guard enabled, maxBytesPerSecond > 0, bytes > 0 else { return }

        let accounted = min(bytes, maxBytesPerSecond)

        while true {
            let now = Date()
            let elapsed = now.timeIntervalSince(windowStart)

            if elapsed >= 1 {
                windowStart = now
                consumedInWindow = 0
            }

            if consumedInWindow + accounted <= maxBytesPerSecond {
                consumedInWindow += accounted
                return
            }

            let waitSeconds = max(1 - elapsed, 0.001)
            let nanos = UInt64(waitSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
        }
    }
}
