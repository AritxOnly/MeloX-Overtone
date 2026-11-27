import AVKit
import Combine
import MediaPlayer
import SwiftUI

private struct PlaybackSlider: View {
    @Binding var value: Double
    var maximum: Double = 1
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        Slider(value: $value, in: 0...maximum, onEditingChanged: onEditingChanged)
            .sliderThumbVisibility(.hidden)
            .tint(.white.opacity(0.68))
    }
}

struct NowPlayingProgressControl: View {
    @Environment(PlayerStore.self) private var player

    let song: Song
    var showsQuality = true

    var body: some View {
        VStack(spacing: 2) {
            PlaybackSlider(
                value: Binding(
                    get: { min(player.progress, progressMaximum) },
                    set: { player.seek(to: $0) }
                ),
                maximum: progressMaximum
            )
            .accessibilityLabel("ui.player.progress")
            .accessibilityValue(
                L10n.format(
                    "ui.player.progress_accessibility",
                    formatTime(player.progress),
                    formatTime(progressMaximum)
                )
            )

            HStack {
                Text(formatTime(player.progress))

                Spacer()

                Text("−\(formatTime(max(player.duration - player.progress, 0)))")
            }
            .overlay {
                Group {
                    if player.isAutoMixTransitioning {
                        NowPlayingAutoMixStatus()
                    } else if showsQuality {
                        NowPlayingQualityMenu()
                    }
                }
                .animation(
                    .smooth(duration: 0.25),
                    value: player.isAutoMixTransitioning
                )
            }
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
        .frame(height: 52)
    }

    private var progressMaximum: TimeInterval {
        max(player.duration, TimeInterval(song.durationMS) / 1_000, 1)
    }

    private func formatTime(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "0:00" }
        let seconds = max(0, Int(value))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct NowPlayingAutoMixStatus: View {
    @Environment(\.accessibilityReduceMotion)
    private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "waveform")
                .font(.system(size: 9, weight: .semibold))
                .symbolEffect(
                    .variableColor.iterative,
                    options: .repeating.speed(1.2),
                    isActive:
                        !accessibilityReduceMotion
                            && player.isAutoMixTransitioning
                )

            Text("ui.player.mixing")
                .fontWeight(.medium)

            ProgressView(
                value:
                    player.autoMixTransitionProgress
                        ?? 0
            )
            .progressViewStyle(.linear)
            .tint(.white)
            .frame(width: 30)

            Text(L10n.percentagePoints(Double(progressPercent)))
                .monospacedDigit()
                .frame(minWidth: 24, alignment: .trailing)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            .white.opacity(0.16),
            in: .rect(cornerRadius: 7)
        )
        .foregroundStyle(.white.opacity(0.86))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ui.player.automix_active")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        if let songName =
            player.autoMixIncomingSongName {
            return L10n.format(
                "ui.player.transitioning_to",
                songName,
                progressPercent
            )
        }
        return L10n.percentagePoints(Double(progressPercent))
    }

    private var progressPercent: Int {
        Int(
            (
                player.autoMixTransitionProgress
                    ?? 0
            ) * 100
        )
    }
}

struct NowPlayingQualityMenu: View {
    @Environment(PlayerStore.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(NeteaseAPI.self) private var api

    var body: some View {
        Menu {
            if player.availablePlaybackQualities.isEmpty {
                Text("ui.player.loading_quality")
            } else {
                Picker("ui.player.quality", selection: qualityBinding) {
                    ForEach(player.availablePlaybackQualities) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "waveform")
                    .font(.system(size: 9, weight: .semibold))
                Text(displayedQualityTitle)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                .white.opacity(0.12),
                in: .rect(cornerRadius: 7)
            )
            .contentShape(.rect)
        }
        .tint(.white)
        .accessibilityLabel("ui.player.playback_quality")
        .accessibilityValue(displayedQualityTitle)
        .accessibilityHint("ui.player.quality_hint")
    }

    private var displayedQualityTitle: String {
        player.effectivePlaybackQuality?.title ?? L10n.string("ui.player.quality")
    }

    private var qualityBinding: Binding<MusicQuality> {
        Binding(
            get: {
                api.isCellularData
                    ? settings.cellularQuality
                    : settings.quality
            },
            set: { player.selectPlaybackQuality($0) }
        )
    }
}

struct NowPlayingTransportControls: View {
    @Environment(AppSettings.self) private var appearanceSettings
    enum Presentation {
        case standard
        case tablet
    }

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player

    var presentation: Presentation = .standard

    private var isTablet: Bool { presentation == .tablet }
    private var controlDiameter: CGFloat { isTablet ? 44 : 64 }

    var body: some View {
        HStack(spacing: isTablet ? 0 : nil) {
            if isTablet {
                Button(action: player.toggleShuffle) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(player.isShuffled ? appearanceSettings.accent.color : .white.opacity(0.58))
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    player.isShuffled
                        ? L10n.string("ui.player.shuffle_off")
                        : L10n.string("ui.player.shuffle_on")
                )
                .accessibilityAddTraits(player.isShuffled ? .isSelected : [])
            }

            Spacer(minLength: isTablet ? 0 : nil)

            Button {
                Task { await player.previous() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: isTablet ? 24 : 29, weight: .medium))
                    .frame(width: controlDiameter, height: controlDiameter)
                    .contentShape(.circle)
            }
            .buttonStyle(
                NowPlayingTransportButtonStyle(
                    reducesMotion: accessibilityReduceMotion,
                    diameter: controlDiameter
                )
            )
            .accessibilityLabel("ui.player.previous")

            Spacer(minLength: isTablet ? 0 : nil)

            Button {
                player.togglePlayback()
            } label: {
                Group {
                    if player.isLoading {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: isTablet ? 30 : 48, weight: .medium))
                            .contentTransition(
                                accessibilityReduceMotion
                                    ? .identity
                                    : .symbolEffect(
                                        .replace.downUp.wholeSymbol,
                                        options: .speed(1.6)
                                    )
                            )
                            .animation(
                                accessibilityReduceMotion
                                    ? nil
                                    : .snappy(duration: 0.2, extraBounce: 0),
                                value: player.isPlaying
                            )
                    }
                }
                .frame(width: controlDiameter, height: controlDiameter)
                .contentShape(.circle)
            }
            .buttonStyle(
                NowPlayingTransportButtonStyle(
                    reducesMotion: accessibilityReduceMotion,
                    diameter: controlDiameter
                )
            )
            .accessibilityLabel(
                player.isPlaying
                    ? L10n.string("ui.player.pause")
                    : L10n.string("ui.common.play")
            )

            Spacer(minLength: isTablet ? 0 : nil)

            Button {
                Task { await player.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: isTablet ? 24 : 29, weight: .medium))
                    .frame(width: controlDiameter, height: controlDiameter)
                    .contentShape(.circle)
            }
            .buttonStyle(
                NowPlayingTransportButtonStyle(
                    reducesMotion: accessibilityReduceMotion,
                    diameter: controlDiameter
                )
            )
            .accessibilityLabel("ui.player.next")

            Spacer(minLength: isTablet ? 0 : nil)

            if isTablet {
                Button(action: player.cycleRepeatMode) {
                    Image(systemName: player.repeatMode.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(player.repeatMode == .off ? .white.opacity(0.58) : appearanceSettings.accent.color)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.repeatMode.accessibilityTitle)
                .accessibilityAddTraits(player.repeatMode == .off ? [] : .isSelected)
            }
        }
        .frame(height: isTablet ? 52 : 82)
    }
}

struct NowPlayingVolumeControl: View {
    @Environment(PlayerStore.self) private var player
    @Environment(AppSettings.self) private var settings

    @ViewBuilder
    var body: some View {
        if settings.playerVolumeControlMode != .hidden {
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.subheadline.bold())

                volumeSlider
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .layoutPriority(1)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.subheadline.bold())
            }
            .foregroundStyle(.white.opacity(0.62))
            .frame(height: 44)
        }
    }

    @ViewBuilder
    private var volumeSlider: some View {
        switch settings.playerVolumeControlMode {
        case .hidden:
            EmptyView()
        case .independent:
            PlaybackSlider(
                value: Binding(
                    get: { player.volume },
                    set: { player.setVolume($0) }
                )
            )
            .accessibilityLabel("ui.player.volume")
        case .system:
            SystemVolumeSlider()
                .accessibilityLabel("ui.player.system_volume")
        }
    }
}

// MPVolumeView supplies the system volume control. The visible slider uses
// the same track and drag interaction as playback progress.
private struct SystemVolumeSlider: View {
    @StateObject private var output = SystemVolumeOutput()
    @State private var isDragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        PlaybackSlider(value: Binding(
            get: { isDragging ? dragValue : output.level },
            set: { value in
                dragValue = value
                output.setVolume(value)
            }
        ), onEditingChanged: { editing in
            if editing { dragValue = output.level }
            isDragging = editing
        })
        .background {
            VolumeViewHost(volumeView: output.volumeView)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

@MainActor
private final class SystemVolumeOutput: ObservableObject {
    let volumeView = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
    @Published private(set) var level: Double

    init() {
        let session = AVAudioSession.sharedInstance()
        level = Double(session.outputVolume)
        session.publisher(for: \.outputVolume)
            .map(Double.init)
            .receive(on: DispatchQueue.main)
            .assign(to: &$level)
    }

    func setVolume(_ value: Double) {
        guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.setValue(Float(value), animated: false)
        slider.sendActions(for: [.valueChanged, .touchUpInside])
    }
}

private struct VolumeViewHost: UIViewRepresentable {
    let volumeView: MPVolumeView
    func makeUIView(context: Context) -> MPVolumeView { volumeView }
    func updateUIView(_ view: MPVolumeView, context: Context) {}
}

struct NowPlayingPageSelector: View {
    @Environment(\.accessibilityReduceMotion)
    private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player

    @Binding var page: NowPlayingPage
    var showsRoutePicker = false

    var body: some View {
        Group {
            if player.currentSong?.isPodcastProgram == true {
                HStack {
                    Spacer()

                    pageButton(
                        page: .queue,
                        systemImage: "list.bullet",
                        accessibilityLabel: L10n.string("ui.player.queue"),
                        badgeSystemImage:
                            page == .queue
                                ? nil
                                : player.queueModeBadgeSystemImage
                    )

                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    pageButton(
                        page: .lyrics,
                        systemImage: "quote.bubble",
                        accessibilityLabel: L10n.string("ui.settings.lyrics.title")
                    )

                    if showsRoutePicker {
                        PlayerAirPlayButton()
                    } else {
                        FloatingLyricsButton()
                            .frame(maxWidth: .infinity)
                    }

                    pageButton(
                        page: .queue,
                        systemImage: "list.bullet",
                        accessibilityLabel: L10n.string("ui.player.queue"),
                        badgeSystemImage:
                            page == .queue
                                ? nil
                                : player.queueModeBadgeSystemImage
                    )
                }
            }
        }
        .padding(.horizontal, 32)
        .foregroundStyle(.white.opacity(0.72))
        .frame(height: 50)
    }

    private func pageButton(
        page destination: NowPlayingPage,
        systemImage: String,
        accessibilityLabel: String,
        badgeSystemImage: String? = nil
    ) -> some View {
        let isSelected = page == destination

        return Button {
            let targetPage: NowPlayingPage =
                isSelected ? .artwork : destination
            withAnimation(
                accessibilityReduceMotion
                    ? nil
                    : NowPlayingPageTransition
                        .selectionAnimation(
                            from: page,
                            to: targetPage
                        )
            ) {
                page = targetPage
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .symbolVariant(isSelected ? .fill : .none)
                    .font(.title3.weight(.medium))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(
                        isSelected
                            ? .black.opacity(0.68)
                            : .white.opacity(0.72)
                    )
                    .background(
                        Circle().fill(.white.opacity(isSelected ? 0.6 : 0)).frame(width: 38, height: 38)
                    )

                if let badgeSystemImage {
                    Image(systemName: badgeSystemImage)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(
                            isSelected
                                ? .white.opacity(0.9)
                                : .black.opacity(0.74)
                        )
                        .frame(width: 15, height: 15)
                        .background(
                            isSelected
                                ? .black.opacity(0.58)
                                : .white.opacity(0.82),
                            in: .circle
                        )
                        .offset(x: 3, y: 1)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PlayerAirPlayButton: View {
    @Environment(AppSettings.self) private var settings
    @State private var outputs = PlaybackAudioOutput.current

    var body: some View {
        let externalOutputs = outputs.filter { !$0.isBuiltIn }
        let name = externalOutputs.map(\.name).filter { !$0.isEmpty }.joined(separator: " · ")
        let isUsingAirPlay = externalOutputs.contains { $0.portType == .airPlay }

        AudioRoutePicker()
            .frame(width: 44, height: 44)
            .accessibilityElement(children: .combine)
            .accessibilityValue(Text(verbatim: name))
            .overlay {
                outputIcon(for: externalOutputs)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(isUsingAirPlay ? 1 : 0.72))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            // Use the space below the controls so route changes keep the buttons aligned.
            .overlay(alignment: .top) {
                if !name.isEmpty {
                    Text(verbatim: name)
                        .font(.caption.weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .offset(y: 47)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onAppear { outputs = PlaybackAudioOutput.current }
            .onReceive(PlaybackAudioOutput.changes) { outputs = $0 }
    }

    @ViewBuilder
    private func outputIcon(for outputs: [PlaybackAudioOutput]) -> some View {
        switch icon(for: outputs) {
        case .symbol(let name):
            Image(systemName: name)
        case .bluetooth:
            BluetoothGlyph()
                .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .frame(width: 20, height: 20)
        }
    }

    private func icon(for outputs: [PlaybackAudioOutput]) -> PlaybackOutputIcon {
        let icons = outputs.map { $0.icon(using: settings.bluetoothDeviceMappings[$0.id]) }
        if let first = icons.first, icons.dropFirst().allSatisfy({ $0 == first }) {
            return first
        }
        return !outputs.isEmpty && outputs.allSatisfy(\.isBluetooth) ? .bluetooth : .symbol("airplay.audio")
    }
}

private struct BluetoothGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let path = Path { path in
            path.move(to: CGPoint(x: 4, y: 5))
            path.addLine(to: CGPoint(x: 15, y: 15))
            path.addLine(to: CGPoint(x: 9, y: 19))
            path.addLine(to: CGPoint(x: 9, y: 1))
            path.addLine(to: CGPoint(x: 15, y: 5))
            path.addLine(to: CGPoint(x: 4, y: 15))
        }
        return path.applying(
            CGAffineTransform(a: rect.width / 20, b: 0, c: 0, d: rect.height / 20, tx: rect.minX, ty: rect.minY)
        )
    }
}

private struct AudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .clear
        picker.activeTintColor = .clear
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {}
}
