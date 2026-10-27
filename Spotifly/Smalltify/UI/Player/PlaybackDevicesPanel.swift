import SwiftUI

struct PlaybackDevicesPanel: View {
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("播放设备").font(.headline)
                Spacer()
                Button("刷新设备", systemImage: "arrow.clockwise") { Task { await model.connect.refreshDevices() } }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .disabled(!model.connect.authorized || model.connect.loading || model.connect.transferring)
            }
            Button {
                Task {
                    await model.connect.activateLocal()
                    if model.player.snapshot.active, model.connect.error == nil { model.notices.toast("已切换到这台 Mac") }
                }
            } label: {
                DeviceRow(symbol: "desktopcomputer", name: "在这台 Mac 播放", note: "Smalltify · 本机播放器",
                          selected: model.player.snapshot.active, pending: model.connect.transferring && model.connect.pendingDeviceID == nil)
            }
            .buttonStyle(.plain)
            .disabled(!model.player.connected || !model.player.snapshot.loggedIn || model.player.snapshot.active
                      || model.connect.transferring || model.connect.commanding)
            if model.player.connected, !model.player.snapshot.loggedIn {
                Text("在官方 Spotify 的设备列表里选择「Smalltify」，只需一次。")
                    .font(.caption).padding(10)
                    .background(.orange.opacity(0.1), in: .rect(cornerRadius: 8))
            }
            Divider()
            if !model.connect.authorized {
                Text("设备列表需要额外权限。重新授权一次即可看到和切换设备。")
                    .font(.callout)
                    .padding(12)
                    .background(.orange.opacity(0.1), in: .rect(cornerRadius: 8))
                Button("重新授权", action: model.signIn).buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            } else {
                Text("账号下的其他设备").font(.caption).foregroundStyle(.secondary)
                if model.connect.loading { ProgressView().controlSize(.small).accessibilityLabel("正在加载设备") }
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.connect.otherDevices.enumerated(), id: \.offset) { _, device in
                            Button {
                                Task {
                                    await model.connect.transfer(to: device)
                                    if model.connect.playback?.device.id == device.id, model.connect.error == nil {
                                        model.notices.toast("已切换到\(device.name)")
                                    }
                                }
                            } label: {
                                DeviceRow(symbol: device.symbol, name: device.name, note: device.note,
                                          selected: model.connect.usesRemote && model.connect.playback?.device.id == device.id,
                                          pending: model.connect.transferring && device.id != nil && model.connect.pendingDeviceID == device.id)
                            }
                            .buttonStyle(.plain)
                            .disabled(!device.selectable || model.connect.transferring || model.connect.commanding)
                        }
                        if model.connect.otherDevices.isEmpty, !model.connect.loading {
                            Text("暂无可用设备。请在目标设备上打开 Spotify，并登录同一账号。")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxHeight: 340)
                if model.connect.transferring {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("等待确认…").foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            Label("在其他设备播放时为远程控制，状态约每 5 秒更新。灰色设备不能从这里控制。", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
                .padding(12)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
        }
        .padding(16)
        .frame(width: 360, height: 560)
        .task { await model.connect.refreshDevices() }
    }
}

private struct DeviceRow: View {
    let symbol: String
    let name: String
    let note: String
    let selected: Bool
    let pending: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 18)
                .foregroundStyle(selected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).bold().lineLimit(1)
                Text(pending ? "正在切换…" : note).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor).accessibilityLabel("当前设备") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 10))
        .contentShape(.rect)
    }
}
