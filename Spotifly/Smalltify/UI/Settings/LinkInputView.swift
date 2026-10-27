import SwiftUI

struct LinkInputView: View {
    @Bindable var recognition: LinkRecognition
    var playlistsOnly = false
    var submit: () -> Void
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(playlistsOnly ? "Spotify 歌单链接" : "粘贴 Spotify 链接", text: Binding(
                get: { recognition.input }, set: { recognition.update($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .overlay {
                if recognition.isInvalid {
                    RoundedRectangle(cornerRadius: 5).stroke(.red, lineWidth: 1).allowsHitTesting(false)
                }
            }
            .onSubmit(submit)
            if recognition.isInvalid {
                Text("无法识别这个链接。").foregroundStyle(.red)
            } else if playlistsOnly, let link = recognition.link, link.kind != "playlist" {
                Text("请粘贴 Spotify 歌单链接。").foregroundStyle(.red)
            } else if recognition.loading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("正在读取链接…").foregroundStyle(.secondary)
                }
            } else if let preview = recognition.preview {
                HStack(spacing: 8) {
                    CoverArt(item: preview.item, size: 28)
                    Text(preview.line).foregroundStyle(.secondary).lineLimit(2).help(preview.line)
                }
            } else if let error = recognition.error {
                HStack {
                    Text(error).foregroundStyle(.red)
                    Button("重试") { Task { await recognition.load(api: model.api, report: model.report) } }
                }
            }
        }
        .font(.callout)
        .task(id: recognition.input) { await recognition.load(api: model.api, report: model.report) }
    }
}
