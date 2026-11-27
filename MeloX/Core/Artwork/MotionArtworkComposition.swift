import AVFoundation
import CoreImage

nonisolated enum MotionArtworkComposition {
    static func frame(_ source: CIImage, size: CGSize, topInset: CGFloat = 0, forLockScreen: Bool = false) -> CIImage {
        let bounds = CGRect(origin: .zero, size: size)
        let extent = source.extent
        let sx = size.width / extent.width
        let top = bounds.maxY - topInset
        let sy = top / extent.height
        // A square master can fill the system's 3:4 canvas by trimming one
        // eighth from either side. Wider masters keep their subject and use the fade.
        let fillTallVariant = forLockScreen && size.height > size.width && sy >= sx && sx / sy >= 0.75
        let scale = fillTallVariant ? sy : min(sx, sy)
        // Core Image's origin is at the bottom. Align the artwork's top edge even
        // when the track transform has moved the source outside the first quadrant.
        let sharp = source.transformed(by: CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: bounds.midX - extent.midX * scale,
            ty: top - extent.maxY * scale
        ))
        let art = sharp.extent
        let spaceBelow = max(0, art.minY)
        let spaceBeside = max(0, art.minX)
        guard max(topInset, spaceBelow, spaceBeside) > 1 else { return sharp.cropped(to: bounds) }

        // Extend edge pixels before blurring. Both layers then sample the same
        // part of the frame throughout the transition, including across its edge.
        let extended = sharp.clampedToExtent()
        let backdrop: CIImage
        if spaceBelow > 1 {
            // Reflect the frame at its lower edge so the continuation has depth
            // even on tall phones. Blurring a clamped last row alone leaves stripes.
            let stretch = max(1, spaceBelow / art.height)
            let reflection = sharp.transformed(by: CGAffineTransform(
                a: 1, b: 0, c: 0, d: -stretch, tx: 0, ty: art.minY * (1 + stretch)
            ))
            backdrop = sharp.composited(over: reflection).clampedToExtent()
        } else {
            backdrop = extended
        }
        let reduced = backdrop.transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
        let soft = reduced
            .applyingGaussianBlur(sigma: min(art.width, art.height) * 0.035)
            .transformed(by: CGAffineTransform(scaleX: 4, y: 4))

        func blendMask(from start: CGPoint, to end: CGPoint) -> CIImage {
            CIFilter(name: "CISmoothLinearGradient", parameters: [
                "inputPoint0": CIVector(cgPoint: start), "inputColor0": CIColor.black,
                "inputPoint1": CIVector(cgPoint: end), "inputColor1": CIColor.white
            ])!.outputImage!
        }

        var mask: CIImage
        if spaceBelow > 1 {
            // Match the album header: the lower half of the art dissolves into
            // its own colors; the top remains sharp at the artwork origin.
            let fade = min(art.height * 0.5, spaceBelow * 1.5)
            mask = blendMask(from: CGPoint(x: 0, y: art.minY),
                             to: CGPoint(x: 0, y: art.minY + fade))
        } else if spaceBeside > 1 {
            let fade = min(art.width * 0.25, spaceBeside)
            let left = blendMask(from: CGPoint(x: art.minX, y: 0),
                                 to: CGPoint(x: art.minX + fade, y: 0))
            let right = blendMask(from: CGPoint(x: art.maxX, y: 0),
                                  to: CGPoint(x: art.maxX - fade, y: 0))
            mask = left.applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: right])
        } else {
            mask = CIImage(color: .white)
        }
        if topInset > 0 {
            let upperEdge = blendMask(from: CGPoint(x: 0, y: bounds.maxY),
                                      to: CGPoint(x: 0, y: art.maxY))
            mask = mask.applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: upperEdge])
        }
        return extended.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: soft, kCIInputMaskImageKey: mask
        ]).cropped(to: bounds)
    }

    static func video(asset: AVAsset, size: CGSize) async throws -> AVVideoComposition {
        // Keep the CI handler and its compositor together. Copying the filter
        // instructions into a new configuration breaks AVAssetExportSession.
        let composition = try await AVMutableVideoComposition.videoComposition(
            with: asset, applyingCIFiltersWithHandler: { request in
                request.finish(with: frame(request.sourceImage, size: size, forLockScreen: true), context: nil)
            }
        )
        composition.renderSize = size
        return composition
    }
}
