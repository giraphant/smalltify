import SwiftUI

/// How wide one column of a `ColumnsLayout` is: a fixed width, or a share of what is left.
nonisolated enum ColumnWidth: Equatable, Sendable {
    case fixed(CGFloat)
    case flexible(CGFloat)
}

private nonisolated struct ColumnWidthKey: LayoutValueKey {
    static let defaultValue = ColumnWidth.flexible(1)
}

extension View {
    func column(_ width: ColumnWidth) -> some View {
        layoutValue(key: ColumnWidthKey.self, value: width)
    }
}

/// Lays out a row's cells as table columns: fixed columns take their width, flexible ones share
/// the rest by weight. Every row and the header use the same specs, so the columns line up.
struct ColumnsLayout: Layout {
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? 640
        let widths = columnWidths(total: width, subviews: subviews)
        let height = zip(subviews, widths).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, columnWidths(total: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }

    private func columnWidths(total: CGFloat, subviews: Subviews) -> [CGFloat] {
        let specs = subviews.map { $0[ColumnWidthKey.self] }
        let fixed = specs.reduce(CGFloat(0)) { if case let .fixed(width) = $1 { $0 + width } else { $0 } }
        let weights = specs.reduce(CGFloat(0)) { if case let .flexible(weight) = $1 { $0 + weight } else { $0 } }
        let spare = max(0, total - fixed - spacing * CGFloat(max(0, specs.count - 1)))
        return specs.map {
            switch $0 {
            case let .fixed(width): width
            case let .flexible(weight): weights > 0 ? spare * weight / weights : 0
            }
        }
    }
}
