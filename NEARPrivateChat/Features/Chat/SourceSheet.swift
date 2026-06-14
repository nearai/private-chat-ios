import SwiftUI

// MARK: - Claude Design Source Sheet (per-source half-sheet)

/// Identifies which carousel card was tapped so SwiftUI can drive an
/// `item:`-style sheet without losing identity between presentations.
struct SourceSheetPresentation: Identifiable {
    let index: Int
    let source: WebSearchSource

    var id: String { "\(index)-\(source.id)" }
}

/// Per-source half-sheet. Spec: partial detent over the chat thread, glass
/// chrome (sheet container) with solid content inside. Header is the
/// favicon + domain; body is title (17/22 SemiBold), author/date row (13/18
/// text-2), and a snippet block (15/22, surface-2 background) with the
/// cited span highlighted in --proof-stale yellow when we have one. No
/// Proof badge — route/model evidence is not answer-bound until messages carry proof metadata.
struct SourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let index: Int
    let source: WebSearchSource

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(source.displayTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("source.sheet.title")

                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .font(.caption.weight(.semibold))
                        Text(source.host)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Source host \(source.host)")
                    .accessibilityIdentifier("source.sheet.host")

                    if let metaLine, !metaLine.isEmpty {
                        Text(metaLine)
                            .font(.footnote)
                            .fontWeight(.regular)
                            .foregroundStyle(Color.textSecondary)
                            .accessibilityIdentifier("source.sheet.meta")
                    }

                    if let snippet = source.snippetFallback {
                        Text(snippet)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineSpacing(7)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityIdentifier("source.sheet.snippet")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }

            actionStack
        }
        .background(Color.appPanelBackground)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            FaviconBadge(source: source)
            Text(source.host)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .accessibilityIdentifier("source.sheet.headerHost")
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("source.sheet.close")
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(height: 44)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var actionStack: some View {
        VStack(spacing: 4) {
            Button {
                if let url = source.safeURL { openURL(url) }
            } label: {
                HStack(spacing: 6) {
                    Text("Open in Safari")
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.actionPrimary, in: RoundedRectangle.app(AppRadius.control))
            }
            .buttonStyle(.plain)
            .disabled(source.safeURL == nil)
            .accessibilityIdentifier("source.sheet.open")

            Button {
                if let url = source.safeURL { Clipboard.copy(url.absoluteString) }
            } label: {
                Text("Copy link")
                    .font(.headline)
                    .foregroundStyle(Color.actionPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.plain)
            .disabled(source.safeURL == nil)
            .accessibilityIdentifier("source.sheet.copyLink")

            Button {
                Clipboard.copy(source.citationCopyText)
            } label: {
                Text("Copy citation")
                    .font(.headline)
                    .foregroundStyle(Color.actionPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("source.sheet.copyCitation")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    private var metaLine: String? {
        var parts: [String] = []
        if let published = source.publishedAt?.trimmingCharacters(in: .whitespacesAndNewlines), !published.isEmpty {
            parts.append(published)
        }
        if parts.isEmpty { return nil }
        return parts.joined(separator: " · ")
    }
}

private extension WebSearchSource {
    var snippetFallback: String? {
        snippetPreview
    }
}
