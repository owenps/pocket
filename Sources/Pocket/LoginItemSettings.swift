import Observation
import ServiceManagement

@MainActor
@Observable
final class LoginItemSettings {
    private(set) var isEnabled = false
    private(set) var error: String?
    private(set) var requiresApproval = false

    var statusMessage: String? {
        requiresApproval
            ? "Allow Pocket in System Settings → General → Login Items to launch at login."
            : nil
    }

    private let status: @MainActor () -> SMAppService.Status
    private let register: @MainActor () throws -> Void
    private let unregister: @MainActor () throws -> Void
    private let openSettings: @MainActor () -> Void

    init(
        status: @escaping @MainActor () -> SMAppService.Status = { SMAppService.mainApp.status },
        register: @escaping @MainActor () throws -> Void = { try SMAppService.mainApp.register() },
        unregister: @escaping @MainActor () throws -> Void = { try SMAppService.mainApp.unregister() },
        openSettings: @escaping @MainActor () -> Void = { SMAppService.openSystemSettingsLoginItems() }
    ) {
        self.status = status
        self.register = register
        self.unregister = unregister
        self.openSettings = openSettings
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try register()
            } else {
                try unregister()
            }
            refresh()
        } catch {
            refresh()
            self.error = error.localizedDescription
        }
    }

    func refresh() {
        let currentStatus = status()
        isEnabled = currentStatus == .enabled
        requiresApproval = currentStatus == .requiresApproval
        error = nil
    }

    func openSystemSettings() {
        openSettings()
    }
}
