import AppKit
import SwiftUI

struct AddShortcutSheet: View {
    @Environment(SmalltifyModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var recognition = LinkRecognition()
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("存到常用歌单").font(.headline)
            Text("保存每周新发现、新歌雷达等歌单链接，之后在侧边栏直接播放。歌单内容随 Spotify 更新。")
                .font(.callout).foregroundStyle(.secondary)
            LabeledContent("歌单名称") {
                TextField("留空时使用歌单名称", text: $name).textFieldStyle(.roundedBorder)
                Menu("常用名称") {
                    Button("每周新发现") { name = "每周新发现" }
                    Button("新歌雷达") { name = "新歌雷达" }
                }.fixedSize()
            }
            LinkInputView(recognition: recognition, playlistsOnly: true, submit: save)
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Text("相同链接再次保存会更新名称。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(recognition.link?.kind != "playlist" || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500)
        .onChange(of: recognition.preview) { _, preview in
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let preview, preview.item.kind == "playlist" {
                name = preview.item.name
            }
            #if DEBUG
                if DebugFixtures.opens("shortcut-save"), preview?.item.kind == "playlist" { save() }
            #endif
        }
        .onChange(of: recognition.input) { error = nil }
        .onAppear {
            #if DEBUG
                if DebugFixtures.isEnabled {
                    recognition.update(FixtureData.settingsInput(shortcut: true))
                    return
                }
            #endif
            if recognition.input.isEmpty, let text = NSPasteboard.general.string(forType: .string), SpotifyLink(text)?.kind == "playlist" {
                recognition.update(text)
            }
        }
    }

    private func save() {
        do {
            try model.playlistShortcuts.save(name: name, link: recognition.input)
            model.notices.toast("已存到常用歌单")
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
