import AVFAudio
import Combine
import UIKit

struct PlaybackAudioOutput: Identifiable {
    let id: String
    let name: String
    let portType: AVAudioSession.Port

    var isBluetooth: Bool {
        portType == .bluetoothA2DP || portType == .bluetoothHFP || portType == .bluetoothLE
    }

    var isBuiltIn: Bool {
        portType == .builtInSpeaker || portType == .builtInReceiver
    }

    func icon(using mapping: BluetoothDeviceMapping?) -> PlaybackOutputIcon {
        if isBluetooth {
            return (mapping?.type ?? .inferred(from: name)).icon
        }

        switch portType {
        case .headphones: return .symbol("headphones")
        case .carAudio: return .bluetooth
        default: return .symbol("airplay.audio")
        }
    }

    static var current: [Self] {
        AVAudioSession.sharedInstance().currentRoute.outputs.map {
            Self(id: $0.uid, name: $0.portName, portType: $0.portType)
        }
    }

    static var changes: AnyPublisher<[Self], Never> {
        let notifications = NotificationCenter.default
        return notifications.publisher(for: AVAudioSession.routeChangeNotification)
            .merge(with: notifications.publisher(for: UIApplication.didBecomeActiveNotification))
            .receive(on: DispatchQueue.main)
            .map { _ in current }
            .eraseToAnyPublisher()
    }
}
