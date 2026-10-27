import SwiftUI

/// An album, playlist or artist as a card: artwork, then its name and a line about it.
/// A click opens it; the context menu plays it or shares it.
struct CatalogCard: View {
    let item: CatalogItem
    var size: CGFloat = 150
    /// The line under the name; the item's subtitle when nil.
    var detail: String?
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        Button { model.open(item) } label: {
            VStack(alignment: item.kind == "artist" ? .center : .leading, spacing: 6) {
                CoverArt(item: item, size: size)
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                VStack(alignment: item.kind == "artist" ? .center : .leading, spacing: 1) {
                    Text(item.name)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    // Artists show only an explicit line, such as the home page's 歌手.
                    if item.kind != "artist" || detail != nil {
                        Text(detail ?? item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(width: size, alignment: item.kind == "artist" ? .center : .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(item.name)
        .contextMenu { CardMenu(item: item) }
    }
}

struct CardMenu: View {
    let item: CatalogItem
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        if item.isPlayable {
            Button("播放") { model.play(uri: item.uri) }
        }
        Button("打开") { model.open(item) }
        Divider()
        Button("复制链接") { model.copyLink(item.openURL) }
        Button("在 Spotify 中打开") { model.openInSpotify(item.openURL) }
    }
}

/// Cards wrapping into as many columns as fit.
struct CatalogGrid: View {
    let items: [CatalogItem]
    var size: CGFloat = 150
    var detail: ((CatalogItem) -> String?)?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: size, maximum: size + 40), spacing: 16, alignment: .top)],
                  alignment: .leading, spacing: 20) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                CatalogCard(item: item, size: size, detail: detail?(item))
            }
        }
    }
}

/// One row of cards that scrolls sideways, for the home page and search's "全部" scope.
struct CatalogShelf: View {
    let items: [CatalogItem]
    var size: CGFloat = 150
    var detail: ((CatalogItem) -> String?)?

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 16) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    CatalogCard(item: item, size: size, detail: detail?(item))
                }
            }
        }
        .scrollIndicators(.never)
    }
}

/// A titled part of a scrolling page, with an optional "显示全部 ›" on the right.
struct PageSection<Content: View>: View {
    let title: String
    var showAll: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title3).bold()
                Spacer()
                if let showAll {
                    Button("显示全部 ›", action: showAll)
                        .buttonStyle(.link)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
    }
}
