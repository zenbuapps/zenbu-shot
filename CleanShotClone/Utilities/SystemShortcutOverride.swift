import Foundation
import AppKit

/// Disables/re-enables macOS built-in screenshot shortcuts (Cmd+Shift+3/4/5/6)
/// Modifies the symbolic hotkeys plist - requires logout/login to fully take effect
class SystemShortcutOverride {

    private static let hotkeyIDs = [28, 29, 30, 31, 184]
    private static let plistPath = NSHomeDirectory() + "/Library/Preferences/com.apple.symbolichotkeys.plist"

    static func apply(override: Bool) {
        applyToPlist(override: override)

        if override {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Restart Required"
                alert.informativeText = "macOS screenshot shortcuts have been disabled in settings. Please log out and log back in (or restart) for this to take effect.\n\nAfter restarting, Cmd+Shift+3/4/5 will only trigger ZenbuShot."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Log Out Now")
                let response = alert.runModal()
                if response == .alertSecondButtonReturn {
                    let script = "tell application \"System Events\" to log out"
                    if let appleScript = NSAppleScript(source: script) {
                        var error: NSDictionary?
                        appleScript.executeAndReturnError(&error)
                    }
                }
            }
        }
    }

    static func applyCurrentSetting() {
        // Re-apply on launch if user has previously enabled override.
        // This guards against the user (or a System Settings reset) restoring
        // the macOS defaults behind our back — without this, ZenbuShot would
        // silently fail to receive Cmd+Shift+3/4/5/6.
        guard UserSettings.shared.overrideSystemShortcuts else { return }
        applyToPlist(override: true)
    }

    static func restore() {
        applyToPlist(override: false)
    }

    // MARK: - Private

    private static func applyToPlist(override: Bool) {
        let boolValue = override ? "false" : "true"

        // Ensure parent containers exist before Set — PlistBuddy `Set` fails on
        // missing keys, and the user's plist may not have an AppleSymbolicHotKeys
        // entry at all (macOS falls back to system defaults).
        runPlistBuddy(["-c", "Add :AppleSymbolicHotKeys dict", plistPath])
        for id in hotkeyIDs {
            runPlistBuddy(["-c", "Add :AppleSymbolicHotKeys:\(id) dict", plistPath])
            runPlistBuddy(["-c", "Add :AppleSymbolicHotKeys:\(id):enabled bool \(boolValue)", plistPath])
            runPlistBuddy(["-c", "Set :AppleSymbolicHotKeys:\(id):enabled \(boolValue)", plistPath])
        }

        // Flush cfprefsd's in-memory cache; otherwise it can overwrite our
        // direct-to-disk changes on logout and the override silently reverts.
        let flush = Process()
        flush.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        flush.arguments = ["cfprefsd"]
        flush.standardError = FileHandle.nullDevice
        flush.standardOutput = FileHandle.nullDevice
        try? flush.run()
        flush.waitUntilExit()

        NSLog("[SystemShortcutOverride] \(override ? "disabled" : "enabled") macOS screenshot shortcuts in plist")
    }

    private static func runPlistBuddy(_ args: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/libexec/PlistBuddy")
        task.arguments = args
        task.standardError = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }
}
