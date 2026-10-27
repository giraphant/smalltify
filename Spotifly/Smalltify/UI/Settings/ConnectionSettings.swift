import AppKit
import SwiftUI

struct ConnectionSettings: View {
    let model: SmalltifyModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                AuthorizationSettings(model: model)
                SoloistSettings(model: model)
                PairingSettings(player: model.player)
                SettingsFooter(expired: model.player.error?.contains("构建已过期") == true)
            }
            .padding(24)
        }
        .background(.quaternary.opacity(0.3))
    }
}

struct AuthorizationSettings: View {
    @Bindable var model: SmalltifyModel

    var body: some View {
        let status = SettingsStatus.authorization(clientID: model.clientID, signedIn: model.signedIn,
                                                  authorizing: model.authorizing, expired: model.authExpired,
                                                  name: model.profile?.displayName, error: model.signInError)
        SettingsStep(number: 1, title: "Spotify 授权", status: status) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Client ID").foregroundStyle(.secondary).frame(width: 96, alignment: .trailing)
                    TextField("Client ID", text: $model.clientID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.callout, design: .monospaced))
                        .autocorrectionDisabled()
                        .overlay {
                            if case .invalid = ClientIDValidation(model.clientID) {
                                RoundedRectangle(cornerRadius: 5).stroke(.red, lineWidth: 1).allowsHitTesting(false)
                            }
                        }
                        .disabled(model.authorizing)
                        .onSubmit { if ClientIDValidation(model.clientID) == .valid { model.signIn() } }
                }
                GridRow {
                    Text("回调地址").foregroundStyle(.secondary).frame(width: 96, alignment: .trailing)
                    HStack {
                        Text(SmalltifyOAuth.redirectURI).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        Button("拷贝") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(SmalltifyOAuth.redirectURI, forType: .string)
                        }.controlSize(.small)
                    }
                }
            }
            if let message = status.message { SettingsMessage(text: message) }
            if model.signedIn, model.needsScopeUpgrade || !model.connect.authorized {
                Text("设备列表需要额外权限。重新授权一次即可看到和切换设备。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                if model.authorizing {
                    ProgressView().controlSize(.small)
                    Button("取消") { model.cancelSignIn() }
                } else {
                    if model.signedIn { Button("退出登录") { model.signOut() } }
                    if !model.signedIn || model.authExpired || model.needsScopeUpgrade || !model.connect.authorized || model.signInError != nil || ClientIDValidation(model.clientID) != .valid {
                        Button(model.authExpired || model.signedIn ? "重新授权" : model.signInError != nil ? "重试" : "登录") { model.signIn() }
                            .buttonStyle(.borderedProminent)
                            .disabled(ClientIDValidation(model.clientID) != .valid)
                    }
                }
            }
        }
    }
}

struct SoloistSettings: View {
    @Bindable var model: SmalltifyModel
    @State private var key = ""

    var body: some View {
        let player = model.player
        let expired = (SoloistBuild(SoloistController.version)?.daysRemaining() ?? 1) <= 0 || player.error?.contains("构建已过期") == true
        let status = SettingsStatus.player(running: player.running, starting: player.starting, stopping: player.stopping,
                                           hasKey: model.hasPlayerKey, expired: expired, error: player.error)
        SettingsStep(number: 2, title: "播放器（Soloist）", status: status) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("API Key").foregroundStyle(.secondary).frame(width: 96, alignment: .trailing)
                    SecureField(model.hasPlayerKey ? "已保存在钥匙串，留空则不修改" : "粘贴 Soloist API Key", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Soloist API Key")
                }
                GridRow {
                    Text("缓存上限").foregroundStyle(.secondary).frame(width: 96, alignment: .trailing)
                    Picker("缓存上限", selection: $model.cacheMB) {
                        ForEach([1, 2, 5, 10, 20], id: \.self) { size in Text("\(size) GB").tag(size * 1024) }
                    }
                    .labelsHidden().pickerStyle(.segmented)
                }
            }
            if let message = status.message { SettingsMessage(text: message) }
            HStack {
                Spacer()
                Button(player.stopping ? "停止中…" : "停止") { Task { await player.stop() } }
                    .disabled((!player.running && !player.starting) || player.stopping)
                Button(player.starting ? "启动中…" : player.running ? "保存并重启" : "保存并启动") {
                    model.savePlayer(key: key)
                    key = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(player.starting || player.stopping || expired || (!model.hasPlayerKey && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
    }
}

struct PairingSettings: View {
    let player: SoloistController

    var body: some View {
        let status = SettingsStatus.pairing(running: player.running, starting: player.starting, stopping: player.stopping,
                                            loggedIn: player.snapshot.loggedIn)
        SettingsStep(number: 3, title: "配对", status: status) {
            Text(status.message ?? "").font(.callout).foregroundStyle(.secondary).padding(.leading, 32)
        }
    }
}

struct SettingsFooter: View {
    var expired = false
    var body: some View {
        let build = SoloistBuild(SoloistController.version)
        let remaining = expired ? 0 : build?.daysRemaining()
        HStack(spacing: 12) {
            Text("播放器版本 \(build?.version ?? SoloistController.version) · \(remaining.map { $0 > 0 ? "约 \($0) 天后过期" : "已过期" } ?? "有效期待确认")")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button("打开缓存目录") { NSWorkspace.shared.open(SoloistController.cacheDirectory) }.buttonStyle(.link)
                OfficialSettingsLinks()
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}
