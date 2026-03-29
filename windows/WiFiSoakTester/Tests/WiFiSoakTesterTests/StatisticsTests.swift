import XCTest
@testable import WiFiSoakTester

final class StatisticsTests: XCTestCase {
    func testMovingAverageUsesWindowSuffix() {
        let values: [Double] = [1, 2, 3, 4, 5, 6]
        let avg = Statistics.movingAverage(values: values, window: 3)
        XCTAssertEqual(avg, 5, accuracy: 0.0001)
    }

    func testMovingAverageHandlesLargeWindow() {
        let values: [Double] = [10, 20, 30]
        let avg = Statistics.movingAverage(values: values, window: 10)
        XCTAssertEqual(avg, 20, accuracy: 0.0001)
    }

    func testPercentilesP50AndP95() {
        let values: [Double] = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
        let p50 = Statistics.percentile(values: values, percentile: 50)
        let p95 = Statistics.percentile(values: values, percentile: 95)

        XCTAssertEqual(p50, 55, accuracy: 0.0001)
        XCTAssertEqual(p95, 95.5, accuracy: 0.0001)
    }
}
