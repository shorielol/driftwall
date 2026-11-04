import Foundation

public enum RotationInterval: String, Codable, CaseIterable, Sendable, Identifiable {
    case thirtyMinutes, hourly, sixHours, daily

    public var id: String { rawValue }

    public var seconds: TimeInterval {
        switch self {
        case .thirtyMinutes: 30 * 60
        case .hourly: 60 * 60
        case .sixHours: 6 * 60 * 60
        case .daily: 24 * 60 * 60
        }
    }

    public var label: String {
        switch self {
        case .thirtyMinutes: "Every 30 minutes"
        case .hourly: "Every hour"
        case .sixHours: "Every 6 hours"
        case .daily: "Every day"
        }
    }
}

public enum VideoScaling: String, Codable, CaseIterable, Sendable, Identifiable {
    case fill, fit

    public var id: String { rawValue }
    public var label: String { self == .fill ? "Fill screen" : "Fit inside" }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public static let playbackRateRange: ClosedRange<Double> = 0.25...2.0
    public static let cacheLimitRange: ClosedRange<Int> = 2...200

    public var launchAtLogin: Bool
    public var autoStartWallpapers: Bool
    public var autoPause: AutoPauseSettings
    public var playbackRate: Double
    public var scaling: VideoScaling
    public var cacheLimitGB: Int
    public var notifyNewDrops: Bool
    public var rotateLatestDrop: Bool
    public var rotationInterval: RotationInterval
    public var setStaticFallback: Bool
    public var catalogURLOverride: String
    public var dayNightSchedule: DayNightSchedule
    /// Offer to import videos that land in ~/Downloads. Off by default: it needs folder access.
    public var watchDownloads: Bool

    public init(
        launchAtLogin: Bool = false, autoStartWallpapers: Bool = true, autoPause: AutoPauseSettings = AutoPauseSettings(),
        playbackRate: Double = 1.0, scaling: VideoScaling = .fill, cacheLimitGB: Int = 10,
        notifyNewDrops: Bool = true, rotateLatestDrop: Bool = false, rotationInterval: RotationInterval = .hourly,
        setStaticFallback: Bool = true, catalogURLOverride: String = "",
        dayNightSchedule: DayNightSchedule = .standard, watchDownloads: Bool = false
    ) {
        self.launchAtLogin = launchAtLogin
        self.autoStartWallpapers = autoStartWallpapers
        self.autoPause = autoPause
        self.playbackRate = min(max(playbackRate, Self.playbackRateRange.lowerBound), Self.playbackRateRange.upperBound)
        self.scaling = scaling
        self.cacheLimitGB = min(max(cacheLimitGB, Self.cacheLimitRange.lowerBound), Self.cacheLimitRange.upperBound)
        self.notifyNewDrops = notifyNewDrops
        self.rotateLatestDrop = rotateLatestDrop
        self.rotationInterval = rotationInterval
        self.setStaticFallback = setStaticFallback
        self.catalogURLOverride = catalogURLOverride
        self.dayNightSchedule = dayNightSchedule
        self.watchDownloads = watchDownloads
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = AppSettings()
        self.init(
            launchAtLogin: try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? base.launchAtLogin,
            autoStartWallpapers: try c.decodeIfPresent(Bool.self, forKey: .autoStartWallpapers) ?? base.autoStartWallpapers,
            autoPause: try c.decodeIfPresent(AutoPauseSettings.self, forKey: .autoPause) ?? base.autoPause,
            playbackRate: try c.decodeIfPresent(Double.self, forKey: .playbackRate) ?? base.playbackRate,
            scaling: try c.decodeIfPresent(VideoScaling.self, forKey: .scaling) ?? base.scaling,
            cacheLimitGB: try c.decodeIfPresent(Int.self, forKey: .cacheLimitGB) ?? base.cacheLimitGB,
            notifyNewDrops: try c.decodeIfPresent(Bool.self, forKey: .notifyNewDrops) ?? base.notifyNewDrops,
            rotateLatestDrop: try c.decodeIfPresent(Bool.self, forKey: .rotateLatestDrop) ?? base.rotateLatestDrop,
            rotationInterval: try c.decodeIfPresent(RotationInterval.self, forKey: .rotationInterval) ?? base.rotationInterval,
            setStaticFallback: try c.decodeIfPresent(Bool.self, forKey: .setStaticFallback) ?? base.setStaticFallback,
            catalogURLOverride: try c.decodeIfPresent(String.self, forKey: .catalogURLOverride) ?? base.catalogURLOverride,
            dayNightSchedule: try c.decodeIfPresent(DayNightSchedule.self, forKey: .dayNightSchedule) ?? base.dayNightSchedule,
            watchDownloads: try c.decodeIfPresent(Bool.self, forKey: .watchDownloads) ?? base.watchDownloads
        )
    }

    public var cacheLimitBytes: Int64 { Int64(cacheLimitGB) * 1_000_000_000 }

    /// https anywhere, plain http only for loopback (local catalog testing).
    public func effectiveCatalogURL(default fallback: URL) -> URL {
        let trimmed = catalogURLOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), let host = url.host() else {
            return fallback
        }
        let isLoopback = ["localhost", "127.0.0.1", "::1"].contains(host)
        return scheme == "https" || (scheme == "http" && isLoopback) ? url : fallback
    }
}
