#if canImport(ActivityKit)
import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

// MARK: - Lock Screen / banner presentation

/// The Live Activity as shown on the Lock Screen and in the (rare) banner
/// presentation. Light aesthetic: a soft tinted card, a status glyph, the run
/// title, the current stage, route/trust copy, and a determinate progress bar
/// with a "n/total" counter.
struct AgentLiveActivityLockScreenView: View {
    let context: ActivityViewContext<AgentActivityAttributes>

    private var status: AgentLiveActivityStatus {
        AgentLiveActivityStatus.resolve(title: context.attributes.title, stage: context.state.stage)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.symbolName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 30, height: 30)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(context.attributes.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(context.state.stage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                AgentLiveActivityStatusLine(status: status, showsOpenChat: true)

                Text(status.trustText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                AgentLiveActivityProgress(state: context.state)
            }
        }
        .padding(14)
        .widgetURL(AgentLiveActivityLinks.openChatURL)
        .activityBackgroundTint(Color.white.opacity(0.001)) // keep system light material
        .activitySystemActionForegroundColor(.primary)
    }
}

// MARK: - Route and trust copy

private enum AgentLiveActivityLinks {
    static let openChatURL = URL(string: "nearprivatechat://chat")
}

private struct AgentLiveActivityStatus {
    let primaryText: String
    let trustText: String
    let symbolName: String

    static func resolve(title: String, stage: String) -> AgentLiveActivityStatus {
        let text = "\(title) \(stage)".lowercased()

        if text.contains("approval") {
            return AgentLiveActivityStatus(
                primaryText: "Waiting for approval",
                trustText: "Open chat to approve or deny",
                symbolName: "hand.raised"
            )
        }

        if text.contains("hosted ironclaw") || text.contains("hosted") || text.contains("workstation") {
            return AgentLiveActivityStatus(
                primaryText: "Running on Hosted IronClaw",
                trustText: "Separate trust boundary",
                symbolName: "terminal"
            )
        }

        if text.contains("ironclaw mobile") || text.contains("phone") || text.contains("mobile") {
            return AgentLiveActivityStatus(
                primaryText: "Running on phone",
                trustText: "Phone route - no NEAR proof",
                symbolName: "iphone"
            )
        }

        return AgentLiveActivityStatus(
            primaryText: "Current route",
            trustText: "Proof shown when route supports it",
            symbolName: "message"
        )
    }
}

private struct AgentLiveActivityStatusLine: View {
    let status: AgentLiveActivityStatus
    let showsOpenChat: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.symbolName)
                .font(.caption2.weight(.semibold))
            Text(status.primaryText)
                .lineLimit(1)
            Spacer(minLength: 6)
            if showsOpenChat {
                Text("Open chat")
                    .lineLimit(1)
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
    }
}

// MARK: - Shared progress row

/// Determinate progress bar + "completed/total" counter used by both the Lock
/// Screen and the expanded Dynamic Island. Clamps to avoid a > 1 fraction.
struct AgentLiveActivityProgress: View {
    let state: AgentActivityAttributes.ContentState

    private var fraction: Double {
        guard state.total > 0 else { return 0 }
        let raw = Double(state.completed) / Double(state.total)
        return min(max(raw, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(Color.accentColor)
            Text("\(min(state.completed, state.total))/\(max(state.total, 0))")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - Widget configuration

/// `ActivityConfiguration` for the agent run. Registered alongside the
/// home-screen widget in `BriefingWidgetBundle`. Defines the Lock Screen view
/// and all three Dynamic Island presentations (expanded, compact, minimal).
struct AgentLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentActivityAttributes.self) { context in
            AgentLiveActivityLockScreenView(context: context)
        } dynamicIsland: { context in
            let status = AgentLiveActivityStatus.resolve(title: context.attributes.title, stage: context.state.stage)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: status.symbolName)
                            .foregroundStyle(.tint)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(min(context.state.completed, context.state.total))/\(max(context.state.total, 0))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.stage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        AgentLiveActivityStatusLine(status: status, showsOpenChat: true)
                        Text(status.trustText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                        AgentLiveActivityProgress(state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: status.symbolName)
                    .foregroundStyle(.tint)
            } compactTrailing: {
                Text("\(min(context.state.completed, context.state.total))/\(max(context.state.total, 0))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: status.symbolName)
                    .foregroundStyle(.tint)
            }
            .widgetURL(AgentLiveActivityLinks.openChatURL)
            .keylineTint(.accentColor)
        }
    }
}
#endif
