import SwiftUI

struct DeviceChip: View {
    @Environment(SmalltifyModel.self) private var model
    @State private var showingDevices = false
    var opensFixture = true

    var body: some View {
        Button { showingDevices.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: model.isRemote ? model.connect.playback?.device.symbol ?? "hifispeaker" : "desktopcomputer")
                    .foregroundStyle(model.isRemote ? Color.accentColor : .secondary)
                Text(model.deviceLabel).lineLimit(1)
                if model.isRemote { Text("· 远程").foregroundStyle(.secondary) }
            }
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .help(model.connectionStatus.text)
        .popover(isPresented: $showingDevices) {
            PlaybackDevicesPanel()
                .environment(model)
        }
        .task {
            #if DEBUG
                if opensFixture, DebugFixtures.opens("devices") { showingDevices = true }
            #endif
        }
    }
}
