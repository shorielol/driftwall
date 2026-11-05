import AppKit
import AVFoundation
import CoreGraphics
import DriftwallCore

/// Borderless window that is moved into the SkyLight lock-screen space and plays one looping video.
/// It starts hidden and paused; the manager shows it while the Mac sits idle on the lock screen.
final class LockWindow: NSWindow {
    private static let readyTimeout: Duration = .seconds(3)
    private static let showDuration: TimeInterval = 0.8
    private static let hideDuration: TimeInterval = 0.25

    let player = LoopingPlayerView(frame: .zero)
    private var transition: Task<Void, Never>?

    init(screen: NSScreen, url: URL, rate: Float, gravity: AVLayerVideoGravity) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        canBecomeVisibleWithoutLogin = true
        ignoresMouseEvents = true
        hasShadow = false
        isOpaque = true
        backgroundColor = .black
        isReleasedWhenClosed = false
        animationBehavior = .none
        alphaValue = 0
        setFrame(screen.frame, display: false)
        player.frame = NSRect(origin: .zero, size: screen.frame.size)
        contentView = player
        player.load(url: url, rate: rate, gravity: gravity, paused: true)
        player.setPaused(true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Fade the video in (once its first frame is ready) or out, playing only while it is visible.
    func setShown(_ shown: Bool) {
        transition?.cancel()
        transition = Task {
            if shown {
                player.setPaused(false)
                let deadline = ContinuousClock.now + Self.readyTimeout
                while !player.isReadyForDisplay, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard !Task.isCancelled, player.isReadyForDisplay, isVisible else { return }
            }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = shown ? Self.showDuration : Self.hideDuration
                animator().alphaValue = shown ? 1 : 0
            }
            if !shown, !Task.isCancelled { player.setPaused(true) }
        }
    }

    func dismiss() {
        transition?.cancel()
        player.tearDown()
        orderOut(nil)
        close()
    }
}

/// Plays the live wallpaper on the lock screen. Experimental: it relies on private macOS API
/// and quietly does nothing if that API is missing.
///
/// macOS has no layer between its lock wallpaper and the clock/password UI, so the video sits above
/// everything. It fades in after a few idle seconds and hides on any input (see `LockOverlayPolicy`).
final class LockScreenWallpaper {
    struct Item {
        let screen: NSScreen
        let url: URL
    }

    private static let idleCheckInterval: Duration = .milliseconds(250)
    private static let anyInputEvent = CGEventType(rawValue: ~0)!

    private var windows: [DisplayID: (window: LockWindow, url: URL)] = [:]
    private var idleTask: Task<Void, Never>?
    private var isOverlayShown = false

    var isAvailable: Bool { SkyLightOperator.shared.isAvailable }

    /// Make the lock-screen windows match `items`: create, replace or remove per display.
    func sync(_ items: [DisplayID: Item], rate: Float, gravity: AVLayerVideoGravity) {
        guard !items.isEmpty else { return removeAll() }
        guard isAvailable else { return }
        for display in windows.keys where items[display] == nil {
            remove(display: display)
        }
        for (display, item) in items {
            if let existing = windows[display] {
                if existing.url == item.url {
                    if existing.window.frame != item.screen.frame {
                        existing.window.setFrame(item.screen.frame, display: true)
                    }
                    continue
                }
                remove(display: display)
            }
            show(item, on: display, rate: rate, gravity: gravity)
        }
        startWatchingIdle()
    }

    func setRate(_ rate: Float) {
        windows.values.forEach { $0.window.player.setRate(rate) }
    }

    func setGravity(_ gravity: AVLayerVideoGravity) {
        windows.values.forEach { $0.window.player.setGravity(gravity) }
    }

    func removeAll() {
        windows.keys.forEach(remove(display:))
        idleTask?.cancel()
        idleTask = nil
        isOverlayShown = false
    }

    private func show(_ item: Item, on display: DisplayID, rate: Float, gravity: AVLayerVideoGravity) {
        let skyLight = SkyLightOperator.shared
        let window = LockWindow(screen: item.screen, url: item.url, rate: rate, gravity: gravity)
        window.orderFrontRegardless()
        skyLight.adopt(window)
        if isOverlayShown { window.setShown(true) }
        windows[display] = (window, item.url)
        AppLog.info("Lock screen wallpaper on display \(display)")
    }

    private func remove(display: DisplayID) {
        windows.removeValue(forKey: display)?.window.dismiss()
    }

    // MARK: Idle

    private func startWatchingIdle() {
        guard idleTask == nil else { return }
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkIdle()
                try? await Task.sleep(for: Self.idleCheckInterval)
            }
        }
    }

    private func checkIdle() {
        let idle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: Self.anyInputEvent)
        let wanted = LockOverlayPolicy.shouldShow(isShowing: isOverlayShown, idleSeconds: idle)
        guard wanted != isOverlayShown else { return }
        isOverlayShown = wanted
        windows.values.forEach { $0.window.setShown(wanted) }
    }
}
