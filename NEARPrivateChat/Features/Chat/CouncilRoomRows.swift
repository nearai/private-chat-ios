import SwiftUI

struct CouncilMessageRow: View {
    let message: CouncilMessageVM

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ModelAvatarDot(participant: message.participant)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(message.participant.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    CouncilStanceBadge(stance: message.participant.stance)

                    Spacer(minLength: 0)
                }

                Group {
                    if message.text.isEmpty && message.isStreaming {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("reasoning…")
                                .foregroundStyle(Color.textSecondary)
                        }
                    } else {
                        Text(message.text.isEmpty ? "No answer yet." : message.text)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                }
                .font(.body)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(cardBorderColor, lineWidth: 1)
            }
        }
    }

    // Dissenting answers get a subtle red-tinted card, per the Council mockup.
    private var cardBackground: Color {
        message.participant.stance == .dissents ? Color.proofMismatch.opacity(0.06) : Color.appPanelBackground
    }

    private var cardBorderColor: Color {
        message.participant.stance == .dissents ? Color.proofMismatch.opacity(0.22) : Color.appBorder
    }
}

struct CouncilRosterStrip: View {
    let participants: [CouncilParticipant]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(participants) { participant in
                HStack(spacing: 8) {
                    ZStack(alignment: .bottomTrailing) {
                        ModelAvatarDot(participant: participant)
                        Circle()
                            .fill(stateColor(participant.stance))
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.appPanelBackground, lineWidth: 2))
                            .offset(x: 1, y: 1)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(participant.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(stateLabel(participant.stance))
                            .font(.system(size: 10))
                            .foregroundStyle(stateColor(participant.stance))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.appPanelBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.appHairline).frame(height: 0.5)
        }
    }

    private func stateColor(_ stance: CouncilStance) -> Color {
        switch stance {
        case .reasoning: return .proofStale
        case .dissents: return .proofMismatch
        case .agrees, .neutral: return .proofVerified
        }
    }

    private func stateLabel(_ stance: CouncilStance) -> String {
        switch stance {
        case .reasoning: return "thinking"
        case .dissents: return "differs"
        case .agrees, .neutral: return "ready"
        }
    }
}

struct CouncilStanceBadge: View {
    let stance: CouncilStance

    var body: some View {
        if let label {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(tint.opacity(0.10), in: Capsule())
                .accessibilityLabel(label)
        }
    }

    private var label: String? {
        switch stance {
        case .agrees:
            return "Likely agrees"
        case .dissents:
            return "Likely differs"
        case .reasoning:
            return "reasoning…"
        case .neutral:
            return nil
        }
    }

    private var tint: Color {
        switch stance {
        case .agrees:
            return .proofVerified
        case .dissents:
            return .proofMismatch
        case .reasoning, .neutral:
            return .textSecondary
        }
    }
}

struct ModelAvatarDot: View {
    let participant: CouncilParticipant

    var body: some View {
        ZStack {
            Circle()
                .fill(participant.color.opacity(0.16))
            Circle()
                .fill(participant.color)
                .frame(width: 13, height: 13)
        }
        .frame(width: 30, height: 30)
        .overlay {
            Circle()
                .stroke(Color.appBorder, lineWidth: 1)
        }
        .accessibilityLabel(participant.displayName)
    }
}
