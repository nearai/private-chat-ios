import SwiftUI

struct AgentRunStatusStrip: View {
    let message: ChatMessage
    let toolCount: Int
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        TimelineView(.periodic(from: message.createdAt, by: 1)) { context in
            let isStale = isStaleRun(now: context.date)
            HStack(spacing: 8) {
                Image(systemName: symbolName(isStale: isStale))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tintColor(isStale: isStale))
                    .frame(width: 24, height: 24)
                    .background(tintColor(isStale: isStale).opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title(isStale: isStale))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(elapsedText(now: context.date))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let detail = detailText(isStale: isStale) {
                        Text(detail)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                if isStale && message.isStreaming {
                    Button(action: onCancel) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop stalled IronClaw run")
                } else if message.status == "failed" || isStale {
                    Button(action: onRetry) {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.brandBlue)
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retry IronClaw run")
                }
            }
            .padding(9)
            .frame(maxWidth: 520, alignment: .leading)
            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tintColor(isStale: isStale).opacity(message.status == "failed" || isStale ? 0.24 : 0.16), lineWidth: 1)
            }
        }
    }

    private func title(isStale: Bool) -> String {
        if message.status == "failed" {
            return "Run stopped"
        }
        if isStale {
            return "No output received"
        }
        if message.pendingApproval != nil || message.status == "approval" {
            return "Agent needs input"
        }
        if message.status == "searching" {
            return "Gathering context"
        }
        return "Agent running"
    }

    private func detailText(isStale: Bool) -> String? {
        if message.status == "failed" {
            return "Hosted IronClaw stopped before a final answer. Check the Agent connection, then retry."
        }
        if isStale {
            return message.isStreaming
                ? "The hosted run may have stalled. Stop it, then retry from the phone."
                : "The hosted run may have stalled. Retry starts a fresh phone-controlled run."
        }
        if message.pendingApproval != nil || message.status == "approval" {
            return "Review the tool request below to continue the run."
        }
        return nil
    }

    private func symbolName(isStale: Bool) -> String {
        if message.status == "failed" {
            return "exclamationmark.triangle.fill"
        }
        if isStale {
            return "clock.badge.exclamationmark"
        }
        if message.pendingApproval != nil || message.status == "approval" {
            return "hand.tap.fill"
        }
        return "arrow.triangle.2.circlepath"
    }

    private func tintColor(isStale: Bool) -> Color {
        if message.status == "failed" { return .red }
        if isStale { return .orange }
        return Color.brandBlue
    }

    private func elapsedText(now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(message.createdAt))
        if message.status == "failed" {
            return "after \(Self.compactDuration(elapsed))"
        }
        if isStaleRun(now: now) {
            return "for \(Self.compactDuration(elapsed))"
        }
        if message.pendingApproval != nil || message.status == "approval" {
            return "paused \(Self.compactDuration(elapsed))"
        }
        return Self.compactDuration(elapsed)
    }

    private func isStaleRun(now: Date) -> Bool {
        guard message.pendingApproval == nil,
              message.status != "failed" else {
            return false
        }
        let activeStatuses = ["reasoning", "searching", "running", "queued", "in_progress"]
        guard message.isStreaming || activeStatuses.contains(message.status.lowercased()) else {
            return false
        }
        return now.timeIntervalSince(message.createdAt) > 2 * 60
    }

    private static func compactDuration(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded(.down))
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        return "\(minutes / 60)h"
    }
}
