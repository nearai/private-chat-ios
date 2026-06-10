import SwiftUI

#if DEBUG
/// Permanent layout-regression surface: renders the exact markdown shapes that
/// clipped or bled in TestFlight build 5 (long bullets, wide tables, source
/// carousels) inside the same width containers the real chat uses. Captured by
/// the release gate at iPhone width — nothing here may overflow or ellipsize.
struct DemoMarkdownGalleryView: View {
    private static let failingCorpus = """
    ## Origin & Meaning

    - The name is **toponymic** — derived from a place or geographic feature.
    - According to *Wisdom Library*, it broadly refers to **"someone from a hilly area"** or a person associated with a hilly/mountainous landscape, fitting with the Garhwal Himalayas region.
    - **Protective provisions:** Investor consent rights over new debt, option pool expansion, and changes to the certificate of incorporation.

    ### Where Emphasis Differed

    | Version | What it foregrounded |
    | --- | --- |
    | #1 (first reply) | Balanced — led with the ceasefire framework and the timeline of strikes |
    | #2 (plain prose) | Military framing first, then markets and the diplomatic backdrop |
    | #3 (briefing style) | Diplomatic breakdown with quoted statements from each principal |

    ### Wide table

    | Term | Value | Notes | Owner | Due |
    | --- | --- | --- | --- | --- |
    | Board seats | 2 founders, 1 investor | Confirm investor vs. founder control balance before signing | CEO | Friday |
    | Vesting reset | Full or partial credit | Acceleration: single vs. double trigger on change of control | Counsel | Next week |

    1. Confirm investor vs. founder board control balance before signing the term sheet.
    2. Quarterly information rights plus an annual inspection right with reasonable notice.
    """

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                gallerySection("Bare column") {
                    MarkdownMessageText(text: Self.failingCorpus)
                }

                gallerySection("Bubble replica (maxWidth 740)") {
                    MarkdownMessageText(text: Self.failingCorpus)
                        .frame(maxWidth: 740, alignment: .leading)
                }

                gallerySection("Streaming tail (sanitized)") {
                    StreamingMarkdownText(text: "## Direct answer\n\nThe council **broadly agrees** the framework holds.\n\nStill streaming with **unclosed bold and a dangling heading marker: ## Disagreem")
                }

                gallerySection("Source carousel") {
                    SourceCarousel(sources: [
                        WebSearchSource(type: nil, url: "https://www.reuters.com/world/middle-east", title: "Iran War: Latest Breaking News, Updates & Analysis", publishedAt: nil, snippet: nil),
                        WebSearchSource(type: nil, url: "https://news.google.com/stories/abc", title: "What is happening on day 96 of the war as US, Iran engage", publishedAt: nil, snippet: nil),
                        WebSearchSource(type: nil, url: "https://www.bbc.com/news/world", title: "Strait of Hormuz reopening talks continue", publishedAt: nil, snippet: nil)
                    ], onSelect: { _ in })
                }
            }
            .padding(16)
        }
        .background(Color.appBackground)
        .accessibilityIdentifier("gallery.root")
    }

    private func gallerySection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.4)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
