import AppKit
import SwiftUI

struct PasteLinkPopover: View {
    let dismiss: () -> Void
    @Environment(SmalltifyModel.self) private var model
    @State private var recognition = LinkRecognition()
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("粘贴 Spotify 链接").bold()
            LinkInputView(recognition: recognition, submit: play)
            if !recognition.isInvalid {
                Text("支持 open.spotify.com 和 spotify: 链接：歌曲、专辑、歌单、播客单集。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    if recognition.link?.kind == "playlist" {
                        Button("存到常用歌单", action: save)
                            .disabled(recognition.preview == nil)
                    }
                    Button("播放", action: play)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(recognition.link == nil)
                }
            }
            if let saveError { Text(saveError).font(.callout).foregroundStyle(.red) }
        }
        .padding(16)
        .frame(width: 410)
        .onAppear {
            guard recognition.input.isEmpty else { return }
            #if DEBUG
                if DebugFixtures.isEnabled {
                    recognition.update(FixtureData.settingsInput(shortcut: false))
                    return
                }
            #endif
            if let text = NSPasteboard.general.string(forType: .string), SpotifyLink(text) != nil {
                recognition.update(text)
            }
        }
    }

    private func play() {
        guard let link = recognition.link else { return }
        model.play(uri: recognition.preview?.item.uri ?? link.uri)
        dismiss()
    }

    private func save() {
        guard let preview = recognition.preview, preview.item.kind == "playlist" else { return }
        do {
            try model.playlistShortcuts.save(name: preview.item.name, link: preview.item.uri)
            model.notices.toast("已存到常用歌单")
            dismiss()
        } catch { saveError = error.localizedDescription }
    }
}
