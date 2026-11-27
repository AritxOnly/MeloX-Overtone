import Intents
import MediaPlayer
import OSLog
import UIKit

@MainActor
final class MeloXAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        guard intent is INPlayMediaIntent else { return nil }
        return PlaybackIntentHandler.shared
    }
}

@MainActor
final class PlaybackIntentHandler: NSObject, @preconcurrency INPlayMediaIntentHandling {
    static let shared = PlaybackIntentHandler()

    private static let queueIdentifier = "overtone:resume-queue"
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Overtone",
        category: "PlaybackSuggestions"
    )

    weak var player: PlayerStore?

    static func donateResumeQueue(for song: Song) {
        let queue = INMediaItem(
            identifier: queueIdentifier,
            title: L10n.string("ui.player.continue_playing"),
            type: song.isPodcastProgram ? .podcastPlaylist : .playlist,
            artwork: song.album?.artworkURL.flatMap { INImage(url: $0) },
            artist: nil
        )
        let intent = INPlayMediaIntent(
            mediaItems: nil,
            mediaContainer: queue,
            playShuffled: nil,
            playbackRepeatMode: .unknown,
            resumePlayback: nil,
            playbackQueueLocation: .unknown,
            playbackSpeed: nil,
            mediaSearch: nil
        )
        INInteraction(intent: intent, response: nil).donate { [logger] error in
            if let error {
                logger.error("Playback suggestion donation failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    func handle(intent: INPlayMediaIntent) async -> INPlayMediaIntentResponse {
        guard Self.requestsResumeQueue(intent),
              await player?.playFromSystem() == true else {
            return INPlayMediaIntentResponse(code: .failure, userActivity: nil)
        }

        let response = INPlayMediaIntentResponse(code: .success, userActivity: nil)
        response.nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo
        return response
    }

    private static func requestsResumeQueue(_ intent: INPlayMediaIntent) -> Bool {
        if let container = intent.mediaContainer {
            return container.identifier == queueIdentifier
        }
        if let items = intent.mediaItems, !items.isEmpty {
            return items.count == 1 && items.first?.identifier == queueIdentifier
        }
        guard let search = intent.mediaSearch else { return true }
        if let identifier = search.mediaIdentifier {
            return identifier == queueIdentifier
        }
        // A general request can resume the queue. A named request needs a matching item.
        return search.mediaName == nil
            && search.artistName == nil
            && search.albumName == nil
            && search.genreNames?.isEmpty != false
            && search.moodNames?.isEmpty != false
            && search.releaseDate == nil
    }
}
