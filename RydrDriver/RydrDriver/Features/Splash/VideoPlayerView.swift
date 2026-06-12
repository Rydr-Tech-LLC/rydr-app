//
//  VideoPlayerView.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 6/14/25.
//
import SwiftUI
import AVFoundation

struct VideoPlayerView: UIViewRepresentable {
    let videoName: String
    var onFinish: () -> Void

    func makeUIView(context: Context) -> UIView {
        return PlayerUIView(videoName: videoName, onFinish: onFinish)
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

class PlayerUIView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?

    init(videoName: String, onFinish: @escaping () -> Void) {
        super.init(frame: .zero)

        guard let path = Bundle.main.path(forResource: videoName, ofType: "mp4") else {
            print("Video file not found")
            return
        }

        let url = URL(fileURLWithPath: path)
        player = AVPlayer(url: url)
        playerLayer = AVPlayerLayer(player: player)

        // 🔧 FIX: Change from .resizeAspectFill to .resizeAspect to avoid cropping/distortion
        playerLayer?.videoGravity = .resizeAspect

        if let layer = playerLayer {
            self.layer.addSublayer(layer)
        }

        // 🔔 Detect video completion
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            onFinish()
        }

        player?.play()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}



