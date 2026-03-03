import XCTest
@testable import WiFiSoakTester

final class URLRotatorTests: XCTestCase {
    func testRoundRobinSkipsFailedURLWhenPossible() async throws {
        let urls = [
            URL(string: "https://a.test.invalid")!,
            URL(string: "https://b.test.invalid")!,
            URL(string: "https://c.test.invalid")!
        ]
        let rotator = URLRotator(urls: urls, failureCooldown: 100, lowPerformanceCooldown: 50)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = await rotator.nextURL(now: now)
        XCTAssertEqual(first, urls[0])

        await rotator.markFailure(urls[0], now: now)

        let second = await rotator.nextURL(avoiding: urls[0], now: now.addingTimeInterval(1))
        XCTAssertEqual(second, urls[1])
    }

    func testLowPerformanceCooldownTemporarilyRemovesEndpoint() async throws {
        let urls = [
            URL(string: "https://a.test.invalid")!,
            URL(string: "https://b.test.invalid")!
        ]
        let rotator = URLRotator(urls: urls, failureCooldown: 100, lowPerformanceCooldown: 30)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = await rotator.nextURL(now: now)
        await rotator.markLowPerformance(urls[1], now: now)

        let duringCooldown = await rotator.nextURL(now: now.addingTimeInterval(5))
        XCTAssertEqual(duringCooldown, urls[0])

        let afterCooldown = await rotator.nextURL(now: now.addingTimeInterval(35))
        XCTAssertEqual(afterCooldown, urls[1])
    }
}
