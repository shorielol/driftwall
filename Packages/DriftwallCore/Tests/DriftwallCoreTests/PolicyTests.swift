import Foundation
import Testing
@testable import DriftwallCore

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func at(_ hour: Int, _ minute: Int = 0, day: Int = 4) -> Date {
    utcCalendar().date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

@Suite("Playlist rotation")
struct PlaylistTests {
    let playlist = Playlist(name: "Chill", wallpaperIDs: ["a", "b", "c"], interval: 3600)

    @Test func `advances one item per interval and wraps`() {
        let start = at(0)
        #expect(playlist.currentID(startedAt: start, now: at(0, 30)) == "a")
        #expect(playlist.currentID(startedAt: start, now: at(1, 1)) == "b")
        #expect(playlist.currentID(startedAt: start, now: at(2, 59)) == "c")
        #expect(playlist.currentID(startedAt: start, now: at(3, 0)) == "a")
    }

    @Test func `next change lands on interval boundary`() {
        #expect(playlist.nextChange(startedAt: at(0), after: at(1, 15)) == at(2))
    }

    @Test func `empty playlist resolves to nil`() {
        let empty = Playlist(name: "Empty", wallpaperIDs: [], interval: 60)
        #expect(empty.currentID(startedAt: at(0), now: at(5)) == nil)
    }

    @Test func `shuffle visits every item once per cycle and is deterministic`() {
        let shuffled = Playlist(name: "S", wallpaperIDs: ["a", "b", "c", "d", "e"], interval: 60, shuffle: true)
        let start = at(0)
        let cycle = (0..<5).compactMap { shuffled.currentID(startedAt: start, now: start.addingTimeInterval(Double($0) * 60 + 1)) }
        #expect(Set(cycle) == Set(shuffled.wallpaperIDs))
        let again = (0..<5).compactMap { shuffled.currentID(startedAt: start, now: start.addingTimeInterval(Double($0) * 60 + 1)) }
        #expect(cycle == again)
    }

    @Test func `interval is clamped to a sane minimum`() {
        let fast = Playlist(name: "F", wallpaperIDs: ["a", "b"], interval: 1)
        #expect(fast.interval == Playlist.minimumInterval)
    }
}

@Suite("Day and night")
struct DayNightTests {
    let schedule = DayNightSchedule(dayStartMinutes: 7 * 60, nightStartMinutes: 19 * 60)

    @Test(arguments: [(6, DayPhase.night), (7, .day), (12, .day), (18, .day), (19, .night), (23, .night)])
    func phase(hour: Int, expected: DayPhase) {
        #expect(schedule.phase(at: at(hour), calendar: utcCalendar()) == expected)
    }

    @Test func `next transition from morning is evening`() {
        #expect(schedule.nextTransition(after: at(9), calendar: utcCalendar()) == at(19))
    }

    @Test func `next transition from late night is next morning`() {
        #expect(schedule.nextTransition(after: at(22), calendar: utcCalendar()) == at(7, day: 5))
    }

    @Test func `night spanning midnight when night starts before day`() {
        let inverted = DayNightSchedule(dayStartMinutes: 20 * 60, nightStartMinutes: 6 * 60)
        #expect(inverted.phase(at: at(21), calendar: utcCalendar()) == .day)
        #expect(inverted.phase(at: at(10), calendar: utcCalendar()) == .night)
    }
}

@Suite("Wallpaper rules")
struct WallpaperRuleTests {
    @Test func `fixed rule`() {
        #expect(WallpaperRule.fixed("x").resolve(at: at(1), isDarkAppearance: false, calendar: utcCalendar()) == "x")
        #expect(WallpaperRule.fixed("x").nextChange(after: at(1), calendar: utcCalendar()) == nil)
    }

    @Test func `appearance rule follows system theme`() {
        let rule = WallpaperRule.appearance(light: "sun", dark: "moon")
        #expect(rule.resolve(at: at(1), isDarkAppearance: true, calendar: utcCalendar()) == "moon")
        #expect(rule.resolve(at: at(1), isDarkAppearance: false, calendar: utcCalendar()) == "sun")
    }

    @Test func `day night rule`() {
        let rule = WallpaperRule.dayNight(day: "d", night: "n", schedule: .standard)
        #expect(rule.resolve(at: at(10), isDarkAppearance: false, calendar: utcCalendar()) == "d")
        #expect(rule.resolve(at: at(22), isDarkAppearance: false, calendar: utcCalendar()) == "n")
        #expect(rule.nextChange(after: at(10), calendar: utcCalendar()) == at(19))
    }

    @Test func `playlist rule`() {
        let rule = WallpaperRule.playlist(Playlist(name: "P", wallpaperIDs: ["a", "b"], interval: 3600), startedAt: at(0))
        #expect(rule.resolve(at: at(1, 5), isDarkAppearance: false, calendar: utcCalendar()) == "b")
        #expect(rule.nextChange(after: at(1, 5), calendar: utcCalendar()) == at(2))
    }

    @Test func `rules round trip through JSON`() throws {
        let rules: [WallpaperRule] = [
            .fixed("a"),
            .appearance(light: "l", dark: "d"),
            .dayNight(day: "d", night: "n", schedule: .standard),
            .playlist(Playlist(name: "P", wallpaperIDs: ["a"], interval: 600), startedAt: at(0)),
        ]
        let data = try JSONEncoder().encode(rules)
        #expect(try JSONDecoder().decode([WallpaperRule].self, from: data) == rules)
    }

    @Test func `referenced ids`() {
        #expect(WallpaperRule.dayNight(day: "d", night: "n", schedule: .standard).referencedIDs == ["d", "n"])
    }
}

@Suite("Auto pause")
struct AutoPauseTests {
    let settings = AutoPauseSettings()

    @Test func `plays when nothing applies`() {
        #expect(AutoPausePolicy.reason(display: 1, state: SystemState(), settings: settings) == nil)
    }

    @Test func `fullscreen pauses only that display`() {
        let state = SystemState(fullscreenDisplayIDs: [2])
        #expect(AutoPausePolicy.reason(display: 2, state: state, settings: settings) == .fullscreenApp)
        #expect(AutoPausePolicy.reason(display: 1, state: state, settings: settings) == nil)
    }

    @Test(arguments: [(19, true), (20, false), (80, false)])
    func lowBattery(percent: Int, paused: Bool) {
        let state = SystemState(batteryPercent: percent, isOnBattery: true)
        #expect((AutoPausePolicy.reason(display: 1, state: state, settings: settings) == .lowBattery) == paused)
    }

    @Test func `low battery ignored while charging`() {
        let state = SystemState(batteryPercent: 5, isOnBattery: false)
        #expect(AutoPausePolicy.reason(display: 1, state: state, settings: settings) == nil)
    }

    @Test func `low power mode pauses`() {
        let state = SystemState(isLowPowerMode: true)
        #expect(AutoPausePolicy.reason(display: 1, state: state, settings: settings) == .lowPowerMode)
    }

    @Test func `user pause wins and sleep pauses everything`() {
        #expect(AutoPausePolicy.reason(display: 1, state: SystemState(isUserPaused: true), settings: settings) == .user)
        #expect(AutoPausePolicy.reason(display: 1, state: SystemState(isDisplayAsleep: true), settings: settings) == .displayAsleep)
    }

    @Test func `disabled settings never pause`() {
        let off = AutoPauseSettings(onFullscreen: false, onLowPowerMode: false, onLowBattery: false, onBatteryPower: false)
        let state = SystemState(fullscreenDisplayIDs: [1], batteryPercent: 3, isOnBattery: true, isLowPowerMode: true)
        #expect(AutoPausePolicy.reason(display: 1, state: state, settings: off) == nil)
    }

    @Test func `optional pause on any battery power`() {
        let strict = AutoPauseSettings(onBatteryPower: true)
        #expect(AutoPausePolicy.reason(display: 1, state: SystemState(batteryPercent: 90, isOnBattery: true), settings: strict) == .batteryPower)
    }
}

@Suite("Display assignments")
struct DisplayAssignmentTests {
    let builtIn = DisplayKey(name: "Built-in Retina Display", width: 1512, height: 982)
    let external = DisplayKey(name: "ED270R", width: 1920, height: 1080)

    @Test func `key format matches name and size`() {
        #expect(external.rawValue == "ED270R_1920x1080")
    }

    @Test func `apply to all clears per display overrides`() {
        let assignments = DisplayAssignments()
            .assigning(.fixed("a"), to: .display(external))
            .assigning(.fixed("b"), to: .allDisplays)
        #expect(assignments.rule(for: external) == .fixed("b"))
        #expect(assignments.rule(for: builtIn) == .fixed("b"))
    }

    @Test func `per display override wins over default`() {
        let assignments = DisplayAssignments()
            .assigning(.fixed("b"), to: .allDisplays)
            .assigning(.fixed("a"), to: .display(external))
        #expect(assignments.rule(for: external) == .fixed("a"))
        #expect(assignments.rule(for: builtIn) == .fixed("b"))
    }

    @Test func `clearing removes everything`() {
        let assignments = DisplayAssignments().assigning(.fixed("a"), to: .allDisplays).cleared()
        #expect(assignments.rule(for: builtIn) == nil)
    }

    @Test func `referenced ids cover all rules`() {
        let assignments = DisplayAssignments()
            .assigning(.fixed("b"), to: .allDisplays)
            .assigning(.appearance(light: "l", dark: "d"), to: .display(external))
        #expect(assignments.referencedIDs == ["b", "d", "l"])
    }
}
