import SwiftUI

struct ChipFlowLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    init(spacing: CGFloat = 6, lineSpacing: CGFloat = 6) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var measuredWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = lineWidth == 0 ? size.width : lineWidth + spacing + size.width

            if lineWidth > 0, nextWidth > maxWidth {
                measuredWidth = max(measuredWidth, lineWidth)
                totalHeight += lineHeight + lineSpacing
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth = nextWidth
                lineHeight = max(lineHeight, size.height)
            }
        }

        measuredWidth = max(measuredWidth, lineWidth)
        totalHeight += lineHeight
        return CGSize(width: proposal.width ?? measuredWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let leadingSpace = x == bounds.minX ? 0 : spacing

            if x > bounds.minX, x + leadingSpace + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }

            let point = CGPoint(x: x + (x == bounds.minX ? 0 : spacing), y: y)
            subview.place(at: point, proposal: ProposedViewSize(width: size.width, height: size.height))
            x = point.x + size.width
            lineHeight = max(lineHeight, size.height)
        }
    }
}
