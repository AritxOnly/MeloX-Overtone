import Foundation
import UIKit

struct BluetoothDeviceMapping: Codable {
    let name: String
    let type: BluetoothDeviceType
}

enum BluetoothDeviceType: String, Codable, CaseIterable, Identifiable {
    case headphones, otherBluetooth, airPods
    case airPods1, airPods2, airPods3, airPods4, airPods4ANC
    case airPods5, airPods5WirelessCharging
    case airPodsPro1, airPodsPro2Lightning, airPodsPro2USB, airPodsPro3
    case airPodsMaxLightning, airPodsMaxUSB, airPodsMax2

    var id: Self { self }

    var title: String {
        switch self {
        case .headphones: L10n.string("ui.settings.bluetooth_devices.headphones")
        case .otherBluetooth: L10n.string("ui.settings.bluetooth_devices.other")
        case .airPods: L10n.string("ui.settings.bluetooth_devices.airpods")
        case .airPods1: "AirPods 1"
        case .airPods2: "AirPods 2"
        case .airPods3: "AirPods 3"
        case .airPods4: "AirPods 4"
        case .airPods4ANC: "AirPods 4 (ANC)"
        case .airPods5: "AirPods 5"
        case .airPods5WirelessCharging: L10n.string("ui.settings.bluetooth_devices.airpods_5_wireless")
        case .airPodsPro1: "AirPods Pro 1"
        case .airPodsPro2Lightning: "AirPods Pro 2 (Lightning)"
        case .airPodsPro2USB: "AirPods Pro 2 (USB-C)"
        case .airPodsPro3: "AirPods Pro 3"
        case .airPodsMaxLightning: "AirPods Max 1 (Lightning)"
        case .airPodsMaxUSB: "AirPods Max 1 (USB-C)"
        case .airPodsMax2: "AirPods Max 2"
        }
    }

    var icon: PlaybackOutputIcon {
        switch self {
        case .headphones: .symbol("headphones")
        case .otherBluetooth: .bluetooth
        case .airPods, .airPods1, .airPods2: .symbol("airpods")
        case .airPods3: .symbol("airpods.gen3")
        case .airPods4, .airPods4ANC: .symbol("airpods.gen4")
        case .airPods5, .airPods5WirelessCharging: .availableSymbol("airpods.gen5", fallback: "airpods.gen4")
        case .airPodsPro1, .airPodsPro2Lightning, .airPodsPro2USB: .symbol("airpodspro")
        case .airPodsPro3: .availableSymbol("airpodspro.gen3", fallback: "airpodspro")
        case .airPodsMaxLightning, .airPodsMaxUSB: .symbol("airpodsmax")
        case .airPodsMax2: .availableSymbol("airpodsmax.gen2", fallback: "airpodsmax")
        }
    }

    static func inferred(from name: String) -> Self {
        if name.localizedCaseInsensitiveContains("AirPods") { return .airPods }
        let headphoneTerms = ["headphone", "headset", "earphone", "earbud", "耳机", "耳機"]
        if headphoneTerms.contains(where: { name.localizedCaseInsensitiveContains($0) }) {
            return .headphones
        }
        return .otherBluetooth
    }
}

enum PlaybackOutputIcon: Equatable {
    case bluetooth
    case symbol(String)

    static func availableSymbol(_ name: String, fallback: String) -> Self {
        .symbol(UIImage(systemName: name) == nil ? fallback : name)
    }
}
