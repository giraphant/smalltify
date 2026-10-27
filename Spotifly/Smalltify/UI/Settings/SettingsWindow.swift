import SwiftUI

/// The ⌘, window. Placeholder: the previous settings form until W5 builds 连接 / 关于.
struct SettingsWindow: View {
    let model: SmalltifyModel

    var body: some View {
        SmalltifySettings(model: model)
            .frame(width: 650, height: 640)
    }
}

/// The toolbar's paste-a-link popover. Placeholder until W5 adds recognition and saving.
struct PasteLinkPopover: View {
    let dismiss: () -> Void
    @Environment(SmalltifyModel.self) private var model
    @State private var link = ""

    var body: some View {
        HStack {
            TextField("粘贴 Spotify 链接", text: $link)
                .frame(width: 300)
                .onSubmit(play)
            Button("播放", action: play)
        }
        .padding()
    }

    private func play() {
        if model.play(link: link) { dismiss() }
    }
}

/// The sidebar's "+": saves a playlist link as a shortcut. Placeholder until W5 builds it.
struct AddShortcutSheet: View {
    @Environment(SmalltifyModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            PlaylistShortcutsSection(shortcuts: model.playlistShortcuts, player: model.player, suggestedLink: "")
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 360)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
        }
    }
}
