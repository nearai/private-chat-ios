import SwiftUI

enum EmptyChatStarterAction {
    case draft
    case research
    case project
    case council
    case agent
    case trust
}

struct EmptyChatStarterSuggestion: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let symbolName: String
    let prompt: String
    var action: EmptyChatStarterAction = .draft
}

enum EmptyChatStarterPlanner {
    static func suggestions(
        projectName: String?,
        isCouncilModeEnabled: Bool,
        councilAvailable: Bool,
        routeKind: ChatRouteKind,
        agentAvailable: Bool
    ) -> [EmptyChatStarterSuggestion] {
        if let projectName = projectName?.nilIfBlank {
            return projectSuggestions(
                projectName: projectName,
                councilAvailable: councilAvailable,
                routeKind: routeKind,
                agentAvailable: agentAvailable
            )
        }

        if isCouncilModeEnabled {
            return [
                EmptyChatStarterSuggestion(
                    title: "Compare",
                    symbolName: "square.grid.2x2",
                    prompt: "Compare the council's answers on this task: "
                ),
                EmptyChatStarterSuggestion(
                    title: "Disagreements",
                    symbolName: "arrow.triangle.branch",
                    prompt: "Show me where the council agrees and disagrees on: "
                ),
                EmptyChatStarterSuggestion(
                    title: "Validate",
                    symbolName: "checkmark.shield",
                    prompt: "Have each council model fact-check this claim and flag what's uncertain: "
                ),
                EmptyChatStarterSuggestion(
                    title: "Decide",
                    symbolName: "arrow.left.arrow.right.circle",
                    prompt: "Ask the council which option they'd recommend and why for: "
                )
            ]
        }

        var suggestions = [
            EmptyChatStarterSuggestion(
                title: "Next actions",
                symbolName: "checklist",
                prompt: "Turn this into actionable next moves: trackers, reminders, calendar-worthy items, risks, decisions, and exact commands. Preview before creating anything: "
            ),
            EmptyChatStarterSuggestion(
                title: "Draft trackers",
                symbolName: "calendar.badge.clock",
                prompt: "Turn this into recurring trackers, reminders, and calendar drafts. Include cadence, date, time, timezone, attendees, missing_fields, confidence, and exact commands. Preview before creating anything: "
            ),
            EmptyChatStarterSuggestion(
                title: "Web research",
                symbolName: "doc.text.magnifyingglass",
                prompt: "Research this with sources and cite what matters: ",
                action: .research
            ),
            EmptyChatStarterSuggestion(
                title: "Files to actions",
                symbolName: "folder.badge.gearshape",
                prompt: "Use attached files or a Project and turn this into actions, trackers, reminders, risks, decisions, and missing facts. Preview before creating anything: ",
                action: .project
            ),
            EmptyChatStarterSuggestion(
                title: "Sources & proof",
                symbolName: "checkmark.shield",
                prompt: trustPrompt(for: routeKind, projectName: nil),
                action: .trust
            )
        ]

        if agentAvailable {
            suggestions.append(
                EmptyChatStarterSuggestion(
                    title: "Handoff to Agent",
                    symbolName: "terminal",
                    prompt: "Agent mission: define the goal, context to inspect, tools to use, risks, and focused verification for this task: ",
                    action: .agent
                )
            )
        } else if councilAvailable {
            suggestions.append(
                EmptyChatStarterSuggestion(
                    title: "Compare with Council",
                    symbolName: "square.grid.2x2",
                    prompt: "Compare options with Council for: ",
                    action: .council
                )
            )
        }

        return suggestions
    }

    private static func projectSuggestions(
        projectName: String,
        councilAvailable: Bool,
        routeKind: ChatRouteKind,
        agentAvailable: Bool
    ) -> [EmptyChatStarterSuggestion] {
        var suggestions = [
            EmptyChatStarterSuggestion(
                title: "Brief project",
                symbolName: "folder.badge.gearshape",
                prompt: "Use \(projectName)'s files, links, and notes to brief me on the next best move."
            ),
            EmptyChatStarterSuggestion(
                title: "Context to actions",
                symbolName: "list.bullet.clipboard",
                prompt: "Use \(projectName)'s files, links, and notes to turn this into actions, trackers, reminders, calendar drafts, risks, and decisions. Preview before creating anything."
            ),
            EmptyChatStarterSuggestion(
                title: "Draft trackers",
                symbolName: "calendar.badge.clock",
                prompt: "Use \(projectName)'s context to draft recurring trackers, reminders, and calendar items. Include cadence, date, time, timezone, missing_fields, confidence, and exact commands. Preview before creating anything."
            ),
            EmptyChatStarterSuggestion(
                title: "Sources & proof",
                symbolName: "checkmark.shield",
                prompt: trustPrompt(for: routeKind, projectName: projectName),
                action: .trust
            )
        ]

        if agentAvailable {
            suggestions.append(
                EmptyChatStarterSuggestion(
                    title: "Handoff to Agent",
                    symbolName: "terminal",
                    prompt: "Use \(projectName)'s context to define an agent mission with goal, files or links to inspect, risks, and focused verification.",
                    action: .agent
                )
            )
        } else if councilAvailable {
            suggestions.append(
                EmptyChatStarterSuggestion(
                    title: "Review with Council",
                    symbolName: "square.grid.2x2",
                    prompt: "Use \(projectName)'s context and compare the council's answers on the next decision: ",
                    action: .council
                )
            )
        } else {
            suggestions.append(
                EmptyChatStarterSuggestion(
                    title: "Find blockers",
                    symbolName: "exclamationmark.triangle",
                    prompt: "Review \(projectName)'s context and identify the highest-risk blockers, missing facts, and next checks."
                )
            )
        }

        return suggestions
    }

    private static func trustPrompt(for routeKind: ChatRouteKind, projectName: String?) -> String {
        let subject = projectName.map {
            "Use \($0)'s context when relevant, answer with sources where useful, then explain"
        } ?? "Answer this with sources where useful, then explain"

        switch routeKind {
        case .nearPrivate:
            return "\(subject) what the current NEAR Private route can prove, whether the proof report is fresh, and what still depends on source quality or trust: "
        case .nearCloud:
            return "\(subject) why this NEAR AI Cloud route does not carry NEAR Private proof, what the trust boundary is instead, and which sources matter most: "
        case .ironclawMobile:
            return "\(subject) what stays on-device with IronClaw Mobile, what is not covered by NEAR Private proof, and where the cited sources came from: "
        case .ironclawHosted:
            return "\(subject) the hosted-agent trust boundary, what is not covered by NEAR Private proof, and where the cited sources came from: "
        }
    }
}

@MainActor
enum EmptyChatStarterCoordinator {
    static func suggestions(for chatStore: ChatStore) -> [EmptyChatStarterSuggestion] {
        let agentAvailable =
            chatStore.ironclawRemoteWorkstationAvailable ||
            chatStore.agentModels.contains(where: { $0.id == ModelOption.ironclawMobileModelID })
        let councilAvailable = chatStore.isCouncilModeEnabled || chatStore.defaultCouncilModels.count >= 2
        var defaults = EmptyChatStarterPlanner.suggestions(
            projectName: chatStore.selectedProject?.name,
            isCouncilModeEnabled: chatStore.isCouncilModeEnabled,
            councilAvailable: councilAvailable,
            routeKind: chatStore.selectedRouteKind,
            agentAvailable: agentAvailable
        )

        if let starter = QuickIntentParser.personalizedStarter(fromMemory: chatStore.memoryStore.items.map(\.text)) {
            let suggestion = EmptyChatStarterSuggestion(
                title: starter.title,
                symbolName: starter.symbol,
                prompt: starter.prompt
            )
            defaults.removeAll { $0.title == suggestion.title }
            defaults.insert(suggestion, at: 0)
        }
        return Array(defaults.prefix(6))
    }

    @discardableResult
    static func apply(
        _ suggestion: EmptyChatStarterSuggestion,
        to chatStore: ChatStore,
        onOpenProject: (() -> Void)? = nil,
        onOpenCouncil: (() -> Void)? = nil
    ) -> Bool {
        var shouldFocusComposer = true

        switch suggestion.action {
        case .draft:
            break
        case .research:
            chatStore.selectSourceMode(.web)
            if !chatStore.researchModeEnabled {
                chatStore.toggleResearchMode()
            }
        case .project:
            chatStore.selectSourceMode(chatStore.selectedProject == nil ? .files : .all)
            if chatStore.selectedProject == nil {
                onOpenProject?()
                shouldFocusComposer = false
            }
        case .council:
            chatStore.useDefaultCouncilLineup()
            if let onOpenCouncil {
                onOpenCouncil()
                shouldFocusComposer = false
            }
        case .agent:
            if chatStore.agentModels.contains(where: { $0.id == ModelOption.ironclawMobileModelID }) {
                chatStore.selectModel(ModelOption.ironclawMobileModelID)
            } else if chatStore.ironclawRemoteWorkstationAvailable {
                chatStore.selectModel(ModelOption.ironclawModelID)
            }
        case .trust:
            if chatStore.selectedProject != nil {
                chatStore.selectSourceMode(.all)
            } else {
                chatStore.selectSourceMode(.web)
                if !chatStore.selectedRouteUsesNearCloud, !chatStore.researchModeEnabled {
                    chatStore.toggleResearchMode()
                }
            }
        }

        chatStore.draft = stagedPrompt(
            suggestion.prompt,
            existingDraft: chatStore.draft
        )
        return shouldFocusComposer
    }

    private static func stagedPrompt(_ prompt: String, existingDraft: String) -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDraft = existingDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return existingDraft }
        guard !trimmedDraft.isEmpty else { return trimmedPrompt }
        guard !trimmedDraft.hasPrefix(trimmedPrompt) else { return trimmedDraft }
        return trimmedPrompt + trimmedDraft
    }
}

/// Empty state for a new chat thread — v2 redesign.
/// Single NEAR mark + caption, optional prompt-suggestion chips below.
/// All setup-recovery / quickstart / capability-callout patterns from the
/// pre-v2 design are intentionally removed — those belong in Setup, never on
/// the chat surface.
struct EmptyChatView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var onOpenProject: () -> Void = {}
    var onOpenCouncil: () -> Void = {}

    var body: some View {
        VStack(spacing: 14) {
            NearAppIconMark(size: 56)

            VStack(spacing: 5) {
                Text("What do you want to ask?")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Private by default. Add sources, Project, Council, or Agent when needed.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !emptyPromptSuggestions.isEmpty {
                LazyVGrid(columns: suggestionColumns, spacing: 8) {
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

    private func suggestionChip(_ suggestion: EmptyChatStarterSuggestion) -> some View {
        Button {
            fillDraft(for: suggestion)
        } label: {
            Label(suggestion.title, systemImage: suggestion.symbolName)
                .font(.footnote.weight(.medium))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.90)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.appSecondaryBackground, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use suggestion, \(suggestion.title)")
        .accessibilityHint(accessibilityHint(for: suggestion))
    }

    private func accessibilityHint(for suggestion: EmptyChatStarterSuggestion) -> String {
        switch suggestion.action {
        case .draft:
            return "Starts a draft without sending."
        case .research:
            return "Turns on Research Mode and starts a draft."
        case .project:
            return "Opens Project context and starts a draft."
        case .council:
            return "Enables Council and starts a draft."
        case .agent:
            return "Selects the Agent route and starts a draft."
        case .trust:
            return "Starts a draft for checking sources and trust boundaries."
        }
    }

    private var suggestionRows: [[EmptyChatStarterSuggestion]] {
        stride(from: 0, to: emptyPromptSuggestions.count, by: 2).map { start in
            Array(emptyPromptSuggestions[start..<min(start + 2, emptyPromptSuggestions.count)])
        }
    }

    private var suggestionColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(minimum: 220), spacing: 8)]
        }
        return [GridItem(.adaptive(minimum: 148), spacing: 8)]
    }

    private var emptyPromptSuggestions: [EmptyChatStarterSuggestion] {
        EmptyChatStarterCoordinator.suggestions(for: chatStore)
    }

    private func fillDraft(for suggestion: EmptyChatStarterSuggestion) {
        AppHaptics.selection()
        _ = EmptyChatStarterCoordinator.apply(
            suggestion,
            to: chatStore,
            onOpenProject: onOpenProject,
            onOpenCouncil: onOpenCouncil
        )
    }
}
