import AppKit

// Last-line defence: log any uncaught Obj-C exception (e.g. CoreText / AppKit
// internals) before the runtime calls abort(). Without this, ZenbuShot dies
// silently and the only forensic trail is a .ips crash report in
// ~/Library/Logs/DiagnosticReports/. The handler can't actually stop abort()
// — it just guarantees we leave a breadcrumb in the unified log.
NSSetUncaughtExceptionHandler { exception in
    NSLog("[ZenbuShot] UNCAUGHT EXCEPTION: %@ — %@\nUser info: %@\nStack:\n%@",
          exception.name.rawValue,
          exception.reason ?? "(no reason)",
          exception.userInfo ?? [:],
          exception.callStackSymbols.joined(separator: "\n"))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
