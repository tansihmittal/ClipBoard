import SwiftUI
import AppKit
import Carbon

// MARK: - Notification names

extension Notification.Name {
    /// Posted by NSPopoverDelegate when the popover closes, so views can reset
    /// transient UI state (Copied badges, selection) without polling.
    static let popoverDidClose = Notification.Name("ClipboardApp.popoverDidClose")
    /// Posted by views when they want the popover to close. AppDelegate observes
    /// this and calls close() on its own popover — avoids fragile NSApp.delegate
    /// casts from within SwiftUI async closures.
    static let closePopoverRequest = Notification.Name("ClipboardApp.closePopoverRequest")
}

// MARK: - App entry point

@main
struct ClipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    // MARK: - Constants

    enum K {
        static let hotKeySignature: OSType   = 0x434C4950   // "CLIP"
        static let hotKeyID:        UInt32   = 1
        static let hotKeyVKeyCode:  UInt32   = 9            // V key
        static let backspaceKeyCode: CGKeyCode = 0x33
        static let pasteKeyCode:    CGKeyCode  = 0x09       // V key for Cmd+V
        /// 120 ms lets even slow Electron apps process all backspace events
        /// before we write the expansion and send Cmd+V.
        static let expansionDelay:  TimeInterval = 0.12
        /// Maximum snippet trigger length (including the leading "/").
        static let maxTriggerLength = 20
        static let permissionPollInterval: TimeInterval = 2
    }

    // MARK: - Properties

    var statusItem:          NSStatusItem!
    var popover:             NSPopover!
    var hotKeyRef:           EventHotKeyRef?
    private var onboarding:  OnboardingWindowController?

    private var globalEventMonitor:     Any?
    private var accessibilityPollTimer: Timer?
    private var monitorIsActive       = false
    private var keyBuffer             = ""
    /// Prevents a second trigger from firing while backspace events are still
    /// being delivered to the target app.
    private var expansionInProgress   = false
    /// Tracks whether the Accessibility prompt has already been shown this
    /// session so the poll timer doesn't re-trigger it every 2 seconds.
    private var hasPromptedAccessibility = false

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()

        ClipboardManager.shared.startMonitoring()
        registerHotKey()
        setupGlobalSnippetMonitor()

        accessibilityPollTimer = Timer.scheduledTimer(
            withTimeInterval: K.permissionPollInterval,
            repeats: true
        ) { [weak self] _ in self?.refreshMonitorState() }

        // Views post .closePopoverRequest; we observe here so the popover owner
        // always handles its own close — no NSApp.delegate cast needed from SwiftUI.
        NotificationCenter.default.addObserver(
            forName: .closePopoverRequest, object: nil, queue: .main
        ) { [weak self] _ in
            self?.popover.close()
        }

        let onboardingKey = "onboardingComplete"
        if !UserDefaults.standard.bool(forKey: onboardingKey) {
            // First launch — show the guided onboarding window.
            // It handles permission requests in order; we skip auto-prompting.
            onboarding = OnboardingWindowController()
            onboarding?.show { [weak self] in
                UserDefaults.standard.set(true, forKey: onboardingKey)
                self?.onboarding = nil
                self?.togglePopover()
            }
        } else {
            // Returning launch — check permissions quietly after a short delay.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.requestPermissionsIfNeeded()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        accessibilityPollTimer?.invalidate()
        if let m = globalEventMonitor { NSEvent.removeMonitor(m) }
        if let r = hotKeyRef           { UnregisterEventHotKey(r) }
    }

    // MARK: - Setup helpers

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let btn = statusItem.button else { return }
        let cfg   = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        btn.image = NSImage(
            systemSymbolName: "clipboard",
            accessibilityDescription: "Clipboard"
        )?.withSymbolConfiguration(cfg)
        btn.action = #selector(handleStatusClick(_:))
        btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        btn.target  = self
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 540)
        popover.behavior    = .transient
        popover.animates    = true
        popover.delegate    = self              // enables popoverDidClose notification
        popover.contentViewController = NSHostingController(rootView: ClipboardView())
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        // Broadcast so views can reset transient state (Copied badges, selection)
        // without holding a direct reference to the popover.
        NotificationCenter.default.post(name: .popoverDidClose, object: nil)
    }

    // MARK: - Permission handling

    private func requestPermissionsIfNeeded() {
        // Request Input Monitoring first; it triggers a system prompt by itself.
        // Only escalate to opening Settings if the prompt was already shown once
        // (tracked via UserDefaults) and the user still hasn't granted it.
        if !CGPreflightListenEventAccess() {
            let key = "didResetInputMonitoringTCC"
            if !UserDefaults.standard.bool(forKey: key) {
                UserDefaults.standard.set(true, forKey: key)
                clearStaleTCCEntryAndRerequest()
            } else {
                Self.openInputMonitoringSettings()
            }
            // Return — handle one permission at a time. The poll timer will
            // call requestPermissionsIfNeeded again once Input Monitoring is
            // granted and Accessibility still needs attention.
            return
        }
        if !AXIsProcessTrusted() {
            // Prompt for Accessibility via the system dialog (no Settings jump).
            hasPromptedAccessibility = true
            _ = ClipboardManager.shared.checkAccessibility()
        }
    }

    private func clearStaleTCCEntryAndRerequest() {
        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.launchPath = "/usr/bin/tccutil"
            task.arguments  = ["reset", "ListenEvent",
                               Bundle.main.bundleIdentifier ?? "com.clipboardapp"]
            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                // tccutil unavailable — fall through to opening Settings.
            }
            DispatchQueue.main.async {
                CGRequestListenEventAccess()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if !CGPreflightListenEventAccess() {
                        Self.openInputMonitoringSettings()
                    }
                }
            }
        }
    }

    // MARK: - System Settings helpers

    static func openInputMonitoringSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        else { return }
        NSWorkspace.shared.open(url)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Monitor lifecycle

    private func refreshMonitorState() {
        let imOK       = CGPreflightListenEventAccess()
        let axOK       = AXIsProcessTrusted()
        let canMonitor = imOK && axOK

        if monitorIsActive && !canMonitor {
            // Permissions were revoked — tear down the monitor.
            if let m = globalEventMonitor { NSEvent.removeMonitor(m) }
            globalEventMonitor       = nil
            monitorIsActive          = false
            keyBuffer                = ""
            expansionInProgress      = false
            hasPromptedAccessibility = false
        } else if !monitorIsActive && canMonitor {
            // Both permissions granted — start the monitor.
            setupGlobalSnippetMonitor()
        } else if !monitorIsActive && imOK && !axOK && !hasPromptedAccessibility {
            // Input Monitoring just became available but Accessibility is still
            // missing. Show the system Accessibility prompt exactly once.
            hasPromptedAccessibility = true
            _ = ClipboardManager.shared.checkAccessibility()
        }
    }

    private func setupGlobalSnippetMonitor() {
        guard AXIsProcessTrusted(),
              CGPreflightListenEventAccess(),
              !monitorIsActive
        else { return }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            self?.handleGlobalKeyDown(event)
        }
        monitorIsActive = globalEventMonitor != nil
    }

    // MARK: - Key handling

    private func handleGlobalKeyDown(_ event: NSEvent) {
        guard !expansionInProgress else { return }

        guard let chars = event.characters?.lowercased(), !chars.isEmpty else {
            keyBuffer = ""; return
        }
        guard let char = chars.first else { return }

        // Tab (keyCode 48), Space, and Enter are expansion delimiters.
        let isDelimiter = char.isWhitespace || char.isNewline || event.keyCode == 48
        if isDelimiter {
            if !keyBuffer.isEmpty {
                if let snippet = ClipboardManager.shared.snippetMatch(for: keyBuffer) {
                    expandSnippet(snippet, deleteDelimiter: true)
                }
                keyBuffer = ""
            }
        } else if char == "/" {
            keyBuffer = "/"
        } else if !keyBuffer.isEmpty {
            // Accept only letters and digits — punctuation (including "/" itself)
            // resets the buffer to avoid false matches.
            if char.isLetter || char.isNumber {
                keyBuffer.append(char)
                if keyBuffer.count > K.maxTriggerLength { keyBuffer = "" }
            } else {
                keyBuffer = ""
            }
        }
    }

    private func expandSnippet(_ snippet: Snippet, deleteDelimiter: Bool) {
        guard AXIsProcessTrusted() else { return }

        expansionInProgress = true
        let deleteCount = snippet.trigger.count + (deleteDelimiter ? 1 : 0)

        let src = CGEventSource(stateID: .privateState)
        for _ in 0..<deleteCount {
            CGEvent(keyboardEventSource: src,
                    virtualKey: K.backspaceKeyCode, keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: src,
                    virtualKey: K.backspaceKeyCode, keyDown: false)?.post(tap: .cghidEventTap)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + K.expansionDelay) { [weak self] in
            defer { self?.expansionInProgress = false }

            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(snippet.expansion, forType: .string)
            ClipboardManager.shared.markCurrentChangeConsumed()

            let src2  = CGEventSource(stateID: .privateState)
            let vDown = CGEvent(keyboardEventSource: src2, virtualKey: K.pasteKeyCode, keyDown: true)
            let vUp   = CGEvent(keyboardEventSource: src2, virtualKey: K.pasteKeyCode, keyDown: false)
            vDown?.flags = .maskCommand
            vUp?.flags   = .maskCommand
            vDown?.post(tap: .cghidEventTap)
            vUp?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Status item actions

    @objc func handleStatusClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { togglePopover(); return }
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Clipboard",
                         action: #selector(togglePopover), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit ClipboardApp",
                         action: #selector(quit), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    @objc func quit() { NSApp.terminate(nil) }

    // MARK: - Global hotkey (⌘⇧V)

    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind:  UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let ptr = userData else { return OSStatus(eventNotHandledErr) }
                Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue().togglePopover()
                return noErr
            },
            1, &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
        let hkID = EventHotKeyID(signature: K.hotKeySignature, id: K.hotKeyID)
        RegisterEventHotKey(K.hotKeyVKeyCode, UInt32(cmdKey | shiftKey),
                            hkID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: - Popover

    @objc func togglePopover() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.popover.isShown {
                self.popover.performClose(nil)
            } else if let btn = self.statusItem.button {
                self.popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
