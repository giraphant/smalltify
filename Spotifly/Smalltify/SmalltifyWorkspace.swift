import SwiftUI

struct SmalltifyWorkspace: View {
    @Bindable var model: SmalltifyModel

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<String?>(get: { model.selected }, set: { if let value = $0 { model.navigate(value) } })) {
                Label("喜欢的歌曲", systemImage: "heart").tag("liked")
                Label("我的歌单", systemImage: "music.note.list").tag("playlists")
                Label("收藏专辑", systemImage: "square.stack").tag("albums")
                Label("搜索", systemImage: "magnifyingglass").tag("search")
                Divider()
                Label("设置与连接", systemImage: "gearshape").tag("settings")
            }
            .navigationTitle("Smalltify")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            VStack(spacing: 0) {
                if let message = model.error {
                    SmalltifyMessage(message: message, isError: true) { model.error = nil }
                }
                if let message = model.notice {
                    SmalltifyMessage(message: message, isError: false) { model.notice = nil }
                }
                if model.selected == "settings" {
                    SmalltifySettings(model: model)
                } else {
                    SmalltifyCatalog(model: model)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SmalltifyPlayerBar(player: model.player)
                .background(.bar)
        }
        .frame(minWidth: 850, minHeight: 620)
    }
}

struct SmalltifyMessage: View {
    let message: String
    let isError: Bool
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: isError ? "exclamationmark.triangle" : "info.circle")
            Text(message).textSelection(.enabled)
            Spacer()
            Button("关闭提示", systemImage: "xmark", action: dismiss).labelStyle(.iconOnly)
        }
        .font(.callout)
        .padding()
        .background(isError ? Color.orange.opacity(0.12) : Color.accentColor.opacity(0.08))
    }
}

struct SmalltifyCatalog: View {
    @Bindable var model: SmalltifyModel

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                if model.collection != nil {
                    Button("返回", systemImage: "chevron.left") { model.navigate(model.selected) }
                }
                Text(model.title).font(.title2).bold().lineLimit(1)
                Spacer()
                if let collection = model.collection {
                    Button("播放歌单或专辑", systemImage: "play.fill") { model.player.control("play", uri: collection.uri) }
                        .disabled(!model.player.canControl)
                }
                Button("刷新", systemImage: "arrow.clockwise") { model.refresh() }
                    .labelStyle(.iconOnly).disabled(!model.signedIn || model.loading)
            }
            .padding([.horizontal, .top])

            if model.selected == "search", model.collection == nil {
                HStack {
                    TextField("歌曲、歌手或专辑名称", text: $model.query).onSubmit { model.search() }
                    Picker("搜索类型", selection: $model.searchType) {
                        Text("歌曲").tag("track")
                        Text("专辑").tag("album")
                        Text("歌单").tag("playlist")
                    }
                    .labelsHidden().frame(width: 100)
                    Button("搜索") { model.search() }.disabled(!model.signedIn)
                }
                .padding(.horizontal)
            }

            if !model.signedIn {
                ContentUnavailableView {
                    Label("连接 Spotify 文库", systemImage: "music.note.list")
                } description: {
                    Text("在设置中填写你的 Client ID 并授权，即可搜索和读取收藏。")
                } actions: {
                    Button("打开设置") { model.navigate("settings") }
                }
            } else if model.items.isEmpty, !model.loading {
                ContentUnavailableView("暂无曲目", systemImage: "music.note", description: Text(model.selected == "search" ? "输入关键词后按回车搜索。" : "可刷新重试；如果上方有错误，请先处理连接或权限问题。"))
            } else {
                List {
                    ForEach(model.items.enumerated(), id: \.offset) { _, item in
                        SmalltifyCatalogRow(item: item, player: model.player) { model.openCollection(item) }
                    }
                    if model.nextPage != nil {
                        HStack {
                            Spacer()
                            Button("加载更多") { model.loadMore() }.disabled(model.loading)
                            Spacer()
                        }
                    }
                }
                .listStyle(.plain)
            }
            if model.loading { ProgressView().controlSize(.small).padding() }
            Divider()
            HStack {
                TextField("粘贴 Spotify 歌曲、专辑或歌单链接", text: $model.directLink).onSubmit { model.playLink() }
                Button("播放链接", systemImage: "play.fill") { model.playLink() }
                    .disabled(!model.player.canControl)
            }
            .padding([.horizontal, .bottom])
        }
    }
}

struct SmalltifyCatalogRow: View {
    let item: CatalogItem
    let player: SoloistController
    let open: () -> Void

    var body: some View {
        HStack {
            AsyncImage(url: item.imageURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: item.isCollection ? "square.stack" : "music.note")
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary)
            }
            .frame(width: 40, height: 40).clipShape(.rect(cornerRadius: 5))
            VStack(alignment: .leading) {
                Text(item.name).lineLimit(1)
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if item.isCollection { Button("查看曲目", systemImage: "list.bullet", action: open).labelStyle(.iconOnly) }
            Button("播放", systemImage: "play.fill") { player.control("play", uri: item.uri) }
                .labelStyle(.iconOnly).disabled(!player.canControl)
            if item.kind == "track" {
                Button("加入队列", systemImage: "text.line.last.and.arrowtriangle.forward") { player.control("add_to_queue", uri: item.uri) }
                    .labelStyle(.iconOnly).disabled(!player.canControl)
            }
        }
        .padding(.vertical, 4)
    }
}
