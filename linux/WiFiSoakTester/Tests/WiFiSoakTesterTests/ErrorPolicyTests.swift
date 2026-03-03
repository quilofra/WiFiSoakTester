import XCTest
@testable import WiFiSoakTester

final class ErrorPolicyTests: XCTestCase {
    func testSecureConnectionFailedIsImmediateRotate() {
        let error = URLError(.secureConnectionFailed)
        XCTAssertEqual(ErrorPolicy.classify(error: error), .rotateImmediately)

        let decision = ErrorPolicy.decision(for: error, retryAttempt: 0, maxRetries: 5, baseBackoffSeconds: 1)
        XCTAssertEqual(decision, .rotateImmediately)
    }

    func testATSBlockedIsImmediateRotateWithSpecificMessage() {
        let error = URLError(.appTransportSecurityRequiresSecureConnection)
        XCTAssertEqual(ErrorPolicy.classify(error: error), .rotateImmediately)
        XCTAssertTrue(ErrorPolicy.describe(error: error).contains("ATS blocked insecure HTTP"))
    }

    func testTimeoutIsTransientRetry() {
        let error = URLError(.timedOut)
        XCTAssertEqual(ErrorPolicy.classify(error: error), .retryTransient)

        let decision = ErrorPolicy.decision(for: error, retryAttempt: 0, maxRetries: 3, baseBackoffSeconds: 1)
        guard case .retry(let delay) = decision else {
            return XCTFail("Expected retry decision")
        }
        XCTAssertGreaterThan(delay, 0)
    }

    func testHTTP404IsImmediateRotate() {
        let error = DownloadWorkerError.invalidHTTPStatus(404)
        XCTAssertEqual(ErrorPolicy.classify(error: error), .rotateImmediately)
    }

    func testHTTP503IsRetryTransient() {
        let error = DownloadWorkerError.invalidHTTPStatus(503)
        XCTAssertEqual(ErrorPolicy.classify(error: error), .retryTransient)
    }

    func testCancelledRequestStopsSessionWithoutRetry() {
        let error = URLError(.cancelled)
        XCTAssertEqual(ErrorPolicy.classify(error: error), .stopSession)

        let decision = ErrorPolicy.decision(for: error, retryAttempt: 0, maxRetries: 3, baseBackoffSeconds: 1)
        XCTAssertEqual(decision, .stopSession)
    }
}
