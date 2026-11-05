import AppKit
import Darwin

/// Puts windows into a private SkyLight space that is drawn on the lock screen.
///
/// SkyLight is a private macOS framework, so every symbol is looked up at runtime. If any is
/// missing (a future macOS may move them) `isAvailable` is false and windows simply stay
/// ordinary desktop windows. Only the lock-screen animation depends on this.
final class SkyLightOperator {
    static let shared = SkyLightOperator()

    /// kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock. Measured on macOS 27: at this level the
    /// space draws above the lock screen's clock and password field; at 300 and below it is hidden.
    /// No level shows it between the lock wallpaper and that UI.
    private static let aboveLockInterfaceLevel: Int32 = 400

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private let connection: Int32
    private let space: Int32
    private let addWindows: AddWindows?
    let isAvailable: Bool

    private init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_LAZY)
        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: type)
        }
        guard let mainConnection = load("SLSMainConnectionID", as: MainConnectionID.self),
              let create = load("SLSSpaceCreate", as: SpaceCreate.self),
              let setLevel = load("SLSSpaceSetAbsoluteLevel", as: SpaceSetAbsoluteLevel.self),
              let show = load("SLSShowSpaces", as: ShowSpaces.self),
              let add = load("SLSSpaceAddWindowsAndRemoveFromSpaces", as: AddWindows.self) else {
            connection = 0
            space = 0
            addWindows = nil
            isAvailable = false
            AppLog.info("SkyLight symbols unavailable, lock screen animation disabled")
            return
        }
        connection = mainConnection()
        space = create(connection, 1, 0)
        addWindows = add
        isAvailable = connection != 0 && space != 0
        if isAvailable {
            _ = setLevel(connection, space, Self.aboveLockInterfaceLevel)
            _ = show(connection, [space] as CFArray)
            AppLog.info("SkyLight space \(space) ready")
        }
    }

    /// Moves the window into the lock-screen space, removing it from its current one.
    func adopt(_ window: NSWindow) {
        guard isAvailable, let addWindows else { return }
        _ = addWindows(connection, space, [window.windowNumber] as CFArray, 7)
    }
}
