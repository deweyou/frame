import XCTest
@testable import FrameApp

@MainActor
final class LaunchAtLoginServiceTests: XCTestCase {
    func testRequestedStatusIncludesEnabledAndRequiresApproval() {
        XCTAssertFalse(LaunchAtLoginStatus.notRegistered.isRequested)
        XCTAssertTrue(LaunchAtLoginStatus.enabled.isRequested)
        XCTAssertTrue(LaunchAtLoginStatus.requiresApproval.isRequested)
        XCTAssertFalse(LaunchAtLoginStatus.unavailable.isRequested)
    }

    func testSettingStateEnablesServiceAndRefreshesSystemStatus() {
        let service = StubLaunchAtLoginService(status: .notRegistered)
        var state = LaunchAtLoginSettingState(service: service)

        state.setEnabled(true, using: service)

        XCTAssertEqual(service.requestedValues, [true])
        XCTAssertEqual(state.status, .enabled)
        XCTAssertTrue(state.isEnabled)
        XCTAssertNil(state.errorDescription)
    }

    func testSettingStateDisablesServiceAndRefreshesSystemStatus() {
        let service = StubLaunchAtLoginService(status: .enabled)
        var state = LaunchAtLoginSettingState(service: service)

        state.setEnabled(false, using: service)

        XCTAssertEqual(service.requestedValues, [false])
        XCTAssertEqual(state.status, .notRegistered)
        XCTAssertFalse(state.isEnabled)
        XCTAssertNil(state.errorDescription)
    }

    func testSettingStateTreatsRequiresApprovalAsRequested() {
        let service = StubLaunchAtLoginService(status: .requiresApproval)
        let state = LaunchAtLoginSettingState(service: service)

        XCTAssertTrue(state.isEnabled)
    }

    func testSettingStateRefreshesExternalSystemChange() {
        let service = StubLaunchAtLoginService(status: .notRegistered)
        var state = LaunchAtLoginSettingState(service: service)
        service.status = .enabled

        state.refresh(using: service)

        XCTAssertEqual(state.status, .enabled)
        XCTAssertTrue(state.isEnabled)
    }

    func testSettingStateRollsBackToSystemStatusAfterFailure() {
        let service = StubLaunchAtLoginService(
            status: .notRegistered,
            error: StubLaunchAtLoginError.registrationFailed
        )
        var state = LaunchAtLoginSettingState(service: service)

        state.setEnabled(true, using: service)

        XCTAssertEqual(service.requestedValues, [true])
        XCTAssertEqual(state.status, .notRegistered)
        XCTAssertFalse(state.isEnabled)
        XCTAssertEqual(state.errorDescription, "Registration failed")
    }
}

@MainActor
private final class StubLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus
    var requestedValues: [Bool] = []
    private let error: Error?

    init(status: LaunchAtLoginStatus, error: Error? = nil) {
        self.status = status
        self.error = error
    }

    func setEnabled(_ isEnabled: Bool) throws {
        requestedValues.append(isEnabled)
        if let error {
            throw error
        }
        status = isEnabled ? .enabled : .notRegistered
    }
}

private enum StubLaunchAtLoginError: LocalizedError {
    case registrationFailed

    var errorDescription: String? {
        "Registration failed"
    }
}
