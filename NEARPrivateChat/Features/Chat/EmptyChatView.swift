import SwiftUI

/// Empty state for a new chat thread — v2 redesign.
/// Single NEAR mark + caption, optional prompt-suggestion chips below.
/// All setup-recovery / quickstart / capability-callout patterns from the
/// pre-v2 design are intentionally removed — those belong in Setup, never on
/// the chat surface.
struct EmptyChatView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var sessionStore: SessionStore

    private struct EmptyPromptSuggestion: Identifiable {
        var id: String { title }
        let title: String
        let symbolName: String
        let prompt: String
    }

    var body: some View {
        VStack(spacing: 14) {
            NearAppIconMark(size: 56)

            Text("Verifiably Yours.")
                .font(.body)
                .lineSpacing(24 - 17)
                .foregroundStyle(Color.textTertiary)

            Text(emptyStateSubtitle)
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            if !emptyPromptSuggestions.isEmpty {
                VStack(spacing: 8) {
                    ForEach(suggestionRows, id: \.first?.id) { row in
                        HStack(spacing: 8) {
                            ForEach(row) { suggestion in
                                suggestionChip(suggestion)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func suggestionChip(_ suggestion: EmptyPromptSuggestion) -> some View {
        Button {
            fillDraft(for: suggestion)
        } label: {
            Label(suggestion.title, systemImage: suggestion.symbolName)
                .font(.footnote.weight(.medium))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Color.appSecondaryBackground, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use suggestion, \(suggestion.title)")
        .accessibilityHint("Fills the composer without sending.")
    }

    private var suggestionRows: [[EmptyPromptSuggestion]] {
        stride(from: 0, to: emptyPromptSuggestions.count, by: 2).map { start in
            Array(emptyPromptSuggestions[start..<min(start + 2, emptyPromptSuggestions.count)])
        }
    }

    private var savedSetupProfile: UserSetupProfile? {
        guard let accountID = sessionStore.setupAccountID else {
            return nil
        }
        return UserSetupStorage.load(for: accountID)?.normalizedForDefaults
    }

    private var inferredSetupProfile: UserSetupProfile {
        UserSetupProfile.inferredCurrentDefaults(
            webSearchEnabled: chatStore.webSearchEnabled,
            sourceMode: chatStore.sourceMode,
            selectedModelID: chatStore.selectedModel,
            hasSelectedProject: chatStore.selectedProject != nil,
            isCouncilModeEnabled: chatStore.isCouncilModeEnabled,
            researchModeEnabled: chatStore.researchModeEnabled
        ).normalizedForDefaults
    }

    private var resolvedSetupProfile: UserSetupProfile {
        savedSetupProfile ?? inferredSetupProfile
    }

    private var emptyStateSubtitle: String {
        if let project = chatStore.selectedProject {
            return "Use \(project.name)'s files, links, and notes to move the work forward."
        }

        if chatStore.isCouncilModeEnabled {
            return "Compare multiple model perspectives, then act on the synthesis."
        }

        return resolvedSetupProfile.emptyStateSubtitle
    }

    private var emptyPromptSuggestions: [EmptyPromptSuggestion] {
        if let project = chatStore.selectedProject {
            let projectName = project.name
            return [
                EmptyPromptSuggestion(
                    title: "Brief project",
                    symbolName: "folder.badge.gearshape",
                    prompt: "Use \(projectName)'s files, links, and notes to brief me on the next best move."
                ),
                EmptyPromptSuggestion(
                    title: "Find blockers",
                    symbolName: "exclamationmark.triangle",
                    prompt: "Review \(projectName)'s context and identify the highest-risk blockers, missing facts, and next checks."
                ),
                EmptyPromptSuggestion(
                    title: "Draft next step",
                    symbolName: "arrow.forward.circle",
                    prompt: "Turn \(projectName)'s current context into a concise next-step plan I can act on."
                )
            ]
        }

        if chatStore.isCouncilModeEnabled {
            return [
                EmptyPromptSuggestion(
                    title: "Compare",
                    symbolName: "square.grid.2x2",
                    prompt: "Compare the council's answers on this task: "
                ),
                EmptyPromptSuggestion(
                    title: "Disagreements",
                    symbolName: "arrow.triangle.branch",
                    prompt: "Show me where the council agrees and disagrees on: "
                ),
                EmptyPromptSuggestion(
                    title: "Validate",
                    symbolName: "checkmark.shield",
                    prompt: "Have each council model fact-check this claim and flag what's uncertain: "
                ),
                EmptyPromptSuggestion(
                    title: "Decide",
                    symbolName: "arrow.left.arrow.right.circle",
                    prompt: "Ask the council which option they'd recommend and why for: "
                )
            ]
        }

        let suggestions = resolvedSetupProfile.emptyStatePromptSuggestions.map {
            EmptyPromptSuggestion(
                title: $0.title,
                symbolName: $0.symbolName,
                prompt: $0.prompt
            )
        }
        if !suggestions.isEmpty {
            return Array(suggestions.prefix(6))
        }

        return [
            EmptyPromptSuggestion(
                title: "Private question",
                symbolName: "lock.shield",
                prompt: "Help me think through a private question."
            ),
            EmptyPromptSuggestion(
                title: "Research brief",
                symbolName: "doc.text.magnifyingglass",
                prompt: "Create a sourced brief on the latest developments in AI."
            ),
            EmptyPromptSuggestion(
                title: "Repo plan",
                symbolName: "chevron.left.forwardslash.chevron.right",
                prompt: "Plan the first repo task: what to inspect, what to change, and which focused tests should run."
            )
        ]
    }

    private func fillDraft(for suggestion: EmptyPromptSuggestion) {
        AppHaptics.selection()
        chatStore.draft = suggestion.prompt
    }
}
