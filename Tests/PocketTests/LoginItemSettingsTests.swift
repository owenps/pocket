import Foundation
import ServiceManagement
import Testing
@testable import Pocket

@MainActor
struct LoginItemSettingsTests {
    @Test(arguments: [
        SMAppService.Status.notRegistered, .enabled, .requiresApproval, .notFound,
    ])
    func initializationReadsSystemStatusWithoutChangingRegistration(status: SMAppService.Status) {
        let settings = LoginItemSettings(
            status: { status },
            register: { Issue.record("Initialization must not register Pocket") },
            unregister: { Issue.record("Initialization must not unregister Pocket") },
            openSettings: { Issue.record("Initialization must not open System Settings") }
        )

        #expect(settings.isEnabled == (status == .enabled))
        #expect(settings.requiresApproval == (status == .requiresApproval))
        #expect((settings.statusMessage != nil) == (status == .requiresApproval))
        #expect(settings.error == nil)
    }

    @Test func enablingAndDisablingReflectSystemRegistration() {
        let service = LoginItemServiceStub()
        let settings = service.makeSettings()

        settings.setEnabled(true)

        #expect(service.registrations == 1)
        #expect(service.unregistrations == 0)
        #expect(settings.isEnabled)
        #expect(!settings.requiresApproval)
        #expect(settings.error == nil)

        settings.setEnabled(false)

        #expect(service.registrations == 1)
        #expect(service.unregistrations == 1)
        #expect(!settings.isEnabled)
        #expect(settings.error == nil)
    }

    @Test func successfulRequestDoesNotInventEnabledState() {
        let settings = LoginItemSettings(
            status: { .notRegistered },
            register: {},
            unregister: {},
            openSettings: {}
        )

        settings.setEnabled(true)

        #expect(!settings.isEnabled)
        #expect(settings.error == nil)
    }

    @Test func approvalExplainsWhyRegistrationIsNotEnabled() {
        let service = LoginItemServiceStub()
        service.registrationStatus = .requiresApproval
        let settings = service.makeSettings()

        settings.setEnabled(true)

        #expect(!settings.isEnabled)
        #expect(settings.requiresApproval)
        #expect(settings.statusMessage?.contains("System Settings") == true)
        #expect(settings.error == nil)

        settings.openSystemSettings()

        #expect(service.settingsOpened == 1)
        #expect(!settings.isEnabled)
        #expect(settings.requiresApproval)
        #expect(service.registrations == 1)

        service.status = .enabled
        settings.refresh()

        #expect(settings.isEnabled)
        #expect(!settings.requiresApproval)
        #expect(settings.statusMessage == nil)

        service.status = .notRegistered
        settings.refresh()

        #expect(!settings.isEnabled)
    }

    @Test(arguments: [false, true])
    func failureRefreshesSystemStatusAndSurfacesError(enabling: Bool) {
        let service = LoginItemServiceStub()
        service.status = enabling ? .notRegistered : .enabled
        service.failure = RegistrationFailure()
        let settings = service.makeSettings()
        // Simulate a concurrent change in System Settings before the failed request.
        service.status = .requiresApproval

        settings.setEnabled(enabling)

        #expect(service.registrations == (enabling ? 1 : 0))
        #expect(service.unregistrations == (enabling ? 0 : 1))
        #expect(!settings.isEnabled)
        #expect(settings.requiresApproval)
        #expect(settings.error == RegistrationFailure().localizedDescription)

        service.failure = nil
        settings.setEnabled(enabling)

        #expect(settings.isEnabled == enabling)
        #expect(!settings.requiresApproval)
        #expect(settings.error == nil)
    }
}

@MainActor
private final class LoginItemServiceStub {
    var status: SMAppService.Status = .notRegistered
    var registrationStatus: SMAppService.Status = .enabled
    var failure: (any Error)?
    var registrations = 0
    var unregistrations = 0
    var settingsOpened = 0

    func makeSettings() -> LoginItemSettings {
        LoginItemSettings(
            status: { self.status },
            register: {
                self.registrations += 1
                if let failure = self.failure { throw failure }
                self.status = self.registrationStatus
            },
            unregister: {
                self.unregistrations += 1
                if let failure = self.failure { throw failure }
                self.status = .notRegistered
            },
            openSettings: { self.settingsOpened += 1 }
        )
    }
}

private struct RegistrationFailure: LocalizedError {
    var errorDescription: String? { "Couldn't update launch at login." }
}
