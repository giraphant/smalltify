import SwiftUI

struct NowPlayingPanel: View {
    /// The inspector column's width: the 268pt cover and text column plus the padding.
    static let width: CGFloat = 300
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("正在播放").font(.headline)
                Spacer()
                Button("关闭正在播放", systemImage: "xmark") { model.inspectorPresented = false }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.isRemote, let device = model.connect.playback?.device {
                        Label("在\(device.name)上播放。远程控制，状态约每 5 秒同步一次\(device.supportsVolume ? "。" : "；此设备不允许调节音量。")",
                              systemImage: device.symbol)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 10))
                    }
                    NowPlayingDetails(snapshot: model.player.displaySnapshot, connect: model.connect)
                    Divider()
                    HStack {
                        Text("接下来播放").bold()
                        Spacer()
                        Text("只读").font(.caption).foregroundStyle(.secondary)
                    }
                    if !model.connect.authorized {
                        Text("设备列表需要额外权限。重新授权一次即可看到和切换设备。")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("重新授权", action: model.signIn)
                    } else if model.connect.queueLoading {
                        ProgressView("正在加载队列").controlSize(.small)
                    } else if let error = model.connect.queueError {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                        Button("重试") { Task { await model.connect.refreshQueue() } }
                    } else if model.connect.queue.isEmpty {
                        Text("接下来没有歌曲").foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(model.connect.queue.enumerated(), id: \.offset) { _, item in
                                HStack(spacing: 8) {
                                    CoverArt(item: item, size: 32)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.name).lineLimit(1).help(item.name)
                                        ArtistLinks(artists: item.artists, fallback: item.subtitle)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    Text("队列不能排序、删除或清空；在歌曲上用「加入队列」只会加到队尾。")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 268, alignment: .leading)
            }
        }
        .padding(16)
        .frame(minWidth: Self.width, maxWidth: .infinity)
    }
}

private struct NowPlayingDetails: View {
    let snapshot: SoloistSnapshot
    let connect: SpotifyConnectController
    private let coverSize: CGFloat = 268

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CoverArt(url: snapshot.coverURL, size: coverSize)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 5) {
                Text(snapshot.hasTrack ? snapshot.title : "没有在播放").font(.title3).bold().lineLimit(2)
                ArtistLinks(artists: snapshot.artists, fallback: snapshot.artist)
                HStack(spacing: 4) {
                    AlbumLink(album: snapshot.album ?? (connect.queuedCurrent?.uri == snapshot.uri ? connect.queuedCurrent?.album : nil))
                    if let year = snapshot.releaseYear ?? (connect.queuedCurrent?.uri == snapshot.uri ? connect.queueYear : nil) {
                        Text("· \(year)")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
