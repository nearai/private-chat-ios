import SwiftUI

enum SlashCommandAction {
    case council
    case proof
    case project
    case sources
}

struct SlashCommandSuggestion: Identifiable {
    var id: String { command }
    let command: String
    let title: String
    let subtitle: String
    let symbolName: String
    let action: SlashCommandAction
}

extension InputBar {
    var slashCommands: [SlashCommandSuggestion] {
        [
            SlashCommandSuggestion(
                command: "/council",
                title: "Council",
                subtitle: "Use a multi-model answer",
                symbolName: "square.grid.2x2",
                action: .council
            ),
            SlashCommandSuggestion(
                command: "/proof",
                title: "Proof",
                subtitle: "Open proof report details",
                symbolName: "checkmark.shield",
                action: .proof
            ),
            SlashCommandSuggestion(
                command: "/project",
                title: "Project",
                subtitle: "Open Project context",
                symbolName: "folder.badge.gearshape",
                action: .project
            ),
            SlashCommandSuggestion(
                command: "/sources",
                title: "Sources",
                subtitle: "Use available web, file, and link context",
                symbolName: "rectangle.3.group",
                action: .sources
            )
        ]
    }

    var slashQuery: String? {
        let trimmed = composerStore.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let token = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first ?? Substring(trimmed)
        return String(token.dropFirst()).lowercased()
    }

    var visibleSlashCommands: [SlashCommandSuggestion] {
        guard let query = slashQuery else { return [] }
        guard !query.isEmpty else { return slashCommands }
        return slashCommands.filter { suggestion in
            suggestion.command.dropFirst().lowercased().hasPrefix(query) ||
                suggestion.title.lowercased().contains(query)
        }
    }

    var slashCommandTray: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(visibleSlashCommands) { suggestion in
                Button {
                    applySlashCommand(suggestion)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: suggestion.symbolName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.brandAccent)
                            .frame(width: 24, height: 24)
                            .background(Color.brandAccent.opacity(0.09), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(suggestion.command)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.primary)
                            Text(suggestion.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "return")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.appBorder, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(suggestion.command), \(suggestion.title)")
                .accessibilityHint(suggestion.subtitle)
            }
        }
    }

    var composerSourceSymbolName: String {
        if researchButtonActive {
            return "doc.text.magnifyingglass"
        }
        if autoSourceModeInfersLiveWeb {
            return "globe"
        }
        switch chatStore.sourceMode {
        case .auto:
            return "sparkles"
        case .web:
            return "globe"
        case .links, .files, .all:
            return "folder"
        }
    }

    var sourceModeControlIsAuto: Bool {
        !researchButtonActive && chatStore.sourceMode == .auto
    }

    var sourceModeControlIsWeb: Bool {
        !researchButtonActive && chatStore.sourceMode == .web
    }

    var sourceModeControlIsProject: Bool {
        !researchButtonActive && chatStore.sourceMode != .auto && chatStore.sourceMode != .web
    }

    func sourceModeMenuSymbolName(isActive: Bool, fallback: String = "circle") -> String {
        isActive ? "checkmark" : fallback
    }

    func exactSourceModeMenuSymbolName(for mode: ChatSourceMode) -> String {
        (!researchButtonActive && mode == chatStore.sourceMode) ? "checkmark" : mode.symbolName
    }

    func selectProjectSourceMode() {
        AppHaptics.selection()
        chatStore.selectSourceMode(chatStore.selectedProject == nil ? .files : .all)
        if chatStore.selectedProject == nil && composerStore.pendingAttachments.isEmpty {
            showingProjectFiles = true
        }
    }

    func selectResearchSourceMode() {
        guard !chatStore.selectedRouteUsesNearCloud else { return }
        AppHaptics.selection()
        if chatStore.sourceMode != .web {
            chatStore.sourceMode = .web
        }
        if !chatStore.researchModeEnabled {
            chatStore.toggleResearchMode()
        }
    }

    func sourceModeMenuTitle(for mode: ChatSourceMode) -> String {
        switch mode {
        case .auto:
            return composerStore.pendingAttachments.isEmpty ? "Auto" : "Auto · \(composerStore.pendingAttachments.count) prompt \(composerStore.pendingAttachments.count == 1 ? "file" : "files")"
        case .web:
            return composerStore.pendingAttachments.isEmpty ? "Web" : "Web · \(composerStore.pendingAttachments.count) prompt \(composerStore.pendingAttachments.count == 1 ? "file" : "files")"
        case .links:
            let count = chatStore.selectedProjectLinks.count
            return count == 0 ? "Saved links" : "Saved links · \(count)"
        case .files:
            let count = chatStore.selectedProjectAttachments.count + composerStore.pendingAttachments.count
            return count == 0 ? "Files" : "Files · \(count)"
        case .all:
            let files = chatStore.selectedProjectAttachments.count + composerStore.pendingAttachments.count
            let links = chatStore.selectedProjectLinks.count
            if files > 0 || links > 0 {
                return "Web + Files · \(files) files / \(links) links"
            }
            return "Web + Files"
        }
    }

    func applyQuickStartSuggestion(_ suggestion: EmptyChatStarterSuggestion) {
        AppHaptics.selection()
        let shouldFocusComposer = EmptyChatStarterCoordinator.apply(
            suggestion,
            to: chatStore,
            onOpenProject: {
                showingProjectFiles = true
            }
        )
        isFocused = shouldFocusComposer
    }

    func applySlashCommand(_ suggestion: SlashCommandSuggestion) {
        AppHaptics.selection()
        let remainder = remainingDraft(after: suggestion.command)
        switch suggestion.action {
        case .council:
            chatStore.useDefaultCouncilLineup()
            chatStore.draft = remainder
            isFocused = true
        case .proof:
            chatStore.draft = remainder
            showingSecurity = true
            isFocused = false
        case .project:
            chatStore.draft = remainder
            showingProjectFiles = true
            isFocused = false
        case .sources:
            if !chatStore.selectedRouteUsesNearCloud {
                chatStore.selectSourceMode(chatStore.selectedProject == nil ? .web : .all)
            }
            chatStore.draft = remainder
            showingProjectFiles = chatStore.selectedProject != nil
            isFocused = chatStore.selectedProject == nil
        }
    }

    func handleRouteReadinessRecovery(_ action: ChatStore.RouteReadinessIssue.RecoveryAction) {
        AppHaptics.selection()
        switch action {
        case .addNearCloudKey:
            accountSettingsDeepLink = .nearCloudKeys
            showingAccountSettings = true
        case .configureIronClawEndpoint:
            accountSettingsDeepLink = .ironclawAgent
            showingAccountSettings = true
        case .switchToPrivate, .editCouncilLineup:
            chatStore.performRouteReadinessRecovery(action)
        }
    }

    func remainingDraft(after command: String) -> String {
        let trimmed = composerStore.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(command) else { return "" }
        return trimmed
            .dropFirst(command.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
