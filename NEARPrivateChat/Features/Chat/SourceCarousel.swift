import SwiftUI

// MARK: - Claude Design Source Carousel

/// Snap-paged source carousel rendered above a web-grounded assistant reply.
/// Spec: 280×88 cards, 16r, panel bg, 1px border, 20px favicon, numbered
/// circular badge (white on action), 2-line 15pt SemiBold title, 13pt domain.
struct SourceCarousel: View {
    let sources: [WebSearchSource]
    let onSelect: (Int) -> Void

    var body: some View {
        // Clipped + width-constrained: .scrollClipDisabled() let 300pt cards
        // draw past the screen edge and bleed out of the bubble column.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                    SourceCard(index: index + 1, source: source)
                        .onTapGesture { onSelect(index) }
                }
            }
        }
        .contentMargins(.trailing, 24, for: .scrollContent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("sources.carousel")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(sources.count) source\(sources.count == 1 ? "" : "s")")
    }
}

private struct SourceCard: View {
    let index: Int
    let source: WebSearchSource

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                FaviconBadge(source: source)
                Text(source.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Text(source.displaySubtitle)
                        .font(.footnote)
                        .fontWeight(.regular)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let badge = source.sourceBadgeLabel {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.actionPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.actionPrimary.opacity(0.10), in: Capsule())
                    }
                }
            }
            .frame(width: 260, alignment: .topLeading)
            .frame(minHeight: 88)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 1)
            }

            Text("\(index)")
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.actionPrimary, in: Circle())
                .padding(12)
        }
        .frame(width: 284, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityLabel("Source \(index), \(source.displayTitle), \(source.host)")
    }
}

struct FaviconBadge: View {
    let source: WebSearchSource

    var body: some View {
        SourceFaviconView(
            domain: source.host,
            size: 20,
            fallbackText: String(source.sourceInitials.prefix(1)),
            cornerRadius: 5,
            allowsNetworkFavicon: source.allowsNetworkFavicon
        )
    }
}
