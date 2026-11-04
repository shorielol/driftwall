import Foundation

/// Stable identity for a monitor across launches: localized name plus point size.
public struct DisplayKey: Codable, Hashable, Sendable {
    public let name: String
    public let width: Int
    public let height: Int

    public init(name: String, width: Int, height: Int) {
        self.name = name
        self.width = width
        self.height = height
    }

    public var rawValue: String { "\(name)_\(width)x\(height)" }
}

public enum ApplyTarget: Hashable, Sendable {
    case allDisplays
    case display(DisplayKey)
}

/// Which rule drives each display. Per-display overrides beat the all-displays default.
public struct DisplayAssignments: Codable, Hashable, Sendable {
    public let defaultRule: WallpaperRule?
    public let perDisplay: [String: WallpaperRule]

    public init(defaultRule: WallpaperRule? = nil, perDisplay: [String: WallpaperRule] = [:]) {
        self.defaultRule = defaultRule
        self.perDisplay = perDisplay
    }

    public func rule(for display: DisplayKey) -> WallpaperRule? {
        perDisplay[display.rawValue] ?? defaultRule
    }

    public func assigning(_ rule: WallpaperRule, to target: ApplyTarget) -> DisplayAssignments {
        switch target {
        case .allDisplays:
            DisplayAssignments(defaultRule: rule, perDisplay: [:])
        case .display(let key):
            DisplayAssignments(defaultRule: defaultRule, perDisplay: perDisplay.merging([key.rawValue: rule]) { _, new in new })
        }
    }

    public func cleared() -> DisplayAssignments {
        DisplayAssignments()
    }

    public var referencedIDs: [String] {
        let rules = [defaultRule].compactMap { $0 } + Array(perDisplay.values)
        return Array(Set(rules.flatMap(\.referencedIDs))).sorted()
    }
}
