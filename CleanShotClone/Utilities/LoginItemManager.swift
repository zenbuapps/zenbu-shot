import AppKit
import Foundation
import ServiceManagement

/// Manages "Launch at Login" via SMAppService (macOS 13+).
/// State lives in the system — SMAppService is the single source of truth,
/// so we don't shadow it in UserDefaults.
class LoginItemManager {

    /// `true` when macOS is set to launch ZenbuShot at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// User toggled it on but macOS is waiting for approval in System Settings.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Register or unregister the app as a login item.
    /// Returns `true` on success. Caller is responsible for surfacing
    /// `requiresApproval` to the user (the call still "succeeds" in that case
    /// — macOS just queues the item pending user approval).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled {
                guard service.status != .enabled else { return true }
                try service.register()
            } else {
                guard service.status != .notRegistered else { return true }
                try service.unregister()
            }
            return true
        } catch {
            NSLog("[LoginItemManager] Failed to \(enabled ? "register" : "unregister"): \(error.localizedDescription)")
            return false
        }
    }

    /// Open System Settings → Login Items so the user can approve / inspect.
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
