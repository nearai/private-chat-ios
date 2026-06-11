import SwiftUI

struct CouncilComposerBar: View {
    let participants: [CouncilParticipant]
    var supportsTargetedSend: Bool = false
    var synthesizeTitle: String? = nil
    let onSend: (String, CouncilTarget) -> Void
    let onSynthesize: () -> Void

    @State private var target: CouncilTarget = .room
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                if supportsTargetedSend {
                    targetMenu
                } else {
                    staticTargetPill
                }

                TextField(supportsTargetedSend ? "Ask the Council" : "Stage a follow-up", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.appHairline, lineWidth: 1)
                    }

                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                        .font(.body.weight(.bold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .minimumTouchTarget()
                .foregroundStyle(canSend ? Color.appPanelBackground : Color.textSecondary)
                .background(canSend ? Color.actionPrimary : Color.appSecondaryBackground, in: Circle())
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "person.3.fill").font(.caption2.weight(.bold))
                    Text("\(participants.count) models").font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.appSecondaryBackground, in: Capsule())

                if let synthesizeTitle {
                    Button(action: onSynthesize) {
                        Label(synthesizeTitle, systemImage: "sparkles")
                            .font(.caption.weight(.bold))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.actionPrimary)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(Color.actionPrimary.opacity(0.10), in: Capsule())
                    .accessibilityHint("Use the completed Council answers that are ready now.")
                }

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(Color.appPanelBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.appHairline)
                .frame(height: 1)
        }
    }

    private var targetMenu: some View {
        Menu {
            Button {
                target = .room
            } label: {
                Label("room", systemImage: target == .room ? "checkmark" : "person.3")
            }

            ForEach(participants) { participant in
                Button {
                    target = .model(id: participant.modelID)
                } label: {
                    Label("@\(participant.displayName)", systemImage: target == .model(id: participant.modelID) ? "checkmark" : "at")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("To: \(targetLabel)")
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(Color.actionPrimary)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(Color.actionPrimary.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var staticTargetPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.bubble")
                .font(.caption.weight(.bold))
            Text("Follow-up")
                .font(.caption.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(Color.appSecondaryBackground, in: Capsule())
        .accessibilityLabel("Stage a room follow-up")
    }

    private var targetLabel: String {
        switch target {
        case .room:
            return "room"
        case let .model(id):
            return "@\(participants.first { $0.modelID == id }?.displayName ?? "model")"
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onSend(text, target)
        draft = ""
    }
}
