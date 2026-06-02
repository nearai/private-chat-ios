import SwiftUI

// MARK: - Claude Design Source Carousel

/// Snap-paged source carousel rendered above a web-grounded assistant reply.
/// Spec: 280×88 cards, 16r, panel bg, 1px border, 20px favicon, numbered
/// circular badge (white on action), 2-line 15pt SemiBold title, 13pt domain.
struct SourceCarousel: View {
    let sources: [WebSearchSource]
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                    SourceCard(index: index + 1, source: source)
                        .onTapGesture { onSelect(index) }
                }
            }
            .padding(.trailing, 24)
        }
        .scrollClipDisabled()
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
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 2)
                Spacer(minLength: 0)
                Text(source.displaySubtitle)
                    .font(.footnote)
                    .fontWeight(.regular)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 280, height: 88, alignment: .topLeading)
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
        .frame(width: 304, height: 112, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityLabel("Source \(index), \(source.displayTitle), \(source.host)")
    }
}

struct FaviconBadge: View {
    let source: WebSearchSource

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.appSecondaryBackground)
            fallback
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var fallback: some View {
        Text(source.sourceInitials.prefix(1))
            .font(.caption)
            .fontWeight(.heavy)
            .foregroundStyle(Color.textSecondary)
    }
}
