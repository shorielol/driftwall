import Foundation

// MARK: - Playlist

public struct Playlist: Codable, Hashable, Sendable, Identifiable {
    public static let minimumInterval: TimeInterval = 60

    public let id: UUID
    public let name: String
    public let wallpaperIDs: [String]
    public let interval: TimeInterval
    public let shuffle: Bool

    public init(id: UUID = UUID(), name: String, wallpaperIDs: [String], interval: TimeInterval, shuffle: Bool = false) {
        self.id = id
        self.name = name
        self.wallpaperIDs = wallpaperIDs
        self.interval = max(Self.minimumInterval, interval)
        self.shuffle = shuffle
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            wallpaperIDs: try container.decode([String].self, forKey: .wallpaperIDs),
            interval: try container.decode(TimeInterval.self, forKey: .interval),
            shuffle: try container.decodeIfPresent(Bool.self, forKey: .shuffle) ?? false
        )
    }

    public func with(name: String? = nil, wallpaperIDs: [String]? = nil, interval: TimeInterval? = nil, shuffle: Bool? = nil) -> Playlist {
        Playlist(
            id: id,
            name: name ?? self.name,
            wallpaperIDs: wallpaperIDs ?? self.wallpaperIDs,
            interval: interval ?? self.interval,
            shuffle: shuffle ?? self.shuffle
        )
    }

    private func slot(startedAt: Date, now: Date) -> Int {
        Int((max(0, now.timeIntervalSince(startedAt)) / interval).rounded(.down))
    }

    public func currentID(startedAt: Date, now: Date) -> String? {
        guard !wallpaperIDs.isEmpty else { return nil }
        let slot = slot(startedAt: startedAt, now: now)
        let position = slot % wallpaperIDs.count
        guard shuffle else { return wallpaperIDs[position] }
        return permutation(cycle: slot / wallpaperIDs.count)[position]
    }

    public func nextChange(startedAt: Date, after date: Date) -> Date {
        let next = slot(startedAt: startedAt, now: date) + 1
        return startedAt.addingTimeInterval(Double(next) * interval)
    }

    /// Stable per (playlist, cycle) so every launch agrees on the order.
    private func permutation(cycle: Int) -> [String] {
        var generator = SplitMix64(seed: StableHash.fnv1a("\(id.uuidString)#\(cycle)"))
        return wallpaperIDs.shuffled(using: &generator)
    }
}

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum StableHash {
    static func fnv1a(_ text: String) -> UInt64 {
        text.utf8.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01B3 }
    }
}

// MARK: - Day / night

public enum DayPhase: String, Codable, Sendable {
    case day
    case night
}

public struct DayNightSchedule: Codable, Hashable, Sendable {
    public static let minutesPerDay = 24 * 60
    public static let standard = DayNightSchedule(dayStartMinutes: 7 * 60, nightStartMinutes: 19 * 60)

    public let dayStartMinutes: Int
    public let nightStartMinutes: Int

    public init(dayStartMinutes: Int, nightStartMinutes: Int) {
        self.dayStartMinutes = Self.clampMinutes(dayStartMinutes)
        self.nightStartMinutes = Self.clampMinutes(nightStartMinutes)
    }

    private static func clampMinutes(_ value: Int) -> Int {
        min(max(0, value), minutesPerDay - 1)
    }

    public func phase(at date: Date, calendar: Calendar = .current) -> DayPhase {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if dayStartMinutes < nightStartMinutes {
            return (dayStartMinutes..<nightStartMinutes).contains(minute) ? .day : .night
        }
        return (nightStartMinutes..<dayStartMinutes).contains(minute) ? .night : .day
    }

    public func nextTransition(after date: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: date)
        let candidates = [0, 1].flatMap { dayOffset -> [Date] in
            guard let base = calendar.date(byAdding: .day, value: dayOffset, to: today) else { return [] }
            return [dayStartMinutes, nightStartMinutes].compactMap { calendar.date(byAdding: .minute, value: $0, to: base) }
        }
        return candidates.filter { $0 > date }.min() ?? date.addingTimeInterval(TimeInterval(Self.minutesPerDay * 60))
    }
}

// MARK: - Rules

/// What a display should show and when that answer changes.
public enum WallpaperRule: Codable, Hashable, Sendable {
    case fixed(String)
    case playlist(Playlist, startedAt: Date)
    case dayNight(day: String, night: String, schedule: DayNightSchedule)
    case appearance(light: String, dark: String)

    public func resolve(at date: Date, isDarkAppearance: Bool, calendar: Calendar = .current) -> String? {
        switch self {
        case .fixed(let id):
            id
        case .playlist(let playlist, let startedAt):
            playlist.currentID(startedAt: startedAt, now: date)
        case .dayNight(let day, let night, let schedule):
            schedule.phase(at: date, calendar: calendar) == .day ? day : night
        case .appearance(let light, let dark):
            isDarkAppearance ? dark : light
        }
    }

    /// Next time `resolve` may return something different (appearance changes are event driven → nil).
    public func nextChange(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .fixed, .appearance:
            nil
        case .playlist(let playlist, let startedAt):
            playlist.wallpaperIDs.count > 1 ? playlist.nextChange(startedAt: startedAt, after: date) : nil
        case .dayNight(_, _, let schedule):
            schedule.nextTransition(after: date, calendar: calendar)
        }
    }

    public var referencedIDs: [String] {
        let ids: [String] = switch self {
        case .fixed(let id): [id]
        case .playlist(let playlist, _): playlist.wallpaperIDs
        case .dayNight(let day, let night, _): [day, night]
        case .appearance(let light, let dark): [light, dark]
        }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    public var label: String {
        switch self {
        case .fixed: "Single wallpaper"
        case .playlist(let playlist, _): "Playlist · \(playlist.name)"
        case .dayNight: "Day & night"
        case .appearance: "Light & dark"
        }
    }
}
