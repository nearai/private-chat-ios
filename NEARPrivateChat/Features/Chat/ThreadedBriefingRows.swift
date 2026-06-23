import SwiftUI

// MARK: - Subviews

struct ThreadDayDivider: View {
    let label: String
    var body: some View {
        Text(label.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(Color.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }
}

struct BotDeliveryRow: View {
    let delivery: BriefingDelivery
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ThreadSourceAvatar(letter: "N", color: Color.actionPrimary)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text("NEAR")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(delivery.timeLabel)
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    if delivery.unread {
                        HStack(spacing: 4) {
                            Circle().fill(statusAccent).frame(width: 6, height: 6)
                            Text(delivery.isFailure ? "failed" : "new")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(statusAccent)
                        }
                    }
                }

                if delivery.isFailure {
                    failureCard
                } else if showsPendingCard {
                    pendingCard
                } else if let widget = delivery.widget {
                    MessageWidgetCard(widget: widget)
                        .padding(.top, 2)
                    deliveryMetadata
                } else if let headline = delivery.headline {
                    ThreadDeliveryStoryCard(
                        title: delivery.title,
                        headline: headline,
                        summary: delivery.summary,
                        extra: delivery.extra,
                        sources: delivery.sources
                    )
                    deliveryMetadata
                } else if let body = delivery.body {
                    Text(delivery.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if delivery.headline == nil && delivery.widget == nil && !showsPendingCard {
                    deliveryMetadata
                }
            }
        }
        .opacity(delivery.collapsed ? 0.5 : 1)
    }

    @ViewBuilder
    private var deliveryMetadata: some View {
        HStack(spacing: 8) {
            if !delivery.sources.isEmpty {
                ThreadVerifiedFooter(
                    model: delivery.verifiedModel,
                    sources: delivery.sources.count,
                    ago: delivery.timeLabel
                )
            } else if let sourceStatusText = delivery.sourceStatusText, delivery.widget != nil, !delivery.isFailure {
                ThreadSourceStatusPill(
                    text: sourceStatusText,
                    symbolName: "checkmark.seal",
                    foreground: Color.actionPrimary,
                    background: Color.actionFill.opacity(0.55)
                )
            } else if delivery.widget != nil && !delivery.isFailure {
                ThreadSourceStatusPill(
                    text: "No source report",
                    symbolName: "exclamationmark.triangle",
                    foreground: Color.proofStaleText,
                    background: Color.proofStale.opacity(0.12)
                )
            }

            if delivery.replyCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left.fill")
                        .font(.caption2)
                    Text("\(delivery.replyCount) replies")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(Color.actionPrimary)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(Color.actionFill.opacity(0.62), in: RoundedRectangle.app(AppRadius.pill))
            }
        }
        .padding(.top, 1)
    }

    private var failureCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.proofStaleText)
                    .frame(width: 30, height: 30)
                    .background(Color.proofStale.opacity(0.14), in: RoundedRectangle.app(AppRadius.control))

                VStack(alignment: .leading, spacing: 4) {
                    Text(delivery.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(delivery.summary ?? delivery.body ?? "Open the briefing to re-run or check the plan's sign-in.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let onRetry {
                Button(action: onRetry) {
                    Label("Re-run now", systemImage: "arrow.clockwise")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Color.actionPrimary, in: RoundedRectangle.app(AppRadius.pill))
                .accessibilityIdentifier("tracker.runAgain")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.control))
        .overlay {
            RoundedRectangle.app(AppRadius.control)
                .stroke(Color.proofStale.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: Color.brandBlack.opacity(0.035), radius: 8, y: 3)
    }

    private var pendingCard: some View {
        let presentation = ThreadPendingDeliveryPresentation(delivery: delivery)
        return HStack(alignment: .top, spacing: 14) {
            ThreadPendingVisual(
                kind: delivery.itemKind,
                visualLabel: presentation.visualLabel
            )

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    if let body = presentation.body {
                        Text(body)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 6) {
                    ThreadSourceStatusPill(
                        text: presentation.statusLabel,
                        symbolName: "calendar.badge.clock",
                        foreground: Color.actionPrimary,
                        background: Color.actionFill.opacity(0.64)
                    )
                    ThreadSourceStatusPill(
                        text: delivery.itemKind == .watcher ? "Watcher" : "Briefing",
                        symbolName: delivery.itemKind == .watcher ? "bell.badge.fill" : "doc.text.magnifyingglass",
                        foreground: Color.textSecondary,
                        background: Color.appSecondaryBackground
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.appPanelBackground,
                    Color.actionFill.opacity(0.42)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle.app(AppRadius.control)
        )
        .overlay {
            RoundedRectangle.app(AppRadius.control)
                .stroke(Color.actionPrimary.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: Color.brandBlack.opacity(0.055), radius: 13, y: 5)
        .accessibilityElement(children: .combine)
    }

    private var statusAccent: Color {
        delivery.isFailure ? .proofStale : .proofVerified
    }

    private var showsPendingCard: Bool {
        delivery.isPending || delivery.looksLikePendingPlaceholder
    }
}

struct ThreadPendingDeliveryPresentation: Equatable {
    let title: String
    let body: String?
    let statusLabel: String
    let visualLabel: String

    init(delivery: BriefingDelivery) {
        let isWatcher = delivery.itemKind == .watcher
        let rawTitle = delivery.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawBody = delivery.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldNormalize = delivery.isPending || delivery.looksLikePendingPlaceholder

        if shouldNormalize {
            title = isWatcher ? "Scheduled watcher" : "Scheduled briefing"
            body = Self.normalizedPendingBody(rawBody, isWatcher: isWatcher)
            statusLabel = "Scheduled"
        } else {
            title = rawTitle.isEmpty ? (isWatcher ? "Watcher" : "Briefing") : rawTitle
            body = rawBody?.nilIfEmpty
            statusLabel = delivery.timeLabel
        }
        visualLabel = isWatcher ? "WATCH" : "BRIEF"
    }

    private static func normalizedPendingBody(_ body: String?, isWatcher: Bool) -> String {
        guard let body, !body.isEmpty else {
            return isWatcher
                ? "First check scheduled. Results appear here after the next run."
                : "First brief scheduled. Delivery appears here after the next run."
        }
        let lowercased = body.lowercased()
        if lowercased.contains("no delivery yet") ||
            lowercased.contains("no check yet") ||
            lowercased.contains("will appear here after the next scheduled run") ||
            lowercased.contains("next scheduled run") {
            return isWatcher
                ? "First check scheduled. Results appear here after the next run."
                : "First brief scheduled. Delivery appears here after the next run."
        }
        return body
    }
}

private struct ThreadPendingVisual: View {
    let kind: BriefingDeliveryKind
    let visualLabel: String

    var body: some View {
        ZStack {
            RoundedRectangle.app(AppRadius.control)
                .fill(
                    LinearGradient(
                        colors: [
                            kind == .watcher ? Color(red: 0.48, green: 0.33, blue: 0.88) : Color.actionPrimary,
                            kind == .watcher ? Color.proofVerified : Color(red: 0.04, green: 0.63, blue: 0.82)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(.white.opacity(0.20))
                        .frame(width: 38, height: 38)
                        .offset(x: 12, y: -14)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(visualLabel)
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                            .tracking(0.8)
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { index in
                                Circle()
                                    .fill(.white.opacity(index == 0 ? 0.95 : 0.48))
                                    .frame(width: 4, height: 4)
                            }
                        }
                    }
                    .padding(8)
                }

            VStack(spacing: 7) {
                Image(systemName: kind == .watcher ? "bell.badge.fill" : "doc.text.magnifyingglass")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white)

                VStack(spacing: 4) {
                    Capsule().fill(.white.opacity(0.9)).frame(width: 38, height: 4)
                    HStack(spacing: 4) {
                        Capsule().fill(.white.opacity(0.58)).frame(width: 14, height: 4)
                        Capsule().fill(.white.opacity(0.78)).frame(width: 21, height: 4)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .frame(width: 92, height: 82)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.appPanelBackground)
                .frame(width: 16, height: 16)
                .overlay {
                    Circle()
                        .fill(Color.proofVerified)
                        .frame(width: 7, height: 7)
                }
                .offset(x: 4, y: -4)
        }
        .accessibilityHidden(true)
    }
}

private struct ThreadSourceStatusPill: View {
    let text: String
    let symbolName: String
    let foreground: Color
    let background: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(background, in: RoundedRectangle.app(AppRadius.pill))
    }
}

private struct ThreadDeliveryStoryCard: View {
    let title: String
    let headline: String
    let summary: String?
    let extra: String?
    let sources: [BriefingSourceTag]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(cardHeader)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)

            ForEach(Array(storyRows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: 9) {
                    rowBadge(for: index)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let body = row.body {
                            Text(body)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if index < storyRows.count - 1 {
                    Divider()
                        .overlay(Color.appHairline)
                        .padding(.leading, 25)
                }
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.control))
        .overlay {
            RoundedRectangle.app(AppRadius.control)
                .stroke(Color.appBorder.opacity(0.72), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func rowBadge(for index: Int) -> some View {
        if let source = sources[safe: index] {
            FaviconChip(source: source, size: 18)
        } else {
            Text("\(index + 1)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 18, height: 18)
                .background(Color.appSecondaryBackground, in: RoundedRectangle.app(AppRadius.pill))
        }
    }

    private var cardHeader: String {
        let normalized = title
            .replacingOccurrences(of: " · briefing", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = normalized.isEmpty ? "Briefing" : normalized
        return "\(prefix) · \(storyRows.count) item\(storyRows.count == 1 ? "" : "s")"
    }

    private var storyRows: [(title: String, body: String?)] {
        var rows: [(String, String?)] = [(headline, summary?.nilIfEmpty)]
        if let extra = extra?.nilIfEmpty {
            let extras = extra
                .replacingOccurrences(of: "+", with: "")
                .components(separatedBy: " · ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for item in extras.prefix(2) {
                rows.append((item, nil))
            }
        }
        return rows
    }
}

struct ThreadInlineView: View {
    let thread: DeliveryThread
    var onUseProxy: ((ThreadReply) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1).fill(Color.actionFill).frame(width: 2)
            VStack(alignment: .leading, spacing: 12) {
                Text("Thread · \(thread.label)".uppercased())
                    .font(.caption2.weight(.medium))
                    .tracking(0.4)
                    .foregroundStyle(Color.textTertiary)

                ForEach(thread.replies) { reply in
                    if reply.role == .user {
                        HStack {
                            Spacer(minLength: 40)
                            Text(reply.text)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.appSecondaryBackground, in: RoundedRectangle.app(AppRadius.control))
                        }
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            ThreadSourceAvatar(letter: "N", color: Color.actionPrimary, size: 20)
                            VStack(alignment: .leading, spacing: 6) {
                                if let widget = reply.widget {
                                    MessageWidgetCard(widget: widget)
                                }
                                if !reply.text.isEmpty {
                                    MarkdownMessageText(text: reply.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if !reply.citations.isEmpty {
                                    HStack(spacing: 4) {
                                        ForEach(Array(reply.citations.enumerated()), id: \.offset) { index, _ in
                                            CitePill(n: index + 1)
                                        }
                                    }
                                }
                                if let model = reply.verifiedModel {
                                    ThreadVerifiedFooter(model: model, sources: reply.verifiedSources, ago: reply.ago ?? "just now")
                                }
                                if reply.proxyModelID != nil, let onUseProxy {
                                    Button {
                                        onUseProxy(reply)
                                    } label: {
                                        Label("Use privacy proxy", systemImage: "eye.slash")
                                            .font(.footnote.weight(.semibold))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .accessibilityIdentifier("thread.useProxy")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.leading, 14)
        }
        .padding(.leading, 32)
    }
}

private struct CitePill: View {
    let n: Int
    var body: some View {
        Text("\(n)")
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(Color.actionPrimary)
            .frame(width: 16, height: 16)
            .background(Color.actionTint, in: Circle())
    }
}

private struct ThreadVerifiedFooter: View {
    let model: String?
    let sources: Int
    let ago: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.seal.fill")
                .font(.caption2)
                .foregroundStyle(Color.proofVerifiedText)
            Text(footerText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.proofVerifiedText)
        }
        .padding(.top, 2)
    }
    private var footerText: String {
        var parts = ["Verified"]
        if let model = model?.nilIfEmpty {
            parts.append(model)
        }
        if sources > 0 { parts.append("\(sources) sources") }
        parts.append(ago)
        return parts.joined(separator: " · ")
    }
}

private struct FaviconChip: View {
    let source: BriefingSourceTag
    var size: CGFloat = 14
    var body: some View {
        Text(source.letter.prefix(1))
            .font(.caption2.weight(.bold))
            .minimumScaleFactor(0.6)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(threadHexColor(source.colorHex), in: RoundedRectangle.app(AppRadius.pill))
    }
}

private struct ThreadSourceAvatar: View {
    let letter: String
    let color: Color
    var size: CGFloat = 24

    var body: some View {
        Text(letter.prefix(1).uppercased())
            .font(.system(size: max(10, size * 0.48), weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle.app(AppRadius.pill))
            .accessibilityHidden(true)
    }
}

private extension BriefingDelivery {
    var timeLabel: String {
        time == "—" ? "scheduled" : time
    }

    var looksLikePendingPlaceholder: Bool {
        guard !isFailure, widget == nil, headline == nil else { return false }
        let text = [title, body, summary]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return text.contains("no delivery yet") ||
            text.contains("no check yet") ||
            text.contains("next scheduled run")
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private func threadHexColor(_ hex: String) -> Color {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return .actionPrimary }
    return Color(
        red: Double((v >> 16) & 0xFF) / 255,
        green: Double((v >> 8) & 0xFF) / 255,
        blue: Double(v & 0xFF) / 255
    )
}
