import SwiftUI

/// A row of the sidebar: a section of the library, or a saved playlist shortcut.
nonisolated enum SidebarItem: Hashable {
    case section(SidebarSection)
    case shortcut(String)
}

/// 首页, the library sections, the saved playlists, and in the footer the connection status
/// and the account.
struct SmalltifySidebar: View {
    @Bindable var model: SmalltifyModel
    @State private var addingShortcut = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        List(selection: selection) {
            row(.home)
            Section("文库") {
                ForEach([SidebarSection.liked, .playlists, .albums, .artists], id: \.self, content: row)
            }
            Section {
                ForEach(model.playlistShortcuts.playlists) { shortcut in
                    ShortcutRow(shortcut: shortcut)
                        .tag(SidebarItem.shortcut(shortcut.uri))
                        .onTapGesture { open(shortcut) }
                }
            } header: {
                HStack {
                    Text("常用歌单")
                    Spacer()
                    Button("保存歌单链接", systemImage: "plus") { addingShortcut = true }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("保存歌单链接")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .sheet(isPresented: $addingShortcut) {
            AddShortcutSheet()
                .environment(model)
        }
        #if DEBUG
            .task { if DebugFixtures.opens("shortcut") { addingShortcut = true } }
        #endif
    }

    private func row(_ section: SidebarSection) -> some View {
        Label(section.title, systemImage: section.symbol)
            .tag(SidebarItem.section(section))
            // Selection only changes on a different row; a click on the highlighted row must
            // still leave a detail page for the section's own list.
            .contentShape(.rect)
            .onTapGesture { model.navigator.go(section.route) }
    }

    private var selection: Binding<SidebarItem?> {
        Binding {
            let route = model.navigator.current
            if case let .playlist(item) = route, model.playlistShortcuts.playlists.contains(where: { $0.uri == item.uri }) {
                return .shortcut(item.uri)
            }
            return route.section.map(SidebarItem.section)
        } set: { item in
            switch item {
            case let .section(section)?: model.navigator.go(section.route)
            case let .shortcut(uri)?:
                if let shortcut = model.playlistShortcuts.playlists.first(where: { $0.uri == uri }) { open(shortcut) }
            case nil: break
            }
        }
    }

    private func open(_ shortcut: SavedPlaylist) {
        model.navigator.go(.playlist(CatalogItem(uri: shortcut.uri, name: shortcut.name, subtitle: "", kind: "playlist", durationMS: 0, imageURL: nil)))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { openSettings() } label: {
                HStack(spacing: 6) {
                    Circle().fill(model.connectionStatus.tone.color).frame(width: 7, height: 7)
                    Text(model.connectionStatus.text).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 8))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("打开设置")

            if let profile = model.profile {
                HStack(spacing: 8) {
                    CoverArt(url: profile.imageURL, size: 24, shape: .circle)
                    Text(profile.displayName).lineLimit(1)
                }
                .padding(.horizontal, 6)
            }
        }
        .padding(10)
    }
}

/// A saved playlist: its name, and a play button that shows on hover.
private struct ShortcutRow: View {
    let shortcut: SavedPlaylist
    @Environment(SmalltifyModel.self) private var model
    @State private var hovering = false

    var body: some View {
        HStack {
            Label(shortcut.name, systemImage: "music.note.list")
                .lineLimit(1)
            Spacer(minLength: 4)
            if hovering {
                Button("播放 \(shortcut.name)", systemImage: "play.fill") { model.play(uri: shortcut.uri) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
        }
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("播放") { model.play(uri: shortcut.uri) }
            Button("复制链接") {
                model.copyLink(URL(string: "https://open.spotify.com/playlist/\(shortcut.uri.split(separator: ":").last ?? "")"))
            }
            Divider()
            Button("从常用歌单移除", role: .destructive) {
                do { try model.playlistShortcuts.remove(shortcut) } catch { model.notices.show(.init(message: error.localizedDescription)) }
            }
        }
    }
}

extension ConnectionStatus.Tone {
    var color: Color {
        switch self {
        case .ok: .green
        case .busy: .orange
        case .warn: .orange
        case .error: .red
        }
    }
}
