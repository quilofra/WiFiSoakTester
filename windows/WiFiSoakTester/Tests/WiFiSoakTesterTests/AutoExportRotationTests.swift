import XCTest
@testable import WiFiSoakTester

final class AutoExportRotationTests: XCTestCase {
    func testRotationRespectsMaxFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        for index in 0..<6 {
            let url = tempDir.appendingPathComponent(String(format: "stats_000%d.csv", index))
            try Data(repeating: UInt8(index), count: 512).write(to: url)
            let date = Date().addingTimeInterval(TimeInterval(index))
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }

        let kept = try AutoExportManager.rotateSnapshots(
            directoryURL: tempDir,
            policy: RotationPolicy(maxFiles: 3, maxTotalBytes: Int64.max)
        )

        XCTAssertEqual(kept.count, 3)
        let names = kept.map(\.lastPathComponent).sorted()
        XCTAssertEqual(names, ["stats_0003.csv", "stats_0004.csv", "stats_0005.csv"])
    }

    func testRotationRespectsMaxTotalBytes() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        for index in 0..<5 {
            let url = tempDir.appendingPathComponent(String(format: "stats_00%d.csv", index))
            try Data(repeating: UInt8(index), count: 1_200_000).write(to: url)
            let date = Date().addingTimeInterval(TimeInterval(index))
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }

        let kept = try AutoExportManager.rotateSnapshots(
            directoryURL: tempDir,
            policy: RotationPolicy(maxFiles: 10, maxTotalBytes: 2_500_000)
        )

        let totalSize = try kept.reduce(into: Int64(0)) { partial, fileURL in
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            partial += Int64(values.fileSize ?? 0)
        }

        XCTAssertLessThanOrEqual(totalSize, 2_500_000)
        XCTAssertFalse(kept.contains { $0.lastPathComponent == "stats_000.csv" })
    }
}
