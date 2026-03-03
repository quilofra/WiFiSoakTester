import Foundation

enum ValueFormatting {
    static func speedMbps(_ bps: Double) -> String {
        String(format: "%.2f Mbps", bps * 8 / 1_000_000)
    }

    static func speedMBps(_ bps: Double) -> String {
        String(format: "%.2f MB/s", bps / 1_048_576)
    }

    static func bytes(_ total: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: total)
    }

    static func elapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}
