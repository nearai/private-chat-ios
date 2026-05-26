import SwiftUI

struct EmptyChatView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var sessionStore: SessionStore

    private struct EmptyPromptSuggestion: Identifiable {
        var id: String { title }
        let title: String
        let symbolName: String
        let prompt: String
    }

    private var emptyHeroSubtitle: String {
        if let project = chatStore.selectedProject {
            let contextCount = chatStore.activeProjectContextAttachments.count + chatStore.activeProjectContextLinks.count
            return contextCount > 0 ? "\(project.name) context is ready." : "\(project.name) is selected."
        }
        if chatStore.selectedModelOption?.isIronclawHostedModel == true {
            return chatStore.ironclawRemoteWorkstationAvailable ? "Hosted agent ready." : "Connect hosted IronClaw to run workstation tasks."
        }
        if chatStore.selectedModelOption?.isIronclawMobileRuntime == true {
            return chatStore.ironclawRemoteWorkstationAvailable ? "Hosted agent ready." : "Mobile agent ready."
        }
        if let setupProfileWithGoal {
            return setupProfileWithGoal.emptyStateSubtitle
        }
        if chatStore.isCouncilModeEnabled {
            return "Council is ready to compare answers."
        }
        if chatStore.researchModeEnabled && !chatStore.selectedRouteUsesNearCloud {
            return "Search current sources."
        }
        if let setupProfile {
            return setupProfile.emptyStateSubtitle
        }
        return "Ask normally. NEAR picks web, project context, or an agent when needed."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                PrivacySeal(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What do you want to ask?")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(emptyHeroSubtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(emptyPromptSuggestions) { suggestion in
                        suggestionButton(suggestion)
                    }
                }
                .padding(.vertical, 1)

                Menu {
                    ForEach(emptyPromptSuggestions) { suggestion in
                        Button {
                            AppHaptics.selection()
                            chatStore.draft = suggestion.prompt
                        } label: {
                            Label(suggestion.title, systemImage: suggestion.symbolName)
                        }
                    }
                } label: {
                    Label("Prompt examples", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(height: 34)
                        .padding(.horizontal, 10)
                        .background(Color.secondarySurface, in: Capsule())
                }
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
    }

    private func suggestionButton(_ suggestion: EmptyPromptSuggestion) -> some View {
        Button {
            AppHaptics.selection()
            chatStore.draft = suggestion.prompt
        } label: {
            Label(suggestion.title, systemImage: suggestion.symbolName)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color.secondarySurface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use suggestion, \(suggestion.title)")
        .accessibilityHint("Fills the composer without sending.")
    }

    private var emptyPromptSuggestions: [EmptyPromptSuggestion] {
        if chatStore.selectedProviderDisplayName == "IronClaw" {
            return [
                EmptyPromptSuggestion(title: "Review repo", symbolName: "chevron.left.forwardslash.chevron.right", prompt: "Agent mission: Review this repo and identify the highest-impact fixes: "),
                EmptyPromptSuggestion(title: "Patch safely", symbolName: "wrench.and.screwdriver", prompt: "Agent mission: Implement this change, run focused tests, and report changed files: "),
                EmptyPromptSuggestion(title: "Research issue", symbolName: "globe", prompt: "Agent mission: Research the latest context and turn it into next actions: ")
            ]
        }

        if let project = chatStore.selectedProject {
            let projectName = project.name
            return [
                EmptyPromptSuggestion(title: "Brief project", symbolName: "folder.badge.gearshape", prompt: "Use \(projectName)'s files, links, and notes to brief me on the next best move."),
                EmptyPromptSuggestion(title: "Find blockers", symbolName: "exclamationmark.triangle", prompt: "Review \(projectName)'s context and identify the highest-risk blockers, missing facts, and next checks."),
                EmptyPromptSuggestion(title: "Draft next step", symbolName: "arrow.forward.circle", prompt: "Turn \(projectName)'s current context into a concise next-step plan I can act on.")
            ]
        }

        if let setupProfileWithGoal {
            return setupProfileWithGoal.emptyStatePromptSuggestions.map {
                EmptyPromptSuggestion(title: $0.title, symbolName: $0.symbolName, prompt: $0.prompt)
            }
        }

        if chatStore.isCouncilModeEnabled {
            return [
                EmptyPromptSuggestion(title: "Compare models", symbolName: "square.grid.2x2", prompt: "Compare Anthropic and OpenAI for this task: "),
                EmptyPromptSuggestion(title: "Disagree", symbolName: "arrow.triangle.branch", prompt: "Ask the council to identify strongest agreements and disagreements on: "),
                EmptyPromptSuggestion(title: "Decision brief", symbolName: "doc.text.magnifyingglass", prompt: "Give me a decision-ready brief with tradeoffs and next steps: ")
            ]
        }

        if chatStore.researchModeEnabled {
            return [
                EmptyPromptSuggestion(title: "Latest AI", symbolName: "globe", prompt: "What is the latest important news in AI? Include sources and dates."),
                EmptyPromptSuggestion(title: "Compare views", symbolName: "square.grid.2x2", prompt: "Compare Anthropic and OpenAI for this task using current sources: "),
                EmptyPromptSuggestion(title: "Brief me", symbolName: "doc.text.magnifyingglass", prompt: "Research this and give me a decision-ready brief with citations: ")
            ]
        }

        if let setupProfile {
            return setupProfile.emptyStatePromptSuggestions.map {
                EmptyPromptSuggestion(title: $0.title, symbolName: $0.symbolName, prompt: $0.prompt)
            }
        }

        return [
            EmptyPromptSuggestion(title: "Plan next move", symbolName: "arrow.forward.circle", prompt: "Help me turn this into the next concrete action: "),
            EmptyPromptSuggestion(title: "Research latest", symbolName: "globe", prompt: "Research the latest context and give me the decision-ready version: "),
            EmptyPromptSuggestion(title: "Compare options", symbolName: "square.grid.2x2", prompt: "Compare the strongest options, tradeoffs, and recommendation for: ")
        ]
    }

    private var setupProfile: UserSetupProfile? {
        guard let accountID = sessionStore.setupAccountID else { return nil }
        return UserSetupStorage.load(for: accountID)
    }

    private var setupProfileWithGoal: UserSetupProfile? {
        guard let setupProfile, !setupProfile.normalizedGoalText.isEmpty else { return nil }
        return setupProfile
    }
}
