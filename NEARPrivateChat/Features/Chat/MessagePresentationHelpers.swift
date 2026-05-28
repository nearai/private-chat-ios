import SwiftUI

extension View {
    func workspaceListRow(top: CGFloat = 3, bottom: CGFloat = 3) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 14, bottom: bottom, trailing: 14))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

extension ChatMessage {
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
        if model == ModelOption.nearCloudQwenMaxModelID {
            return "Qwen Max"
        }
        if model == "near-cloud/anthropic/claude-opus-4-7" {
            return "Claude Opus 4.7"
        }
        // Strip the org prefix and precision suffix so message headers
        // show "GLM 5.1" instead of "zai-org/GLM-5.1-FP8" or the raw
        // trailing segment "GLM-5.1-FP8".
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
                return "Running mobile agent"
            }
        }

        if model == ModelOption.ironclawModelID {
            switch status {
            case "reasoning":
                return "Running IronClaw agent"
            case "approval":
                return "Waiting for approval"
            case "searching":
                if let searchQuery, !searchQuery.isEmpty {
                    return "Searching \(searchQuery)"
                }
                return "Searching web before IronClaw"
            default:
                return "Waiting for final IronClaw output"
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
            return "Needs approval"
        default:
            return "Thinking"
        }
    }
}
