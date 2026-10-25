import AppKit
import SwiftUI
import Combine

// MARK: - Notch-Safe Floating Panel (Prevents Window from Entering Menu Bar / Dynamic Island)

final class NotchSafePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Computes the maximum safe Y coordinate strictly below the Menu Bar and MacBook Notch (Dynamic Island)
    static func safeTopY(for screen: NSScreen) -> CGFloat {
        let menuBarThickness = NSStatusBar.system.thickness
        let notchHeight = screen.safeAreaInsets.top
        // Reserve extra clearance for MacBook Notch & Dynamic Island overlays
        let topObstruction = max(menuBarThickness, notchHeight, 36.0)
        let rawSafeTop = min(screen.visibleFrame.maxY, screen.frame.maxY - topObstruction)
        return rawSafeTop - 10.0
    }

    /// Computes the horizontal X range of the MacBook Notch / Dynamic Island (including safety margin)
    static func notchHorizontalRange(for screen: NSScreen) -> ClosedRange<CGFloat>? {
        if #available(macOS 12.0, *),
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let minX = leftArea.maxX - 16.0
            let maxX = rightArea.minX + 16.0
            if maxX > minX {
                return minX...maxX
            }
        }
        return nil
    }

    /// Kernel/AppKit-level frame constraint: guarantees the window can NEVER move or resize into the Notch or Menu Bar
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let targetScreen = screen ?? self.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            return frameRect
        }
        var rect = frameRect
        let maxTopY = Self.safeTopY(for: targetScreen)
        let vis = targetScreen.visibleFrame

        // 1. Never allow top edge (maxY) to go above safeTopY (below Notch & Menu Bar)
        if rect.maxY > maxTopY {
            rect.origin.y = maxTopY - rect.height
        }
        // 2. Never allow bottom edge below Dock / bottom of screen
        if rect.minY < vis.minY + 8 {
            rect.origin.y = vis.minY + 8
        }
        // 3. Keep horizontally inside screen bounds with 10pt margin
        if rect.maxX > vis.maxX - 10 {
            rect.origin.x = vis.maxX - rect.width - 10
        }
        if rect.minX < vis.minX + 10 {
            rect.origin.x = vis.minX + 10
        }
        return rect
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NotchSafePanel!
    private var hostingController: NSHostingController<ControllerView>!
    private let client = SmartGlassClient()
    private var isPinned: Bool = true
    private var hasUserDraggedPanel: Bool = false
    private var outsideClickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private let panelWidth: CGFloat = 344

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a permanent macOS Menu Bar utility without a Dock icon
        NSApp.setActivationPolicy(.accessory)
        setupMainMenuForEditCommands()

        // Place the status item in the right-hand priority zone of the Menu Bar (away from the MacBook Notch)
        let autosaveKey = "NSStatusItem Preferred Position com.xboxiptv.toolbar.statusitem"
        let currentPref = UserDefaults.standard.double(forKey: autosaveKey)
        if currentPref <= 0 || currentPref > 520 {
            UserDefaults.standard.set(210.0, forKey: autosaveKey)
        }

        // Fixed 26pt compact width prevents width jitter and stops macOS from pushing the item into the Notch
        statusItem = NSStatusBar.system.statusItem(withLength: 26)
        statusItem.autosaveName = "com.xboxiptv.toolbar.statusitem"

        if let button = statusItem.button {
            updateStatusBarIcon(connected: false)
            button.action = #selector(togglePanel(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        configurePanel()

        // Observe connection state changes to update the Menu Bar badge & keep top edge anchored
        client.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] newState in
                guard let self else { return }
                if case .connected = newState {
                    self.updateStatusBarIcon(connected: true)
                } else {
                    self.updateStatusBarIcon(connected: false)
                }
                self.reanchorPanelKeepingTopEdge()
            }
            .store(in: &cancellables)

        // Open the controller panel below the menu bar on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.showPanel(snapToStatusBar: true)
        }
    }

    private func setupMainMenuForEditCommands() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Paneli Hizala", action: #selector(snapPanelToStatusBarAction), keyEquivalent: "0")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Xbox Toolbar Controller", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // Edit menu (required for Cmd+V Paste, Cmd+C Copy, Cmd+X Cut, Cmd+A Select All in TextField)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func configurePanel() {
        let rootView = ControllerView(
            client: client,
            isPinned: Binding(
                get: { [weak self] in self?.isPinned ?? true },
                set: { [weak self] newVal in
                    self?.setPinned(newVal)
                }
            ),
            onTogglePin: { [weak self] in
                guard let self else { return }
                self.setPinned(!self.isPinned)
            },
            onLayoutHeightChanged: { [weak self] in
                self?.reanchorPanelKeepingTopEdge()
            },
            onSnapToToolbar: { [weak self] in
                guard let self else { return }
                self.hasUserDraggedPanel = false
                self.positionPanelBelowStatusBar()
            }
        )

        hostingController = NSHostingController(rootView: rootView)
        if #available(macOS 13.0, *) {
            hostingController.sizingOptions = [.intrinsicContentSize]
        }

        let initialSize = hostingController.view.fittingSize
        let contentRect = NSRect(
            x: 0,
            y: 0,
            width: panelWidth,
            height: max(initialSize.height, 540)
        )

        panel = NotchSafePanel(
            contentRect: contentRect,
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentViewController = hostingController

        installOutsideClickMonitor()
    }

    private func setPinned(_ pinned: Bool) {
        isPinned = pinned
        panel?.level = pinned ? .statusBar : .floating
    }

    private func installOutsideClickMonitor() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isPinned, self.panel.isVisible else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    func windowDidMove(_ notification: Notification) {
        if panel.isVisible && NSApp.currentEvent?.type == .leftMouseDragged {
            hasUserDraggedPanel = true
        }
    }

    /// Keeps the top edge (maxY) strictly anchored while growing/shrinking downward when drawer toggles
    func reanchorPanelKeepingTopEdge() {
        guard let panel = panel else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hostingController.view.layoutSubtreeIfNeeded()
            let fitting = self.hostingController.view.fittingSize
            let targetHeight = max(fitting.height, 480)
            let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
            let maxSafeTop = screen.map { NotchSafePanel.safeTopY(for: $0) } ?? panel.frame.maxY

            let currentTopY = min(panel.frame.maxY, maxSafeTop)
            var newFrame = NSRect(
                x: panel.frame.origin.x,
                y: currentTopY - targetHeight,
                width: self.panelWidth,
                height: targetHeight
            )
            newFrame = panel.constrainFrameRect(newFrame, to: screen)
            if abs(panel.frame.height - newFrame.height) > 1 || panel.frame.maxY > maxSafeTop {
                panel.setFrame(newFrame, display: true, animate: false)
            }
        }
    }

    /// Notch-aware positioning: places the panel cleanly below the Menu Bar & outside the MacBook Notch
    func positionPanelBelowStatusBar() {
        hostingController.view.layoutSubtreeIfNeeded()
        let fitting = hostingController.view.fittingSize
        let panelHeight = max(fitting.height, 500)

        let buttonWindow = statusItem.button?.window
        let targetScreen = buttonWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = targetScreen else { return }

        let safeTopY = NotchSafePanel.safeTopY(for: screen)
        let vis = screen.visibleFrame

        // Minimum safe X so the panel never sits underneath the MacBook Notch / Dynamic Island
        var minSafeX = vis.minX + 12
        var notchMaxX: CGFloat?
        if #available(macOS 12.0, *),
           let rightArea = screen.auxiliaryTopRightArea,
           rightArea.width >= panelWidth {
            minSafeX = max(minSafeX, rightArea.minX + 12)
            notchMaxX = rightArea.minX
        }

        var targetX = vis.maxX - panelWidth - 16

        if let btnWin = buttonWindow {
            let btnFrame = btnWin.frame
            let btnCenterX = btnFrame.midX

            var isOccludedByNotch = false
            if let nMax = notchMaxX, btnFrame.minX < nMax + 4 {
                isOccludedByNotch = true
            }

            if !isOccludedByNotch && btnFrame.width > 0 && btnCenterX >= minSafeX && btnCenterX <= vis.maxX {
                targetX = round(btnCenterX - (panelWidth / 2.0))
            }
        }

        // Clamp X strictly inside the right-of-Notch safe zone and Y strictly below safeTopY
        targetX = max(minSafeX, min(targetX, vis.maxX - panelWidth - 12))
        let targetY = max(vis.minY + 10, safeTopY - panelHeight)

        let rawFrame = NSRect(x: targetX, y: targetY, width: panelWidth, height: panelHeight)
        let constrained = panel.constrainFrameRect(rawFrame, to: screen)
        panel.setFrame(constrained, display: true, animate: false)
    }

    /// Composite fixed-size Menu Bar icon with status indicator dot (zero width jitter)
    private func updateStatusBarIcon(connected: Bool) {
        guard let button = statusItem.button else { return }
        let size = NSSize(width: 24, height: 18)
        let composedImage = NSImage(size: size, flipped: false) { rect in
            if let symbol = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: "Xbox") {
                let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .bold)
                let sym = symbol.withSymbolConfiguration(config) ?? symbol
                let symSize = sym.size
                let symRect = NSRect(
                    x: 1,
                    y: (rect.height - symSize.height) / 2.0,
                    width: symSize.width,
                    height: symSize.height
                )
                NSColor.white.set()
                sym.draw(in: symRect)
            }

            // Status Dot in bottom-right corner
            let dotRect = NSRect(x: rect.width - 6.5, y: 2.0, width: 5.5, height: 5.5)
            let dotPath = NSBezierPath(ovalIn: dotRect)
            if connected {
                NSColor(calibratedRed: 0.16, green: 0.85, blue: 0.20, alpha: 1.0).setFill()
            } else {
                NSColor(calibratedWhite: 0.65, alpha: 0.9).setFill()
            }
            dotPath.fill()
            return true
        }
        composedImage.isTemplate = false
        button.image = composedImage
        button.title = ""
        button.toolTip = connected ? "Xbox Toolbar Kumandası (Bağlı)" : "Xbox Toolbar Kumandası (Tıklayın)"
    }

    @objc private func snapPanelToStatusBarAction() {
        hasUserDraggedPanel = false
        showPanel(snapToStatusBar: true)
    }

    @objc private func togglePanel(_ sender: AnyObject?) {
        if panel.isVisible {
            panel.orderOut(sender)
        } else {
            showPanel(snapToStatusBar: !hasUserDraggedPanel)
        }
    }

    private func showPanel(snapToStatusBar: Bool) {
        if snapToStatusBar {
            positionPanelBelowStatusBar()
        } else {
            reanchorPanelKeepingTopEdge()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}
