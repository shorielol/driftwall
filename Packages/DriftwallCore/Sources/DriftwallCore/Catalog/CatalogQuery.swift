import Foundation

public enum WallpaperSort: String, CaseIterable, Codable, Sendable, Identifiable {
    case popular
    case newest
    case longest
    case title

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .popular: "Popular"
        case .newest: "Newest"
        case .longest: "Longest"
        case .title: "A–Z"
        }
    }
}

/// Search + category filter + sort. Pure value; apply it to any wallpaper list.
public struct CatalogQuery: Hashable, Sendable {
    public var text: String
    public var category: String?
    public var sort: WallpaperSort

    public init(text: String = "", category: String? = nil, sort: WallpaperSort = .popular) {
        self.text = text
        self.category = category
        self.sort = sort
    }

    public func apply(to wallpapers: [Wallpaper]) -> [Wallpaper] {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = wallpapers.filter { wallpaper in
            (category == nil || wallpaper.category == category) && (needle.isEmpty || Self.matches(wallpaper, needle))
        }
        return filtered.sorted(by: comparator)
    }

    private static func matches(_ wallpaper: Wallpaper, _ needle: String) -> Bool {
        let haystack = [wallpaper.title, wallpaper.description, wallpaper.category] + wallpaper.tags
        return haystack.contains { $0.localizedStandardContains(needle) }
    }

    private var comparator: (Wallpaper, Wallpaper) -> Bool {
        switch sort {
        case .popular:
            { ($0.sourceRank, $0.id) < ($1.sourceRank, $1.id) }
        case .newest:
            { ($0.addedInDrop, $0.uploadedAt, $1.id) > ($1.addedInDrop, $1.uploadedAt, $0.id) }
        case .longest:
            { ($0.durationSeconds, $1.id) > ($1.durationSeconds, $0.id) }
        case .title:
            { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }
}
