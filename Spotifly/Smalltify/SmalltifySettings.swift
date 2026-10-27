import AppKit
import SwiftUI

struct SmalltifySettings: View {
    @Bindable var model: SmalltifyModel
    @State private var playerKey = ""

    var body: some View {
        Form {
            PlaylistShortcutsSection(shortcuts: model.playlistShortcuts, player: model.player, suggestedLink: model.directLink)
            Section("文库与搜索") {
                TextField("Client ID", text: $model.clientID)
                    .autocorrectionDisabled()
                LabeledContent("Redirect URI") {
                    Text(SmalltifyOAuth.redirectURI).textSelection(.enabled)
                    Button("复制") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(SmalltifyOAuth.redirectURI, forType: .string)
                    }
                }
                Text("先在 Developer Dashboard 的应用设置中添加以上完整回调地址，保留端口 43821。使用你自己的 Client ID，无需 Client Secret。")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button(model.signedIn ? "重新授权文库" : "登录 Spotify 文库") { model.signIn() }
                        .disabled(model.authorizing)
                    if model.authorizing {
                        ProgressView().controlSize(.small)
                        Button("取消") { model.cancelSignIn() }
                    }
                    if model.signedIn {
                        Label("已授权", systemImage: "checkmark.circle").foregroundStyle(.green)
                        Button("退出文库") { model.signOut() }.disabled(model.authorizing)
                    }
                }
            }
            Section("播放与硬盘缓存") {
                SecureField(model.hasPlayerKey ? "Soloist API Key（已保存，留空保留）" : "Soloist API Key", text: $playerKey)
                Text("在 Dashboard 单独生成 Soloist API Key，需要 Premium。密钥保存在本机钥匙串。")
                    .font(.callout).foregroundStyle(.secondary)
                Picker("缓存上限", selection: $model.cacheMB) {
                    Text("1 GB").tag(1024)
                    Text("2 GB").tag(2048)
                    Text("5 GB").tag(5120)
                    Text("10 GB").tag(10240)
                    Text("20 GB").tag(20480)
                }
                HStack {
                    Button("保存并启动播放器") {
                        model.savePlayer(key: playerKey)
                        playerKey = ""
                    }
                    .disabled(model.player.starting || model.player.stopping)
                    Button("停止播放器") { Task { await model.player.stop() } }
                        .disabled(!model.player.running || model.player.stopping)
                    if model.player.starting || model.player.stopping { ProgressView().controlSize(.small) }
                }
                Text("首次启动后，打开官方 Spotify，在设备列表中选择「Smalltify」完成配对。之后可关闭官方客户端，配对会保留。两个入口请使用同一 Spotify 账号。")
                    .font(.callout).foregroundStyle(.secondary)
                LabeledContent("播放器", value: "Spotify Soloist \(SoloistController.version)")
                LabeledContent("音质", value: "引擎支持无损；本次播放音质待验证")
                Text("Soloist 当前控制接口不报告音频码率；界面不会把引擎能力当作当前播放音质。缓存由 Soloist 管理，用于再次播放，不是离线下载。")
                    .font(.callout).foregroundStyle(.secondary)
                Button("打开缓存目录") { NSWorkspace.shared.open(SoloistController.cacheDirectory) }
            }
            Section("官方服务") {
                if let url = URL(string: "https://developer.spotify.com/dashboard") {
                    Link("Spotify Developer Dashboard", destination: url)
                }
                if let url = URL(string: "https://developer.spotify.com/documentation/soloist") {
                    Link("Soloist 文档与更新", destination: url)
                }
                Text("歌单内容受官方 API 权限限制。无法查看内容时，可尝试通过 Spotify 链接直接播放。Soloist 构建有有效期，到期后需手动核验并更新。")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
