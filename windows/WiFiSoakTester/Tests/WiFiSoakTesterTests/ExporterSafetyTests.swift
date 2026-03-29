import XCTest
@testable import WiFiSoakTester

final class ExporterSafetyTests: XCTestCase {
    func testCSVExportProducesConsistentRowsAndTrailingNewline() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("stats.csv")
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        let samples = [
            SessionSample(timestamp: baseDate, speedBps: 1_000_000, totalBytes: 100_000, primaryURL: "https://proof.ovh.net/files/1Gb.dat", errors: 0, retries: 0),
            SessionSample(timestamp: baseDate.addingTimeInterval(1), speedBps: 2_000_000, totalBytes: 300_000, primaryURL: "https://download.thinkbroadband.com/1GB.zip", errors: 1, retries: 1)
        ]

        try CSVExporter.export(samples: samples, to: fileURL, onlyLastHours: nil)

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.hasSuffix("\n"))

        let lines = content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "timestamp,speed_Bps,total_bytes,url,errors,retries")

        for line in lines.dropFirst() {
            XCTAssertFalse(line.range(of: "^[0-9]+$", options: .regularExpression) != nil, "Row should not be a stray number: \(line)")
            XCTAssertGreaterThanOrEqual(line.filter { $0 == "," }.count, 5)
        }
    }
}
