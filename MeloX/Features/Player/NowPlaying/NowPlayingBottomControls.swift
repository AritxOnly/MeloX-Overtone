import SwiftUI

struct NowPlayingBottomControls: View {
    static let coreHeight: CGFloat = 279
    static let overlayHeight = coreHeight

    @Environment(\.accessibilityReduceMotion)
    private var accessibilityReduceMotion

    let song: Song
    @Binding var page: NowPlayingPage
    let isInterfaceHidden: Bool

    var body: some View {
        VStack(spacing: 0) {
            coreControls
        }
        .frame(height: Self.overlayHeight)
    }

    private var coreControls: some View {
        VStack(spacing: 0) {
            interfaceLayer(.progress) {
                NowPlayingProgressControl(song: song, showsQuality: false)
            }

            Color.clear
                .frame(height: 19)

            interfaceLayer(.transport) {
                NowPlayingTransportControls()
            }

            Color.clear
                .frame(height: 31)

            interfaceLayer(.volume) {
                NowPlayingVolumeControl()
            }

            Color.clear
                .frame(height: 3)

            interfaceLayer(.pageSelector) {
                NowPlayingPageSelector(page: $page, showsRoutePicker: true)
            }
        }
        .frame(height: Self.coreHeight)
        .background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture {}
        }
    }

    private func interfaceLayer<Content: View>(
        _ layer: NowPlayingInterfaceTransition.ControlLayer,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .offset(
                y: isInterfaceHidden
                    ? NowPlayingInterfaceTransition.hiddenOffset(
                        for: layer
                    )
                    : 0
            )
            .opacity(isInterfaceHidden ? 0 : 1)
            .animation(
                NowPlayingInterfaceTransition.controlAnimation(
                    for: layer,
                    isVisible: !isInterfaceHidden,
                    reducesMotion: accessibilityReduceMotion
                ),
                value: isInterfaceHidden
            )
    }
}
