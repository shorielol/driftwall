import DriftwallCore
import SwiftUI

/// Full-window preview. Streams the preview rendition, or plays the 4K master if it's already downloaded.
/// Chrome fades away when the pointer rests.
struct PreviewView: View {
    let wallpaper: Wallpaper

    @Environment(AppModel.self) private var model
    @State private var localURL: URL?
    @State private var chromeVisible = true
    @State private var idleTask: Task<Void, Never>?
    @State private var titleHovered = false

    private static let idleDelay: Duration = .seconds(2.5)

    var body: some View {
        ZStack {
            // Media lives in an overlay so its fill-scaling can never widen the layout.
            Color.black
                .overlay {
                    ZStack {
                        WallpaperPoster(wallpaper: wallpaper)
                        WallpaperMotion(wallpaper: wallpaper, url: localURL ?? wallpaper.previewURL)
                            .id(localURL ?? wallpaper.previewURL)
                    }
                }
                .clipped()

            Group {
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .center)
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                topBar
                footBar
            }
            .opacity(chromeVisible ? 1 : 0)
            .animation(Theme.Motion.fade, value: chromeVisible)
        }
        .ignoresSafeArea()
        .onContinuousHover { _ in wake() }
        .onAppear(perform: wake)
        .task(id: wallpaper.id) {
            localURL = wallpaper.source == "custom" ? wallpaper.videoURL : await model.cache.localURL(for: wallpaper.id)
        }
        .onChange(of: model.downloads[wallpaper.id] == nil) {
            guard wallpaper.source != "custom" else { return }
            Task { localURL = await model.cache.localURL(for: wallpaper.id) }
        }
        .onExitCommand { close() }
        .onDisappear { idleTask?.cancel() }
    }

    private var topBar: some View {
        VStack {
            HStack {
                GlassButton(title: nil, systemImage: "xmark", help: "Close preview") { close() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Badge(text: wallpaper.isOriginal ? "RENDERED LIVE · ANY RESOLUTION" : localURL == nil ? "STREAMING PREVIEW" : (wallpaper.source == "custom" ? "ON THIS MAC" : "\(wallpaper.resolutionLabel) · OFFLINE"),
                      systemImage: wallpaper.isOriginal ? "sparkles" : localURL == nil ? "wifi" : "checkmark.seal.fill",
                      tint: wallpaper.isOriginal || localURL != nil ? Theme.teal : .white)
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            Spacer()
        }
    }

    private var footBar: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    RefractedTitle(text: wallpaper.title, size: 40, isHighlighted: titleHovered)
                        .onHover { titleHovered = $0 }
                    WallpaperMeta(wallpaper: wallpaper)
                    attribution
                }
                .frame(maxWidth: 560, alignment: .leading)
                Spacer()
                GlassGroup(spacing: 8) {
                    HStack(spacing: 10) {
                        ApplyControl(wallpaper: wallpaper)
                        if localURL == nil, !wallpaper.isOriginal {
                            GlassButton(title: nil, systemImage: "arrow.down", help: "Download 4K") { model.download(wallpaper) }
                                .disabled(model.downloads[wallpaper.id] != nil)
                        }
                        GlassButton(title: nil, systemImage: model.library.isLiked(wallpaper.id) ? "heart.fill" : "heart",
                                    isOn: model.library.isLiked(wallpaper.id), help: "Like") { model.toggleLike(wallpaper) }
                        GlassButton(title: nil, systemImage: model.library.isInMyList(wallpaper.id) ? "checkmark" : "plus", help: "My List") {
                            model.toggleMyList(wallpaper)
                        }
                        Menu {
                            WallpaperActions(wallpaper: wallpaper)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .glassCircle(interactive: true)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityLabel("More actions")
                    }
                }
            }
            .padding(22)
            .glass(cornerRadius: Theme.Radius.hero)
            .padding(24)
        }
    }

    @ViewBuilder private var attribution: some View {
        if wallpaper.isOriginal {
            Text("An original Driftwall scene, rendered in real time")
                .font(Theme.Typeface.caption).foregroundStyle(Theme.textTertiary)
        } else if wallpaper.source == "custom" {
            Text("Your own video").font(Theme.Typeface.caption).foregroundStyle(Theme.textTertiary)
        } else {
            HStack(spacing: 4) {
                Text("Video by \(wallpaper.author) ·")
                if let license = wallpaper.licenseURL {
                    Link(wallpaper.license, destination: license)
                } else {
                    Text(wallpaper.license)
                }
            }
            .font(Theme.Typeface.caption)
            .foregroundStyle(Theme.textTertiary)
        }
    }

    private func wake() {
        chromeVisible = true
        idleTask?.cancel()
        idleTask = Task {
            try? await Task.sleep(for: Self.idleDelay)
            guard !Task.isCancelled else { return }
            chromeVisible = false
        }
    }

    private func close() {
        withAnimation(Theme.Motion.standard) { model.previewing = nil }
    }
}

/// Pick the second half of a Day & Night or Light & Dark pair.
struct PairPickerSheet: View {
    let request: PairRequest
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var secondID: String?
    @State private var search = ""
    @State private var target: String = "all"

    private var labels: (String, String) {
        request.kind == .dayNight ? ("Day", "Night") : ("Light mode", "Dark mode")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.kind == .dayNight ? "Day & Night" : "Light & Dark").font(Theme.Typeface.title(22))
            Text(request.kind == .dayNight
                 ? "Driftwall switches between these two at the times below."
                 : "Driftwall follows your Mac's appearance setting.")
                .font(Theme.Typeface.body).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                slot(labels.0, wallpaper: request.first)
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
                slot(labels.1, wallpaper: secondID.flatMap(model.wallpaper(id:)))
                Spacer()
                if request.kind == .dayNight { ScheduleEditor() }
            }
            HStack {
                Text("Choose the \(labels.1.lowercased()) wallpaper").font(.headline)
                Spacer()
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(CatalogQuery(text: search).apply(to: model.allWallpapers).filter { $0.id != request.first.id }) { wallpaper in
                        SelectableThumb(wallpaper: wallpaper, isSelected: secondID == wallpaper.id) { secondID = wallpaper.id }
                    }
                }
            }
            HStack {
                Picker("Apply to", selection: $target) {
                    Text("All Displays").tag("all")
                    ForEach(model.displays) { Text($0.name).tag($0.key.rawValue) }
                }
                .frame(width: 280)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") { apply() }.keyboardShortcut(.defaultAction).disabled(secondID == nil)
            }
        }
        .padding(24)
        .frame(width: 860, height: 660)
    }

    private func slot(_ label: String, wallpaper: Wallpaper?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(Theme.Typeface.eyebrow).foregroundStyle(.secondary)
            Group {
                if let wallpaper {
                    WallpaperPoster(wallpaper: wallpaper)
                } else {
                    Rectangle().fill(Theme.inkRaised).overlay(Text("Pick below").font(.caption).foregroundStyle(.secondary))
                }
            }
            .frame(width: 176, height: 99)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func apply() {
        guard let second = secondID.flatMap(model.wallpaper(id:)) else { return }
        let applyTarget: ApplyTarget = model.displays.first { $0.key.rawValue == target }.map { .display($0.key) } ?? .allDisplays
        model.applyPair(kind: request.kind, first: request.first, second: second, to: applyTarget)
        dismiss()
    }
}

/// Day start / night start pickers bound to settings.
struct ScheduleEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker("Day starts", selection: binding(\.dayStartMinutes), displayedComponents: .hourAndMinute)
            DatePicker("Night starts", selection: binding(\.nightStartMinutes), displayedComponents: .hourAndMinute)
        }
        .frame(width: 220)
    }

    private func binding(_ keyPath: KeyPath<DayNightSchedule, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = model.settings.dayNightSchedule[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                let current = model.settings.dayNightSchedule
                let next = keyPath == \DayNightSchedule.dayStartMinutes
                    ? DayNightSchedule(dayStartMinutes: minutes, nightStartMinutes: current.nightStartMinutes)
                    : DayNightSchedule(dayStartMinutes: current.dayStartMinutes, nightStartMinutes: minutes)
                model.updateSettings { $0.dayNightSchedule = next }
            }
        )
    }
}
