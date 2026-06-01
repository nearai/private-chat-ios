import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import Speech
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

private enum SlashCommandAction {
    case council
    case proof
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
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showingProjectFiles = false
    @State private var showingSecurity = false
    @State private var showingAgentWorkspace = false
    @State private var showingAccountSettings = false
    @State private var accountSettingsDeepLink: AccountSettingsDeepLink?
    @State private var showingCapabilities = false
    @State private var showingModelPicker = false
    @State private var modelPickerOpeningCouncil = false
    @StateObject private var dictation = VoiceDictation()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shouldShowProjectContextStrip {
                ProjectContextStrip(
                    attachments: chatStore.activeProjectContextAttachments,
                    linkCount: chatStore.activeProjectContextLinks.count
                )
            }

            if !composerStore.pendingAttachments.isEmpty {
                AttachmentStrip(
                    attachments: composerStore.pendingAttachments,
                    showsMetadataOnly: chatStore.selectedRouteKind == .ironclawHosted
                ) { attachment in
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
            }

            if !visibleSlashCommands.isEmpty {
                slashCommandTray
            }

            composerRouteControl

            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button {
                        AppHaptics.selection()
                        showingFileImporter = true
                    } label: {
                        Label("Files", systemImage: "folder")
                    }

                    Button {
                        AppHaptics.selection()
                        showingPhotoPicker = true
                    } label: {
                        Label("Photos", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        AppHaptics.selection()
                        openCamera()
                    } label: {
                        Label("Camera", systemImage: "camera")
                    }

                    Button {
                        AppHaptics.selection()
                        attachPasteboard()
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(transcriptStore.isStreaming)
                .accessibilityLabel("Add attachment")
                .accessibilityHint("Choose files, photos, camera capture, or pasteboard text.")

                TextField(
                    "",
                    text: draftBinding,
                    prompt: Text(composerPlaceholder)
                        .font(.body)
                        .foregroundColor(Color.textTertiary),
                    axis: .vertical
                )
                    .textFieldStyle(.plain)
                    .tokenInputTraits()
                    .autocorrectionDisabled()
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                    .onSubmit {
                        chatStore.sendDraft()
                        isFocused = false
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                    .disabled(transcriptStore.isStreaming)
                    .accessibilityLabel("Message")
                    .accessibilityHint(transcriptStore.isStreaming ? "Stop the current response before editing the draft." : "Enter a message or slash command.")

                if !transcriptStore.isStreaming && (!canSend || dictation.isRecording) {
                    Button {
                        AppHaptics.lightImpact()
                        if !dictation.isRecording { isFocused = false }
                        dictation.toggle()
                    } label: {
                        Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(dictation.isRecording ? Color.proofMismatch : Color.textSecondary)
                            .frame(width: 44, height: 44)
                            .background(
                                dictation.isRecording ? Color.proofMismatch.opacity(0.14) : Color.clear,
                                in: Circle()
                            )
                    }
                    .accessibilityLabel(dictation.isRecording ? "Stop dictation" : "Voice input")
                    .accessibilityHint(dictation.isRecording ? "Stops dictation and keeps the transcribed text." : "Dictate your message by voice.")
                    .onAppear {
                        dictation.onTranscript = { transcript in
                            chatStore.draft = transcript
                        }
                    }
                }

                if (canSend && !dictation.isRecording) || transcriptStore.isStreaming {
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
                        Image(systemName: transcriptStore.isStreaming ? "stop.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 36, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(transcriptStore.isStreaming ? Color.proofMismatch : Color.actionPrimary)
                            .frame(width: 44, height: 44)
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
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .glassBackground(in: Capsule())
            .overlay {
                Capsule()
                    .stroke(isFocused ? Color.actionPrimary.opacity(0.38) : Color.appBorder, lineWidth: 0.5)
            }
        }
        .safeAreaPadding(.bottom, 8)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [
                .pdf,
                .plainText,
                .text,
                .commaSeparatedText,
                .json,
                .image,
                UTType(filenameExtension: "tsv") ?? .text,
                UTType(filenameExtension: "xlsx") ?? .data,
                UTType(filenameExtension: "xls") ?? .data,
                .data
            ],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                for url in urls.prefix(5) {
                    Task { await chatStore.addAttachment(from: url) }
                }
            }
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 5,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { items in
            attachPhotoItems(items)
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showingCamera) {
            CameraCaptureView { image in
                showingCamera = false
                attachCapturedImage(image)
            } onCancel: {
                showingCamera = false
            }
        }
        #endif
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
        .sheet(isPresented: $showingAccountSettings, onDismiss: {
            accountSettingsDeepLink = nil
        }) {
            AccountSettingsView(initialDeepLink: accountSettingsDeepLink, onRunSetupAgain: {})
                .environmentObject(chatStore)
                .environmentObject(sessionStore)
        }
        .sheet(isPresented: $showingCapabilities) {
            CapabilitiesView(
                onOpenAccountSettings: { deepLink in
                    accountSettingsDeepLink = deepLink
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
            return .proofMismatch
        }
        return sendDisabled ? Color.appSecondaryBackground : Color.actionPrimary
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

    private var researchButtonActive: Bool {
        chatStore.researchModeEnabled && !chatStore.selectedRouteUsesNearCloud
    }

    private var composerRoutingControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
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
                .accessibilityHint("Choose a private, Cloud, Council, or Agent model for the next message.")

                Button {
                    openModelPicker(openingCouncil: true)
                } label: {
                    ComposerRouteChip(
                        title: chatStore.isCouncilModeEnabled ? "Council \(chatStore.activeCouncilModels.count)" : "Council",
                        symbolName: "person.3",
                        isActive: chatStore.isCouncilModeEnabled,
                        showsChevron: false
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(chatStore.isCouncilModeEnabled ? "LLM Council active" : "Configure LLM Council")
                .accessibilityHint("Opens the Council lineup for the next message.")

                if selectedModelSupportsReasoningEffort {
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
                            symbolName: "gauge.medium",
                            isActive: chatStore.advancedModelParams.reasoningEffort != .automatic,
                            showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reasoning effort \(chatStore.advancedModelParams.reasoningEffort.title)")
                    .accessibilityHint("Changes reasoning effort from the chat window.")
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var composerRouteControl: some View {
        Menu {
            Button {
                openModelPicker(openingCouncil: false)
            } label: {
                Label("Model: \(chatStore.selectedModelDisplayName)", systemImage: composerModelSymbolName)
            }

            Button {
                openModelPicker(openingCouncil: true)
            } label: {
                Label(
                    chatStore.isCouncilModeEnabled ? "Council: \(chatStore.activeCouncilModels.count) models" : "Use Council",
                    systemImage: "person.3"
                )
            }

            if selectedModelSupportsReasoningEffort {
                Divider()
                ForEach(ModelReasoningEffort.allCases) { effort in
                    Button {
                        chatStore.setReasoningEffort(effort)
                    } label: {
                        Label("Effort: \(effort.title)", systemImage: effort == chatStore.advancedModelParams.reasoningEffort ? "checkmark" : "gauge.medium")
                    }
                }
            }

            Divider()

            Button {
                AppHaptics.selection()
                chatStore.selectSourceMode(.auto)
            } label: {
                Label("Auto sources", systemImage: sourceModeMenuSymbolName(isActive: sourceModeControlIsAuto))
            }

            Button {
                AppHaptics.selection()
                chatStore.selectSourceMode(.web)
            } label: {
                Label("Web", systemImage: sourceModeMenuSymbolName(isActive: sourceModeControlIsWeb))
            }

            Button {
                selectProjectSourceMode()
            } label: {
                Label("Project", systemImage: sourceModeMenuSymbolName(isActive: sourceModeControlIsProject))
            }

            Button {
                selectResearchSourceMode()
            } label: {
                Label("Research", systemImage: sourceModeMenuSymbolName(isActive: researchButtonActive, fallback: "doc.text.magnifyingglass"))
            }
            .disabled(chatStore.selectedRouteUsesNearCloud)

            Divider()

            ForEach(exactProjectSourceModes) { mode in
                Button {
                    AppHaptics.selection()
                    chatStore.selectSourceMode(mode)
                    if mode == .files && chatStore.selectedProject == nil && composerStore.pendingAttachments.isEmpty {
                        showingProjectFiles = true
                    }
                } label: {
                    Label(sourceModeMenuTitle(for: mode), systemImage: exactSourceModeMenuSymbolName(for: mode))
                }
            }

            if !quickStartSuggestions.isEmpty {
                Divider()

                Section("Quick starts") {
                    ForEach(quickStartSuggestions) { suggestion in
                        Button {
                            applyQuickStartSuggestion(suggestion)
                        } label: {
                            Label(suggestion.title, systemImage: suggestion.symbolName)
                        }
                    }
                }
            }
        } label: {
            ComposerRouteChip(
                title: composerRouteSummaryTitle,
                symbolName: composerRouteSummarySymbolName,
                isActive: composerRouteIsCustomized,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Route \(composerRouteSummaryTitle)")
        .accessibilityHint("Choose model, Council, effort, web, research, project files, or saved links for the next message.")
    }

    private var composerRouteSummaryTitle: String {
        var parts: [String] = []
        if chatStore.isCouncilModeEnabled {
            parts.append("Council \(chatStore.activeCouncilModels.count)")
        } else if chatStore.selectedRouteKind == .nearPrivate {
            parts.append("Private")
        } else {
            parts.append(chatStore.selectedProviderDisplayName)
        }

        if chatStore.sourceMode != .auto || chatStore.researchModeEnabled {
            parts.append(composerSourceTitle)
        }

        if chatStore.advancedModelParams.reasoningEffort != .automatic {
            parts.append(chatStore.advancedModelParams.reasoningEffort.title)
        }

        return parts.prefix(2).joined(separator: " · ")
    }

    private var composerRouteSummarySymbolName: String {
        if chatStore.isCouncilModeEnabled {
            return "person.3"
        }
        if researchButtonActive {
            return "doc.text.magnifyingglass"
        }
        if chatStore.sourceMode == .web {
            return "globe"
        }
        if chatStore.sourceMode != .auto {
            return "folder"
        }
        return composerModelSymbolName
    }

    private var composerRouteIsCustomized: Bool {
        chatStore.isCouncilModeEnabled ||
            chatStore.sourceMode != .auto ||
            chatStore.researchModeEnabled ||
            chatStore.selectedRouteKind != .nearPrivate ||
            chatStore.advancedModelParams.reasoningEffort != .automatic
    }

    private var selectedModelSupportsReasoningEffort: Bool {
        guard let model = chatStore.selectedModelOption else { return false }
        return model.isRecommendedReasoningModel || model.isNearCloudModel
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
        if researchButtonActive {
            return "Research"
        }
        switch chatStore.sourceMode {
        case .auto:
            return "Auto"
        case .web:
            return "Web"
        case .links:
            return "Links"
        case .files:
            return "Files"
        case .all:
            return "Web + Files"
        }
    }

    private var exactProjectSourceModes: [ChatSourceMode] {
        [.links, .files, .all]
    }

    private var quickStartSuggestions: [EmptyChatStarterSuggestion] {
        EmptyChatStarterCoordinator.suggestions(for: chatStore)
    }

    private var sourceModeControl: some View {
        Menu {
            Button {
                AppHaptics.selection()
                chatStore.selectSourceMode(.auto)
            } label: {
                Label("Auto", systemImage: sourceModeMenuSymbolName(isActive: sourceModeControlIsAuto))
            }

            Button {
                AppHaptics.selection()
                chatStore.selectSourceMode(.web)
            } label: {
                Label("Web", systemImage: sourceModeMenuSymbolName(isActive: sourceModeControlIsWeb))
            }

            Button {
                selectProjectSourceMode()
            } label: {
                Label("Project", systemImage: sourceModeMenuSymbolName(isActive: sourceModeControlIsProject))
            }

            Button {
                selectResearchSourceMode()
            } label: {
                Label("Research", systemImage: sourceModeMenuSymbolName(isActive: researchButtonActive, fallback: "doc.text.magnifyingglass"))
            }
            .disabled(chatStore.selectedRouteUsesNearCloud)

            Divider()

            ForEach(exactProjectSourceModes) { mode in
                Button {
                    AppHaptics.selection()
                    chatStore.selectSourceMode(mode)
                    if mode == .files && chatStore.selectedProject == nil && composerStore.pendingAttachments.isEmpty {
                        showingProjectFiles = true
                    }
                } label: {
                    Label(sourceModeMenuTitle(for: mode), systemImage: exactSourceModeMenuSymbolName(for: mode))
                }
            }
        } label: {
            ComposerRouteChip(
                title: composerSourceTitle,
                symbolName: composerSourceSymbolName,
                isActive: chatStore.sourceMode != .auto || chatStore.researchModeEnabled,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Source mode \(composerSourceTitle)")
        .accessibilityHint("Choose web, saved link, file, combined, or research context for the next message.")
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

    private var composerSourceSymbolName: String {
        if researchButtonActive {
            return "doc.text.magnifyingglass"
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

    private var sourceModeControlIsAuto: Bool {
        !researchButtonActive && chatStore.sourceMode == .auto
    }

    private var sourceModeControlIsWeb: Bool {
        !researchButtonActive && chatStore.sourceMode == .web
    }

    private var sourceModeControlIsProject: Bool {
        !researchButtonActive && chatStore.sourceMode != .auto && chatStore.sourceMode != .web
    }

    private func sourceModeMenuSymbolName(isActive: Bool, fallback: String = "checkmark") -> String {
        isActive ? "checkmark" : fallback
    }

    private func exactSourceModeMenuSymbolName(for mode: ChatSourceMode) -> String {
        (!researchButtonActive && mode == chatStore.sourceMode) ? "checkmark" : mode.symbolName
    }

    private func selectProjectSourceMode() {
        AppHaptics.selection()
        chatStore.selectSourceMode(chatStore.selectedProject == nil ? .files : .all)
        if chatStore.selectedProject == nil && composerStore.pendingAttachments.isEmpty {
            showingProjectFiles = true
        }
    }

    private func selectResearchSourceMode() {
        guard !chatStore.selectedRouteUsesNearCloud else { return }
        AppHaptics.selection()
        if chatStore.sourceMode != .web {
            chatStore.sourceMode = .web
        }
        if !chatStore.researchModeEnabled {
            chatStore.toggleResearchMode()
        }
    }

    private func sourceModeMenuTitle(for mode: ChatSourceMode) -> String {
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

    private func applyQuickStartSuggestion(_ suggestion: EmptyChatStarterSuggestion) {
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

    private func applySlashCommand(_ suggestion: SlashCommandSuggestion) {
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

    private func handleRouteReadinessRecovery(_ action: ChatStore.RouteReadinessIssue.RecoveryAction) {
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

    private func remainingDraft(after command: String) -> String {
        let trimmed = composerStore.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(command) else { return "" }
        return trimmed
            .dropFirst(command.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func attachPhotoItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for (index, item) in items.prefix(5).enumerated() {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        continue
                    }
                    await attachImageData(data, preferredName: "photo-\(index + 1).jpg")
                } catch {
                    await MainActor.run {
                        chatStore.bannerMessage = "Could not attach one of those photos."
                    }
                }
            }
            await MainActor.run {
                selectedPhotoItems = []
            }
        }
    }

    private func attachImageData(_ data: Data, preferredName: String) async {
        guard data.count <= ChatStore.maxAttachmentUploadBytes else {
            await MainActor.run {
                chatStore.bannerMessage = "Images must be 10 MB or smaller."
            }
            return
        }
        let safeName = preferredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "image.jpg" : preferredName
        let pathExtension = (safeName as NSString).pathExtension
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(pathExtension.isEmpty ? "jpg" : pathExtension)
        do {
            try data.write(to: url, options: [.atomic])
            await chatStore.addAttachment(from: url, displayName: safeName)
        } catch {
            await MainActor.run {
                chatStore.bannerMessage = "Could not prepare that image."
            }
        }
    }

    private func openCamera() {
        #if canImport(UIKit)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showingCamera = true
        } else {
            chatStore.bannerMessage = "Camera is not available here. Choose Photos or Files."
        }
        #else
        chatStore.bannerMessage = "Camera is not available here. Choose Photos or Files."
        #endif
    }

    private func attachPasteboard() {
        #if canImport(UIKit)
        let pasteboard = UIPasteboard.general
        if let text = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            chatStore.stageTextAttachment(text, suggestedName: "clipboard.txt")
            return
        }
        if let image = pasteboard.image,
           let data = image.jpegData(compressionQuality: 0.9) {
            Task { await attachImageData(data, preferredName: "clipboard-image.jpg") }
            return
        }
        chatStore.bannerMessage = "Clipboard has no text or image to attach."
        #else
        chatStore.bannerMessage = "Paste attachments are not available on this platform."
        #endif
    }

    #if canImport(UIKit)
    private func attachCapturedImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            chatStore.bannerMessage = "Could not read that photo."
            return
        }
        Task { await attachImageData(data, preferredName: "camera-photo.jpg") }
    }
    #endif
}

#if canImport(UIKit)
private struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
#endif

struct ComposerRouteChip: View {
    let title: String
    let symbolName: String
    let isActive: Bool
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.footnote)
                .fontWeight(.medium)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.55)
            }
        }
        .foregroundStyle(isActive ? Color.actionPress : Color.textPrimary)
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: 30)
        .background(background, in: Capsule())
        .overlay {
            Capsule()
                .stroke(border, lineWidth: 1)
        }
    }

    private var background: Color {
        isActive ? Color.actionFill : Color.appPanelBackground
    }

    private var border: Color {
        isActive ? Color.actionPrimary.opacity(0.30) : Color.appBorder
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
    var showsMetadataOnly = false
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
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        if showsMetadataOnly {
            var hostedParts = ["File names only", "filename plus prompt excerpts only"]
            if let displaySize = attachment.displaySize {
                hostedParts.append(displaySize)
            }
            return hostedParts.joined(separator: " · ")
        }

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

/// On-device dictation for the composer. Streams partial speech-to-text into a
/// callback while recording. Every failure path degrades to a status message
/// rather than a crash, and audio is never persisted.
@MainActor
final class VoiceDictation: ObservableObject {
    @Published private(set) var isRecording = false
    @Published var statusMessage: String?

    /// Receives the latest transcript (partial or final) on the main actor.
    var onTranscript: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var isSupported: Bool { recognizer != nil }

    func toggle() {
        if isRecording {
            stop()
        } else {
            requestAuthorizationAndStart()
        }
    }

    private func requestAuthorizationAndStart() {
        SFSpeechRecognizer.requestAuthorization { [weak self] speechAuth in
            Task { @MainActor in
                guard let self else { return }
                guard speechAuth == .authorized else {
                    self.statusMessage = "Enable Speech Recognition in Settings to dictate."
                    return
                }
                AVAudioApplication.requestRecordPermission { [weak self] micGranted in
                    Task { @MainActor in
                        guard let self else { return }
                        guard micGranted else {
                            self.statusMessage = "Enable Microphone access in Settings to dictate."
                            return
                        }
                        self.beginRecording()
                    }
                }
            }
        }
    }

    private func beginRecording() {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else {
            statusMessage = "Dictation isn't available right now."
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            statusMessage = "Couldn't start the microphone."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        // The tap runs on a real-time audio thread — only append to the
        // request here (thread-safe); never touch @Published state.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            statusMessage = "Couldn't start the microphone."
            teardownAudio()
            return
        }

        isRecording = true
        statusMessage = nil
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.onTranscript?(result.bestTranscription.formattedString)
                    if result.isFinal { self.stop() }
                } else if error != nil {
                    self.stop()
                }
            }
        }
    }

    func stop() {
        request?.endAudio()
        task?.cancel()
        teardownAudio()
        isRecording = false
    }

    private func teardownAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
