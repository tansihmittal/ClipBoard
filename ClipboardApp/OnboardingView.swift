import SwiftUI
import AppKit

// MARK: - Window controller

final class OnboardingWindowController {
    private var window: NSWindow?

    func show(onComplete: @escaping () -> Void) {
        guard window == nil else { return }

        // The app runs as .accessory (no Dock icon), but that policy prevents
        // windows from receiving focus. Switch to .regular for the duration of
        // onboarding so the window can appear and be interacted with normally.
        NSApp.setActivationPolicy(.regular)

        let view = OnboardingView { [weak self] in
            self?.close()
            onComplete()
        }
        let vc  = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: vc)
        win.styleMask               = [.titled, .closable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.title                   = ""
        win.isMovableByWindowBackground = true
        win.setContentSize(NSSize(width: 480, height: 570))
        win.center()
        win.level                   = .floating
        win.isReleasedWhenClosed    = false
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
        // Return to menu-bar-only mode once onboarding is finished.
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Onboarding view

struct OnboardingView: View {
    @State private var step      = 0
    @State private var axGranted = AXIsProcessTrusted()
    @State private var imGranted = CGPreflightListenEventAccess()
    @State private var permTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    let onComplete: () -> Void

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 32)

            Spacer(minLength: 0)

            Group {
                switch step {
                case 0: welcomeStep
                case 1: accessibilityStep
                case 2: inputMonitoringStep
                default: doneStep
                }
            }
            .frame(maxWidth: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal:   .move(edge: .leading).combined(with: .opacity)
            ))
            .id(step)

            Spacer(minLength: 0)

            navigationBar
                .padding(.bottom, 30)
        }
        .frame(width: 480, height: 570)
        .background(Color(NSColor.windowBackgroundColor))
        .onReceive(permTimer) { _ in
            axGranted = AXIsProcessTrusted()
            imGranted = CGPreflightListenEventAccess()
        }
        // Auto-open the relevant Settings pane when the user reaches a
        // permission step and the permission is not yet granted, so they
        // don't have to hunt for the button themselves.
        .onChange(of: step) { _, newStep in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if newStep == 1 && !axGranted {
                    AppDelegate.openAccessibilitySettings()
                } else if newStep == 2 && !imGranted {
                    AppDelegate.openInputMonitoringSettings()
                }
            }
        }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Color.onboardGreen : Color.primary.opacity(0.13))
                    .frame(width: i == step ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: step)
            }
        }
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(Color.onboardGreen.opacity(0.10))
                    .frame(width: 90, height: 90)
                Image(systemName: "clipboard.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(.onboardGreen)
            }

            VStack(spacing: 7) {
                Text("Welcome to ClipboardApp")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("A lightweight clipboard manager that lives\nin your menu bar — no Dock icon, no clutter.")
                    .font(.system(size: 13.5))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 11) {
                OnboardFeatureRow(icon: "doc.on.clipboard",
                                  color: Color(red: 0.22, green: 0.53, blue: 1.0),
                                  title: "Clipboard History",
                                  detail: "Stores up to 200 items — text, links, images — automatically.")
                OnboardFeatureRow(icon: "bolt.fill",
                                  color: .orange,
                                  title: "Text Snippets",
                                  detail: "Type /trigger in any app, press Space to expand it instantly.")
                OnboardFeatureRow(icon: "command.square.fill",
                                  color: .onboardGreen,
                                  title: "Global Hotkey ⌘⇧V",
                                  detail: "Open the clipboard from anywhere — no need to find the icon.")
            }
            .padding(18)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 36)
        }
        .padding(.horizontal, 36)
    }

    // MARK: - Step 1: Accessibility

    private var accessibilityStep: some View {
        permissionStep(
            sfSymbol:    "accessibility",
            iconColor:   Color(red: 0.22, green: 0.53, blue: 1.0),
            title:       "Allow Accessibility",
            body:        "Accessibility lets ClipboardApp type on your behalf — it presses Backspace to remove your trigger text, then Cmd-V to paste the expansion.\n\nThis is required for the Snippets feature. Your clipboard history works fine without it.",
            note:        "Open System Settings → Privacy & Security → Accessibility. Click +, choose ClipboardApp, and turn the toggle on.",
            isGranted:   axGranted,
            buttonLabel: "Open Accessibility Settings",
            onOpen:      { AppDelegate.openAccessibilitySettings() }
        )
    }

    // MARK: - Step 2: Input Monitoring

    private var inputMonitoringStep: some View {
        permissionStep(
            sfSymbol:    "keyboard",
            iconColor:   Color(red: 0.60, green: 0.33, blue: 0.98),
            title:       "Allow Input Monitoring",
            body:        "Input Monitoring lets ClipboardApp watch for /trigger sequences as you type in any app — Safari, Slack, VS Code, or anywhere else.\n\nThis is required for the Snippets feature. Your clipboard history works fine without it.",
            note:        "Open System Settings → Privacy & Security → Input Monitoring. Click +, choose ClipboardApp, and turn the toggle on.",
            isGranted:   imGranted,
            buttonLabel: "Open Input Monitoring Settings",
            onOpen:      { AppDelegate.openInputMonitoringSettings() }
        )
    }

    // MARK: - Step 3: Done

    private var doneStep: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.onboardGreen.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.onboardGreen)
            }

            VStack(spacing: 7) {
                Text("You're all set!")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Click the clipboard icon in your menu bar\nor press ⌘⇧V from any app.")
                    .font(.system(size: 13.5))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 10) {
                OnboardStatusRow(icon: "doc.on.clipboard",
                                 label: "Clipboard history",
                                 granted: true)
                OnboardStatusRow(icon: "bolt.fill",
                                 label: "Snippet expansion",
                                 granted: axGranted && imGranted)

                if !axGranted || !imGranted {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.top, 1)
                        Text("Snippet expansion needs both Accessibility and Input Monitoring. You can grant them later in System Settings → Privacy & Security.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(18)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 36)
        }
        .padding(.horizontal, 36)
    }

    // MARK: - Reusable permission step

    @ViewBuilder
    private func permissionStep(
        sfSymbol:    String,
        iconColor:   Color,
        title:       String,
        body:        String,
        note:        String,
        isGranted:   Bool,
        buttonLabel: String,
        onOpen:      @escaping () -> Void
    ) -> some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.11))
                    .frame(width: 74, height: 74)
                Image(systemName: sfSymbol)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(iconColor)
            }

            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))

            Text(body)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            // Live status badge
            HStack(spacing: 5) {
                Circle()
                    .fill(isGranted ? Color.onboardGreen : Color.orange)
                    .frame(width: 7, height: 7)
                Text(isGranted ? "Permission granted" : "Not granted yet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isGranted ? .onboardGreen : .orange)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background((isGranted ? Color.onboardGreen : Color.orange).opacity(0.10))
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.25), value: isGranted)

            if !isGranted {
                VStack(spacing: 10) {
                    Button(buttonLabel) { onOpen() }
                        .buttonStyle(OnboardPrimaryButton())

                    Text(note)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
            }
        }
        .padding(.horizontal, 48)
    }

    // MARK: - Navigation bar

    private var navigationBar: some View {
        HStack {
            if step > 0 {
                Button("← Back") {
                    withAnimation(.easeInOut(duration: 0.22)) { step -= 1 }
                }
                .buttonStyle(OnboardSecondaryButton())
            } else {
                Color.clear.frame(width: 80, height: 36)
            }

            Spacer()

            if step < totalSteps - 1 {
                Button(step == 0 ? "Get Started  →" : "Continue  →") {
                    withAnimation(.easeInOut(duration: 0.22)) { step += 1 }
                }
                .buttonStyle(OnboardPrimaryButton())
            } else {
                Button("Open ClipboardApp") { onComplete() }
                    .buttonStyle(OnboardPrimaryButton())
            }
        }
        .padding(.horizontal, 36)
    }
}

// MARK: - Supporting views

private struct OnboardFeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.11))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct OnboardStatusRow: View {
    let icon: String
    let label: String
    let granted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(granted ? .onboardGreen : .secondary)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 13))
            Spacer()
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 15))
                .foregroundColor(granted ? .onboardGreen : Color.secondary.opacity(0.5))
        }
    }
}

private struct OnboardPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            .background(Color.onboardGreen)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct OnboardSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Color.primary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private extension Color {
    static let onboardGreen = Color(red: 0.18, green: 0.78, blue: 0.44)
}
