import AppKit
import AVFoundation

class PreferencesWindowController: NSWindowController {
    static var instance: PreferencesWindowController?

    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let existing = instance {
            existing.window?.orderFrontRegardless()
            existing.window?.makeKey()
            return
        }
        let ctrl = PreferencesWindowController()
        instance = ctrl
        ctrl.showWindow(nil)
        ctrl.window?.orderFrontRegardless()
    }

    init() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 500, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.center()

        super.init(window: window)
        window.delegate = self
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let tabView = NSTabView(frame: contentView.bounds)
        tabView.autoresizingMask = [.width, .height]

        tabView.addTabViewItem(createGeneralTab())
        tabView.addTabViewItem(createShortcutsTab())
        tabView.addTabViewItem(createRecordingTab())
        tabView.addTabViewItem(createEditorTab())
        tabView.addTabViewItem(createAboutTab())

        contentView.addSubview(tabView)
    }

    // MARK: - General Tab

    private func createGeneralTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "general")
        item.label = L("prefs.general")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 476, height: 430))

        var y: CGFloat = 370

        // Language selector at top
        let langLabel = NSTextField(labelWithString: L("prefs.language"))
        langLabel.frame = CGRect(x: 20, y: y + 2, width: 80, height: 18)
        langLabel.font = NSFont.systemFont(ofSize: 12)
        view.addSubview(langLabel)

        let langPopup = NSPopUpButton(frame: CGRect(x: 110, y: y, width: 200, height: 24))
        langPopup.target = self
        langPopup.action = #selector(languageChanged(_:))
        let currentLang = L10n.currentLanguage
        for (i, lang) in L10n.supportedLanguages.enumerated() {
            langPopup.addItem(withTitle: lang.name)
            langPopup.lastItem?.tag = i
            if lang.code == currentLang { langPopup.selectItem(at: i) }
        }
        view.addSubview(langPopup)
        y -= 36

        // Section header
        let captureHeader = NSTextField(labelWithString: L("prefs.capture"))
        captureHeader.frame = CGRect(x: 20, y: y, width: 200, height: 14)
        captureHeader.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        captureHeader.textColor = .tertiaryLabelColor
        view.addSubview(captureHeader)
        y -= 26

        let soundCheck = NSButton(checkboxWithTitle: L("prefs.play.sound"), target: self, action: #selector(soundToggled(_:)))
        soundCheck.state = UserSettings.shared.playSoundOnCapture ? .on : .off
        soundCheck.frame.origin = CGPoint(x: 20, y: y)
        view.addSubview(soundCheck)
        y -= 26

        let clipCheck = NSButton(checkboxWithTitle: L("prefs.copy.clipboard"), target: self, action: #selector(clipboardToggled(_:)))
        clipCheck.state = UserSettings.shared.copyToClipboardOnCapture ? .on : .off
        clipCheck.frame.origin = CGPoint(x: 20, y: y)
        view.addSubview(clipCheck)
        y -= 26

        let autoSaveCheck = NSButton(checkboxWithTitle: L("prefs.auto.save"), target: self, action: #selector(autoSaveToggled(_:)))
        autoSaveCheck.state = UserSettings.shared.autoSaveCapture ? .on : .off
        autoSaveCheck.frame.origin = CGPoint(x: 20, y: y)
        view.addSubview(autoSaveCheck)
        y -= 26

        let previewCheck = NSButton(checkboxWithTitle: L("prefs.show.preview"), target: self, action: #selector(previewToggled(_:)))
        previewCheck.state = UserSettings.shared.showFloatingPreview ? .on : .off
        previewCheck.frame.origin = CGPoint(x: 20, y: y)
        view.addSubview(previewCheck)
        y -= 36

        // Save directory
        let saveLabel = NSTextField(labelWithString: L("prefs.save.location"))
        saveLabel.frame = CGRect(x: 20, y: y, width: 180, height: 20)
        saveLabel.font = Theme.Fonts.label
        view.addSubview(saveLabel)

        let pathLabel = NSTextField(labelWithString: UserSettings.shared.saveDirectory.path)
        pathLabel.frame = CGRect(x: 20, y: y - 22, width: 340, height: 18)
        pathLabel.font = NSFont.systemFont(ofSize: 10)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.tag = 200
        view.addSubview(pathLabel)

        let browseBtn = NSButton(title: L("prefs.browse"), target: self, action: #selector(browseSaveDir))
        browseBtn.frame = CGRect(x: 370, y: y - 4, width: 80, height: 24)
        browseBtn.bezelStyle = .rounded
        browseBtn.controlSize = .small
        view.addSubview(browseBtn)
        y -= 50

        // Preview auto-dismiss delay
        let delayLabel = NSTextField(labelWithString: L("prefs.dismiss.delay"))
        delayLabel.frame = CGRect(x: 20, y: y, width: 200, height: 20)
        delayLabel.font = Theme.Fonts.label
        view.addSubview(delayLabel)

        let delaySlider = NSSlider(frame: CGRect(x: 230, y: y, width: 140, height: 20))
        delaySlider.minValue = 2
        delaySlider.maxValue = 15
        delaySlider.integerValue = Int(UserSettings.shared.previewDismissDelay)
        delaySlider.numberOfTickMarks = 14
        delaySlider.allowsTickMarkValuesOnly = true
        delaySlider.tickMarkPosition = .below
        delaySlider.target = self
        delaySlider.action = #selector(dismissDelayChanged(_:))
        view.addSubview(delaySlider)

        let delayVal = NSTextField(labelWithString: "\(Int(UserSettings.shared.previewDismissDelay))s")
        delayVal.frame = CGRect(x: 380, y: y, width: 40, height: 20)
        delayVal.font = Theme.Fonts.strokeValue
        delayVal.tag = 202
        view.addSubview(delayVal)

        item.view = view
        return item
    }

    // MARK: - Shortcuts Tab

    private func createShortcutsTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "shortcuts")
        item.label = L("prefs.shortcuts")

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 476, height: 310))
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false

        let view = NSFlippedView(frame: NSRect(x: 0, y: 0, width: 476, height: 500))

        // All shortcut actions with their settings keys and defaults
        let shortcutGroups: [(String, [(String, String, String)])] = [
            ("Capture", [
                ("Area Screenshot", "shortcut_area", "Cmd+Shift+4"),
                ("Fullscreen Screenshot", "shortcut_fullscreen", "Cmd+Shift+3"),
                ("Window Screenshot", "shortcut_window", "Cmd+Shift+5"),
                ("Previous Area", "shortcut_previous", "Cmd+Shift+6"),
                ("Freeze Screen & Capture", "shortcut_freeze", "Cmd+Shift+F"),
            ]),
            ("Text & Recording", [
                ("OCR Capture", "shortcut_ocr", "Cmd+Shift+2"),
                ("Record Area", "shortcut_record_area", "Cmd+Shift+8"),
                ("Record Fullscreen", "shortcut_record_full", "Cmd+Shift+9"),
                ("Stop Recording", "shortcut_stop_record", "Cmd+Shift+."),
            ]),
            ("Tools", [
                ("Capture History", "shortcut_history", "Cmd+Shift+H"),
                ("Hide Desktop Icons", "shortcut_desktop", "Cmd+Shift+D"),
            ]),
            ("Editor Tools", [
                ("Selection Tool", "shortcut_tool_select", "V"),
                ("Arrow Tool", "shortcut_tool_arrow", "A"),
                ("Line Tool", "shortcut_tool_line", "L"),
                ("Rectangle Tool", "shortcut_tool_rect", "R"),
                ("Ellipse Tool", "shortcut_tool_ellipse", "O"),
                ("Pencil Tool", "shortcut_tool_pencil", "P"),
                ("Text Tool", "shortcut_tool_text", "T"),
                ("Counter Tool", "shortcut_tool_counter", "N"),
                ("Highlighter Tool", "shortcut_tool_highlight", "H"),
                ("Blur Tool", "shortcut_tool_blur", "B"),
                ("Mosaic Tool", "shortcut_tool_mosaic", "M"),
                ("Spotlight Tool", "shortcut_tool_spotlight", "S"),
            ]),
        ]

        var y: CGFloat = 20

        // === macOS Integration: override built-in screenshot shortcuts ===
        let overrideHeader = NSTextField(labelWithString: "MACOS INTEGRATION")
        overrideHeader.frame = CGRect(x: 20, y: y, width: 300, height: 16)
        overrideHeader.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        overrideHeader.textColor = .tertiaryLabelColor
        view.addSubview(overrideHeader)
        y += 22

        let overrideCheck = NSButton(
            checkboxWithTitle: "Override macOS screenshot shortcuts (Cmd+Shift+3/4/5/6)",
            target: self,
            action: #selector(overrideShortcutsToggled(_:))
        )
        overrideCheck.frame = CGRect(x: 20, y: y, width: 440, height: 18)
        overrideCheck.state = UserSettings.shared.overrideSystemShortcuts ? .on : .off
        view.addSubview(overrideCheck)
        y += 22

        let overrideDesc = NSTextField(wrappingLabelWithString:
            "Required for Cmd+Shift+3/4/5/6 to trigger ZenbuShot instead of macOS built-in screenshots. Modifies macOS settings — you must log out and back in for changes to take effect."
        )
        overrideDesc.frame = CGRect(x: 38, y: y, width: 420, height: 34)
        overrideDesc.font = NSFont.systemFont(ofSize: 11)
        overrideDesc.textColor = .secondaryLabelColor
        view.addSubview(overrideDesc)
        y += 44

        for (groupTitle, shortcuts) in shortcutGroups {
            let header = NSTextField(labelWithString: groupTitle.uppercased())
            header.frame = CGRect(x: 20, y: y, width: 200, height: 16)
            header.font = NSFont.systemFont(ofSize: 10, weight: .bold)
            header.textColor = .tertiaryLabelColor
            view.addSubview(header)
            y += 22

            for (name, key, defaultValue) in shortcuts {
                let iconName = shortcutIcon(for: name)
                let iconView = NSImageView(frame: CGRect(x: 20, y: y, width: 16, height: 16))
                iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: name)
                iconView.contentTintColor = .secondaryLabelColor
                view.addSubview(iconView)

                let nameLabel = NSTextField(labelWithString: name)
                nameLabel.frame = CGRect(x: 42, y: y - 1, width: 200, height: 18)
                nameLabel.font = NSFont.systemFont(ofSize: 12)
                view.addSubview(nameLabel)

                let saved = UserDefaults.standard.string(forKey: key) ?? defaultValue
                let shortcutField = ShortcutField(frame: CGRect(x: 290, y: y - 2, width: 140, height: 22))
                shortcutField.settingsKey = key
                shortcutField.stringValue = saved
                shortcutField.placeholderString = "Click to set"
                view.addSubview(shortcutField)

                y += 26
            }
            y += 8
        }

        view.frame = NSRect(x: 0, y: 0, width: 476, height: max(y + 8, 310))
        scrollView.documentView = view

        item.view = scrollView
        return item
    }

    private func shortcutIcon(for name: String) -> String {
        switch name {
        case "Area Screenshot": return "rectangle.dashed"
        case "Window Screenshot": return "macwindow"
        case "Fullscreen Screenshot": return "desktopcomputer"
        case "Previous Area": return "arrow.counterclockwise.rectangle"
        case "Freeze Screen & Capture": return "snowflake"
        case "OCR Capture": return "text.viewfinder"
        case "Record Screen": return "record.circle"
        case "Stop Recording": return "stop.circle.fill"
        case "Capture History": return "clock.arrow.circlepath"
        case "Hide Desktop Icons": return "eye.slash"
        case "Selection Tool": return "cursorarrow"
        case "Arrow Tool": return "arrow.up.right"
        case "Line Tool": return "line.diagonal"
        case "Rectangle Tool": return "rectangle"
        case "Ellipse Tool": return "circle"
        case "Pencil Tool": return "pencil.tip"
        case "Text Tool": return "textformat"
        case "Counter Tool": return "number"
        case "Highlighter Tool": return "highlighter"
        case "Blur Tool": return "drop.halffull"
        case "Mosaic Tool": return "squareshape.split.3x3"
        case "Spotlight Tool": return "light.max"
        default: return "keyboard"
        }
    }

    // MARK: - Recording Tab

    private func createRecordingTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "recording")
        item.label = L("prefs.recording")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 476, height: 430))

        var y: CGFloat = 370

        let audioHeader = NSTextField(labelWithString: L("prefs.audio"))
        audioHeader.frame = CGRect(x: 20, y: y, width: 200, height: 14)
        audioHeader.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        audioHeader.textColor = .tertiaryLabelColor
        view.addSubview(audioHeader)
        y -= 28

        let audioCheck = NSButton(checkboxWithTitle: L("prefs.record.audio"), target: self, action: #selector(recordAudioToggled(_:)))
        audioCheck.state = UserSettings.shared.recordAudio ? .on : .off
        audioCheck.frame.origin = CGPoint(x: 20, y: y)
        view.addSubview(audioCheck)
        y -= 34

        let deviceLabel = NSTextField(labelWithString: L("prefs.audio.device"))
        deviceLabel.frame = CGRect(x: 20, y: y + 2, width: 140, height: 18)
        deviceLabel.font = NSFont.systemFont(ofSize: 12)
        view.addSubview(deviceLabel)

        let devicePopup = NSPopUpButton(frame: CGRect(x: 170, y: y, width: 280, height: 24))
        devicePopup.target = self
        devicePopup.action = #selector(audioDeviceChanged(_:))
        populateAudioDevices(popup: devicePopup)
        view.addSubview(devicePopup)
        y -= 34

        // Mic gain slider
        let gainLabel = NSTextField(labelWithString: L("prefs.mic.volume"))
        gainLabel.frame = CGRect(x: 20, y: y + 2, width: 140, height: 18)
        gainLabel.font = NSFont.systemFont(ofSize: 12)
        view.addSubview(gainLabel)

        let gainSlider = NSSlider(value: Double(UserSettings.shared.micGain), minValue: 0.5, maxValue: 3.0, target: self, action: #selector(micGainChanged(_:)))
        gainSlider.frame = CGRect(x: 170, y: y, width: 220, height: 24)
        view.addSubview(gainSlider)

        let gainValueLabel = NSTextField(labelWithString: String(format: "%.1fx", UserSettings.shared.micGain))
        gainValueLabel.frame = CGRect(x: 395, y: y + 2, width: 40, height: 18)
        gainValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        gainValueLabel.tag = 999
        view.addSubview(gainValueLabel)
        y -= 40

        // Video section
        let videoHeader = NSTextField(labelWithString: L("prefs.video"))
        videoHeader.frame = CGRect(x: 20, y: y, width: 200, height: 14)
        videoHeader.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        videoHeader.textColor = .tertiaryLabelColor
        view.addSubview(videoHeader)
        y -= 28

        // Show countdown
        let countdownCheck = NSButton(checkboxWithTitle: L("prefs.show.countdown"), target: self, action: #selector(countdownToggled(_:)))
        countdownCheck.state = UserSettings.shared.showRecordingCountdown ? .on : .off
        countdownCheck.frame.origin = CGPoint(x: 20, y: y)
        view.addSubview(countdownCheck)

        item.view = view
        return item
    }

    private func populateAudioDevices(popup: NSPopUpButton) {
        popup.removeAllItems()

        let devices = AVCaptureDevice.devices(for: .audio)
        let savedDevice = UserSettings.shared.audioDeviceUID

        let defaultDevice = AVCaptureDevice.default(for: .audio)
        let defaultName = defaultDevice?.localizedName ?? "None"
        popup.addItem(withTitle: L("prefs.system.default", defaultName))
        popup.lastItem?.representedObject = "" as String

        for device in devices {
            popup.addItem(withTitle: device.localizedName)
            popup.lastItem?.representedObject = device.uniqueID
            if device.uniqueID == savedDevice && !savedDevice.isEmpty {
                popup.select(popup.lastItem!)
            }
        }

        // If no saved device or empty, select System Default
        if savedDevice.isEmpty {
            popup.selectItem(at: 0)
        }
    }

    @objc private func recordAudioToggled(_ sender: NSButton) {
        UserSettings.shared.recordAudio = sender.state == .on
    }

    @objc private func micGainChanged(_ sender: NSSlider) {
        let gain = Float(sender.doubleValue)
        UserSettings.shared.micGain = gain
        if let label = sender.superview?.viewWithTag(999) as? NSTextField {
            label.stringValue = String(format: "%.1fx", gain)
        }
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0 && idx < L10n.supportedLanguages.count else { return }
        let code = L10n.supportedLanguages[idx].code
        L10n.currentLanguage = code

        // Rebuild the status bar menu with new language
        StatusBarController.current?.rebuildMenu()

        // Close and reopen preferences to refresh all tabs
        let frame = window?.frame
        window?.close()
        PreferencesWindowController.instance = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let newPrefs = PreferencesWindowController()
            PreferencesWindowController.instance = newPrefs
            if let f = frame { newPrefs.window?.setFrame(f, display: true) }
            newPrefs.showWindow(nil)
            newPrefs.window?.orderFrontRegardless()
        }
    }

    @objc private func audioDeviceChanged(_ sender: NSPopUpButton) {
        if let uid = sender.selectedItem?.representedObject as? String {
            UserSettings.shared.audioDeviceUID = uid
        } else {
            UserSettings.shared.audioDeviceUID = ""
        }
    }

    @objc private func countdownToggled(_ sender: NSButton) {
        UserSettings.shared.showRecordingCountdown = sender.state == .on
    }

    // MARK: - Editor Tab

    private func createEditorTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "editor")
        item.label = L("prefs.editor")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 476, height: 430))

        var y: CGFloat = 370

        // Default color
        let colorLabel = NSTextField(labelWithString: L("prefs.annotation.color"))
        colorLabel.frame = CGRect(x: 20, y: y, width: 180, height: 20)
        colorLabel.font = Theme.Fonts.label
        view.addSubview(colorLabel)

        let colorWell = NSColorWell(frame: CGRect(x: 210, y: y - 2, width: 40, height: 24))
        colorWell.color = UserSettings.shared.defaultAnnotationColor
        colorWell.target = self
        colorWell.action = #selector(defaultColorChanged(_:))
        view.addSubview(colorWell)
        y -= 44

        // Default stroke width
        let strokeLabel = NSTextField(labelWithString: L("prefs.stroke.width"))
        strokeLabel.frame = CGRect(x: 20, y: y, width: 180, height: 20)
        strokeLabel.font = Theme.Fonts.label
        view.addSubview(strokeLabel)

        let strokeSlider = NSSlider(frame: CGRect(x: 210, y: y, width: 160, height: 20))
        strokeSlider.minValue = 1
        strokeSlider.maxValue = 10
        strokeSlider.integerValue = Int(UserSettings.shared.defaultStrokeWidth)
        strokeSlider.numberOfTickMarks = 10
        strokeSlider.allowsTickMarkValuesOnly = true
        strokeSlider.tickMarkPosition = .below
        strokeSlider.target = self
        strokeSlider.action = #selector(defaultStrokeChanged(_:))
        view.addSubview(strokeSlider)

        let strokeVal = NSTextField(labelWithString: "\(Int(UserSettings.shared.defaultStrokeWidth))")
        strokeVal.frame = CGRect(x: 380, y: y, width: 30, height: 20)
        strokeVal.font = Theme.Fonts.strokeValue
        strokeVal.tag = 201
        view.addSubview(strokeVal)

        item.view = view
        return item
    }

    // MARK: - About Tab

    private func createAboutTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "about")
        item.label = L("prefs.about")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 476, height: 430))

        let icon = NSImageView(frame: CGRect(x: 198, y: 260, width: 80, height: 80))
        icon.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)
        icon.contentTintColor = .controlAccentColor
        view.addSubview(icon)

        let title = NSTextField(labelWithString: "ZenbuShot")
        title.frame = CGRect(x: 0, y: 230, width: 476, height: 24)
        title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        title.alignment = .center
        view.addSubview(title)

        let version = NSTextField(labelWithString: L("prefs.version"))
        version.frame = CGRect(x: 0, y: 208, width: 476, height: 18)
        version.font = NSFont.systemFont(ofSize: 12)
        version.textColor = .secondaryLabelColor
        version.alignment = .center
        view.addSubview(version)

        let desc = NSTextField(labelWithString: L("prefs.description"))
        desc.frame = CGRect(x: 0, y: 180, width: 476, height: 18)
        desc.font = NSFont.systemFont(ofSize: 11)
        desc.textColor = .tertiaryLabelColor
        desc.alignment = .center
        view.addSubview(desc)

        item.view = view
        return item
    }

    // MARK: - Actions

    @objc private func soundToggled(_ sender: NSButton) {
        UserSettings.shared.playSoundOnCapture = sender.state == .on
    }

    @objc private func clipboardToggled(_ sender: NSButton) {
        UserSettings.shared.copyToClipboardOnCapture = sender.state == .on
    }

    @objc private func previewToggled(_ sender: NSButton) {
        UserSettings.shared.showFloatingPreview = sender.state == .on
    }

    @objc private func autoSaveToggled(_ sender: NSButton) {
        UserSettings.shared.autoSaveCapture = sender.state == .on
    }

    @objc private func overrideShortcutsToggled(_ sender: NSButton) {
        UserSettings.shared.overrideSystemShortcuts = sender.state == .on
    }

    @objc private func browseSaveDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            UserSettings.shared.saveDirectory = url
            // Update label
            if let tabView = window?.contentView?.subviews.first as? NSTabView,
               let generalView = tabView.tabViewItem(at: 0).view,
               let pathLabel = generalView.viewWithTag(200) as? NSTextField {
                pathLabel.stringValue = url.path
            }
        }
    }

    @objc private func defaultColorChanged(_ sender: NSColorWell) {
        UserSettings.shared.defaultAnnotationColor = sender.color
    }

    @objc private func defaultStrokeChanged(_ sender: NSSlider) {
        let value = Int(sender.integerValue)
        UserSettings.shared.defaultStrokeWidth = CGFloat(value)
        // Find the label with tag 201 in the same parent view
        if let parent = sender.superview {
            if let label = parent.viewWithTag(201) as? NSTextField {
                label.stringValue = "\(value)"
            }
        }
    }

    @objc private func dismissDelayChanged(_ sender: NSSlider) {
        let value = Int(sender.integerValue)
        UserSettings.shared.previewDismissDelay = Double(value)
        if let parent = sender.superview,
           let label = parent.viewWithTag(202) as? NSTextField {
            label.stringValue = "\(value)s"
        }
    }
}

extension PreferencesWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        PreferencesWindowController.instance = nil
    }
}

// MARK: - Shortcut Recording View

class ShortcutField: NSView {
    var settingsKey: String = ""
    var stringValue: String = "" {
        didSet { label.stringValue = stringValue }
    }
    var placeholderString: String = "Click to set" {
        didSet { if stringValue.isEmpty { label.stringValue = placeholderString } }
    }

    private let label = NSTextField(labelWithString: "")
    private var isRecording = false
    private var localMonitor: Any?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        label.frame = bounds.insetBy(dx: 8, dy: 2)
        label.autoresizingMask = [.width, .height]
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        // Track clicks
        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        addGestureRecognizer(click)
    }

    @objc private func clicked() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        label.stringValue = "Press shortcut..."
        label.textColor = .controlAccentColor
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 2

        // Pause global hotkeys so they don't trigger while recording
        HotkeyManager.shared?.pause()

        // Install a local monitor to capture ALL key events (including Cmd+Shift combos)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleRecordedKey(event)
            return nil // Consume the event
        }
    }

    private func stopRecording() {
        isRecording = false
        label.textColor = .secondaryLabelColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        // Resume global hotkeys
        HotkeyManager.shared?.resume()

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        if stringValue.isEmpty {
            label.stringValue = placeholderString
        }
    }

    private func handleRecordedKey(_ event: NSEvent) {
        // Escape = cancel
        if event.keyCode == 53 {
            stopRecording()
            return
        }

        var parts: [String] = []
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Fixed order: Cmd → Shift → Ctrl → Opt (consistent display)
        if flags.contains(.command) { parts.append("Cmd") }
        if flags.contains(.shift) { parts.append("Shift") }
        if flags.contains(.control) { parts.append("Ctrl") }
        if flags.contains(.option) { parts.append("Opt") }

        // Get the key character
        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return }

        let keyName = readableKeyName(keyCode: event.keyCode, chars: chars)
        if !keyName.isEmpty {
            parts.append(keyName)
            stringValue = parts.joined(separator: "+")
            UserDefaults.standard.set(stringValue, forKey: settingsKey)
            stopRecording()
        }
    }

    private func readableKeyName(keyCode: UInt16, chars: String) -> String {
        switch keyCode {
        // Numbers
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 29: return "0"
        // Letters (use keyCode to avoid locale issues)
        case 0: return "A"
        case 11: return "B"
        case 8: return "C"
        case 2: return "D"
        case 14: return "E"
        case 3: return "F"
        case 5: return "G"
        case 4: return "H"
        case 34: return "I"
        case 38: return "J"
        case 40: return "K"
        case 37: return "L"
        case 46: return "M"
        case 45: return "N"
        case 31: return "O"
        case 35: return "P"
        case 12: return "Q"
        case 15: return "R"
        case 1: return "S"
        case 17: return "T"
        case 32: return "U"
        case 9: return "V"
        case 13: return "W"
        case 7: return "X"
        case 16: return "Y"
        case 6: return "Z"
        // Special keys
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Escape"
        case 123: return "Left"
        case 124: return "Right"
        case 125: return "Down"
        case 126: return "Up"
        case 27: return "-"
        case 24: return "="
        case 33: return "["
        case 30: return "]"
        case 42: return "\\"
        case 41: return ";"
        case 39: return "'"
        case 43: return ","
        case 47: return "."
        case 44: return "/"
        case 50: return "`"
        // Function keys
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:
            // Fallback: use keyCode number
            return "Key\(keyCode)"
        }
    }

    override var acceptsFirstResponder: Bool { true }
}

/// NSView with flipped coordinates (origin at top-left, like UIKit)
class NSFlippedView: NSView {
    override var isFlipped: Bool { true }
}
