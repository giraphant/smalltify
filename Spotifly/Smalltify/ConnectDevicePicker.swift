import SwiftUI

struct ConnectDevicePicker: View {
    @Bindable var connect: SpotifyConnectController
    let player: SoloistController
    let authorize: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Label("Spotify Connect", systemImage: "hifispeaker.and.homepod")
                    .font(.headline)
                Spacer()
                Button("刷新设备", systemImage: "arrow.clockwise") {
                    Task { await connect.refreshDevices() }
                }
                .labelStyle(.iconOnly)
                .disabled(!connect.authorized || connect.loading || connect.transferring)
            }
            if !connect.authorized {
                Text("重新授权一次，即可查看并切换到手机、音箱等 Spotify 设备。")
                    .font(.callout).foregroundStyle(.secondary)
                Button("授权 Spotify Connect", action: authorize)
            } else {
                if connect.loading || connect.transferring { ProgressView().controlSize(.small) }
                if connect.devices.isEmpty, !connect.loading {
                    Text("暂无可用设备。请在目标设备上打开 Spotify，并登录同一账号。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(connect.devices.enumerated(), id: \.offset) { _, device in
                            Button {
                                Task { await connect.transfer(to: device) }
                            } label: {
                                HStack {
                                    Image(systemName: device.symbol)
                                    Text(device.name).lineLimit(1)
                                    Spacer()
                                    if connect.playback?.device.id == device.id, connect.playback?.device.active == true {
                                        Image(systemName: "checkmark").foregroundStyle(.green)
                                    } else if !device.selectable {
                                        Text("不可控制").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 5)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .disabled(!device.selectable || connect.transferring || connect.commanding)
                        }
                    }
                }
                .frame(maxHeight: 250)
            }
            Divider()
            Button("在这台 Mac 播放", systemImage: "desktopcomputer") {
                Task { await connect.activateLocal() }
            }
            .disabled(!player.connected || !player.snapshot.loggedIn || player.snapshot.active || connect.transferring || connect.commanding)
            if let error = connect.error {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                if connect.authorized { Button("重新授权", action: authorize) }
            }
        }
        .padding()
        .frame(width: 340)
        .task { await connect.refreshDevices() }
    }
}
