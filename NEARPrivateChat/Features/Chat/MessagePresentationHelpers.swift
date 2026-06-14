import SwiftUI

extension View {
    func workspaceListRow(top: CGFloat = 3, bottom: CGFloat = 3) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 14, bottom: bottom, trailing: 14))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

extension ChatMessage {
    var canShowAnswerProofFooter: Bool {
        let modelID = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return canShowAssistantActions && !modelID.isEmpty
    }

    /// Inline answer actions (copy, export, regenerate, proof, save) apply only
    /// to real, completed answers — never to failed or still-streaming turns.
    var canShowAssistantActions: Bool {
        role == .assistant &&
            !isStreaming &&
            status.lowercased() != "failed" &&
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Rich widget cards already own their primary interaction. Keep answer
    /// proof visible, but avoid stacking the full copy/export/regenerate strip
    /// under chart, briefing, and action-plan cards.
    var canShowAssistantInlineActions: Bool {
        canShowAssistantActions && widget == nil
    }

    var isAgentRouteMessage: Bool {
        model == ModelOption.ironclawModelID ||
            model == ModelOption.ironclawMobileModelID
    }

    var shouldShowAgentRunStatus: Bool {
        guard role == .assistant, model == ModelOption.ironclawModelID else {
            return false
        }
        return isStreaming ||
            pendingApproval != nil ||
            ["reasoning", "searching", "approval", "failed", "running", "queued", "in_progress"].contains(status.lowercased())
    }

    var modelDisplayName: String {
        if model == ModelOption.ironclawMobileModelID {
            return "IronClaw Mobile"
        }
        if model == ModelOption.ironclawModelID {
            return "Hosted IronClaw"
        }
        if model == ModelOption.llmCouncilSynthesisModelID {
            return "Council Synthesis"
        }
        if let model, model.hasPrefix(ModelOption.nearCloudModelPrefix) {
            return ModelOption(modelID: model, publicModel: true, metadata: nil).displayName
        }
        // Strip provider prefixes and precision suffixes so message headers
        // are readable without exposing raw route IDs.
        if let modelID = model {
            return ModelOption.humanize(modelID: modelID)
        }
        return "Assistant"
    }

    var streamingStatusText: String {
        if model == ModelOption.ironclawMobileModelID {
            switch status {
            case "reasoning":
                return "Running IronClaw Mobile"
            case "searching":
                return "Searching with NEAR Private"
            default:
                return "Running mobile Agent"
            }
        }

        if model == ModelOption.ironclawModelID {
            switch status {
            case "reasoning":
                return "Running Hosted IronClaw"
            case "approval":
                return "Needs your input"
            case "searching":
                if let searchQuery, !searchQuery.isEmpty {
                    return "Searching \(searchQuery)"
                }
                return "Searching web before Agent"
            default:
                return "Waiting for final Agent output"
            }
        }

        if model == ModelOption.llmCouncilSynthesisModelID {
            return status == "searching" ? "Checking sources" : "Synthesizing council"
        }

        switch status {
        case "searching":
            if let searchQuery, !searchQuery.isEmpty {
                return "Searching \(searchQuery)"
            }
            return "Searching web"
        case "reasoning":
            return "Reasoning"
        case "approval":
            return "Needs input"
        default:
            return "Thinking"
        }
    }
}
