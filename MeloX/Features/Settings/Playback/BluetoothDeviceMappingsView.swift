import SwiftUI

struct BluetoothDeviceMappingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var outputs = PlaybackAudioOutput.current

    var body: some View {
        let activeDevices = outputs.filter { $0.isBluetooth && !$0.id.isEmpty }
        let activeIDs = Set(activeDevices.map(\.id))
        let savedIDs = settings.bluetoothDeviceMappings.keys.filter { !activeIDs.contains($0) }
            .sorted { displayName(for: $0).localizedStandardCompare(displayName(for: $1)) == .orderedAscending }

        Form {
            Section {
                if activeDevices.isEmpty {
                    Text("ui.settings.bluetooth_devices.empty")
                        .foregroundStyle(.secondary)
                }

                ForEach(activeDevices) { device in
                    mappingPicker(id: device.id, name: device.name)
                }
            } header: {
                Text("ui.settings.bluetooth_devices.current")
            } footer: {
                Text("ui.settings.bluetooth_devices.footer")
            }

            if !savedIDs.isEmpty {
                Section("ui.settings.bluetooth_devices.saved") {
                    ForEach(savedIDs, id: \.self) { id in
                        if let mapping = settings.bluetoothDeviceMappings[id] {
                            mappingPicker(id: id, name: mapping.name)
                        }
                    }
                }
            }
        }
        .navigationTitle("ui.settings.bluetooth_devices.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { outputs = PlaybackAudioOutput.current }
        .onReceive(PlaybackAudioOutput.changes) { outputs = $0 }
    }

    private func displayName(for id: String) -> String {
        settings.bluetoothDeviceMappings[id]?.name ?? ""
    }

    private func mappingPicker(id: String, name: String) -> some View {
        let selection = Binding<BluetoothDeviceType?>(
            get: { settings.bluetoothDeviceMappings[id]?.type },
            set: { type in
                settings.bluetoothDeviceMappings[id] = type.map {
                    BluetoothDeviceMapping(name: name, type: $0)
                }
            }
        )

        return Picker(selection: selection) {
            Text("ui.settings.bluetooth_devices.automatic").tag(nil as BluetoothDeviceType?)
            ForEach(BluetoothDeviceType.allCases) { type in
                Text(type.title).tag(type)
            }
        } label: {
            Text(name.isEmpty ? L10n.string("ui.settings.bluetooth_devices.unknown") : name)
        }
        .pickerStyle(.menu)
    }
}
