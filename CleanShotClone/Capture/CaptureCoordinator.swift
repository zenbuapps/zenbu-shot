import AppKit
import UserNotifications

class CaptureCoordinator {
    static let shared = CaptureCoordinator()
    private(set) var state: CaptureState = .idle
    private var areaOverlays: [AreaSelectionOverlay] = []
    private var windowPicker: WindowPicker?
    private var activeTimerOverlay: TimerOverlay?
    private var scrollingCoordinator: ScrollingCaptureCoordinator?
    private var globalEscMonitor: Any?
    private var previewWindow: FloatingPreviewWindow?
    private var currentResult: CaptureResult?
    private var lastCaptureRect: CGRect?
    private var lastCaptureScreenFrame: CGRect?

    func startCapture(mode: CaptureMode) {
        // Auto-recover if state is stuck (e.g. preview auto-dismissed but state wasn't reset)
        if state != .idle {
            if state == .previewing && previewWindow == nil {
                state = .idle
            } else if state == .editing {
                state = .idle
            } else {
                // Force reset after giving a moment
                dismissOverlays()
                previewWindow?.dismiss()
                previewWindow = nil
                currentResult = nil
                state = .idle
            }
        }
        guard state == .idle else { return }

        switch mode {
        case .fullscreen:
            captureFullscreen()
        case .area:
            startAreaSelection()
        case .window:
            startWindowSelection()
        case .ocr:
            startOCRCapture()
        case .previousArea:
            capturePreviousArea()
        case .timedFullscreen(let delay):
            startTimedCapture(delay: delay)
        case .freezeArea:
            startFreezeCapture()
        case .scrollingCapture:
            startScrollingCapture()
        }
    }

    // MARK: - Fullscreen Capture

    private func captureFullscreen() {
        state = .capturing
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }

            if let image = ScreenCapturer.captureFullscreen() {
                let result = CaptureResult(image: image, mode: .fullscreen)
                self.handleCaptureResult(result)
            } else {
                self.showCaptureError(L("alert.capture.error"))
                self.state = .idle
            }
        }
    }

    // MARK: - Area Selection
    // Pre-capture approach: capture screen before showing overlay, crop after selection.
    // This avoids coordinate conversion issues with CGWindowListCreateImage.

    private var areaPreCaptures: [String: NSImage] = [:] // keyed by screen displayID

    private func startAreaSelection() {
        state = .selectingArea
        NSApp.activate(ignoringOtherApps: true)
        installEscMonitor()

        // Capture every screen CLEANLY, BEFORE the overlay is shown. The overlay
        // is fully transparent (no dim), but we still crop the final image from
        // this pre-capture so nothing drawn on the overlay — the selection
        // border, handles, crosshair guides — can ever bleed into the
        // screenshot. Capturing AFTER the overlay was on screen is exactly what
        // produced the "everything looks grey" bug: CGDisplayCreateImage grabs
        // the whole display, including our own overlay window.
        areaPreCaptures.removeAll()
        for screen in NSScreen.screens {
            let key = "\(screen.displayID)"
            if let image = ScreenCapturer.captureScreen(screen) {
                areaPreCaptures[key] = image
            }
        }

        let overlay = AreaSelectionOverlay(screens: NSScreen.screens) { [weak self] rect, screen in
            self?.finishAreaSelection(rect: rect, screen: screen)
        } cancelHandler: { [weak self] in
            self?.cancelSelection()
            self?.areaPreCaptures.removeAll()
        }
        areaOverlays.append(overlay)
        overlay.show()
    }

    private func finishAreaSelection(rect: CGRect, screen: NSScreen) {
        dismissOverlays()
        removeEscMonitor()

        let key = "\(screen.displayID)"
        var preCapture = areaPreCaptures[key]
        areaPreCaptures.removeAll()

        // Fallback: pre-capture missing — grab it inline now that the overlay is
        // already dismissed, so the overlay still can't land in the image.
        if preCapture == nil {
            preCapture = ScreenCapturer.captureScreen(screen)
        }

        guard let preCapture = preCapture else {
            showCaptureError(L("alert.capture.error"))
            state = .idle
            return
        }

        guard let croppedImage = preCapture.cropped(to: rect) else {
            showCaptureError(L("alert.capture.error"))
            state = .idle
            return
        }

        let result = CaptureResult(image: croppedImage, captureRect: rect, mode: .area)
        handleCaptureResult(result)
    }

    // MARK: - Window Selection

    private func startWindowSelection() {
        state = .selectingWindow
        NSApp.activate(ignoringOtherApps: true)

        windowPicker = WindowPicker { [weak self] windowID in
            self?.captureWindow(windowID: windowID)
        } cancelHandler: { [weak self] in
            self?.windowPicker?.dismiss()
            self?.windowPicker = nil
            self?.state = .idle
        }
        windowPicker?.show()
    }

    private func captureWindow(windowID: CGWindowID) {
        windowPicker?.dismiss()
        windowPicker = nil

        if let image = ScreenCapturer.captureWindow(windowID: windowID) {
            let result = CaptureResult(image: image, mode: .window)
            handleCaptureResult(result)
        } else {
            showCaptureError("Failed to capture window.")
            state = .idle
        }
    }

    // MARK: - OCR Capture
    // Strategy: silently capture screen BEFORE showing overlay, then show normal
    // dim overlay for selection, crop from pre-captured image. No window disruption.

    private var ocrPreCaptures: [String: NSImage] = [:]

    private func startOCRCapture() {
        state = .selectingArea
        NSApp.activate(ignoringOtherApps: true)

        // Step 1: Silently capture all screens BEFORE showing any overlay
        ocrPreCaptures.removeAll()
        for screen in NSScreen.screens {
            let key = "\(screen.displayID)"
            if let image = ScreenCapturer.captureScreen(screen) {
                ocrPreCaptures[key] = image
            }
        }

        // Step 2: Show overlay across all screens
        let overlay = AreaSelectionOverlay(screens: NSScreen.screens) { [weak self] rect, screen in
            self?.finishOCRSelection(rect: rect, screen: screen)
        } cancelHandler: { [weak self] in
            self?.cancelSelection()
            self?.ocrPreCaptures.removeAll()
        }
        areaOverlays.append(overlay)
        overlay.show()
    }

    private func finishOCRSelection(rect: CGRect, screen: NSScreen) {
        dismissOverlays()

        let screenKey = "\(screen.displayID)"
        guard let preCapture = ocrPreCaptures[screenKey] else {
            showCaptureError(L("alert.capture.error"))
            state = .idle
            ocrPreCaptures.removeAll()
            return
        }
        ocrPreCaptures.removeAll()

        guard let croppedImage = preCapture.cropped(to: rect) else {
            showCaptureError(L("alert.capture.error"))
            state = .idle
            return
        }

        state = .idle

        ProgressHUD.show(message: L("ocr.recognizing"))

        OCREngine.shared.recognizeText(in: croppedImage) { [weak self] result in
            ProgressHUD.dismiss()
            switch result {
            case .success(let texts):
                if texts.isEmpty {
                    self?.showOCRNotification(text: nil)
                } else {
                    let text = texts.joined(separator: "\n")
                    // Copy to clipboard immediately
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    // Show notification with the text
                    self?.showOCRNotification(text: text, image: croppedImage)
                }
            case .failure(let error):
                self?.showCaptureError("OCR failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Previous Area Capture

    private func capturePreviousArea() {
        guard let rect = lastCaptureRect else {
            showCaptureError(L("alert.no.previous"))
            return
        }

        state = .capturing

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }

            if let image = ScreenCapturer.captureRect(rect) {
                let result = CaptureResult(image: image, captureRect: rect, mode: .area)
                self.handleCaptureResult(result)
            } else {
                self.showCaptureError(L("alert.capture.error"))
                self.state = .idle
            }
        }
    }

    // MARK: - Timed Capture

    private func startTimedCapture(delay: Int) {
        state = .capturing

        let timerOverlay = TimerOverlay(countdown: delay) { [weak self] in
            self?.activeTimerOverlay = nil
            guard let self = self else { return }
            if let image = ScreenCapturer.captureFullscreen() {
                let result = CaptureResult(image: image, mode: .fullscreen)
                self.handleCaptureResult(result)
            } else {
                self.showCaptureError(L("alert.capture.error"))
                self.state = .idle
            }
        } cancelHandler: { [weak self] in
            self?.activeTimerOverlay = nil
            self?.state = .idle
        }
        activeTimerOverlay = timerOverlay
        timerOverlay.show()
    }

    // MARK: - Scrolling Capture

    private func startScrollingCapture() {
        state = .capturing
        NSApp.activate(ignoringOtherApps: true)

        let coordinator = ScrollingCaptureCoordinator()
        scrollingCoordinator = coordinator

        coordinator.onComplete = { [weak self] image in
            self?.scrollingCoordinator = nil
            let result = CaptureResult(image: image, mode: .scrollingCapture)
            self?.handleCaptureResult(result)
        }

        coordinator.onCancel = { [weak self] in
            self?.scrollingCoordinator = nil
            self?.state = .idle
        }

        coordinator.startAreaSelection()
    }

    // MARK: - Freeze Screen Capture

    private func startFreezeCapture() {
        state = .selectingArea

        // Capture all screens first — freeze mode shows these as static images.
        areaPreCaptures.removeAll()
        for screen in NSScreen.screens {
            if let image = ScreenCapturer.captureScreen(screen) {
                areaPreCaptures["\(screen.displayID)"] = image
            }
        }

        // For freeze mode, pass frozen images to the overlay so screen appears "frozen"
        let overlay = AreaSelectionOverlay(screens: NSScreen.screens, frozenImages: areaPreCaptures) { [weak self] rect, screen in
            self?.finishAreaSelection(rect: rect, screen: screen)
        } cancelHandler: { [weak self] in
            self?.cancelSelection()
            self?.areaPreCaptures.removeAll()
        }
        areaOverlays.append(overlay)
        overlay.show()
    }

    // MARK: - Handle Result

    private func handleCaptureResult(_ result: CaptureResult) {
        currentResult = result
        state = .previewing

        let settings = UserSettings.shared

        // Play capture sound
        if settings.playSoundOnCapture {
            let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path), let sound = NSSound(contentsOf: url, byReference: true) {
                sound.play()
            } else {
                NSSound(named: "Tink")?.play()
            }
        }

        // Copy to clipboard
        if settings.copyToClipboardOnCapture {
            ClipboardService.copyImage(result.image)
        }

        // Auto-save to file if enabled
        if settings.autoSaveCapture {
            FileExportService.quickSave(result.image)
        }

        // Save to history
        CaptureHistoryStore.shared.save(result: result)

        // Show floating preview
        if settings.showFloatingPreview {
            previewWindow = FloatingPreviewWindow(result: result) { [weak self] action in
                self?.handlePreviewAction(action)
            }
            previewWindow?.show()
        } else {
            state = .idle
        }
    }

    func handlePreviewAction(_ action: PreviewAction) {
        guard let result = currentResult else { return }

        switch action {
        case .copy:
            ClipboardService.copyImage(result.image)
            dismissPreview()

        case .save:
            FileExportService.saveImage(result.image)
            dismissPreview()

        case .quickSave:
            FileExportService.quickSave(result.image)
            dismissPreview()

        case .edit:
            dismissPreview()
            let editor = EditorWindowController(result: result)
            editor.showWindow(nil)
            state = .editing

        case .ocr:
            ProgressHUD.show(message: L("ocr.recognizing"))
            OCREngine.shared.recognizeText(in: result.image) { [weak self] ocrResult in
                ProgressHUD.dismiss()
                switch ocrResult {
                case .success(let texts):
                    let text = texts.joined(separator: "\n")
                    OCRResultWindow.show(text: text, sourceImage: result.image)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                case .failure(let error):
                    self?.showCaptureError("OCR failed: \(error.localizedDescription)")
                }
            }
            dismissPreview()

        case .pin:
            PinnedScreenshotWindow.pin(image: result.image)
            dismissPreview()

        case .close:
            dismissPreview()
        }
    }

    // MARK: - Helpers

    private func dismissOverlays() {
        areaOverlays.forEach { $0.dismiss() }
        areaOverlays.removeAll()
    }

    private func dismissPreview() {
        previewWindow?.dismiss()
        previewWindow = nil
        currentResult = nil
        state = .idle
    }

    private func cancelSelection() {
        dismissOverlays()
        removeEscMonitor()
        state = .idle
    }

    private func installEscMonitor() {
        removeEscMonitor()
        globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.forceCancel() }
        }
    }

    private func removeEscMonitor() {
        if let m = globalEscMonitor { NSEvent.removeMonitor(m) }
        globalEscMonitor = nil
    }

    /// Force cancel any active capture mode
    private func forceCancel() {
        dismissOverlays()
        areaPreCaptures.removeAll()
        ocrPreCaptures.removeAll()
        scrollingCoordinator = nil
        windowPicker?.dismiss()
        windowPicker = nil
        removeEscMonitor()
        state = .idle
    }

    private func showOCRNotification(text: String?, image: NSImage? = nil) {
        if let text = text, !text.isEmpty {
            OCRToast.show(text: text)
        } else {
            OCRToast.show(text: nil)
        }
    }

    private func showCaptureError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = L("alert.capture.error")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("alert.ok"))
        alert.runModal()
    }
}
