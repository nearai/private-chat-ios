import SwiftUI

struct ClaudeThreadRow: View {
    let conversation: ConversationSummary
    let preview: String
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(conversation.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    Text(timestampText)
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }

                Text(preview)
                    .font(.footnote)
                    .fontWeight(.regular)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.top, 11)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .frame(minHeight: 64, alignment: .center)
            .contentShape(Rectangle())

            if !isLast {
                Rectangle()
                    .fill(Color.appHairline)
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)
            }
        }
        .background(Color.appBackground)
    }

    private var timestampText: String {
        guard let createdAt = conversation.createdAt else { return "Recent" }
        let date = Date(timeIntervalSince1970: createdAt)
        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 60 {
            return "Just now"
        }
        if elapsed < 3600 {
            return "\(Int(elapsed / 60))m"
        }
        if elapsed < 86_400 {
            return "\(Int(elapsed / 3600))h"
        }
        if elapsed < 172_800 {
            return "Yesterday"
        }
        if elapsed < 604_800 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct ClaudeHomeEmptyState: View {
    let title: String
    let showsAction: Bool
    let action: () -> Void

    var body: some View {
        // Spec (home.jsx EmptyView):
        //   gridTemplateRows: "1fr auto 0.85fr"
        //   paddingBottom: 56
        //
        // Translated: top spacer and bottom region split the remaining
        // height in a 1 : 0.85 ratio (top gets 54%, bottom 46%). The
        // mark+caption block sits between them with padding-top 30; the
        // CTA pins to the bottom of the lower region with the 56pt
        // padding accounting for the home indicator.
        GeometryReader { proxy in
            let bottomPadding: CGFloat = 56
            let contentHeight: CGFloat = 30 + 64 + 18 + 20 // padding-top + mark + gap + caption line
            let ctaHeight: CGFloat = showsAction ? 52 : 0
            let remaining = max(0, proxy.size.height - contentHeight - ctaHeight - bottomPadding)
            let topSpacer = remaining * (1.0 / 1.85)
            let bottomSpacer = remaining * (0.85 / 1.85)

            VStack(spacing: 0) {
                Color.clear.frame(height: topSpacer)

                VStack(spacing: 18) {
                    NearAppIconMark(size: 64)
                        .accessibilityHidden(true)

                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 30)

                Color.clear.frame(height: bottomSpacer)

                if showsAction {
                    Button(action: action) {
                        Text("Start a new chat")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.actionPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: Color.actionPrimary.opacity(0.18), radius: 12, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.bottom, bottomPadding)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(minHeight: 560)
    }
}

struct HomeEmptyState: View {
    let title: String
    let subtitle: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 30)

            VStack(spacing: 14) {
                PrivacySeal(size: 64)
                    .accessibilityHidden(true)

                VStack(spacing: 7) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
            }

            Spacer(minLength: 28)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.actionPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 420)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
    }
}

