import SwiftUI

#if DEBUG
#Preview("Council Room") {
    let glm = CouncilParticipant(
        id: "preview-private-model",
        modelID: "preview-private-model",
        displayName: "Private",
        color: .actionPrimary,
        stance: .agrees
    )
    let claude = CouncilParticipant(
        id: "preview-independent-model-a",
        modelID: "preview-independent-model-a",
        displayName: "Model A",
        color: .proofVerified,
        stance: .agrees
    )
    let gemini = CouncilParticipant(
        id: "preview-independent-model-b",
        modelID: "preview-independent-model-b",
        displayName: "Model B",
        color: .proofMismatch,
        stance: .dissents
    )

    CouncilRoomView(
        model: CouncilRoomModel(
            title: "Council",
            subtitle: "Private · Model A · Model B",
            participants: [glm, claude, gemini],
            messages: [
                CouncilMessageVM(
                    id: "glm",
                    participant: glm,
                    text: "I agree with the low-risk path: ship the UI as a separate affordance and keep the existing council stack untouched.",
                    isStreaming: false,
                    searchQuery: nil,
                    sources: []
                ),
                CouncilMessageVM(
                    id: "claude",
                    participant: claude,
                    text: "I agree with caveats. The room should avoid inventing vote counts until synthesis emits structured evidence.",
                    isStreaming: false,
                    searchQuery: nil,
                    sources: []
                ),
                CouncilMessageVM(
                    id: "gemini",
                    participant: gemini,
                    text: "I dissent on making it the default. However, an opt-in room is useful for comparing answer quality and tone.",
                    isStreaming: false,
                    searchQuery: nil,
                    sources: []
                )
            ],
            synthesis: CouncilSynthesisVM(
                agreement: "All models support a separate room that preserves the current council transcript and does not call store APIs directly.",
                disagreement: "Model B would not make the room the default presentation until usage proves it is clearer than the compact stack.",
                nextStep: "Add an Open Council Room affordance, map the selected batch through `CouncilRoomModel.from`, then wire send and synthesize callbacks.",
                fullText: "The council broadly supports a separate room UI while keeping the existing stacked rendering stable. The main disagreement is default placement versus opt-in access.",
                isFailed: false
            )
        ),
        onSend: { _, _ in },
        onSynthesize: {}
    )
}
#endif
