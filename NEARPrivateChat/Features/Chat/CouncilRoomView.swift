import SwiftUI

struct CouncilRoomView: View {
    let model: CouncilRoomModel
    var supportsTargetedSend: Bool = false
    var synthesizeTitle: String? = nil
    let onSend: (String, CouncilTarget) -> Void
    let onSynthesize: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            CouncilRosterStrip(participants: model.participants)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(model.messages) { message in
                        CouncilMessageRow(message: message)
                    }

                    if let synthesis = model.synthesis {
                        CouncilSynthesisCard(synthesis: synthesis)
                            .padding(.top, 2)
                    }
                }
                .padding(16)
            }
            .background(Color.appSecondaryBackground)

            CouncilComposerBar(
                participants: model.participants,
                supportsTargetedSend: supportsTargetedSend,
                synthesizeTitle: synthesizeTitle,
                onSend: onSend,
                onSynthesize: onSynthesize
            )
        }
        .background(Color.appSecondaryBackground)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.actionPrimary)
                .frame(width: 36, height: 36)
                .background(Color.actionPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.headline.weight(.semibold))
                Text(model.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.appPanelBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.appHairline)
                .frame(height: 1)
        }
    }
}
