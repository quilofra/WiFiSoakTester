import XCTest
@testable import WiFiSoakTester

@MainActor
final class ValidationTests: XCTestCase {
    func testStartBlockedWhenPlaceholderURLExists() {
        let vm = SoakTestViewModel()
        vm.endpointRows = [EndpointRow(value: "https://example.com/file.bin")]

        XCTAssertFalse(vm.canStart)
        XCTAssertNotNil(vm.startValidationError)
        XCTAssertTrue(vm.startValidationError?.contains("placeholder") ?? false)
    }

    func testStartBlockedWhenURLIsInvalid() {
        let vm = SoakTestViewModel()
        vm.endpointRows = [EndpointRow(value: "not a valid url")]

        XCTAssertFalse(vm.canStart)
        XCTAssertNotNil(vm.startValidationError)
        XCTAssertTrue(vm.startValidationError?.contains("URL inválida") ?? false)
    }

    func testStartEnabledForDefaultAllowedEndpoints() {
        let vm = SoakTestViewModel()
        vm.endpointRows = SoakTestViewModel.defaultEndpointStrings.map { EndpointRow(value: $0) }

        XCTAssertTrue(vm.canStart)
        XCTAssertNil(vm.startValidationError)
    }
}
