import Foundation
import IOKit.pwr_mgt

final class SleepAssertionManager {
    private var assertionID: IOPMAssertionID = 0

    var isActive: Bool {
        assertionID != 0
    }

    @discardableResult
    func begin(reason: String = "Wi-Fi soak test in progress") -> Bool {
        guard assertionID == 0 else {
            return true
        }

        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )

        if result != kIOReturnSuccess {
            assertionID = 0
            return false
        }

        return true
    }

    func end() {
        guard assertionID != 0 else {
            return
        }

        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }

    deinit {
        end()
    }
}
