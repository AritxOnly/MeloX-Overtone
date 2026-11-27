import AVFoundation
import CoreImage

nonisolated enum MotionArtworkComposition {
    // Work in output pixels. Keep the original composition visible and feather its
    // two exposed edges into a low-resolution, aspect-filled copy of this frame.
    static func frame(_ source: CIImage, size: CGSize) -> CIImage {
        let bounds = CGRect(origin: .zero, size: size)
        let extent = source.extent
        let sx = size.width / extent.width
        let sy = size.height / extent.height
        func centered(scale: CGFloat, in canvas: CGSize) -> CIImage {
            source.transformed(by: CGAffineTransform(
                a: scale, b: 0, c: 0, d: scale,
                tx: canvas.width / 2 - extent.midX * scale,
                ty: canvas.height / 2 - extent.midY * scale
            ))
        }
        let sharp = centered(scale: min(sx, sy), in: size)
        guard abs(sx / sy - 1) > 0.002 else { return sharp.cropped(to: bounds) }
        let small = CGSize(width: size.width / 4, height: size.height / 4)
        let background = centered(scale: max(sx, sy) / 4, in: small)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: min(small.width, small.height) * 0.08)
            .transformed(by: CGAffineTransform(scaleX: 4, y: 4))
        // Extend the mask across the sides which already touch the viewport.
        let rect = sx < sy ? sharp.extent.insetBy(dx: -size.width, dy: 0)
                           : sharp.extent.insetBy(dx: 0, dy: -size.height)
        let mask = CIImage(color: .white).cropped(to: rect)
            .applyingGaussianBlur(sigma: min(size.width, size.height) * 0.018)
        return sharp.clampedToExtent().applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background, kCIInputMaskImageKey: mask
        ]).cropped(to: bounds)
    }

    static func video(asset: AVAsset, size: CGSize) async throws -> AVVideoComposition {
        // Keep the CI handler and its compositor together. Copying the filter
        // instructions into a new configuration breaks AVAssetExportSession.
        let composition = try await AVMutableVideoComposition.videoComposition(
            with: asset, applyingCIFiltersWithHandler: { request in
                request.finish(with: frame(request.sourceImage, size: size), context: nil)
            }
        )
        composition.renderSize = size
        return composition
    }
}
