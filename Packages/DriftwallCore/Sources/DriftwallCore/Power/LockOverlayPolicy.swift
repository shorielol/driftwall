import Foundation

/// When the animated wallpaper may cover the lock screen.
///
/// The video has to sit above the lock screen's own clock and password field (macOS offers no layer
/// between its wallpaper and that UI), so it only shows while nobody is interacting and steps aside
/// the moment there is input.
public enum LockOverlayPolicy {
    /// Seconds without input before the video fades in.
    public static let showAfter: TimeInterval = 6
    /// Input this recent hides the video again.
    public static let hideWithin: TimeInterval = 1

    public static func shouldShow(isShowing: Bool, idleSeconds: TimeInterval) -> Bool {
        isShowing ? idleSeconds >= hideWithin : idleSeconds >= showAfter
    }
}
