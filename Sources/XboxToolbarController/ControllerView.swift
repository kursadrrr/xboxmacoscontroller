import SwiftUI
import AppKit

struct ControllerView: View {
    @ObservedObject var client: SmartGlassClient
    @ObservedObject private var l10n = LocalizationManager.shared
    @Binding var isPinned: Bool
    var onTogglePin: () -> Void
    var onLayoutHeightChanged: () -> Void = {}
    var onSnapToToolbar: () -> Void = {}

    @State private var showConnectionDrawer: Bool = false
    @State private var keyboardText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var keyMonitor: Any?

    // Xbox Theme Colors
    private let xboxGreen = Color(red: 0.06, green: 0.49, blue: 0.06)       // #107C10
    private let xboxBrightGreen = Color(red: 0.16, green: 0.78, blue: 0.16)
    private let cardBG = Color(red: 0.13, green: 0.14, blue: 0.16)
    private let buttonBG = Color(red: 0.19, green: 0.20, blue: 0.23)

    var isConnected: Bool {
        if case .connected = client.state { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 10) {
            headerBar

            if showConnectionDrawer || !isConnected {
                connectionSection
            }

            topSystemButtonsRow

            shoulderAndXRow

            dpadSection

            iptvAndMediaSection

            keyboardInputSection

            footerStatusSection
        }
        .padding(12)
        .frame(width: 344)
        .background(Color(red: 0.08, green: 0.09, blue: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .preferredColorScheme(.dark)
        .onAppear {
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    // MARK: - 1. Header Bar

    private var headerBar: some View {
        HStack(spacing: 5) {
            // Status Indicator + Xbox Title
            Button {
                showConnectionDrawer.toggle()
                onLayoutHeightChanged()
            } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 9, height: 9)
                        .shadow(color: statusDotColor.opacity(0.8), radius: 4)

                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isConnected ? xboxBrightGreen : .white)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(headerTitle)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(headerSubtitle)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                    Image(systemName: showConnectionDrawer ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(cardBG)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Spacer()

            // Language Switcher Menu (8 Languages)
            Menu {
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        l10n.language = lang
                        client.statusLog = l10n.readyStatus
                    } label: {
                        if l10n.language == lang {
                            Label(lang.displayName, systemImage: "checkmark")
                        } else {
                            Text(lang.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "globe")
                        .font(.system(size: 10, weight: .bold))
                    Text(l10n.language.shortBadge)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 34, height: 28)
                .background(cardBG)
                .cornerRadius(7)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 34, height: 28)
            .help(l10n.languageMenuHelp)

            // Snap to Toolbar (Notch-Safe Re-align)
            Button {
                onSnapToToolbar()
            } label: {
                Image(systemName: "menubar.dock.rectangle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 26, height: 28)
                    .background(cardBG)
                    .cornerRadius(7)
            }
            .buttonStyle(.plain)
            .help(l10n.snapToToolbarHelp)

            // Power Menu (Wake on LAN / Power Off)
            Menu {
                Button {
                    client.powerOn()
                } label: {
                    Label(l10n.wakeXboxLabel, systemImage: "bolt.fill")
                }
                Button(role: .destructive) {
                    client.powerOff()
                } label: {
                    Label(l10n.powerOffXboxLabel, systemImage: "power")
                }
                Divider()
                Button {
                    onSnapToToolbar()
                } label: {
                    Label(l10n.snapToToolbarLabel, systemImage: "menubar.dock.rectangle")
                }
                Button {
                    client.discoverConsoles()
                } label: {
                    Label(l10n.scanConsolesLabel, systemImage: "dot.radiowaves.left.and.right")
                }
                if isConnected {
                    Button(role: .destructive) {
                        client.disconnect()
                    } label: {
                        Label(l10n.disconnectLabel, systemImage: "xmark.circle")
                    }
                }
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 28)
                    .background(cardBG)
                    .cornerRadius(7)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26, height: 28)
            .help(l10n.powerMenuHelp)

            // Pin / Floating Window Toggle
            Button {
                onTogglePin()
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isPinned ? xboxBrightGreen : .gray)
                    .frame(width: 26, height: 28)
                    .background(isPinned ? xboxGreen.opacity(0.35) : cardBG)
                    .cornerRadius(7)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(isPinned ? xboxBrightGreen.opacity(0.7) : Color.clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(l10n.pinHelp(isPinned: isPinned))
        }
    }

    private var statusDotColor: Color {
        switch client.state {
        case .connected:  return xboxBrightGreen
        case .connecting, .scanning: return .orange
        case .error:      return .red
        case .disconnected: return .gray
        }
    }

    private var headerTitle: String {
        switch client.state {
        case .connected(let dev): return dev.name
        case .connecting(let ip): return l10n.connectingTitle(ip)
        case .scanning:           return l10n.scanningTitle
        case .error:              return l10n.connectionErrorTitle
        case .disconnected:       return "Xbox Toolbar"
        }
    }

    private var headerSubtitle: String {
        switch client.state {
        case .connected(let dev):
            let appSuffix = client.activeAppDisplayName.isEmpty ? l10n.smartGlassActive : client.activeAppDisplayName
            return "\(dev.ip) • \(appSuffix)"
        case .connecting:         return l10n.udpHandshakeSubtitle
        case .scanning:           return l10n.scanningLanSubtitle
        case .error(let msg):     return msg
        case .disconnected:       return l10n.clickToConnectSubtitle
        }
    }

    // MARK: - 2. Connection & Discovery Drawer

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField(l10n.ipPlaceholder, text: $client.manualIP)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.45))
                    .cornerRadius(6)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        client.connect(to: client.manualIP)
                    }

                Button {
                    client.connect(to: client.manualIP)
                } label: {
                    Text(l10n.connectButton)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(xboxGreen)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button {
                    client.discoverConsoles()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(buttonBG)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help(l10n.scanLanHelp)
            }

            if !client.discoveredConsoles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(client.discoveredConsoles) { dev in
                            Button {
                                client.manualIP = dev.ip
                                client.connect(to: dev.ip)
                                showConnectionDrawer = false
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "tv.and.mediabox")
                                        .font(.system(size: 10))
                                        .foregroundColor(xboxBrightGreen)
                                    Text("\(dev.name) (\(dev.ip))")
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(buttonBG)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(9)
        .background(cardBG)
        .cornerRadius(9)
    }

    // MARK: - 3. Top System Buttons Row (B | View | Xbox Home | Menu | Y)

    private var topSystemButtonsRow: some View {
        HStack(spacing: 7) {
            // B (Back)
            gamepadPillButton(
                title: "B",
                subtitle: l10n.backSubtitle,
                accent: Color(red: 0.85, green: 0.22, blue: 0.22),
                action: { client.sendButton(.b) }
            )

            // View (Two squares)
            iconCircleButton(
                systemIcon: "square.on.square",
                label: "View",
                action: { client.sendButton(.view) }
            )

            // Xbox Nexus / Guide (Home)
            Button {
                client.sendButton(.nexus)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "xbox.logo")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Text("HOME")
                        .font(.system(size: 8.5, weight: .heavy))
                        .foregroundColor(.white.opacity(0.9))
                }
                .frame(width: 64, height: 42)
                .background(
                    LinearGradient(
                        colors: [xboxBrightGreen.opacity(0.85), xboxGreen],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(21)
                .shadow(color: xboxGreen.opacity(0.5), radius: 5)
            }
            .buttonStyle(.plain)
            .help("Xbox Guide / Home (H)")

            // Menu (Three lines)
            iconCircleButton(
                systemIcon: "line.3.horizontal",
                label: "Menu",
                action: { client.sendButton(.menu) }
            )

            // Y (Search)
            gamepadPillButton(
                title: "Y",
                subtitle: l10n.searchSubtitle,
                accent: Color(red: 0.92, green: 0.72, blue: 0.12),
                action: { client.sendButton(.y) }
            )
        }
    }

    // MARK: - 4. Shoulder & X Row (LB | X | RB)

    private var shoulderAndXRow: some View {
        HStack(spacing: 8) {
            Button {
                client.sendButton(.leftShoulder)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left.2")
                        .font(.system(size: 10, weight: .bold))
                    Text("LB")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(buttonBG)
                .cornerRadius(7)
            }
            .buttonStyle(.plain)
            .help("LB ([)")

            Button {
                client.sendButton(.x)
            } label: {
                HStack(spacing: 5) {
                    Text("X")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(Color(red: 0.25, green: 0.62, blue: 0.98))
                    Text(l10n.xButtonSuffix)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(buttonBG)
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color(red: 0.25, green: 0.62, blue: 0.98).opacity(0.45), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("X")

            Button {
                client.sendButton(.rightShoulder)
            } label: {
                HStack(spacing: 4) {
                    Text("RB")
                        .font(.system(size: 12, weight: .bold))
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(buttonBG)
                .cornerRadius(7)
            }
            .buttonStyle(.plain)
            .help("RB (])")
        }
    }

    // MARK: - 5. Circular D-Pad with Center Green "A" Button

    @ViewBuilder
    private var dpadSection: some View {
        ZStack {
            Circle()
                .fill(cardBG)
                .frame(width: 192, height: 192)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1.5)
                )

            VStack(spacing: 6) {
                // UP
                dpadDirectionButton(icon: "chevron.up", label: "▲", button: .up)

                HStack(spacing: 6) {
                    // LEFT
                    dpadDirectionButton(icon: "chevron.left", label: "◀", button: .left)

                    // CENTER "A" BUTTON (Select / OK)
                    Button {
                        client.sendButton(.a)
                    } label: {
                        VStack(spacing: 1) {
                            Text("A")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text(l10n.selectCenterLabel)
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .frame(width: 64, height: 64)
                        .background(
                            RadialGradient(
                                colors: [xboxBrightGreen, xboxGreen],
                                center: .topLeading,
                                startRadius: 5,
                                endRadius: 55
                            )
                        )
                        .clipShape(Circle())
                        .shadow(color: xboxGreen.opacity(0.6), radius: 6)
                    }
                    .buttonStyle(.plain)
                    .help("A / Enter / Space")

                    // RIGHT
                    dpadDirectionButton(icon: "chevron.right", label: "▶", button: .right)
                }

                // DOWN
                dpadDirectionButton(icon: "chevron.down", label: "▼", button: .down)
            }
        }
        .padding(.vertical, 2)

        // D-Pad / Analog Mode Switcher for IPTV & UWP Apps
        HStack(spacing: 4) {
            Text(l10n.directionModeLabel)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.gray)
            ForEach([(0, "D-Pad + Kodi"), (1, "Analog + Kodi"), (2, l10n.modeAllLabel)], id: \.0) { mode, title in
                Button {
                    client.dpadInputMode = mode
                } label: {
                    Text(title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(client.dpadInputMode == mode ? .white : .gray)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(client.dpadInputMode == mode ? xboxGreen : buttonBG)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dpadDirectionButton(icon: String, label: String, button: GamepadButton) -> some View {
        Button {
            client.sendButton(button)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 52, height: 48)
                .background(buttonBG)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .help(l10n.buttonLabel(button))
    }

    // MARK: - 6. IPTV Anti-Freeze & Media Transport Section

    private var iptvAndMediaSection: some View {
        VStack(spacing: 6) {
            // Row 1: IPTV Stream Unfreeze / Channel Up-Down
            HStack(spacing: 6) {
                Button {
                    client.sendMediaCommand(.channelDown)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 11))
                        Text("CH-")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(width: 62, height: 30)
                    .background(buttonBG)
                    .cornerRadius(7)
                }
                .buttonStyle(.plain)
                .help("Channel Down (CH-)")

                // Anti-Freeze / Stream Reload Macro Button
                Button {
                    client.reloadIPTVStream()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.heart.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(xboxBrightGreen)
                        Text(l10n.reviveIptvButton)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(xboxGreen.opacity(0.32))
                    .cornerRadius(7)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(xboxBrightGreen.opacity(0.55), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Picker(l10n.reviveModeTitle, selection: $client.iptvReloadMode) {
                        Text(l10n.reviveMode1).tag(0)
                        Text(l10n.reviveMode2).tag(1)
                        Text(l10n.reviveMode3).tag(2)
                    }
                }
                .help(l10n.reviveIptvHelp)

                Button {
                    client.sendMediaCommand(.channelUp)
                } label: {
                    HStack(spacing: 3) {
                        Text("CH+")
                            .font(.system(size: 11, weight: .bold))
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.white)
                    .frame(width: 62, height: 30)
                    .background(buttonBG)
                    .cornerRadius(7)
                }
                .buttonStyle(.plain)
                .help("Channel Up (CH+)")
            }

            // Row 2: Media Transport (Rewind, Play, Pause, Stop, FastForward)
            HStack(spacing: 6) {
                mediaTransportButton(icon: "backward.fill", help: "Rewind", cmd: .rewind)
                mediaTransportButton(icon: "play.fill", help: "Play", cmd: .play)
                mediaTransportButton(icon: "pause.fill", help: "Pause", cmd: .pause)
                mediaTransportButton(icon: "stop.fill", help: "Stop", cmd: .stop)
                mediaTransportButton(icon: "forward.fill", help: "Fast Forward", cmd: .fastForward)
            }
        }
        .padding(7)
        .background(cardBG)
        .cornerRadius(9)
    }

    private func mediaTransportButton(icon: String, help: String, cmd: MediaCommand) -> some View {
        Button {
            client.sendMediaCommand(cmd)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(buttonBG)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - 7. Xbox Keyboard (SystemText) Input Section

    private var keyboardInputSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: "keyboard")
                    .font(.system(size: 10.5))
                    .foregroundColor(client.hasActiveTextInput ? xboxBrightGreen : .gray)
                Text(l10n.keyboardTitle(active: client.hasActiveTextInput))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(client.hasActiveTextInput ? xboxBrightGreen : .gray)
                    .lineLimit(1)
                Spacer()
                Button {
                    if let pasted = NSPasteboard.general.string(forType: .string), !pasted.isEmpty {
                        keyboardText = pasted
                        client.sendTextInput(pasted)
                    } else {
                        client.statusLog = l10n.clipboardEmptyStatus
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 9))
                        Text(l10n.pasteAndSendButton)
                            .font(.system(size: 9.5, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(xboxGreen)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help(l10n.pasteAndSendHelp)

                Toggle(l10n.shortcutsToggle, isOn: $client.keyboardShortcutsEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 9.5))
                    .foregroundColor(.gray)
            }

            HStack(spacing: 5) {
                HStack(spacing: 4) {
                    TextField(l10n.textFieldPlaceholder, text: $keyboardText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            sendTypedText()
                        }

                    if !keyboardText.isEmpty {
                        Button {
                            keyboardText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.45))
                .cornerRadius(6)

                Button {
                    sendTypedText()
                } label: {
                    Text(l10n.sendButton)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(client.hasActiveTextInput ? xboxGreen : buttonBG)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(cardBG)
        .cornerRadius(9)
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(client.hasActiveTextInput ? xboxBrightGreen.opacity(0.6) : Color.clear, lineWidth: 1)
        )
    }

    private func sendTypedText() {
        client.sendTextInput(keyboardText)
    }

    // MARK: - 8. Footer Status Bar

    private var footerStatusSection: some View {
        HStack {
            Text(client.statusLog)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.gray)
                .lineLimit(1)
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text(l10n.quitButton)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(.red.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Reusable Button Builders

    private func gamepadPillButton(title: String, subtitle: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(accent)
                Text(subtitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(buttonBG)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(accent.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func iconCircleButton(systemIcon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemIcon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.gray)
            }
            .frame(width: 42, height: 36)
            .background(buttonBG)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mac Hardware Keyboard Monitor

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Never intercept keystrokes when a text field / NSText editor is focused
            if let resp = event.window?.firstResponder, resp is NSText {
                return event
            }
            if let resp = NSApp.keyWindow?.firstResponder, resp is NSText {
                return event
            }
            guard client.keyboardShortcutsEnabled, !isTextFieldFocused else {
                return event
            }
            // Ignore Cmd+key shortcuts so Copy/Paste/Quit still work normally
            if event.modifierFlags.contains(.command) {
                return event
            }
            switch event.keyCode {
            case 126: // Up Arrow
                client.sendButton(.up)
                return nil
            case 125: // Down Arrow
                client.sendButton(.down)
                return nil
            case 123: // Left Arrow
                client.sendButton(.left)
                return nil
            case 124: // Right Arrow
                client.sendButton(.right)
                return nil
            case 36, 49: // Return or Space -> A
                client.sendButton(.a)
                return nil
            case 53: // Esc -> B (Never bind Backspace 51 so deleting text never closes Xbox keyboard)
                client.sendButton(.b)
                return nil
            default:
                if let chars = event.charactersIgnoringModifiers?.lowercased() {
                    switch chars {
                    case "h":
                        client.sendButton(.nexus)
                        return nil
                    case "m":
                        client.sendButton(.menu)
                        return nil
                    case "v":
                        client.sendButton(.view)
                        return nil
                    case "x":
                        client.sendButton(.x)
                        return nil
                    case "y":
                        client.sendButton(.y)
                        return nil
                    case "[":
                        client.sendButton(.leftShoulder)
                        return nil
                    case "]":
                        client.sendButton(.rightShoulder)
                        return nil
                    case "r":
                        client.reloadIPTVStream()
                        return nil
                    default:
                        break
                    }
                }
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}
