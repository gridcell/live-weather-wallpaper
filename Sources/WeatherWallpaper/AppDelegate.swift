import AppKit
import ServiceManagement
import SpriteKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlays: [(window: NSWindow, view: OverlayView)] = []
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let location = LocationProvider()
    private var timer: Timer?
    private var demoTimer: Timer?
    private var frameTimer: Timer?
    private var demoQueue: [WeatherKind] = []

    private var live: Weather?
    private var lastError: String?
    private var preview: WeatherKind? = UserDefaults.standard.string(forKey: "previewKind").flatMap(WeatherKind.init(rawValue:)) {
        didSet { UserDefaults.standard.set(preview?.rawValue, forKey: "previewKind") }
    }

    /// What the wallpaper should show: the preview override if set, else live weather.
    private var displayed: Weather? {
        guard let preview else { return live }
        return Weather(kind: preview, isDay: live?.isDay ?? true, windX: 12, temperatureC: live?.temperatureC)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        rebuildOverlays()
        updateUI()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)

        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
        if CommandLine.arguments.contains("--demo") { cycleEffects() }

        // One shared loop draws every screen in turn. Letting each view run its own
        // display link starves all but one when the displays' refresh rates differ.
        let frames = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                // Skip screens whose desktop is fully covered by other windows.
                self?.overlays.forEach { overlay in
                    if overlay.window.occlusionState.contains(.visible) { overlay.view.draw() }
                }
            }
        }
        RunLoop.main.add(frames, forMode: .common)
        frameTimer = frames
    }

    // MARK: - Overlay windows

    private func rebuildOverlays() {
        overlays.forEach { $0.window.orderOut(nil) }
        overlays = NSScreen.screens.map { screen in
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            // Just above the wallpaper, below the desktop icons.
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false

            let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            window.contentView = view
            window.orderFront(nil)
            return (window, view)
        }
    }

    @objc private func screensChanged() {
        rebuildOverlays()
        updateUI()
    }

    // MARK: - Weather

    @objc private func refresh() {
        Task {
            guard let coordinate = await location.currentCoordinate() else {
                lastError = "Couldn't determine location"
                updateUI()
                return
            }
            do {
                live = try await WeatherService.fetch(latitude: coordinate.latitude, longitude: coordinate.longitude)
                lastError = nil
            } catch {
                lastError = "Couldn't fetch weather"
            }
            updateUI()
        }
    }

    // MARK: - UI

    private func updateUI() {
        let weather = displayed
        overlays.forEach { $0.view.scene.apply(weather) }

        let symbol = weather.map { $0.kind.symbolName(isDay: $0.isDay) } ?? "cloud.slash"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: weather?.kind.title ?? "Weather")

        let menu = NSMenu()
        menu.addItem(withTitle: summary(), action: nil, keyEquivalent: "")
        if let lastError { menu.addItem(withTitle: lastError, action: nil, keyEquivalent: "") }
        menu.addItem(.separator())

        let previewItem = NSMenuItem(title: "Effect", action: nil, keyEquivalent: "")
        let previewMenu = NSMenu()
        let auto = NSMenuItem(title: "Live Weather", action: #selector(selectPreview(_:)), keyEquivalent: "")
        auto.state = preview == nil ? .on : .off
        previewMenu.addItem(auto)
        previewMenu.addItem(.separator())
        for kind in WeatherKind.allCases {
            let item = NSMenuItem(title: kind.title, action: #selector(selectPreview(_:)), keyEquivalent: "")
            item.representedObject = kind.rawValue
            item.state = preview == kind ? .on : .off
            previewMenu.addItem(item)
        }
        previewItem.submenu = previewMenu
        menu.addItem(previewItem)
        menu.addItem(withTitle: "Cycle All Effects", action: #selector(cycleEffects), keyEquivalent: "")

        menu.addItem(withTitle: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Weather Wallpaper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func summary() -> String {
        guard let live else { return lastError == nil ? "Loading weather…" : "Weather unavailable" }
        var text = live.kind.title
        if let celsius = live.temperatureC {
            let formatter = MeasurementFormatter()
            formatter.numberFormatter.maximumFractionDigits = 0
            text += " · " + formatter.string(from: Measurement(value: celsius, unit: UnitTemperature.celsius))
        }
        return text
    }

    /// Shows every effect for 10 seconds each, then restores the previous setting.
    @objc private func cycleEffects() {
        demoTimer?.invalidate()
        let restore = preview
        demoQueue = WeatherKind.allCases
        preview = demoQueue.removeFirst()
        updateUI()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.demoQueue.isEmpty {
                    self.demoTimer?.invalidate()
                    self.preview = restore
                } else {
                    self.preview = self.demoQueue.removeFirst()
                }
                self.updateUI()
            }
        }
    }

    @objc private func selectPreview(_ sender: NSMenuItem) {
        demoTimer?.invalidate()
        preview = (sender.representedObject as? String).flatMap(WeatherKind.init(rawValue:))
        updateUI()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
        updateUI()
    }
}
