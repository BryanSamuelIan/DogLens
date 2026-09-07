//
//  MacVideoPlayerView.swift
//  DogLensMac
//

import SwiftUI
import AVKit

struct MacVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer?
    var showsPlaybackControls: Bool = true

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = showsPlaybackControls ? .inline : .none
        playerView.showsFullScreenToggleButton = true
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
        nsView.controlsStyle = showsPlaybackControls ? .inline : .none
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }
}
