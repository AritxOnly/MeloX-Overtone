import Foundation

struct PlaybackSource: Codable, Equatable, Sendable {
    let url: URL
    let bitrate: Int?
    let format: String?
    let quality: MusicQuality?

    init(
        url: URL,
        bitrate: Int?,
        format: String?,
        quality: MusicQuality? = nil
    ) {
        self.url = url
        self.bitrate = bitrate
        self.format = format
        self.quality = quality
    }

    var preferredForwardBufferDuration: TimeInterval {
        guard !url.isFileURL else { return 0 }
        if quality?.prefersExtendedBuffering == true
            || (bitrate ?? 0) >= 1_000_000 {
            return 24
        }
        return 16
    }
}
