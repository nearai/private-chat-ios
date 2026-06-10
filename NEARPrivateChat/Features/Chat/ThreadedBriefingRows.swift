import SwiftUI

// MARK: - Subviews

struct ThreadDayDivider: View {
    let label: String
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.appHairline).frame(height: 0.5)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(Color.textTertiary)
            Rectangle().fill(Color.appHairline).frame(height: 0.5)
        }
    }
}

struct BotDeliveryRow: View {
    let delivery: BriefingDelivery
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            NearMark(size: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("NEAR")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(delivery.time)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                    if delivery.unread {
                        HStack(spacing: 4) {
                            Circle().fill(statusAccent).frame(width: 6, height: 6)
                            Text(delivery.isFailure ? "failed" : "new")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(statusAccent)
                        }
                    }
                }

                Text(delivery.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                if let widget = delivery.widget {
                    // A live briefing (price/account/news) renders its real
                    // widget card here, not just a text summary.
                    MessageWidgetCard(widget: widget)
                        .padding(.top, 4)
                } else if let headline = delivery.headline {
                    Text(headline)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(delivery.isFailure ? Color.red : Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let summary = delivery.summary {
                        Text(summary)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let extra = delivery.extra {
                        Text(extra)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textTertiary)
                            .padding(.top, 2)
                    }
                } else if let body = delivery.body {
                    Text(body)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if delivery.isFailure, let onRetry {
                    Button(action: onRetry) {
                        Label("Run again", systemImage: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
                }

                if !delivery.sources.isEmpty || delivery.replyCount > 0 {
                    HStack(spacing: 8) {
                        if !delivery.sources.isEmpty {
                            HStack(spacing: 3) {
                                ForEach(delivery.sources) { FaviconChip(source: $0, size: 14) }
                            }
                        }
                        if delivery.replyCount > 0 {
                            HStack(spacing: 6) {
                                Image(systemName: "bubble.left.fill").font(.system(size: 10))
                                Text("\(delivery.replyCount) replies").font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(Color.actionPress)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(Color.actionTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .opacity(delivery.collapsed ? 0.5 : 1)
    }

    private var statusAccent: Color {
        delivery.isFailure ? .red : .proofVerified
    }
}

struct ThreadInlineView: View {
    let thread: DeliveryThread

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1).fill(Color.actionFill).frame(width: 2)
            VStack(alignment: .leading, spacing: 12) {
                Text("Thread · \(thread.label)".uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(Color.textTertiary)

                ForEach(thread.replies) { reply in
                    if reply.role == .user {
                        HStack {
                            Spacer(minLength: 40)
                            Text(reply.text)
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            NearMark(size: 20)
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
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.actionPrimary)
            .frame(width: 16, height: 16)
            .background(Color.actionTint, in: Circle())
    }
}

private struct ThreadVerifiedFooter: View {
    let model: String
    let sources: Int
    let ago: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.proofVerified)
            Text(footerText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.top, 2)
    }
    private var footerText: String {
        var parts = ["Proof", model]
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
            .font(.system(size: size * 0.6, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(threadHexColor(source.colorHex), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
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
