import AVFoundation
import SwiftUI

/// Muted looping video for previews. Streams remote URLs (no disk write) or plays local files.
/// Transparent until the first frame, so a poster underneath shows through while it buffers.
struct VideoSurface: NSViewRepresentable {
    let url: URL
    var isPlaying = true
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    func makeNSView(context: Context) -> LoopingPlayerView {
        let view = LoopingPlayerView(frame: .zero)
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.load(url: url, rate: 1, gravity: gravity, paused: !isPlaying)
        return view
    }

    func updateNSView(_ view: LoopingPlayerView, context: Context) {
        if view.url != url {
            view.tearDown()
            view.load(url: url, rate: 1, gravity: gravity, paused: !isPlaying)
        } else {
            view.setPaused(!isPlaying)
            view.setGravity(gravity)
        }
    }

    static func dismantleNSView(_ view: LoopingPlayerView, coordinator: ()) {
        view.tearDown()
    }
}
