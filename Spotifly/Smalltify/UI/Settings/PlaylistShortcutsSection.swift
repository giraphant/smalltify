import SwiftUI

struct PlaylistShortcutsSection: View {
    let shortcuts: PlaylistShortcuts
    let player: SoloistController
    let suggestedLink: String
    @State private var name = ""
    @State private var link = ""
    @State private var error: String?

    var body: some View {
        Section("常用歌单") {
            Text("保存每周新发现、新歌雷达等歌单链接，之后在这里直接播放。歌单内容随 Spotify 更新。")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(shortcuts.playlists) { playlist in
                HStack {
                    Text(playlist.name).lineLimit(1).help(playlist.name)
                    Spacer()
                    Button("播放", systemImage: "play.fill") {
                        player.control("play", uri: playlist.uri)
                    }
                    .disabled(!player.canControl)
                    Button("删除", systemImage: "trash", role: .destructive) {
                        do {
                            try shortcuts.remove(playlist)
                            error = nil
                        } catch { self.error = error.localizedDescription }
                    }
                    .labelStyle(.iconOnly)
                    .help("删除常用入口，不影响 Spotify 中的歌单")
                }
            }
            HStack {
                TextField("歌单名称", text: $name)
                Menu("常用名称") {
                    Button("每周新发现") { name = "每周新发现" }
                    Button("新歌雷达") { name = "新歌雷达" }
                }
                .fixedSize()
            }
            TextField("Spotify 歌单链接", text: $link)
                .autocorrectionDisabled()
                .onSubmit { save() }
            HStack {
                Button("保存歌单", systemImage: "plus") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("相同链接再次保存会更新名称。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
        .onAppear {
            if link.isEmpty, let uri = SmalltifyModel.spotifyURI(from: suggestedLink), uri.hasPrefix("spotify:playlist:") {
                link = suggestedLink
            }
        }
    }

    private func save() {
        do {
            try shortcuts.save(name: name, link: link)
            name = ""
            link = ""
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
