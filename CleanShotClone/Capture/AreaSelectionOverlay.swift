import AppKit

class AreaSelectionOverlay: NSObject {
    private var windows: [NSWindow] = []
    private var selectionView: AreaSelectionView?
    private var screens: [NSScreen]
    private let frozenImages: [String: NSImage]?
    private let completionHandler: (CGRect, NSScreen) -> Void
    private let cancelHandler: () -> Void

    init(screens: [NSScreen], frozenImages: [String: NSImage]? = nil, completionHandler: @escaping (CGRect, NSScreen) -> Void, cancelHandler: @escaping () -> Void) {
        self.screens = screens
        self.frozenImages = frozenImages
        self.completionHandler = completionHandler
        self.cancelHandler = cancelHandler
        super.init()
    }

    // Single-screen convenience init (for freeze mode)
    convenience init(screen: NSScreen, frozenImage: NSImage? = nil, completionHandler: @escaping (CGRect, CGRect) -> Void, cancelHandler: @escaping () -> Void) {
        self.init(screens: [screen], completionHandler: { rect, scr in
            completionHandler(rect, scr.frame)
        }, cancelHandler: cancelHandler)
    }

    func show() {
        // Create one overlay window per screen
        for screen in screens {
            let screenFrame = screen.frame

            // Create window with local size, then position it on the correct screen
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: screenFrame.size),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.hidesOnDeactivate = false

            let view = AreaSelectionView(frame: NSRect(origin: .zero, size: screenFrame.size))
            view.screenBackingScale = screen.backingScaleFactor
            view.associatedScreen = screen
            // Pass frozen image for this screen if available
            let screenKey = "\(screen.displayID)"
            view.frozenImage = frozenImages?[screenKey]
            view.completionHandler = { [weak self] rect in
                guard let self = self else { return }
                self.completionHandler(rect, screen)
            }
            view.cancelHandler = cancelHandler

            window.contentView = view

            // Position the window to exactly cover this screen
            window.setFrame(screenFrame, display: true)
            window.orderFrontRegardless()

            windows.append(window)
        }

        // Make the primary (first) window key for keyboard events
        if let firstWindow = windows.first {
            firstWindow.makeKey()
            firstWindow.makeFirstResponder(firstWindow.contentView)
        }

        // Use global mouse monitor to relay events to the right window
        setupGlobalMouseMonitor()

        NSCursor.crosshair.push()
    }

    private var globalMouseMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var localMouseMonitor: Any?
    private var cursorTimer: Timer?

    private func setupGlobalMouseMonitor() {
        // Monitor mouse events globally so they work across all screens
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved]) { [weak self] event in
            self?.handleGlobalMouse(event)
        }

        // Local mouse monitor (when ZenbuShot is active)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved]) { [weak self] event in
            self?.handleGlobalMouse(event)
            return event
        }

        // ESC key: both global (background) and local (foreground) monitors
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancelHandler() }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancelHandler(); return nil }
            return event
        }

        // Force crosshair cursor continuously while overlay is visible
        NSCursor.crosshair.set()
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            NSCursor.crosshair.set()
        }
    }

    private func handleGlobalMouse(_ event: NSEvent) {
        // Find which window/view the mouse is over
        let mouseLocation = NSEvent.mouseLocation

        for window in windows {
            if window.frame.contains(mouseLocation) {
                guard let view = window.contentView as? AreaSelectionView else { continue }
                let localPoint = NSPoint(
                    x: mouseLocation.x - window.frame.origin.x,
                    y: mouseLocation.y - window.frame.origin.y
                )

                switch event.type {
                case .leftMouseDown:
                    // Make this window key
                    window.makeKey()
                    window.makeFirstResponder(view)
                    view.handleMouseDown(at: localPoint)
                case .leftMouseDragged:
                    view.handleMouseDragged(to: localPoint)
                case .leftMouseUp:
                    view.handleMouseUp(at: localPoint)
                case .mouseMoved:
                    view.handleMouseMoved(at: localPoint)
                default:
                    break
                }
                break
            }
        }
    }

    func dismiss() {
        // Stop cursor timer and restore normal cursor
        cursorTimer?.invalidate()
        cursorTimer = nil
        NSCursor.arrow.set()

        // Remove all event monitors
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m) }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m) }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m) }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m) }
        globalMouseMonitor = nil
        globalKeyMonitor = nil
        localKeyMonitor = nil
        localMouseMonitor = nil

        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        selectionView = nil
    }
}

// MARK: - Selection View

class AreaSelectionView: NSView {
    var completionHandler: ((CGRect) -> Void)?
    var cancelHandler: (() -> Void)?

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }
    var frozenImage: NSImage?
    var screenBackingScale: CGFloat = 2.0
    var associatedScreen: NSScreen?

    private var selectionStart: NSPoint?
    private var selectionEnd: NSPoint?
    private var currentMouseLocation: NSPoint?
    private var isSelecting = false
    private var showMagnifier = false

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw frozen image if available
        if let frozenImage = frozenImage, let cgImage = frozenImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(cgImage, in: bounds)
        }

        // Dim overlay
        context.setFillColor(NSColor.black.withAlphaComponent(0.3).cgColor)
        context.fill(bounds)

        // Selection
        if let rect = normalizedSelectionRect {
            context.setBlendMode(.clear)
            context.fill(rect)
            context.setBlendMode(.normal)

            if let frozenImage = frozenImage, let cgImage = frozenImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                context.saveGState()
                context.clip(to: rect)
                context.draw(cgImage, in: bounds)
                context.restoreGState()
            }

            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(2)
            context.stroke(rect)

            drawDimensionLabel(for: rect, in: context)
            drawHandles(for: rect, in: context)
            drawCrosshairGuides(for: rect, in: context)
        }
    }

    private var normalizedSelectionRect: CGRect? {
        guard let start = selectionStart, let end = selectionEnd else { return nil }
        return CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        )
    }

    // MARK: - External event handlers (called by AreaSelectionOverlay)

    func handleMouseDown(at point: NSPoint) {
        selectionStart = point
        selectionEnd = point
        isSelecting = true
        needsDisplay = true
    }

    func handleMouseDragged(to point: NSPoint) {
        guard isSelecting else { return }
        selectionEnd = point
        currentMouseLocation = point
        needsDisplay = true
    }

    func handleMouseUp(at point: NSPoint) {
        guard isSelecting, let rect = normalizedSelectionRect else { return }
        isSelecting = false
        if rect.width > 3 && rect.height > 3 {
            completionHandler?(rect)
        }
    }

    func handleMouseMoved(at point: NSPoint) {
        currentMouseLocation = point
    }

    // MARK: - Keyboard (received when this view is first responder)

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelHandler?() }
    }

    override func flagsChanged(with event: NSEvent) {
        let wasShowing = showMagnifier
        showMagnifier = event.modifierFlags.contains(.command)
        if showMagnifier != wasShowing { needsDisplay = true }
    }

    // MARK: - Also handle local mouse events as fallback

    override func mouseDown(with event: NSEvent) {
        handleMouseDown(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        handleMouseDragged(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        handleMouseUp(at: convert(event.locationInWindow, from: nil))
    }

    // MARK: - Drawing helpers

    // Cached once: drawDimensionLabel runs every frame during drag.
    // Rebuilding the font/attributes per-frame triggers a race in CoreText's
    // font cache on macOS 26.x that crashes with NSInvalidArgumentException
    // ("attempt to insert nil object from objects[0]") inside CTLine creation.
    // Using a concrete font ("Menlo") sidesteps the flaky system-font path.
    private static let labelFont: NSFont = NSFont(name: "Menlo", size: 12)
        ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    private static let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: AreaSelectionView.labelFont,
        .foregroundColor: NSColor.white,
    ]

    private func drawDimensionLabel(for rect: CGRect, in context: CGContext) {
        let width = Int(rect.width * screenBackingScale)
        let height = Int(rect.height * screenBackingScale)
        let text = "\(width) × \(height)" as NSString
        let attributes = AreaSelectionView.labelAttributes
        let textSize = text.size(withAttributes: attributes)
        let padding: CGFloat = 8
        let labelWidth = textSize.width + padding * 2
        let labelHeight = textSize.height + padding
        let pillRect = CGRect(x: rect.midX - labelWidth / 2, y: max(rect.minY - labelHeight - 8, 4), width: labelWidth, height: labelHeight)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6).fill()
        text.draw(at: NSPoint(x: pillRect.origin.x + padding, y: pillRect.origin.y + (labelHeight - textSize.height) / 2), withAttributes: attributes)
    }

    private func drawHandles(for rect: CGRect, in context: CGContext) {
        let s: CGFloat = 8
        let points = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.midY),
        ]
        for p in points {
            let r = CGRect(x: p.x - s/2, y: p.y - s/2, width: s, height: s)
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: r)
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: r)
        }
    }

    private func drawCrosshairGuides(for rect: CGRect, in context: CGContext) {
        context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(0.5)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.move(to: CGPoint(x: rect.minX, y: rect.midY))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        context.strokePath()
        context.move(to: CGPoint(x: rect.midX, y: rect.minY))
        context.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
    }
}
