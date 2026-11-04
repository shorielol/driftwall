import DriftwallCore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    enum Section: String, CaseIterable, Identifiable {
        case liked = "Liked", myList = "My List", recent = "Recent", downloaded = "Downloaded"
        case playlists = "Playlists", imported = "Imported"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State private var section: Section = .liked
    @State private var downloadedIDs: [String] = []
    @State private var isImporting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Library", subtitle: "Everything you've liked, saved and made") {
                    GlassSegmented(options: Section.allCases.map { ($0, $0.rawValue) }, selection: $section)
                }
                content
            }
            .padding(.bottom, 48)
        }
        .scrollIndicators(.never)
        .task(id: section) {
            if section == .downloaded { downloadedIDs = await model.cache.cachedIDs() }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): model.importCustom(from: urls)
            case .failure(let error): model.show(error.localizedDescription, isError: true)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .liked:
            collection(model.wallpapers(ids: model.library.liked), empty: "Tap the heart on any wallpaper to keep it here.")
        case .myList:
            collection(model.wallpapers(ids: model.library.myList), empty: "Use + on a wallpaper to save it for later.")
        case .recent:
            collection(model.wallpapers(ids: model.library.recents), empty: "Wallpapers you set will show up here.")
        case .downloaded:
            collection(model.wallpapers(ids: downloadedIDs), empty: "Downloaded 4K wallpapers play offline and switch instantly.")
        case .playlists:
            PlaylistList()
        case .imported:
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    ChromaticButton(title: "Import a Video", systemImage: "square.and.arrow.down") { isImporting = true }
                    let found = model.wallspaceCandidates.count
                    if found > 0 {
                        GlassButton(title: "Import \(found) from Wallspace", systemImage: "arrow.down.doc") { model.importFromWallspace() }
                    }
                    Text("Or drag videos onto the window. MP4, MOV, M4V; 1080p or better looks best. Imports stay on this Mac.")
                        .font(Theme.Typeface.body).foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, Theme.Space.gutter)
                if model.customWallpapers.isEmpty {
                    EmptyState(title: "No imports yet", message: "Your own clips stay on this Mac and never leave it.")
                } else {
                    WallpaperGrid(wallpapers: model.customWallpapers)
                }
            }
        }
    }

    @ViewBuilder private func collection(_ wallpapers: [Wallpaper], empty: String) -> some View {
        if wallpapers.isEmpty {
            EmptyState(title: "Nothing here yet", message: empty, actionTitle: "Browse Wallpapers") { model.tab = .explore }
        } else {
            WallpaperGrid(wallpapers: wallpapers)
        }
    }
}

struct PlaylistList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ChromaticButton(title: "New Playlist", systemImage: "plus") {
                    model.editingPlaylist = Playlist(name: "", wallpaperIDs: model.library.myList, interval: RotationInterval.hourly.seconds)
                }
                Toggle("Rotate through each fresh drop", isOn: model.binding(\.rotateLatestDrop))
                    .toggleStyle(.switch)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, Theme.Space.gutter)

            if model.library.playlists.isEmpty {
                EmptyState(title: "No playlists", message: "Playlists rotate your favourites on a timer, on one display or all of them.")
            }
            ForEach(model.library.playlists) { playlist in
                PlaylistRow(playlist: playlist)
                    .padding(.horizontal, Theme.Space.gutter)
            }
        }
    }
}

struct PlaylistRow: View {
    let playlist: Playlist
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: -28) {
                ForEach(model.wallpapers(ids: Array(playlist.wallpaperIDs.prefix(4)))) { wallpaper in
                    WallpaperPoster(wallpaper: wallpaper)
                        .frame(width: 96, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.ink, lineWidth: 2))
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name).font(Theme.Typeface.title(16)).foregroundStyle(.white)
                Text("\(playlist.wallpaperIDs.count) wallpapers · every \(Duration.seconds(playlist.interval).formatted(.units(allowed: [.hours, .minutes], width: .wide)))\(playlist.shuffle ? " · shuffled" : "")")
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            GlassButton(title: "Play", systemImage: "play.fill") { model.startPlaylist(playlist) }
            GlassButton(title: nil, systemImage: "pencil", help: "Edit") { model.editingPlaylist = playlist }
            GlassButton(title: nil, systemImage: "trash", help: "Delete") { model.deletePlaylist(playlist) }
        }
        .padding(14)
        .glass(cornerRadius: Theme.Radius.panel)
    }
}

struct PlaylistEditor: View {
    let original: Playlist
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selected: [String] = []
    @State private var interval: RotationInterval = .hourly
    @State private var shuffle = false
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(original.name.isEmpty ? "New Playlist" : "Edit Playlist").font(Theme.Typeface.title(22))
            HStack(spacing: 14) {
                TextField("Name", text: $name).textFieldStyle(.roundedBorder).frame(width: 240)
                Picker("Rotate", selection: $interval) {
                    ForEach(RotationInterval.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 230)
                Toggle("Shuffle", isOn: $shuffle)
                Spacer()
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            Text("\(selected.count) selected").font(Theme.Typeface.caption).foregroundStyle(Theme.textSecondary)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(CatalogQuery(text: search).apply(to: model.allWallpapers)) { wallpaper in
                        SelectableThumb(wallpaper: wallpaper, isSelected: selected.contains(wallpaper.id)) {
                            if let index = selected.firstIndex(of: wallpaper.id) {
                                selected.remove(at: index)
                            } else {
                                selected.append(wallpaper.id)
                            }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save(andPlay: false) }.disabled(!isValid)
                Button("Save & Play") { save(andPlay: true) }.keyboardShortcut(.defaultAction).disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 860, height: 640)
        .onAppear {
            name = original.name.isEmpty ? "My Playlist" : original.name
            selected = original.wallpaperIDs
            shuffle = original.shuffle
            interval = RotationInterval.allCases.min { abs($0.seconds - original.interval) < abs($1.seconds - original.interval) } ?? .hourly
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selected.isEmpty
    }

    private func save(andPlay play: Bool) {
        let playlist = original.with(name: name.trimmingCharacters(in: .whitespaces), wallpaperIDs: selected, interval: interval.seconds, shuffle: shuffle)
        model.savePlaylist(playlist)
        if play { model.startPlaylist(playlist) }
        dismiss()
    }
}

struct SelectableThumb: View {
    let wallpaper: Wallpaper
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay { WallpaperPoster(wallpaper: wallpaper) }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Theme.teal : Color.clear, lineWidth: 3)
                )
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? Theme.teal : .white.opacity(0.8))
                        .padding(6)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(wallpaper.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        .padding(6).foregroundStyle(.white).shadow(radius: 3)
                }
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .accessibilityLabel(Text(wallpaper.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
