import XCTest
@testable import WiFiSoakTester

final class DiskRingBufferTests: XCTestCase {
    func testDiskRingBufferUsageStaysBounded() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let ring = try DiskRingBuffer(directoryURL: tempDir, cacheSizeBytes: 64, segmentSizeBytes: 16)

        let payload = Data((0..<100).map { UInt8($0 % 255) })
        try await ring.consume(payload)
        await ring.close()

        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.fileSizeKey])
        let total = try files.reduce(into: Int64(0)) { partial, url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            partial += Int64(values.fileSize ?? 0)
        }

        XCTAssertLessThanOrEqual(total, 64)
    }

    func testDiskRingBufferWritesDataAcrossSegments() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let ring = try DiskRingBuffer(directoryURL: tempDir, cacheSizeBytes: 256, segmentSizeBytes: 64)
        let payload = Data((0..<128).map { UInt8($0) })
        try await ring.consume(payload)
        await ring.close()

        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let merged = try files
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .reduce(into: Data()) { result, url in
                result.append(try Data(contentsOf: url))
            }

        XCTAssertTrue(merged.contains(127))
    }
}
