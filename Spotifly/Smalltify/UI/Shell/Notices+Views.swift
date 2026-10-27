import SwiftUI

/// The one error banner, at the top of the page: the model's, else the player's or Connect's.
struct BannerView: View {
    let model: SmalltifyModel

    var body: some View {
        if let banner = model.notices.banner {
            BannerRow(message: banner.message, tone: banner.tone, actions: banner.actions) {
                model.notices.dismissBanner()
            }
        } else if let error = model.player.error {
            BannerRow(message: "播放器出错：\(error)", tone: .error, actions: []) { model.player.error = nil }
        } else if let error = model.connect.error {
            BannerRow(message: error, tone: .warning, actions: []) { model.connect.error = nil }
        }
    }
}

private struct BannerRow: View {
    let message: String
    let tone: Notices.Banner.Tone
    let actions: [Notices.Action]
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tone == .error ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(tone == .error ? .red : .orange)
            Text(message)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(actions) { action in
                Button(action.title) { action.perform() }
            }
            Button("关闭", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background((tone == .error ? Color.red : Color.orange).opacity(0.1))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// The toast above the player bar, gone after `Notices.toastDuration`.
struct ToastView: View {
    let notices: Notices

    var body: some View {
        ZStack {
            if let toast = notices.toast {
                Label {
                    Text(toast)
                } icon: {
                    Image(systemName: notices.toastIsError ? "exclamationmark.triangle.fill" : "checkmark")
                        .foregroundStyle(notices.toastIsError ? Color.red : Color.accentColor)
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast)
            }
        }
        .padding(.bottom, 16)
        .animation(.snappy, value: notices.toast)
        .allowsHitTesting(false)
    }
}
