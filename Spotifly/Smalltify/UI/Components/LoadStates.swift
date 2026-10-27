import SwiftUI

/// A page's content once its loader has something to show, and the states before that:
/// signed out, first load, failure, and nothing there.
struct LoadedContent<Content: View>: View {
    let loader: PagedLoader
    var emptyTitle = "这里还没有内容"
    var emptyDescription = ""
    @ViewBuilder let content: Content
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        if !model.signedIn {
            SignedOutView()
        } else if let failure = loader.failure, loader.items.isEmpty {
            PageFailureView(message: failure) { loader.refresh() }
        } else if loader.items.isEmpty, loader.phase != .loaded {
            LoadingRows()
        } else if loader.items.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: "music.note", description: Text(emptyDescription))
        } else {
            content
        }
    }
}

/// "连接你的 Spotify 账号": the library needs authorization before anything shows.
struct SignedOutView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ContentUnavailableView {
            Label("连接你的 Spotify 账号", systemImage: "person.crop.circle.badge.questionmark")
        } description: {
            Text("授权后才能读取文库和搜索。")
        } actions: {
            Button("打开设置") { openSettings() }
                .buttonStyle(.borderedProminent)
        }
    }
}

struct PageFailureView: View {
    var title = "没能加载"
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message).textSelection(.enabled)
        } actions: {
            Button("重试", action: retry)
        }
    }
}

/// Placeholder rows while a list's first page loads.
struct LoadingRows: View {
    var count = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(0 ..< count, id: \.self) { _ in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 5).frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).frame(width: 180, height: 10)
                        RoundedRectangle(cornerRadius: 3).frame(width: 110, height: 8)
                    }
                }
            }
            Spacer()
        }
        .foregroundStyle(.quaternary)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel("正在加载")
    }
}

/// The end of a paged list: loading the next page, its failure, or a button to load it.
struct LoaderFooter: View {
    let loader: PagedLoader
    /// "首" for tracks, "个" for albums and playlists.
    var unit = "个"
    var pageSize = 50
    /// Search pages say how many: "加载更多 10 条".
    var moreTitle = "加载更多"

    var body: some View {
        HStack {
            Spacer()
            if loader.loadingMore {
                ProgressView().controlSize(.small)
                Text("正在加载第 \(loader.items.count + 1)–\(loader.items.count + pageSize) \(unit)")
                    .foregroundStyle(.secondary)
            } else if let error = loader.loadMoreError {
                Text(error).foregroundStyle(.secondary).lineLimit(2)
                Button("重试") { loader.loadMore() }
            } else if loader.next != nil {
                Button(moreTitle) { loader.loadMore() }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
            Spacer()
        }
        .font(.callout)
        .padding(.vertical, 8)
    }
}
