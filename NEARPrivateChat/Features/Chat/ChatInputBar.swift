import SwiftUI
import UniformTypeIdentifiers

private enum ComposerFocusMode: String, CaseIterable, Identifiable {
    case auto
    case web
    case project
    case research

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .web: "Web"
        case .project: "Project"
        case .research: "Research"
        }
    }

    var symbolName: String {
        switch self {
        case .auto: "sparkles"
        case .web: "globe"
        case .project: "folder"
        case .research: "doc.text.magnifyingglass"
        }
    }
}

private enum SlashCommandAction {
    case council
    case verify
    case project
    case sources
}

private struct SlashCommandSuggestion: Identifiable {
    var id: String { command }
    let command: String
    let title: String
    let subtitle: String
    let symbolName: String
    let action: SlashCommandAction
}

struct InputBar: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject var transcriptStore: ChatTranscriptStore
    @ObservedObject var composerStore: ChatComposerStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var showingFileImporter = false
    @State private var showingProjectFiles = false
    @State private var showingSecurity = false
    @State private var showingAgentWorkspace = false
    @State private var showingAccountSettings = false
    @State private var showingCapabilities = false
    @State private var showingModelPicker = false
    @State private var modelPickerOpeningCouncil = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shouldShowProjectContextStrip {
                ProjectContextStrip(
                    attachments: chatStore.activeProjectContextAttachments,
                    linkCount: chatStore.activeProjectContextLinks.count
                )
            }

            if !composerStore.pendingAttachments.isEmpty {
                AttachmentStrip(attachments: composerStore.pendingAttachments) { attachment in
                    chatStore.removePendingAttachment(attachment)
                }
            }

            if composerStore.isUploadingAttachment {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Uploading file")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)
            }

            if let issue = composerStore.routeReadinessIssue {
                RouteReadinessRecoveryCard(
                    issue: issue,
                    onPrimaryAction: { handleRouteReadinessRecovery(issue.recoveryAction) },
                    onSwitchPrivate: { chatStore.performRouteReadinessRecovery(.switchToPrivate) },
                    onViewCapabilities: { showingCapabilities = true }
                )
            } else if let notice = chatStore.selectedRouteNotice {
                Label(notice, systemImage: chatStore.selectedRouteUsesNearCloud ? "cloud" : "point.3.connected.trianglepath.dotted")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 2)
            }

            if !visibleSlashCommands.isEmpty {
                slashCommandTray
            }

            composerRoutingControls

            VStack(alignment: .leading, spacing: 4) {
                TextField(composerPlaceholder, text: draftBinding, axis: .vertical)
                    .textFieldStyle(.plain)
                    .tokenInputTraits()
                    .autocorrectionDisabled()
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .onSubmit {
                        chatStore.sendDraft()
                        isFocused = false
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
                    .disabled(transcriptStore.isStreaming)
                    .accessibilityLabel("Message")
                    .accessibilityHint(transcriptStore.isStreaming ? "Stop the current response before editing the draft." : "Enter a message or slash command.")

                HStack(spacing: 8) {
                    Button {
                        AppHaptics.selection()
                        showingFileImporter = true
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(transcriptStore.isStreaming)
                    .accessibilityLabel("Attach File")

                    Spacer(minLength: 0)

                    Button {
                        if transcriptStore.isStreaming {
                            AppHaptics.mediumImpact()
                            chatStore.cancelStream()
                        } else {
                            AppHaptics.lightImpact()
                            chatStore.sendDraft()
                            isFocused = false
                        }
                    } label: {
                        Image(systemName: transcriptStore.isStreaming ? "stop.fill" : "arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(sendIconColor)
                            .frame(width: 32, height: 32)
                            .background(sendButtonColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(sendDisabled)
                    .scaleEffect(sendButtonScale)
                    .opacity(reduceMotion ? (sendDisabled ? 0.72 : 1) : 1)
                    .animation(sendButtonAnimation, value: canSend)
                    .animation(sendButtonAnimation, value: transcriptStore.isStreaming)
                    .accessibilityLabel(transcriptStore.isStreaming ? "Stop response" : "Send message")
                    .accessibilityHint(transcriptStore.isStreaming ? "Stops the current response." : "Sends the draft and staged attachments.")
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isFocused ? Color.brandBlue.opacity(0.45) : Color.appBorder, lineWidth: 1)
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.pdf, .plainText, .text, .commaSeparatedText, .json, .data],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                for url in urls.prefix(5) {
                    Task { await chatStore.addAttachment(from: url) }
                }
            }
        }
        .sheet(isPresented: $showingProjectFiles) {
            ProjectFilesView()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingSecurity) {
            SecurityView()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingAgentWorkspace) {
            AgentWorkspaceView()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingAccountSettings) {
            AccountSettingsView(onRunSetupAgain: {})
                .environmentObject(chatStore)
                .environmentObject(sessionStore)
        }
        .sheet(isPresented: $showingCapabilities) {
            CapabilitiesView(
                onOpenAccountSettings: {
                    showingAccountSettings = true
                },
                onOpenSecurity: {
                    showingSecurity = true
                },
                onOpenAgentWorkspace: {
                    showingAgentWorkspace = true
                },
                onRunSetupAgain: nil
            )
            .environmentObject(chatStore)
            .environmentObject(sessionStore)
        }
        .sheet(isPresented: $showingModelPicker) {
            ModelPickerView(openingCouncil: modelPickerOpeningCouncil)
                .environmentObject(chatStore)
        }
    }

    private var shouldShowProjectContextStrip: Bool {
        !chatStore.activeProjectContextAttachments.isEmpty || !chatStore.activeProjectContextLinks.isEmpty
    }

    private var canSend: Bool {
        composerState.hasSendableContent
    }

    private var sendDisabled: Bool {
        composerState.sendDisabled
    }

    private var composerState: ComposerState {
        ComposerState(
            draft: composerStore.draft,
            pendingAttachments: composerStore.pendingAttachments,
            isStreaming: transcriptStore.isStreaming,
            routeReadinessTitle: composerStore.routeReadinessIssue?.title,
            routeReadinessMessage: composerStore.routeReadinessIssue?.message
        )
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { composerStore.draft },
            set: { chatStore.draft = $0 }
        )
    }

    private var sendButtonColor: Color {
        if transcriptStore.isStreaming {
            return .red.opacity(0.90)
        }
        return sendDisabled ? Color.appSecondaryBackground : Color.brandBlue
    }

    private var sendIconColor: Color {
        sendDisabled && !transcriptStore.isStreaming ? .secondary : .white
    }

    private var sendButtonScale: CGFloat {
        guard !reduceMotion else { return 1 }
        if transcriptStore.isStreaming {
            return 1
        }
        return canSend ? 1 : 0.9
    }

    private var sendButtonAnimation: Animation? {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.22, dampingFraction: 0.72)
    }

    private var composerPlaceholder: String {
        if chatStore.selectedRouteUsesNearCloud || chatStore.selectedProviderDisplayName == "IronClaw" {
            return chatStore.inputPlaceholder
        }
        if researchButtonActive {
            return "Ask for a researched answer with citations"
        }
        switch chatStore.sourceMode {
        case .auto:
            return "Ask anything"
        case .web:
            return "Ask with live web"
        case .files:
            return "Ask your project files"
        case .links:
            return "Ask your saved links"
        case .all:
            return "Ask across sources"
        }
    }

    private var researchButtonActive: Bool {
        chatStore.researchModeEnabled && !chatStore.selectedRouteUsesNearCloud
    }

    private var composerRoutingControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                Button {
                    openModelPicker(openingCouncil: false)
                } label: {
                    ComposerRouteChip(
                        title: chatStore.selectedModelDisplayName,
                        symbolName: composerModelSymbolName,
                        isActive: true,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Model \(chatStore.selectedModelDisplayName)")
                .accessibilityHint("Choose GLM, NEAR Cloud, or another model for the next message.")

                Button {
                    openModelPicker(openingCouncil: true)
                } label: {
                    ComposerRouteChip(
                        title: chatStore.isCouncilModeEnabled ? "Council \(chatStore.activeCouncilModels.count)" : "Council",
                        symbolName: "square.grid.2x2",
                        isActive: chatStore.isCouncilModeEnabled,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(chatStore.isCouncilModeEnabled ? "LLM Council active" : "Configure LLM Council")
                .accessibilityHint("Opens the Council lineup for the next message.")

                Menu {
                    ForEach(ModelReasoningEffort.allCases) { effort in
                        Button {
                            chatStore.setReasoningEffort(effort)
                        } label: {
                            Label(effort.title, systemImage: effort == chatStore.advancedModelParams.reasoningEffort ? "checkmark" : "circle")
                        }
                    }
                    Divider()
                    Button {
                        openModelPicker(openingCouncil: false)
                    } label: {
                        Label("Open model settings", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    ComposerRouteChip(
                        title: "Effort \(chatStore.advancedModelParams.reasoningEffort.title)",
                        symbolName: "brain.head.profile",
                        isActive: chatStore.advancedModelParams.reasoningEffort != .automatic,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reasoning effort \(chatStore.advancedModelParams.reasoningEffort.title)")
                .accessibilityHint("Changes reasoning effort from the chat window.")
            }
            .padding(.horizontal, 1)
        }
    }

    private var composerModelSymbolName: String {
        if chatStore.selectedModelOption?.isIronclawModel == true {
            return "terminal"
        }
        if chatStore.selectedRouteUsesNearCloud {
            return "cloud"
        }
        return "cpu"
    }

    private func openModelPicker(openingCouncil: Bool) {
        AppHaptics.selection()
        modelPickerOpeningCouncil = openingCouncil
        showingModelPicker = true
    }

    private var composerSourceTitle: String {
        if chatStore.selectedRouteUsesNearCloud {
            return "Cloud"
        }
        if researchButtonActive {
            return "Research"
        }
        return chatStore.sourceMode.shortTitle
    }

    private var composerContextModes: [ChatSourceMode] {
        [.auto, .web, .files, .links]
    }

    private var focusModes: [ComposerFocusMode] {
        [.auto, .web, .project, .research]
    }

    private var selectedFocusMode: ComposerFocusMode? {
        if chatStore.selectedRouteUsesNearCloud {
            return nil
        }
        if researchButtonActive {
            return .research
        }
        switch chatStore.sourceMode {
        case .auto: return .auto
        case .web: return .web
        case .files, .links, .all: return .project
        }
    }

    private var focusModeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(focusModes) { mode in
                    Button {
                        selectFocusMode(mode)
                    } label: {
                        Label(mode.title, systemImage: mode.symbolName)
                            .font(.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                            .foregroundStyle(focusModeColor(mode))
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(focusModeBackground(mode), in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(focusModeBorder(mode), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(transcriptStore.isStreaming || chatStore.selectedRouteUsesNearCloud)
                    .accessibilityLabel(selectedFocusMode == mode ? "Focus: \(mode.title), selected" : "Focus: \(mode.title)")
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var slashCommands: [SlashCommandSuggestion] {
        [
            SlashCommandSuggestion(
                command: "/council",
                title: "Council",
                subtitle: "Use a multi-model answer",
                symbolName: "square.grid.2x2",
                action: .council
            ),
            SlashCommandSuggestion(
                command: "/verify",
                title: "Verify",
                subtitle: "Open verification details",
                symbolName: "checkmark.shield",
                action: .verify
            ),
            SlashCommandSuggestion(
                command: "/project",
                title: "Project",
                subtitle: "Open project context",
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

    private var slashQuery: String? {
        let trimmed = composerStore.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let token = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first ?? Substring(trimmed)
        return String(token.dropFirst()).lowercased()
    }

    private var visibleSlashCommands: [SlashCommandSuggestion] {
        guard let query = slashQuery else { return [] }
        guard !query.isEmpty else { return slashCommands }
        return slashCommands.filter { suggestion in
            suggestion.command.dropFirst().lowercased().hasPrefix(query) ||
                suggestion.title.lowercased().contains(query)
        }
    }

    private var slashCommandTray: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(visibleSlashCommands) { suggestion in
                Button {
                    applySlashCommand(suggestion)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: suggestion.symbolName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.brandBlue)
                            .frame(width: 24, height: 24)
                            .background(Color.brandBlue.opacity(0.09), in: Circle())
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

    private func selectFocusMode(_ mode: ComposerFocusMode) {
        guard !chatStore.selectedRouteUsesNearCloud else { return }
        AppHaptics.selection()
        switch mode {
        case .auto:
            chatStore.selectSourceMode(.auto)
        case .web:
            chatStore.selectSourceMode(.web)
        case .project:
            chatStore.selectSourceMode(chatStore.selectedProject == nil ? .files : .all)
            if chatStore.selectedProject == nil && composerStore.pendingAttachments.isEmpty {
                showingProjectFiles = true
            }
        case .research:
            if chatStore.sourceMode != .web {
                chatStore.sourceMode = .web
            }
            if !chatStore.researchModeEnabled {
                chatStore.toggleResearchMode()
            }
        }
    }

    private func applySlashCommand(_ suggestion: SlashCommandSuggestion) {
        AppHaptics.selection()
        let remainder = remainingDraft(after: suggestion.command)
        switch suggestion.action {
        case .council:
            chatStore.useDefaultCouncilLineup()
            chatStore.draft = remainder
            isFocused = true
        case .verify:
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

    private func handleRouteReadinessRecovery(_ action: ChatStore.RouteReadinessIssue.RecoveryAction) {
        AppHaptics.selection()
        switch action {
        case .addNearCloudKey, .configureIronClawEndpoint:
            showingAccountSettings = true
        case .switchToPrivate, .editCouncilLineup:
            chatStore.performRouteReadinessRecovery(action)
        }
    }

    private func remainingDraft(after command: String) -> String {
        let trimmed = composerStore.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(command) else { return "" }
        return trimmed
            .dropFirst(command.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func focusModeColor(_ mode: ComposerFocusMode) -> Color {
        guard selectedFocusMode == mode else { return .secondary }
        return mode == .auto ? Color.brandBlack : Color.white
    }

    private func focusModeBackground(_ mode: ComposerFocusMode) -> Color {
        guard selectedFocusMode == mode else { return Color.clear }
        return mode == .auto ? Color.brandSky : Color.brandBlue
    }

    private func focusModeBorder(_ mode: ComposerFocusMode) -> Color {
        guard selectedFocusMode == mode else { return Color.appBorder.opacity(0.8) }
        return Color.clear
    }
}

struct ComposerRouteChip: View {
    let title: String
    let symbolName: String
    let isActive: Bool
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.caption.weight(.bold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .opacity(0.65)
            }
        }
        .foregroundStyle(isActive ? activeForeground : Color.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(background, in: Capsule())
        .overlay {
            Capsule()
                .stroke(border, lineWidth: 1)
        }
    }

    private var activeForeground: Color {
        symbolName == "brain.head.profile" ? Color.brandBlack : Color.brandBlue
    }

    private var background: Color {
        if isActive {
            return symbolName == "brain.head.profile" ? Color.brandSky.opacity(0.55) : Color.brandBlue.opacity(0.08)
        }
        return Color.appPanelBackground
    }

    private var border: Color {
        isActive ? Color.brandBlue.opacity(0.16) : Color.appBorder
    }
}

private struct RouteReadinessRecoveryCard: View {
    let issue: ChatStore.RouteReadinessIssue
    let onPrimaryAction: () -> Void
    let onSwitchPrivate: () -> Void
    let onViewCapabilities: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 28, height: 28)
                    .background(Color.appSymbolBlueBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(issue.message)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button(action: onPrimaryAction) {
                    Label(issue.recoveryTitle, systemImage: primarySymbolName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color.primaryAction, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                if issue.recoveryAction != .switchToPrivate {
                    Button(action: onSwitchPrivate) {
                        Text("Use Private")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.primaryAction)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(action: onViewCapabilities) {
                    Label("Open Capabilities", systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.primaryAction)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.brandBlue.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(issue.title). \(issue.message)")
    }

    private var symbolName: String {
        switch issue.route {
        case .nearCloud: "key"
        case .hostedIronclaw: "terminal"
        case .council: "square.grid.2x2"
        }
    }

    private var primarySymbolName: String {
        switch issue.recoveryAction {
        case .addNearCloudKey: "key"
        case .configureIronClawEndpoint: "point.3.connected.trianglepath.dotted"
        case .switchToPrivate: "lock.shield"
        case .editCouncilLineup: "slider.horizontal.3"
        }
    }
}

private struct ProjectContextStrip: View {
    let attachments: [ChatAttachment]
    let linkCount: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Label(contextLabel, systemImage: "folder")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.brandBlue.opacity(0.10), in: Capsule())

                ForEach(attachments.prefix(4)) { attachment in
                    Label(attachment.name, systemImage: attachment.systemImageName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.appSecondaryBackground, in: Capsule())
                }
            }
        }
    }

    private var contextLabel: String {
        var parts: [String] = []
        if !attachments.isEmpty {
            parts.append(countLabel(attachments.count, singular: "file"))
        }
        if linkCount > 0 {
            parts.append(countLabel(linkCount, singular: "source link"))
        }
        return parts.isEmpty ? "Project context" : parts.joined(separator: " · ")
    }

    private func countLabel(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }
}

private struct AttachmentStrip: View {
    let attachments: [ChatAttachment]
    let onRemove: (ChatAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 6) {
                        Image(systemName: attachment.systemImageName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.brandBlue)
                            .frame(width: 28, height: 28)
                            .background(Color.brandBlue.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(attachmentShelfTitle(for: attachment))
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                            Text(attachmentShelfDetail(for: attachment))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(attachmentShelfTitle(for: attachment)), \(attachmentShelfDetail(for: attachment))")
                        Button {
                            AppHaptics.selection()
                            onRemove(attachment)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(attachment.name)")
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 56)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func attachmentShelfTitle(for attachment: ChatAttachment) -> String {
        if attachment.isLocalPendingText {
            return "Large paste staged"
        }
        if attachment.kind == "pdf_text" {
            return "PDF text extracted"
        }
        return attachment.name
    }

    private func attachmentShelfDetail(for attachment: ChatAttachment) -> String {
        var parts: [String] = []
        if attachment.isLocalPendingText {
            parts.append("Uploads as text on send")
            parts.append(attachment.name)
        } else if attachment.kind == "pdf_text" {
            parts.append("Readable text attachment")
            parts.append(attachment.name)
        } else {
            parts.append(attachment.displayKind)
        }
        if let displaySize = attachment.displaySize {
            parts.append(displaySize)
        }
        return parts.joined(separator: " · ")
    }
}
