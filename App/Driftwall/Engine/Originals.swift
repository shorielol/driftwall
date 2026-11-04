import AppKit
import AVFoundation
import DriftwallCore
import SwiftUI

/// Driftwall Originals: live scenes rendered by Metal at the display's native resolution.
/// All original procedural artwork; no third-party characters or footage.
enum OriginalScene: String, CaseIterable, Identifiable {
    case inkMist, paperValley, roseWindow, risoTide, impasto, bauhaus, chromeBloom, amberTerminal

    static let source = "original"
    static let category = "Originals"
    static let idPrefix = "original-"

    var id: String { Self.idPrefix + rawValue }

    var title: String {
        switch self {
        case .inkMist: "Ink & Mist"
        case .paperValley: "Paper Valley"
        case .roseWindow: "Rose Window"
        case .risoTide: "Riso Tide"
        case .impasto: "Impasto Night"
        case .bauhaus: "Bauhaus Shift"
        case .chromeBloom: "Chrome Bloom"
        case .amberTerminal: "Amber Terminal"
        }
    }

    /// The artistic medium each scene is drawn in.
    var medium: String {
        switch self {
        case .inkMist: "Sumi-e ink wash"
        case .paperValley: "Papercraft diorama"
        case .roseWindow: "Stained glass"
        case .risoTide: "Two-ink risograph"
        case .impasto: "Impasto oil paint"
        case .bauhaus: "Bauhaus geometry"
        case .chromeBloom: "Iridescent liquid"
        case .amberTerminal: "1-bit dithering"
        }
    }

    var blurb: String {
        switch self {
        case .inkMist: "Ink bleeds into rice paper as mountain ridges fade into drifting mist and cranes cross a pale sun."
        case .paperValley: "Six layers of cut paper cast real shadows across a pastel valley while paper clouds drift by."
        case .roseWindow: "A turning rose window of jewel-coloured glass, with light sweeping slowly across the lead."
        case .risoTide: "Waves printed in fluorescent pink and blue halftone, slightly out of register like a real riso print."
        case .impasto: "Thick, swirling brush strokes circle glowing orbs above dark sea cliffs."
        case .bauhaus: "Primary-coloured tiles rotate and swap their shapes on a steady three-second beat."
        case .chromeBloom: "Oil-on-water colours ripple through liquid chrome with glossy highlights."
        case .amberTerminal: "A sunset over the sea, dithered into four shades of amber on a flickering CRT."
        }
    }

    var tags: [String] {
        switch self {
        case .inkMist: ["ink", "japanese", "mountains", "minimal", "anime"]
        case .paperValley: ["paper", "pastel", "valley", "craft"]
        case .roseWindow: ["glass", "cathedral", "jewel", "pattern"]
        case .risoTide: ["print", "waves", "halftone", "retro"]
        case .impasto: ["painting", "oil", "night", "swirl"]
        case .bauhaus: ["geometric", "modernist", "pattern", "bold"]
        case .chromeBloom: ["abstract", "iridescent", "liquid", "chrome"]
        case .amberTerminal: ["pixel", "retro", "dither", "gaming", "sunset"]
        }
    }

    /// Picks a pleasing still for posters (seconds into the scene).
    var posterTime: Float {
        switch self {
        case .bauhaus: 1.4
        case .chromeBloom: 20
        default: 8
        }
    }

    var shaderName: String { "original" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    func shader(size: CGSize, time: Float) -> Shader {
        Shader(function: ShaderFunction(library: .default, name: shaderName), arguments: [.float2(size), .float(time)])
    }

    init?(wallpaperID: String) {
        guard wallpaperID.hasPrefix(Self.idPrefix) else { return nil }
        self.init(rawValue: String(wallpaperID.dropFirst(Self.idPrefix.count)))
    }

    /// Catalog-shaped entry so Originals work everywhere wallpapers do (rows, playlists, rules).
    var wallpaper: Wallpaper {
        let placeholder = URL(string: "https://driftwall.app/originals/\(rawValue)")!
        return Wallpaper(
            id: id, title: title, description: blurb, category: Self.category, tags: tags,
            source: Self.source, sourcePageURL: placeholder, previewURL: placeholder, videoURL: placeholder,
            posterURL: placeholder, author: "Driftwall", license: "Driftwall Original",
            durationSeconds: 0, width: 7680, height: 4320, addedInDrop: ""
        )
    }
}

extension Wallpaper {
    var isOriginal: Bool { source == OriginalScene.source }
    var originalScene: OriginalScene? { OriginalScene(wallpaperID: id) }
}

/// Live (or frozen) rendering of an Original scene.
struct OriginalSceneView: View {
    let scene: OriginalScene
    var isPlaying = true
    var rate: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying || reduceMotion)) { timeline in
            let elapsed = isPlaying && !reduceMotion ? Float(timeline.date.timeIntervalSince(start) * rate) : 0
            GeometryReader { proxy in
                Rectangle()
                    .fill(Color.black)
                    .colorEffect(scene.shader(size: proxy.size, time: scene.posterTime + elapsed))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Poster for any wallpaper: a frozen frame for Originals, the downloaded image otherwise.
struct WallpaperPoster: View {
    let wallpaper: Wallpaper

    var body: some View {
        if let scene = wallpaper.originalScene {
            OriginalSceneView(scene: scene, isPlaying: false)
        } else {
            PosterImage(url: wallpaper.posterURL)
        }
    }
}

/// Moving preview for any wallpaper: the live scene for Originals, streamed or local video otherwise.
struct WallpaperMotion: View {
    let wallpaper: Wallpaper
    var url: URL?
    var isPlaying = true

    var body: some View {
        if let scene = wallpaper.originalScene {
            OriginalSceneView(scene: scene, isPlaying: isPlaying)
        } else {
            VideoSurface(url: url ?? wallpaper.previewURL, isPlaying: isPlaying)
        }
    }
}

/// Desktop surface that renders an Original scene behind the icons.
@Observable
final class SceneSurfaceState {
    var isPlaying = true
    var rate: Double = 1
}

final class SceneSurfaceView: NSView, WallpaperSurface {
    private let state = SceneSurfaceState()
    private let host: NSHostingView<SceneSurfaceRoot>
    let scene: OriginalScene
    var wallpaperID: String?

    init(scene: OriginalScene, frame: NSRect, rate: Float, paused: Bool) {
        self.scene = scene
        state.rate = Double(rate)
        state.isPlaying = !paused
        host = NSHostingView(rootView: SceneSurfaceRoot(scene: scene, state: state))
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var surfaceKey: String { "scene:\(scene.rawValue)" }
    var isReadyForDisplay: Bool { true }
    var hasFailed: Bool { false }
    func setPaused(_ paused: Bool) { state.isPlaying = !paused }
    func setRate(_ rate: Float) { state.rate = Double(rate) }
    func setGravity(_ gravity: AVLayerVideoGravity) {}
    func tearDown() { state.isPlaying = false }
}

struct SceneSurfaceRoot: View {
    let scene: OriginalScene
    let state: SceneSurfaceState

    var body: some View {
        OriginalSceneView(scene: scene, isPlaying: state.isPlaying, rate: state.rate)
            .ignoresSafeArea()
    }
}
