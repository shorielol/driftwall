import Foundation

/// The user's personal collection. Every mutation returns a new value.
public struct LibraryState: Codable, Hashable, Sendable {
    public static let recentsLimit = 30

    public let liked: [String]
    public let recents: [String]
    public let myList: [String]
    public let playlists: [Playlist]
    public let lastSeenDropID: String?

    public init(
        liked: [String] = [], recents: [String] = [], myList: [String] = [],
        playlists: [Playlist] = [], lastSeenDropID: String? = nil
    ) {
        self.liked = liked
        self.recents = recents
        self.myList = myList
        self.playlists = playlists
        self.lastSeenDropID = lastSeenDropID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            liked: try container.decodeIfPresent([String].self, forKey: .liked) ?? [],
            recents: try container.decodeIfPresent([String].self, forKey: .recents) ?? [],
            myList: try container.decodeIfPresent([String].self, forKey: .myList) ?? [],
            playlists: try container.decodeIfPresent([Playlist].self, forKey: .playlists) ?? [],
            lastSeenDropID: try container.decodeIfPresent(String.self, forKey: .lastSeenDropID)
        )
    }

    private func copy(
        liked: [String]? = nil, recents: [String]? = nil, myList: [String]? = nil,
        playlists: [Playlist]? = nil, lastSeenDropID: String?? = nil
    ) -> LibraryState {
        LibraryState(
            liked: liked ?? self.liked,
            recents: recents ?? self.recents,
            myList: myList ?? self.myList,
            playlists: playlists ?? self.playlists,
            lastSeenDropID: lastSeenDropID ?? self.lastSeenDropID
        )
    }

    private static func toggled(_ id: String, in list: [String]) -> [String] {
        list.contains(id) ? list.filter { $0 != id } : [id] + list
    }

    public func isLiked(_ id: String) -> Bool { liked.contains(id) }
    public func isInMyList(_ id: String) -> Bool { myList.contains(id) }

    public func togglingLike(_ id: String) -> LibraryState {
        copy(liked: Self.toggled(id, in: liked))
    }

    public func togglingMyList(_ id: String) -> LibraryState {
        copy(myList: Self.toggled(id, in: myList))
    }

    public func recordingRecent(_ id: String) -> LibraryState {
        copy(recents: Array(([id] + recents.filter { $0 != id }).prefix(Self.recentsLimit)))
    }

    public func upserting(_ playlist: Playlist) -> LibraryState {
        let exists = playlists.contains { $0.id == playlist.id }
        let updated = exists ? playlists.map { $0.id == playlist.id ? playlist : $0 } : playlists + [playlist]
        return copy(playlists: updated)
    }

    public func removingPlaylist(id: UUID) -> LibraryState {
        copy(playlists: playlists.filter { $0.id != id })
    }

    public func markingDropSeen(_ dropID: String) -> LibraryState {
        copy(lastSeenDropID: .some(dropID))
    }
}
