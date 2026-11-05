import AppKit
import AVFoundation
import DriftwallCore

extension NSScreen {
    var displayID: DisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var displayKey: DisplayKey {
        DisplayKey(name: localizedName, width: Int(frame.width), height: Int(frame.height))
    }
}

/// Borderless, click-through window that sits at desktop level: behind Finder icons, on every Space.
final class DesktopWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        // One above the system wallpaper level: still under Finder's desktop icons, but over other
        // wallpaper apps that draw at exactly the desktop level.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hasShadow = false
        isOpaque = true
        backgroundColor = .black
        isReleasedWhenClosed = false
        animationBehavior = .none
        alphaValue = 0
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Anything the engine can put on the desktop: a looping video or a live Original scene.
protocol WallpaperSurface: NSView {
    var surfaceKey: String { get }
    var wallpaperID: String? { get set }
    var isReadyForDisplay: Bool { get }
    var hasFailed: Bool { get }
    func setPaused(_ paused: Bool)
    func setRate(_ rate: Float)
    func setGravity(_ gravity: AVLayerVideoGravity)
    func tearDown()
}

enum SurfaceContent {
    case video(URL)
    case scene(OriginalScene)
}

/// Seamless, muted, hardware-decoded loop of one local video.
final class LoopingPlayerView: NSView, WallpaperSurface {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private(set) var url: URL?
    var wallpaperID: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.frame = bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(playerLayer)
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func load(url: URL, rate: Float, gravity: AVLayerVideoGravity, paused: Bool) {
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.preventsDisplaySleepDuringVideoPlayback = false
        queue.allowsExternalPlayback = false
        queue.defaultRate = rate
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        self.url = url
        playerLayer.videoGravity = gravity
        playerLayer.player = queue
        // Always start playing so the first frame renders; the engine pauses once it's on screen.
        queue.play()
    }

    var surfaceKey: String { url?.absoluteString ?? "" }
    var isReadyForDisplay: Bool { playerLayer.isReadyForDisplay }
    var hasFailed: Bool { looper?.status == .failed }

    func setPaused(_ paused: Bool) {
        guard let player else { return }
        if paused {
            player.pause()
        } else if player.rate == 0 {
            player.play()
        }
    }

    func setRate(_ rate: Float) {
        guard let player else { return }
        player.defaultRate = rate
        if player.rate != 0 { player.rate = rate }
    }

    func setGravity(_ gravity: AVLayerVideoGravity) {
        playerLayer.videoGravity = gravity
    }

    func tearDown() {
        player?.pause()
        looper?.disableLooping()
        playerLayer.player = nil
        looper = nil
        player = nil
    }
}

/// Owns one desktop window per display and swaps videos with a cross-fade.
final class WallpaperEngine {
    private struct Slot {
        let window: DesktopWindow
        var view: any WallpaperSurface
        var wallpaperID: String
        var isPaused: Bool
    }

    private static let fadeDuration: TimeInterval = 0.7
    private static let readyTimeout: Duration = .seconds(6)

    private var slots: [DisplayID: Slot] = [:]
    private var rate: Float = 1
    private var gravity: AVLayerVideoGravity = .resizeAspectFill

    /// Called when a video can't be shown (corrupt or unreadable file). The previous picture stays.
    var onPlaybackFailure: ((DisplayID, String) -> Void)?

    /// Called whenever what a display is playing changes (shown, replaced, reverted or removed).
    var onSlotChange: (() -> Void)?

    var activeDisplayIDs: Set<DisplayID> { Set(slots.keys) }

    func wallpaperID(on display: DisplayID) -> String? { slots[display]?.wallpaperID }

    /// The local video playing on `display`, or nil for Original scenes (they have no file to loop).
    func videoURL(on display: DisplayID) -> URL? { (slots[display]?.view as? LoopingPlayerView)?.url }

    var currentRate: Float { rate }
    var currentGravity: AVLayerVideoGravity { gravity }

    func show(url: URL, wallpaperID: String, on screen: NSScreen, paused: Bool) {
        show(.video(url), wallpaperID: wallpaperID, on: screen, paused: paused)
    }

    func show(_ content: SurfaceContent, wallpaperID: String, on screen: NSScreen, paused: Bool) {
        let display = screen.displayID
        if var slot = slots[display] {
            slot.window.setFrame(screen.frame, display: true)
            guard slot.view.surfaceKey != Self.key(for: content) else { return }
            let incoming = makeSurface(content, in: slot.window, paused: paused)
            incoming.wallpaperID = wallpaperID
            let outgoing = slot.view
            slot.view = incoming
            slot.wallpaperID = wallpaperID
            slot.isPaused = paused
            slots[display] = slot
            crossFade(from: outgoing, to: incoming, display: display, wallpaperID: wallpaperID)
        } else {
            let window = DesktopWindow(screen: screen)
            let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor.black.cgColor
            window.contentView = container
            let view = makeSurface(content, in: window, paused: paused)
            view.wallpaperID = wallpaperID
            slots[display] = Slot(window: window, view: view, wallpaperID: wallpaperID, isPaused: paused)
            window.orderFrontRegardless()
            fadeInWindow(window, when: view, display: display, wallpaperID: wallpaperID)
        }
        AppLog.info("Showing \(wallpaperID) on display \(display)")
        onSlotChange?()
    }

    private static func key(for content: SurfaceContent) -> String {
        switch content {
        case .video(let url): url.absoluteString
        case .scene(let scene): "scene:\(scene.rawValue)"
        }
    }

    private func makeSurface(_ content: SurfaceContent, in window: NSWindow, paused: Bool) -> any WallpaperSurface {
        let frame = window.contentView?.bounds ?? window.frame
        let surface: any WallpaperSurface
        switch content {
        case .video(let url):
            let view = LoopingPlayerView(frame: frame)
            view.load(url: url, rate: rate, gravity: gravity, paused: paused)
            surface = view
        case .scene(let scene):
            surface = SceneSurfaceView(scene: scene, frame: frame, rate: rate, paused: paused)
        }
        window.contentView?.addSubview(surface)
        return surface
    }

    private func waitUntilReady(_ view: any WallpaperSurface) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.readyTimeout)
        while !view.isReadyForDisplay, !view.hasFailed, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func fadeInWindow(_ window: NSWindow, when view: any WallpaperSurface, display: DisplayID, wallpaperID: String) {
        Task {
            await waitUntilReady(view)
            guard view.isReadyForDisplay else {
                remove(display: display)
                onPlaybackFailure?(display, wallpaperID)
                return
            }
            applyPendingPause(display: display, view: view)
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration
                window.animator().alphaValue = 1
            }
        }
    }

    private func crossFade(from outgoing: any WallpaperSurface, to incoming: any WallpaperSurface, display: DisplayID, wallpaperID: String) {
        incoming.alphaValue = 0
        Task {
            await waitUntilReady(incoming)
            guard incoming.isReadyForDisplay else {
                incoming.tearDown()
                incoming.removeFromSuperview()
                if var slot = slots[display], slot.view === incoming {
                    slot.view = outgoing
                    slot.wallpaperID = outgoing.wallpaperID ?? slot.wallpaperID
                    slots[display] = slot
                    onSlotChange?()
                }
                onPlaybackFailure?(display, wallpaperID)
                return
            }
            applyPendingPause(display: display, view: incoming)
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration
                incoming.animator().alphaValue = 1
            }
            outgoing.tearDown()
            outgoing.removeFromSuperview()
        }
    }

    private func applyPendingPause(display: DisplayID, view: any WallpaperSurface) {
        if let slot = slots[display], slot.view === view, slot.isPaused { view.setPaused(true) }
    }

    /// Re-assert our windows above any other wallpaper app that re-ordered itself.
    func bringToFront() {
        slots.values.forEach { $0.window.orderFrontRegardless() }
    }

    func setPaused(_ paused: Bool, on display: DisplayID) {
        guard var slot = slots[display], slot.isPaused != paused else { return }
        slot.view.setPaused(paused)
        slot.isPaused = paused
        slots[display] = slot
    }

    func isPaused(_ display: DisplayID) -> Bool { slots[display]?.isPaused ?? true }

    func setRate(_ newRate: Double) {
        rate = Float(newRate)
        slots.values.forEach { $0.view.setRate(rate) }
    }

    func setScaling(_ scaling: VideoScaling) {
        gravity = scaling == .fill ? .resizeAspectFill : .resizeAspect
        slots.values.forEach { $0.view.setGravity(gravity) }
    }

    func reframe(screens: [NSScreen]) {
        let byID = Dictionary(screens.map { ($0.displayID, $0) }, uniquingKeysWith: { first, _ in first })
        for (display, slot) in slots {
            if let screen = byID[display] {
                slot.window.setFrame(screen.frame, display: true)
            } else {
                remove(display: display)
            }
        }
    }

    func remove(display: DisplayID) {
        guard let slot = slots.removeValue(forKey: display) else { return }
        slot.view.tearDown()
        slot.window.orderOut(nil)
        slot.window.close()
        onSlotChange?()
    }

    func removeAll() {
        slots.keys.forEach(remove(display:))
    }
}
