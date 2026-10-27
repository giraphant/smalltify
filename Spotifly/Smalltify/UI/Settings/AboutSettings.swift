import SwiftUI

struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list").font(.largeTitle).foregroundStyle(Color.accentColor)
            Text("Smalltify").font(.title).bold()
            Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                .foregroundStyle(.secondary)
            Text("轻巧的 macOS Spotify 客户端。通过 Spotify 官方接口浏览文库，使用 Soloist 播放音乐。")
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack(spacing: 16) { OfficialSettingsLinks() }.font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct OfficialSettingsLinks: View {
    var body: some View {
        if let url = URL(string: "https://developer.spotify.com/dashboard") { Link("Dashboard", destination: url) }
        if let url = URL(string: "https://developer.spotify.com/documentation/soloist") { Link("Soloist 文档", destination: url) }
    }
}
