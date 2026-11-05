import DriftwallCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var model = model
        ZStack(alignment: .top) {
            Theme.ink.ignoresSafeArea()
            AuroraBackground(isActive: model.previewing == nil && model.isWindowVisible)
                .ignoresSafeArea()

            screen
                .id(model.tab)
                .transition(.opacity)

            LinearGradient(colors: [Theme.ink.opacity(0.92), Theme.ink.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 96)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            NavBar()

            if let wallpaper = model.previewing {
                PreviewView(wallpaper: wallpaper)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(10)
            }

            if model.showOnboarding {
                OnboardingView()
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .overlay(alignment: .bottom) { BannerView() }
        .overlay(alignment: .bottomTrailing) { DownloadOfferView() }
        .overlay { if isDropTargeted { DropTargetOverlay() } }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            model.importCustom(from: files)
            model.tab = .library
            return true
        } isTargeted: { targeted in
            withAnimation(Theme.Motion.fade) { isDropTargeted = targeted }
        }
        .animation(Theme.Motion.standard, value: model.tab)
        .animation(Theme.Motion.standard, value: model.previewing?.id)
        .animation(Theme.Motion.standard, value: model.showOnboarding)
        .sheet(item: $model.pairRequest) { request in
            PairPickerSheet(request: request)
        }
        .sheet(item: $model.editingPlaylist) { playlist in
            PlaylistEditor(original: playlist)
        }
        .background(WindowVisibilityReader { visible in model.isWindowVisible = visible })
        .environment(\.animationsActive, model.isWindowVisible)
        .tint(Theme.violet)
        .frame(minWidth: 1080, minHeight: 700)
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(.dark)
        .onOpenURL { model.open(url: $0) }
    }

    @ViewBuilder private var screen: some View {
        switch model.tab {
        case .home: HomeView()
        case .explore: ExploreView()
        case .popular: PopularView()
        case .library: LibraryView()
        case .settings: SettingsView()
        }
    }
}

struct NavBar: View {
    @Environment(AppModel.self) private var model
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 16) {
            Color.clear.frame(width: 64, height: 1)
            Wordmark()
            Spacer(minLength: 12)
            GlassGroup(spacing: 4) {
                HStack(spacing: 2) {
                    ForEach(AppTab.allCases) { tab in tabButton(tab) }
                }
                .padding(4)
                .glassCapsule()
            }
            Spacer(minLength: 12)
            statusControls
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .frame(height: 68)
        .background(Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()))
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = model.tab == tab
        return Button {
            withAnimation(Theme.Motion.standard) { model.tab = tab }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.symbol).font(.system(size: 12, weight: .semibold))
                Text(tab.title).font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSelected ? Color.black : Theme.textSecondary)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background {
                if isSelected {
                    Capsule().fill(Color.white).matchedGeometryEffect(id: "tab", in: selection)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .keyboardShortcut(KeyEquivalent(Character(String(AppTab.allCases.firstIndex(of: tab)! + 1))), modifiers: .command)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var statusControls: some View {
        HStack(spacing: 8) {
            if let reason = model.pauseReasons.values.first(where: { $0 != .user }), !model.nowPlaying.isEmpty {
                Button { model.playAnyway() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pause.circle.fill").foregroundStyle(Theme.amber)
                        Text("Paused: \(reason.label)").font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("Play anyway").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Theme.teal)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .glassCapsule(tint: Theme.amber)
                }
                .buttonStyle(PressScaleStyle())
                .help("Auto-pause is on in Settings. Click to play anyway.")
            }
            if model.isRefreshing {
                ProgressView().controlSize(.small).help("Checking for a new drop")
            }
            if !model.nowPlaying.isEmpty {
                GlassButton(
                    title: nil,
                    systemImage: model.isUserPaused ? "play.fill" : "pause.fill",
                    help: model.isUserPaused ? "Resume wallpapers" : "Pause wallpapers"
                ) { model.togglePause() }
            }
        }
        .frame(minWidth: 120, alignment: .trailing)
    }
}

/// Shown while a file is dragged over the window.
struct DropTargetOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 14) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Theme.auroraGradient)
                Text("Drop to import as a wallpaper")
                    .font(Theme.Typeface.title(22))
                    .foregroundStyle(.white)
                Text("MP4, MOV or M4V. It stays on this Mac.")
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(40)
            .glass(cornerRadius: 28)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.auroraGradient, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                .padding(18)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

struct Wordmark: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AngularGradient(colors: Theme.aurora, center: .center))
                .frame(width: 14, height: 14)
                .shadow(color: Theme.violet.opacity(0.8), radius: 6)
            Text("Driftwall")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .tracking(-0.3)
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
    }
}

struct BannerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if let banner = model.banner {
                HStack(spacing: 10) {
                    Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "sparkles")
                        .foregroundStyle(banner.isError ? Theme.amber : Theme.teal)
                    Text(banner.message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassCapsule(tint: banner.isError ? Theme.amber : nil)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(banner.id)
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(Theme.Motion.standard, value: model.banner)
    }
}

/// "Use as wallpaper?" for a video that just finished downloading (Settings → Downloads).
struct DownloadOfferView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if let url = model.downloadOffer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use as wallpaper?").font(Theme.Typeface.title(15)).foregroundStyle(.white)
                            Text(url.lastPathComponent).font(Theme.Typeface.caption).foregroundStyle(Theme.textSecondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    HStack(spacing: 8) {
                        ChromaticButton(title: "Set Wallpaper", systemImage: "sparkles") { model.useOfferedDownload() }
                        GlassButton(title: "Import", systemImage: "square.and.arrow.down") { model.importOfferedDownload() }
                        GlassButton(title: nil, systemImage: "xmark", help: "Not now") { model.dismissDownloadOffer() }
                    }
                }
                .padding(16)
                .frame(width: 360, alignment: .leading)
                .glass(cornerRadius: Theme.Radius.panel)
                .padding(24)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("New download: \(url.lastPathComponent). Use as wallpaper?"))
            }
        }
        .animation(Theme.Motion.standard, value: model.downloadOffer)
    }
}

enum DropDate {
    static func short(_ isoDay: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: isoDay) else { return isoDay }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
