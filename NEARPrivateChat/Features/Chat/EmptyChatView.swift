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
                    prompt: "Compare the Council's answers on this task: "
                ),
                EmptyChatStarterSuggestion(
                    title: "Disagreements",
                    symbolName: "arrow.triangle.branch",
                    prompt: "Show where the Council agrees and disagrees on: "
                ),
                EmptyChatStarterSuggestion(
                    title: "Validate",
                    symbolName: "checkmark.shield",
                    prompt: "Have each Council model check this claim and flag what's uncertain: "
                ),
                EmptyChatStarterSuggestion(
                    title: "Decide",
                    symbolName: "arrow.left.arrow.right.circle",
                    prompt: "Ask the Council which option to pick and why for: "
                )
            ]
        }

        var suggestions = [
            EmptyChatStarterSuggestion(
                title: "Next actions",
                symbolName: "checklist",
                prompt: "Turn this into next moves: trackers, reminders, calendar items, risks, decisions, and exact commands. Preview before creating anything: "
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
                prompt: "Use attached files or a Project to turn this into actions, trackers, reminders, risks, decisions, and missing facts. Preview before creating anything: ",
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
                    prompt: "Agent mission: define the goal, context to inspect, tools, risks, and verification for this task: ",
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
                prompt: "Use \(projectName)'s files, links, and notes to brief the next best move."
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
                    prompt: "Use \(projectName)'s context to define an Agent mission: goal, files or links to inspect, risks, and verification.",
                    action: .agent
                )
            )
        } else if councilAvailable {
            suggestions.append(
                EmptyChatStarterSuggestion(
                    title: "Review with Council",
                    symbolName: "square.grid.2x2",
                    prompt: "Use \(projectName)'s context to compare the Council's answers on the next decision: ",
                    action: .council
                )
            )
        } else {
            suggestions.append(
                EmptyChatStarterSuggestion(
                    title: "Find blockers",
                    symbolName: "exclamationmark.triangle",
                    prompt: "Review \(projectName)'s context for the highest-risk blockers, missing facts, and next checks."
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
            return "\(subject) what the NEAR Private route can prove, whether the proof report is fresh, and what still depends on source quality: "
        case .nearCloud:
            return "\(subject) why the NEAR AI Cloud route carries no NEAR Private proof, what the trust boundary is, and which sources matter most: "
        case .ironclawMobile:
            return "\(subject) what stays on-device with IronClaw Mobile, what NEAR Private proof does not cover, and where the cited sources came from: "
        case .ironclawHosted:
            return "\(subject) the Hosted IronClaw trust boundary, what NEAR Private proof does not cover, and where the cited sources came from: "
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

        // On agent routes inside a project, lead with concrete tasks built
        // from the project's real files/links instead of generic starters.
        if chatStore.selectedRouteKind.isIronclawRoute, let project = chatStore.selectedProject {
            let agentSuggestions = AgentSuggestionPlanner.suggestions(
                projectName: project.name,
                attachmentNames: project.attachments.map(\.name),
                linkHosts: project.links.compactMap(\.host),
                recentConversationTitles: []
            ).map { EmptyChatStarterSuggestion(title: $0.title, symbolName: $0.symbolName, prompt: $0.prompt) }
            if !agentSuggestions.isEmpty {
                defaults = agentSuggestions + defaults.filter { fallback in
                    !agentSuggestions.contains(where: { $0.title == fallback.title })
                }
            }
        }

        if chatStore.selectedRouteKind.isIronclawRoute && !agentStarterAvailable(in: chatStore) {
            defaults.removeAll { $0.action == .agent }
            defaults.insert(
                EmptyChatStarterSuggestion(
                    title: "Connect Agent",
                    symbolName: "point.3.connected.trianglepath.dotted",
                    prompt: "Set up Hosted IronClaw before running Agent tasks: add a Hosted IronClaw URL, save an Agent token, then check hosted tools.",
                    action: .agent
                ),
                at: 0
            )
        }

        if chatStore.isCouncilModeEnabled && !councilStarterAvailable(in: chatStore) {
            defaults.removeAll { $0.action == .council }
            defaults.insert(
                EmptyChatStarterSuggestion(
                    title: "Set up Council",
                    symbolName: "person.3",
                    prompt: "Set up Council before comparing answers: choose at least two available models, then ask: ",
                    action: .council
                ),
                at: 0
            )
        }

        if let starter = QuickIntentParser.personalizedStarter(fromMemory: chatStore.memoryStore.items.map(\.text)) {
            let suggestion = EmptyChatStarterSuggestion(
                title: starter.title,
                symbolName: starter.symbol,
                prompt: starter.prompt
            )
            defaults.removeAll { $0.title == suggestion.title }
            defaults.insert(suggestion, at: 0)
        }
        return Array(defaults.prefix(4))
    }

    static func agentStarterAvailable(in chatStore: ChatStore) -> Bool {
        chatStore.agentModels.contains(where: { $0.id == ModelOption.ironclawMobileModelID }) ||
            chatStore.ironclawRemoteWorkstationAvailable
    }

    static func councilStarterAvailable(in chatStore: ChatStore) -> Bool {
        chatStore.isCouncilModeEnabled && chatStore.activeCouncilModels.count >= 2 ||
            chatStore.defaultCouncilModels.count >= 2
    }

    @discardableResult
    static func prepare(
        _ suggestion: EmptyChatStarterSuggestion,
        to chatStore: ChatStore,
        onOpenProject: (() -> Void)? = nil,
        onOpenCouncil: (() -> Void)? = nil
    ) -> Bool {
        switch suggestion.action {
        case .draft:
            return true
        case .research:
            chatStore.selectSourceMode(.web)
            if !chatStore.researchModeEnabled {
                chatStore.toggleResearchMode()
            }
            return true
        case .project:
            chatStore.selectSourceMode(chatStore.selectedProject == nil ? .files : .all)
            guard chatStore.selectedProject != nil else {
                onOpenProject?()
                return false
            }
            return true
        case .council:
            guard councilStarterAvailable(in: chatStore) else {
                onOpenCouncil?()
                return false
            }
            chatStore.useDefaultCouncilLineup()
            if let onOpenCouncil {
                onOpenCouncil()
                return false
            }
            return true
        case .agent:
            guard agentStarterAvailable(in: chatStore) else {
                chatStore.switchToPrivateFallbackModel()
                return true
            }
            if chatStore.agentModels.contains(where: { $0.id == ModelOption.ironclawMobileModelID }) {
                chatStore.selectModel(ModelOption.ironclawMobileModelID)
            } else if chatStore.ironclawRemoteWorkstationAvailable {
                chatStore.selectModel(ModelOption.ironclawModelID)
            }
            return true
        case .trust:
            if chatStore.selectedProject != nil {
                chatStore.selectSourceMode(.all)
            } else {
                chatStore.selectSourceMode(.web)
                if !chatStore.selectedRouteUsesNearCloud, !chatStore.researchModeEnabled {
                    chatStore.toggleResearchMode()
                }
            }
            return true
        }
    }

    nonisolated static func stagedPrompt(_ prompt: String, existingDraft: String) -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDraft = existingDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return existingDraft }
        guard !trimmedDraft.isEmpty else { return trimmedPrompt }
        guard !trimmedDraft.hasPrefix(trimmedPrompt) else { return trimmedDraft }
        return "\(trimmedPrompt) \(trimmedDraft)"
    }

    @discardableResult
    static func apply(
        _ suggestion: EmptyChatStarterSuggestion,
        to chatStore: ChatStore,
        onOpenProject: (() -> Void)? = nil,
        onOpenCouncil: (() -> Void)? = nil
    ) -> Bool {
        let shouldFocusComposer = prepare(
            suggestion,
            to: chatStore,
            onOpenProject: onOpenProject,
            onOpenCouncil: onOpenCouncil
        )

        chatStore.draft = stagedPrompt(suggestion.prompt, existingDraft: chatStore.draft)
        return shouldFocusComposer
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
        VStack(spacing: 12) {
            NearAppIconMark(size: 52)

            VStack(spacing: 5) {
                Text("What do you want to ask?")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Ask privately, then add sources or tools only when the task needs them.")
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
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: suggestion.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 24, height: 24)

                Text(suggestion.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.90)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
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
            return EmptyChatStarterCoordinator.councilStarterAvailable(in: chatStore) ? "Enables Council and starts a draft." : "Opens Council setup before starting a draft."
        case .agent:
            return EmptyChatStarterCoordinator.agentStarterAvailable(in: chatStore) ? "Selects the Agent route and starts a draft." : "Starts an Agent setup draft without selecting an unavailable route."
        case .trust:
            return "Starts a draft for checking sources and trust boundaries."
        }
    }

    private var suggestionColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(minimum: 220), spacing: 8)]
        }
        return [
            GridItem(.flexible(minimum: 0), spacing: 8),
            GridItem(.flexible(minimum: 0), spacing: 8)
        ]
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
