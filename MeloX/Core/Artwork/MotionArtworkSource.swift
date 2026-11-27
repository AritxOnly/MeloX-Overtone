import AVFoundation
import CoreImage
import MediaPlayer
import UIKit

@Observable
final class MotionArtworkSelection {
    var source: MotionArtworkSource?
}

/// One active song shares its on-demand download between the player and system.
@MainActor
final class MotionArtworkSource {
    let songID: Int
    private let remoteURL: URL
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MeloX-Motion-" + UUID().uuidString, isDirectory: true)
    private var download: Task<URL, Error>?
    private var renders: [Int: Task<URL, Error>] = [:]
    private var firstFrame: Task<CGImage, Error>?

    init(songID: Int, url: URL) {
        self.songID = songID
        self.remoteURL = url
    }

    deinit {
        download?.cancel()
        firstFrame?.cancel()
        for task in renders.values { task.cancel() }
        try? FileManager.default.removeItem(at: directory)
    }

    func localFile() async throws -> URL {
        if let download { return try await download.value }
        let task = Task { [remoteURL, directory] in
            let (file, response) = try await URLSession.shared.download(from: remoteURL)
            defer { try? FileManager.default.removeItem(at: file) }
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
            else { throw APIError.invalidResponse }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let local = directory.appendingPathComponent("cover.mp4")
            try FileManager.default.moveItem(at: file, to: local)
            return local
        }
        download = task
        do { return try await task.value }
        catch {
            download = nil
            throw error
        }
    }

    private func poster() async throws -> CGImage {
        if let firstFrame { return try await firstFrame.value }
        let task = Task {
            let asset = AVURLAsset(url: try await localFile())
            let generator = AVAssetImageGenerator(asset: asset)
            generator.maximumSize = CGSize(width: 960, height: 960)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceAfter = .zero
            return try await generator.image(at: .zero).image
        }
        firstFrame = task
        do { return try await task.value }
        catch {
            firstFrame = nil
            throw error
        }
    }

    func systemArtwork(tall: Bool) -> MPMediaItemAnimatedArtwork {
        let size = CGSize(width: 720, height: tall ? 960 : 720)
        return MPMediaItemAnimatedArtwork(
            artworkID: "netease-motion-\(songID)-\(Int(size.height))",
            previewImageRequestHandler: { _ in
                guard let image = try? await self.poster() else { return nil }
                let preview = MotionArtworkComposition.frame(CIImage(cgImage: image), size: size)
                guard let cg = Self.previewContext.createCGImage(preview, from: preview.extent)
                else { return nil }
                return UIImage(cgImage: cg)
            },
            videoAssetFileURLRequestHandler: { _ in try? await self.systemFile(size: size) }
        )
    }

    private static let previewContext = CIContext()

    private func systemFile(size: CGSize) async throws -> URL {
        let key = Int(size.height)
        if let task = renders[key] { return try await task.value }
        let task = Task {
            let local = try await localFile()
            let asset = AVURLAsset(url: local)
            guard let track = try await asset.loadTracks(withMediaType: .video).first
            else { throw APIError.invalidResponse }
            let natural = try await track.load(.naturalSize)
            let oriented = natural.applying(try await track.load(.preferredTransform))
            if abs(abs(oriented.width / oriented.height) - size.width / size.height) < 0.001 {
                return local
            }
            // Export only the picture track, on demand, for this lock-screen variant.
            let silent = AVMutableComposition()
            guard let video = silent.addMutableTrack(withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid) else { throw APIError.invalidResponse }
            try video.insertTimeRange(try await track.load(.timeRange), of: track, at: .zero)
            video.preferredTransform = try await track.load(.preferredTransform)
            guard let export = AVAssetExportSession(asset: silent, presetName: AVAssetExportPresetHighestQuality)
            else { throw APIError.invalidResponse }
            export.videoComposition = try await MotionArtworkComposition.video(asset: silent, size: size)
            let target = directory.appendingPathComponent("cover-\(key)-\(UUID().uuidString).mp4")
            try await export.export(to: target, as: .mp4)
            return target
        }
        renders[key] = task
        do { return try await task.value }
        catch {
            renders[key] = nil
            throw error
        }
    }
}
