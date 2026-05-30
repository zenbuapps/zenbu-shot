import AppKit
import IOKit.hid

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var hotkeyManager: HotkeyManager!
    private var keepAliveTimer: Timer?
    let captureCoordinator = CaptureCoordinator.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon (menu bar only app)
        NSApp.setActivationPolicy(.accessory)

        // Request screen recording permission
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }

        // Request accessibility permission
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        // Request Input Monitoring. A keyboard CGEventTap needs BOTH Accessibility
        // (to create the active tap) AND Input Monitoring (to actually receive
        // keyDown events). Without this the tap reports enabled=true but silently
        // receives nothing — which is exactly why every hotkey was dead.
        let imAccess = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        HotkeyManager.dbg("InputMonitoring on launch = \(imAccess.rawValue) (0=granted 1=denied 2=unknown)")
        if imAccess != kIOHIDAccessTypeGranted {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }

        // Setup menu bar
        statusBarController = StatusBarController(coordinator: captureCoordinator)

        // Setup global hotkeys
        hotkeyManager = HotkeyManager(coordinator: captureCoordinator)

        // Apply system shortcut override if enabled
        SystemShortcutOverride.applyCurrentSetting()

        // Keep the run loop alive so CGEvent tap receives events
        // even when there are no visible windows
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // no-op, just keeps the run loop spinning
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Restore macOS screenshot shortcuts when app quits
        SystemShortcutOverride.restore()
    }
}
