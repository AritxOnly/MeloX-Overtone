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
    let isActive: Bool
    let onReady: () -> Void

    func makeUIView(context: Context) -> Surface { Surface() }

    func updateUIView(_ view: Surface, context: Context) {
        view.configure(source: source, playing: isPlaying, active: isActive, onReady: onReady)
    }

    static func dismantleUIView(_ view: Surface, coordinator: ()) { view.stop() }

    final class Surface: MTKView {
        private static let artworkTopInset: CGFloat = 48
        private var source: MotionArtworkSource?
        private var playing = false
        private var active = false
        private var retriedDecoder = false
        private var load: Task<Void, Never>?
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private weak var attachedItem: AVPlayerItem?
        private var output: AVPlayerItemVideoOutput?
        private var frameTransform = CGAffineTransform.identity
        private var lastFrame: CIImage?
        private var renderedSize = CGSize.zero
        private var didShowFrame = false
        private var onReady: (() -> Void)?
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

        func configure(source: MotionArtworkSource, playing: Bool, active: Bool, onReady: @escaping () -> Void) {
            let changedSource = self.source !== source
            if changedSource { stop() }
            self.onReady = onReady
            self.source = source
            guard changedSource || self.active != active || self.playing != playing else { return }
            let resumed = active && !self.active
            if resumed {
                renderedSize = .zero // The system may have discarded the last drawable.
                retriedDecoder = false
            }
            self.active = active
            self.playing = playing
            if resumed && player == nil { preparePlayer(for: source) }
            updateRate()
        }

        private func preparePlayer(for source: MotionArtworkSource) {
            load?.cancel()
            load = Task { [weak self] in
                guard let file = try? await source.localFile() else { return }
                let asset = AVURLAsset(url: file)
                guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                      let orientation = try? await track.load(.preferredTransform),
                      (try? await asset.load(.duration)) != nil,
                      !Task.isCancelled, let self, self.source === source else { return }
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
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.width > 0, bounds.height > 0 else { return }
            let scale = min(traitCollection.displayScale, 1080 / max(bounds.width, bounds.height))
            let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
            if size != drawableSize {
                drawableSize = size
                if active && player != nil { isPaused = false }
            }
        }

        override func draw(_ rect: CGRect) {
            guard active, let player else { return }
            if player.status == .failed || looper?.status == .failed || player.currentItem?.status == .failed {
                isPaused = true
                if !retriedDecoder, let source {
                    retriedDecoder = true
                    releasePlayer()
                    preparePlayer(for: source)
                }
            } else if let item = player.currentItem, let frame = nextFrame(from: item) {
                lastFrame = frame
                retriedDecoder = false
            } else if renderedSize == drawableSize { return }
            renderLastFrame()
        }

        private func nextFrame(from item: AVPlayerItem) -> CIImage? {
            if attachedItem !== item {
                if let output { attachedItem?.remove(output) }
                let next = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ])
                item.add(next)
                attachedItem = item
                output = next
            }
            guard let output else { return nil }
            let time = output.itemTime(forHostTime: CACurrentMediaTime())
            if output.hasNewPixelBuffer(forItemTime: time),
               let frame = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                return CIImage(cvPixelBuffer: frame).transformed(by: frameTransform)
            }
            return nil
        }

        private func renderLastFrame() {
            guard let lastFrame, let renderer, let buffer = commands?.makeCommandBuffer(),
                  let drawable = currentDrawable else { return }
            let size = drawableSize
            guard bounds.height > Self.artworkTopInset else { return }
            // The surface extends under the status bar. Convert the point
            // inset to drawable pixels independently of screen scale or resolution.
            let topInset = Self.artworkTopInset * size.height / bounds.height
            let image = MotionArtworkComposition.frame(lastFrame, size: size, topInset: topInset)
            renderer.render(image, to: drawable.texture, commandBuffer: buffer,
                            bounds: CGRect(origin: .zero, size: size), colorSpace: colorSpace)
            buffer.present(drawable)
            buffer.commit()
            renderedSize = size
            if !didShowFrame {
                didShowFrame = true
                onReady?()
            }
            if !playing { isPaused = true }
        }

        private func updateRate() {
            guard let player else {
                isPaused = true
                return
            }
            if active && playing { player.play() } else { player.pause() }
            isPaused = !active || (!playing && didShowFrame && renderedSize == drawableSize)
        }

        private func releasePlayer() {
            if let output { attachedItem?.remove(output) }
            attachedItem = nil
            output = nil
            player?.pause()
            looper?.disableLooping()
            looper = nil
            player = nil
        }

        func stop() {
            load?.cancel()
            isPaused = true
            releasePlayer()
            source = nil
            onReady = nil
            active = false
            retriedDecoder = false
            lastFrame = nil
            didShowFrame = false
            renderedSize = .zero
        }
    }
}
