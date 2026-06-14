import SwiftUI

extension InputBar {
    var shouldShowProjectContextStrip: Bool {
        !chatStore.activeProjectContextAttachments.isEmpty || !chatStore.activeProjectContextLinks.isEmpty
    }

    var canSend: Bool {
        composerState.hasSendableContent
    }

    var sendDisabled: Bool {
        composerState.sendDisabled
    }

    var composerState: ComposerState {
        ComposerState(
            draft: composerStore.draft,
            pendingAttachments: composerStore.pendingAttachments,
            isStreaming: transcriptStore.isStreaming,
            routeReadinessTitle: composerStore.routeReadinessIssue?.title,
            routeReadinessMessage: composerStore.routeReadinessIssue?.message
        )
    }

    var draftBinding: Binding<String> {
        Binding(
            get: { composerStore.draft },
            set: { chatStore.draft = $0 }
        )
    }

    var sendButtonColor: Color {
        if transcriptStore.isStreaming {
            return .proofMismatch
        }
        return sendDisabled ? Color.appSecondaryBackground : Color.actionPrimary
    }

    var sendIconColor: Color {
        sendDisabled && !transcriptStore.isStreaming ? .secondary : .white
    }

    var sendButtonScale: CGFloat {
        guard !reduceMotion else { return 1 }
        if transcriptStore.isStreaming {
            return 1
        }
        return canSend ? 1 : 0.9
    }

    var sendButtonAnimation: Animation? {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.22, dampingFraction: 0.72)
    }

    var composerPlaceholder: String {
        if chatStore.isCouncilModeEnabled {
            return "Ask the Council"
        }
        switch chatStore.selectedRouteKind {
        case .nearCloud:
            return "Ask with NEAR AI Cloud"
        case .ironclawMobile:
            return "Tell the phone Agent what to do"
        case .ironclawHosted:
            return "Tell the Agent what to run"
        case .nearPrivate:
            if researchButtonActive {
                return "Ask for a cited answer"
            }
            switch chatStore.sourceMode {
            case .web:
                return "Ask with web sources"
            case .files, .links, .all:
                return chatStore.selectedProject == nil ? "Ask with sources" : "Ask this Project"
            case .auto:
                return "Ask, attach, or say what to track"
            }
        }
    }

    var researchButtonActive: Bool {
        chatStore.researchModeEnabled && !chatStore.selectedRouteUsesNearCloud
    }

    var autoSourceModeInfersLiveWeb: Bool {
        ChatStore.shouldDiscloseAutoLiveWeb(
            sourceMode: chatStore.sourceMode,
            researchModeEnabled: chatStore.researchModeEnabled,
            prompt: composerStore.draft
        )
    }
}
