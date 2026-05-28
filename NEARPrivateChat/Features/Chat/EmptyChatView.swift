import SwiftUI

/// Empty state for a new chat thread — v2 redesign.
/// Single NEAR mark + caption, optional prompt-suggestion chips below.
/// All setup-recovery / quickstart / capability-callout patterns from the
/// pre-v2 design are intentionally removed — those belong in Setup, never on
/// the chat surface.
struct EmptyChatView: View {
    @EnvironmentObject private var chatStore: ChatStore

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

            if !emptyPromptSuggestions.isEmpty {
                // 4 short chips on iPhone width fit without scrolling.
                // A plain centered HStack with maxWidth=.infinity puts
                // them in the middle of the screen — no GeometryReader
                // or ScrollView gymnastics needed. minimumScaleFactor
                // on the labels lets longer chip titles (project mode)
                // shrink slightly rather than overflow.
                HStack(spacing: 8) {
                    ForEach(emptyPromptSuggestions) { suggestion in
                        suggestionChip(suggestion)
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

    private var emptyPromptSuggestions: [EmptyPromptSuggestion] {
        // Context-aware suggestions remain, but stripped of setup/capability
        // recovery patterns. These are conversation starters, not setup CTAs.
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

        return []
    }

    private func fillDraft(for suggestion: EmptyPromptSuggestion) {
        AppHaptics.selection()
        chatStore.draft = suggestion.prompt
    }
}
