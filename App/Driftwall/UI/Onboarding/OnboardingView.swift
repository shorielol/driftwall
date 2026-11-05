import SwiftUI

/// Who made Driftwall. Edit this to change the welcome note.
enum AuthorInfo {
    static let name = "Shaurya"
    static let handle = "@shorielol"
    static let profileURL = URL(string: "https://github.com/shorielol")!
    static let repositoryURL = URL(string: "https://github.com/shorielol/driftwall")!
    static let note = """
    I made Driftwall because I wanted my Mac to feel a little more alive: calm motion behind my work, \
    without clutter or fuss. It's free, open source, and built with a lot of care.

    I hope it makes your desktop feel like yours. Enjoy it.
    """
}

/// First-launch welcome: a note from the author, then a short walkthrough.
struct OnboardingView: View {
    enum Page: Int, CaseIterable {
        case author, browse, apply, personalize, drops, ready
    }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Page = .author
    @State private var direction: Edge = .trailing
    @FocusState private var hasFocus: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            AuroraBackground(opacity: 0.9)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Wordmark()
                    Spacer()
                    if page != .ready {
                        Button("Skip") { finish() }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.textSecondary)
                            .keyboardShortcut(.cancelAction)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)

                ZStack {
                    pageContent
                        .id(page)
                        .transition(pageTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                footer
            }
            .frame(width: 880, height: 600)
            .glass(cornerRadius: 32)
            .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
        }
        .animation(reduceMotion ? Theme.Motion.fade : Theme.Motion.standard, value: page)
        .focusable()
        .focusEffectDisabled()
        .focused($hasFocus)
        .onAppear { hasFocus = true }
        .onChange(of: page) { hasFocus = true }
        .onKeyPress(.rightArrow) { advance(); return .handled }
        .onKeyPress(.return) {
            if page == .ready { finish() } else { advance() }
            return .handled
        }
        .onKeyPress(.escape) { finish(); return .handled }
        .onKeyPress(.leftArrow) { goBack(); return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to Driftwall")
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let opposite: Edge = direction == .trailing ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: direction).combined(with: .opacity),
            removal: .move(edge: opposite).combined(with: .opacity)
        )
    }

    @ViewBuilder private var pageContent: some View {
        switch page {
        case .author: AuthorPage()
        case .browse:
            WalkthroughPage(
                eyebrow: "STEP 1 · BROWSE",
                title: "Find something you love",
                message: "Home opens on the latest drop. Explore lets you search and filter by mood, from aurora and ocean to neon cities and cozy rain. Popular shows what tops the charts. Hover any card to see it move.",
                tiles: [("sparkles.tv", "Home"), ("magnifyingglass", "Explore"), ("flame", "Popular")]
            )
        case .apply:
            WalkthroughPage(
                eyebrow: "STEP 2 · SET IT",
                title: "One click, behind your icons",
                message: "Previews stream instantly. Set as Wallpaper downloads the 4K original and fades it in behind your desktop icons on every display. Use the chevron to pick a single screen.",
                tiles: [("play.fill", "Preview"), ("arrow.down.circle", "4K download"), ("display.2", "Every display")]
            )
        case .personalize:
            WalkthroughPage(
                eyebrow: "STEP 3 · MAKE IT YOURS",
                title: "Your desktop, your rules",
                message: "Like and save to My List. Build playlists that rotate on a timer. Pair a day and a night wallpaper, or one for light mode and one for dark. Import your own videos too.",
                tiles: [("heart.fill", "Like"), ("rectangle.stack", "Playlists"), ("sun.and.horizon", "Day & Night"), ("square.and.arrow.down", "Import")]
            )
        case .drops: DropsPage()
        case .ready: ReadyPage(finish: finish)
        }
    }

    private var footer: some View {
        HStack {
            Button("Back") { goBack() }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .opacity(page == .author ? 0 : 1)
                .disabled(page == .author)
            Spacer()
            HStack(spacing: 6) {
                ForEach(Page.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item == page ? Color.white : Color.white.opacity(0.3))
                        .frame(width: item == page ? 22 : 6, height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Page \(page.rawValue + 1) of \(Page.allCases.count)")
            Spacer()
            if page != .ready {
                ChromaticButton(title: page == .author ? "Show Me Around" : "Next", systemImage: "arrow.right") { advance() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Color.clear.frame(width: 120, height: 42)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
    }

    private func advance() {
        guard let next = Page(rawValue: page.rawValue + 1) else { return }
        direction = .trailing
        page = next
    }

    private func goBack() {
        guard let previous = Page(rawValue: page.rawValue - 1) else { return }
        direction = .leading
        page = previous
    }

    private func finish() {
        model.completeOnboarding()
    }
}

private struct AuthorPage: View {
    var body: some View {
        HStack(spacing: 48) {
            ZStack {
                LiquidGlassOrb(size: 220)
                Text(String(AuthorInfo.name.prefix(1)))
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.4), radius: 10)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 16) {
                Text("A NOTE FROM THE MAKER")
                    .font(Theme.Typeface.eyebrow).tracking(1.6).foregroundStyle(Theme.textSecondary)
                RefractedTitle(text: "Hi, I'm \(AuthorInfo.name).", size: 44)
                Text(AuthorInfo.note)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Text("— \(AuthorInfo.name)")
                        .font(.system(size: 18, weight: .semibold, design: .serif).italic())
                        .foregroundStyle(.white)
                    Link(AuthorInfo.handle, destination: AuthorInfo.profileURL)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: 420, alignment: .leading)
        }
        .padding(.horizontal, 48)
    }
}

private struct WalkthroughPage: View {
    let eyebrow: String
    let title: String
    let message: String
    let tiles: [(symbol: String, label: String)]

    var body: some View {
        VStack(spacing: 30) {
            HStack(spacing: 14) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                    VStack(spacing: 10) {
                        Image(systemName: tile.symbol)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Theme.aurora[index % 3])
                            .symbolEffect(.bounce, options: .nonRepeating)
                        Text(tile.label)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 130, height: 110)
                    .glass(cornerRadius: 20)
                }
            }
            .accessibilityHidden(true)
            VStack(spacing: 12) {
                Text(eyebrow).font(Theme.Typeface.eyebrow).tracking(1.6).foregroundStyle(Theme.textSecondary)
                Text(title)
                    .font(Theme.Typeface.display(36))
                    .displayTracking(36)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 600)
            }
        }
        .padding(.horizontal, 40)
    }
}

private struct DropsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 48) {
            VStack(spacing: 14) {
                LiquidGlassOrb(size: 150)
                if let days = model.catalog.daysUntilNextDrop(from: Date()) {
                    Text(days == 0 ? "Next drop today" : "Next drop in \(days) days")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("STEP 4 · STAY FRESH").font(Theme.Typeface.eyebrow).tracking(1.6).foregroundStyle(Theme.textSecondary)
                Text("New wallpapers every three weeks")
                    .font(Theme.Typeface.display(32)).displayTracking(32).foregroundStyle(.white)
                Text("Every drop brings a new set of live wallpapers, mostly 4K and never below 1080p. Driftwall pauses on its own when an app goes full screen, in Low Power Mode, or when your battery dips below 20%.")
                    .font(.system(size: 15)).lineSpacing(3).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Tell me when a new drop lands", isOn: model.binding(\.notifyNewDrops))
                    Toggle("Rotate through each new drop automatically", isOn: model.binding(\.rotateLatestDrop))
                    Toggle("Launch Driftwall at login", isOn: model.binding(\.launchAtLogin))
                }
                .toggleStyle(.switch)
                .padding(.top, 6)
            }
            .frame(maxWidth: 440, alignment: .leading)
        }
        .padding(.horizontal, 48)
    }
}

private struct ReadyPage: View {
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            LiquidGlassOrb(size: 130)
            RefractedTitle(text: "You're all set.", size: 46)
            Text("Pick a wallpaper you love and make your desktop drift.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
            ChromaticButton(title: "Pick My First Wallpaper", systemImage: "sparkles", action: finish)
                .keyboardShortcut(.defaultAction)
            Link("Star Driftwall on GitHub", destination: AuthorInfo.repositoryURL)
                .font(.system(size: 12, weight: .semibold))
        }
    }
}
