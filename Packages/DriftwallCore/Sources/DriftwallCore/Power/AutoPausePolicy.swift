import Foundation

public typealias DisplayID = UInt32

public struct AutoPauseSettings: Codable, Hashable, Sendable {
    public static let lowBatteryThreshold = 20

    public var onFullscreen: Bool
    public var onLowPowerMode: Bool
    public var onLowBattery: Bool
    public var onBatteryPower: Bool

    public init(onFullscreen: Bool = true, onLowPowerMode: Bool = true, onLowBattery: Bool = true, onBatteryPower: Bool = false) {
        self.onFullscreen = onFullscreen
        self.onLowPowerMode = onLowPowerMode
        self.onLowBattery = onLowBattery
        self.onBatteryPower = onBatteryPower
    }
}

/// Snapshot of everything outside the app that can make us pause.
public struct SystemState: Hashable, Sendable {
    public var fullscreenDisplayIDs: Set<DisplayID>
    public var batteryPercent: Int?
    public var isOnBattery: Bool
    public var isLowPowerMode: Bool
    public var isUserPaused: Bool
    /// The display is off or the user session is switched away. Not set for a plain lock.
    public var isDisplayAsleep: Bool
    /// The screen is showing the macOS lock screen.
    public var isScreenLocked: Bool

    public init(
        fullscreenDisplayIDs: Set<DisplayID> = [], batteryPercent: Int? = nil, isOnBattery: Bool = false,
        isLowPowerMode: Bool = false, isUserPaused: Bool = false, isDisplayAsleep: Bool = false,
        isScreenLocked: Bool = false
    ) {
        self.fullscreenDisplayIDs = fullscreenDisplayIDs
        self.batteryPercent = batteryPercent
        self.isOnBattery = isOnBattery
        self.isLowPowerMode = isLowPowerMode
        self.isUserPaused = isUserPaused
        self.isDisplayAsleep = isDisplayAsleep
        self.isScreenLocked = isScreenLocked
    }
}

public enum PauseReason: String, Sendable, CaseIterable {
    case user
    case displayAsleep
    case fullscreenApp
    case lowPowerMode
    case lowBattery
    case batteryPower

    public var label: String {
        switch self {
        case .user: "Paused"
        case .displayAsleep: "Display asleep"
        case .fullscreenApp: "Full-screen app"
        case .lowPowerMode: "Low Power Mode"
        case .lowBattery: "Battery below \(AutoPauseSettings.lowBatteryThreshold)%"
        case .batteryPower: "On battery"
        }
    }
}

public enum AutoPausePolicy {
    /// Why `display` should be paused right now, or nil to keep playing. Highest priority first.
    public static func reason(display: DisplayID, state: SystemState, settings: AutoPauseSettings) -> PauseReason? {
        if state.isUserPaused { return .user }
        // The desktop is hidden behind the lock screen, so it never plays while locked.
        if state.isDisplayAsleep || state.isScreenLocked { return .displayAsleep }
        if settings.onFullscreen, state.fullscreenDisplayIDs.contains(display) { return .fullscreenApp }
        if settings.onLowPowerMode, state.isLowPowerMode { return .lowPowerMode }
        if settings.onLowBattery, state.isOnBattery, let percent = state.batteryPercent,
           percent < AutoPauseSettings.lowBatteryThreshold {
            return .lowBattery
        }
        if settings.onBatteryPower, state.isOnBattery { return .batteryPower }
        return nil
    }

    /// Whether the lock screen should show the animated wallpaper on `display`.
    /// Uses the same user and power rules as the desktop, ignoring the lock itself and
    /// full-screen apps (they sit behind the lock screen).
    public static func allowsLockAnimation(display: DisplayID, state: SystemState, settings: AutoPauseSettings, enabled: Bool) -> Bool {
        guard enabled, state.isScreenLocked else { return false }
        var unlocked = state
        unlocked.isScreenLocked = false
        unlocked.fullscreenDisplayIDs = []
        return reason(display: display, state: unlocked, settings: settings) == nil
    }
}
