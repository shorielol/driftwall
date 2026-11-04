import AppKit
import CoreGraphics
import DriftwallCore
import IOKit.ps

/// Watches everything outside the app that affects playback and reports one combined snapshot.
final class SystemMonitor {
    private static let fullscreenPollInterval: Duration = .seconds(2)
    private static let batteryPollInterval: Duration = .seconds(60)

    private(set) var fullscreenDisplays: Set<DisplayID> = []
    private(set) var batteryPercent: Int?
    private(set) var isOnBattery = false
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var screensAsleep = false
    private var screenLocked = false
    private var sessionInactive = false
    var isAsleepOrLocked: Bool { screensAsleep || screenLocked || sessionInactive }
    private(set) var isDarkAppearance = false

    var onStateChange: (() -> Void)?
    var onScreensChange: (() -> Void)?
    var onAppearanceChange: (() -> Void)?
    var onWake: (() -> Void)?

    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var pollTasks: [Task<Void, Never>] = []
    private var powerSource: CFRunLoopSource?

    func start() {
        isDarkAppearance = Self.systemIsDark()
        refreshBattery()
        refreshFullscreen()
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { $0.onScreensChange?() }
        observe(NotificationCenter.default, .NSProcessInfoPowerStateDidChange) { monitor in
            monitor.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            monitor.onStateChange?()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.update(\.screensAsleep, true) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { monitor in
            monitor.update(\.screensAsleep, false)
            monitor.onWake?()
        }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.update(\.sessionInactive, true) }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.update(\.sessionInactive, false) }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.refreshFullscreen() }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { $0.refreshFullscreen() }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.update(\.screenLocked, true) }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.update(\.screenLocked, false) }
        startPowerSourceNotifications()
        observe(distributed, Notification.Name("AppleInterfaceThemeChangedNotification")) { monitor in
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                monitor.isDarkAppearance = Self.systemIsDark()
                monitor.onAppearanceChange?()
            }
        }

        pollTasks = [
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.fullscreenPollInterval)
                    self?.refreshFullscreen()
                }
            },
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.batteryPollInterval)
                    self?.refreshBattery()
                }
            },
        ]
    }

    func stop() {
        tokens.forEach { center, token in center.removeObserver(token) }
        tokens.removeAll()
        pollTasks.forEach { $0.cancel() }
        pollTasks.removeAll()
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
            self.powerSource = nil
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, handler: @escaping @MainActor (SystemMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        tokens.append((center, token))
    }

    private func update(_ flag: ReferenceWritableKeyPath<SystemMonitor, Bool>, _ value: Bool) {
        guard self[keyPath: flag] != value else { return }
        let before = isAsleepOrLocked
        self[keyPath: flag] = value
        if before != isAsleepOrLocked { onStateChange?() }
    }

    /// Power source changes (plug/unplug, level steps) arrive immediately instead of on the next poll.
    private func startPowerSourceNotifications() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<SystemMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refreshBattery() }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSource = source
    }

    func snapshot(userPaused: Bool) -> SystemState {
        SystemState(
            fullscreenDisplayIDs: fullscreenDisplays,
            batteryPercent: batteryPercent,
            isOnBattery: isOnBattery,
            isLowPowerMode: isLowPowerMode,
            isUserPaused: userPaused,
            isDisplayAsleep: isAsleepOrLocked
        )
    }

    // MARK: Appearance

    static func systemIsDark() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // MARK: Full-screen detection

    /// A display counts as full-screen when another app's normal-layer window covers its entire bounds.
    private func refreshFullscreen() {
        let detected = Self.detectFullscreenDisplays()
        guard detected != fullscreenDisplays else { return }
        fullscreenDisplays = detected
        onStateChange?()
    }

    static func detectFullscreenDisplays() -> Set<DisplayID> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let displays = NSScreen.screens.map { ($0.displayID, CGDisplayBounds($0.displayID)) }
        var result = Set<DisplayID>()
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let owner = window[kCGWindowOwnerPID as String] as? pid_t, owner != ownPID,
                  // Overlays from menu-bar utilities and automation tools are not full-screen apps.
                  NSRunningApplication(processIdentifier: owner)?.activationPolicy == .regular,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            for (display, displayBounds) in displays where covers(bounds, displayBounds) {
                result.insert(display)
            }
        }
        return result
    }

    private static func covers(_ window: CGRect, _ display: CGRect) -> Bool {
        let tolerance: CGFloat = 1
        return window.minX <= display.minX + tolerance && window.minY <= display.minY + tolerance
            && window.maxX >= display.maxX - tolerance && window.maxY >= display.maxY - tolerance
    }

    // MARK: Battery

    private func refreshBattery() {
        let reading = Self.readBattery()
        guard reading.percent != batteryPercent || reading.onBattery != isOnBattery else { return }
        batteryPercent = reading.percent
        isOnBattery = reading.onBattery
        onStateChange?()
    }

    static func readBattery() -> (percent: Int?, onBattery: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return (nil, false)
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(1, description[kIOPSMaxCapacityKey] as? Int ?? 100)
            let onBattery = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
            return (current * 100 / maximum, onBattery)
        }
        return (nil, false)
    }
}
