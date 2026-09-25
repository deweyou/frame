import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable

    var isRequested: Bool {
        self == .enabled || self == .requiresApproval
    }
}

@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func setEnabled(_ isEnabled: Bool) throws
}

@MainActor
final class LaunchAtLoginService: LaunchAtLoginServicing {
    private let appService: SMAppService

    init(appService: SMAppService = .mainApp) {
        self.appService = appService
    }

    var status: LaunchAtLoginStatus {
        switch appService.status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        @unknown default:
            .unavailable
        }
    }

    func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            guard !status.isRequested else {
                return
            }
            try appService.register()
        } else {
            guard status.isRequested else {
                return
            }
            try appService.unregister()
        }
    }
}

@MainActor
struct LaunchAtLoginSettingState: Equatable {
    private(set) var status: LaunchAtLoginStatus
    private(set) var errorDescription: String?

    init(service: any LaunchAtLoginServicing) {
        status = service.status
    }

    var isEnabled: Bool {
        status.isRequested
    }

    mutating func refresh(using service: any LaunchAtLoginServicing) {
        status = service.status
        errorDescription = nil
    }

    mutating func setEnabled(
        _ isEnabled: Bool,
        using service: any LaunchAtLoginServicing
    ) {
        do {
            try service.setEnabled(isEnabled)
            errorDescription = nil
        } catch {
            errorDescription = error.localizedDescription
        }

        status = service.status
    }
}
