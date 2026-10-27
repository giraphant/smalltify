import SwiftUI

/// The menu bar: playback, navigation and the window's panels, each with its shortcut.
struct SmalltifyCommands: Commands {
    let model: SmalltifyModel?
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        SidebarCommands()
        CommandGroup(after: .sidebar) {
            Button("正在播放") { model?.inspectorPresented.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Button("迷你播放器") { openWindow(id: MiniPlayerWindow.id) }
                .keyboardShortcut("m", modifiers: [.command, .option])
        }
        CommandMenu("播放") {
            Button("播放 / 暂停") {
                guard let player = model?.player else { return }
                player.control(player.displaySnapshot.status == "playing" ? "pause" : "play")
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(model?.player.canControl != true)
            Button("下一首") { model?.player.control("skip_next") }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(model?.player.canControl != true)
            Button("上一首") { model?.player.control("skip_prev") }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(model?.player.canControl != true)
            Divider()
            Button("随机播放") {
                guard let player = model?.player else { return }
                player.control("set_shuffle", enabled: !player.displaySnapshot.shuffle)
            }
            .disabled(model?.player.canControl != true)
            Divider()
            Button("粘贴 Spotify 链接并播放") {
                guard let text = NSPasteboard.general.string(forType: .string), model?.play(link: text) == true else {
                    model?.notices.show(.init(message: "剪贴板里没有可识别的 Spotify 链接。", tone: .warning))
                    return
                }
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        }
        CommandMenu("前往") {
            Button("后退") { model?.navigator.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(model?.navigator.canGoBack != true)
            Button("前进") { model?.navigator.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(model?.navigator.canGoForward != true)
            Divider()
            ForEach(Array(SidebarSection.allCases.enumerated()), id: \.offset) { index, section in
                Button(section.title) { model?.navigator.go(section.route) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Divider()
            Button("搜索") { focusToolbarSearchField() }
                .keyboardShortcut("f", modifiers: .command)
            Button("刷新") { model?.refreshCurrentPage() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model?.signedIn != true)
        }
    }
}
