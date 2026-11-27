import AVFoundation
import CoreImage
import MetalKit
import SwiftUI

extension EnvironmentValues {
    @Entry var showsFullScreenMotionArtwork = false
}

/// Pull each decoded frame once and composite both the sharp and blurred regions.
struct NowPlayingMotionArtwork: UIViewRepresentable {
    let source: MotionArtworkSource
    let isPlaying: Bool
    let onReady: (Bool) -> Void

    func makeUIView(context: Context) -> Surface { Surface() }

    func updateUIView(_ view: Surface, context: Context) {
        view.configure(source: source, playing: isPlaying, onReady: onReady)
    }

    static func dismantleUIView(_ view: Surface, coordinator: ()) { view.stop() }

    final class Surface: MTKView {
        private var source: MotionArtworkSource?
        private var playing = false
        private var load: Task<Void, Never>?
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private weak var attachedItem: AVPlayerItem?
        private var output: AVPlayerItemVideoOutput?
        private var frameTransform = CGAffineTransform.identity
        private var lastFrame: CIImage?
        private var renderedSize = CGSize.zero
        private var didShowFrame = false
        private var onReady: ((Bool) -> Void)?
        private let commands: MTLCommandQueue?
        private let renderer: CIContext?
        private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

        init() {
            let gpu = MTLCreateSystemDefaultDevice()
            commands = gpu?.makeCommandQueue()
            renderer = commands.map { CIContext(mtlCommandQueue: $0, options: [.cacheIntermediates: false]) }
            super.init(frame: .zero, device: gpu)
            framebufferOnly = false
            autoResizeDrawable = false
            preferredFramesPerSecond = 30
            isPaused = true
            isUserInteractionEnabled = false
        }

        required init(coder: NSCoder) { fatalError("Use init()") }

        func configure(source: MotionArtworkSource, playing: Bool, onReady: @escaping (Bool) -> Void) {
            self.onReady = onReady
            if self.source !== source {
                stop()
                self.source = source
                load = Task { [weak self] in
                    do {
                        let asset = AVURLAsset(url: try await source.localFile())
                        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return }
                        let orientation = try await track.load(.preferredTransform)
                        _ = try await asset.load(.duration)
                        try Task.checkCancellation()
                        guard let self else { return }
                        // Convert the track's top-left coordinates to Core Image's bottom-left space.
                        frameTransform = CGAffineTransform(a: orientation.a, b: -orientation.b,
                                                      c: -orientation.c, d: orientation.d, tx: 0, ty: 0)
                        let queue = AVQueuePlayer()
                        queue.isMuted = true
                        queue.preventsDisplaySleepDuringVideoPlayback = false
                        queue.allowsExternalPlayback = false
                        queue.audiovisualBackgroundPlaybackPolicy = .pauses
                        player = queue
                        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(asset: asset))
                        updateRate()
                    } catch {
                        if !Task.isCancelled { self?.onReady?(false) }
                    }
                }
            }
            if self.playing != playing {
                self.playing = playing
                updateRate()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.width > 0, bounds.height > 0 else { return }
            let scale = min(traitCollection.displayScale, 1080 / max(bounds.width, bounds.height))
            let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
            if size != drawableSize {
                drawableSize = size
                if player != nil { isPaused = false }
            }
        }

        override func draw(_ rect: CGRect) {
            guard let player else { return }
            if looper?.status == .failed || player.currentItem?.status == .failed {
                isPaused = true
                onReady?(false)
                return
            }
            guard let item = player.currentItem else { return }
            if attachedItem !== item {
                if let output { attachedItem?.remove(output) }
                let next = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ])
                item.add(next)
                attachedItem = item
                output = next
            }
            guard let output else { return }
            let time = output.itemTime(forHostTime: CACurrentMediaTime())
            if output.hasNewPixelBuffer(forItemTime: time),
               let frame = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                lastFrame = CIImage(cvPixelBuffer: frame).transformed(by: frameTransform)
            } else if renderedSize == drawableSize { return }
            guard let lastFrame, let renderer, let buffer = commands?.makeCommandBuffer(),
                  let drawable = currentDrawable else { return }
            let size = drawableSize
            guard bounds.height > 15 else { return }
            // The surface extends under the status bar. Convert the 15-point
            // inset to drawable pixels independently of screen scale or resolution.
            let topInset = 15 * size.height / bounds.height
            let image = MotionArtworkComposition.frame(lastFrame, size: size, topInset: topInset)
            renderer.render(image, to: drawable.texture, commandBuffer: buffer,
                            bounds: CGRect(origin: .zero, size: size), colorSpace: colorSpace)
            buffer.present(drawable)
            buffer.commit()
            renderedSize = size
            if !didShowFrame {
                didShowFrame = true
                onReady?(true)
            }
            isPaused = !playing
        }

        private func updateRate() {
            guard let player else {
                isPaused = true
                return
            }
            if playing { player.play() } else { player.pause() }
            isPaused = !playing && didShowFrame
        }

        func stop() {
            load?.cancel()
            isPaused = true
            if let output { attachedItem?.remove(output) }
            attachedItem = nil
            output = nil
            player?.pause()
            looper?.disableLooping()
            looper = nil
            player = nil
            source = nil
            lastFrame = nil
            didShowFrame = false
            renderedSize = .zero
        }
    }
}
