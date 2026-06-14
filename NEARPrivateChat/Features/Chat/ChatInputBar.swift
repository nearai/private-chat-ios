import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

/// Every modal the composer can present, as a single identifiable value so one
/// `.sheet(item:)` replaces nine `.sheet(isPresented:)` modifiers. Associated
/// values carry the per-presentation context the old separate `@State` flags
/// used to hold (`modelPickerOpeningCouncil`, `accountSettingsDeepLink`).
enum InputBarSheet: Identifiable, Hashable {
    case camera
    case projectFiles
    case security
    case agentWorkspace
    case accountSettings(deepLink: AccountSettingsDeepLink?)
    case capabilities
    case routeConfig
    case modelPicker(openingCouncil: Bool)
    case reasoningEffort

    var id: String {
        switch self {
        case .camera: return "camera"
        case .projectFiles: return "projectFiles"
        case .security: return "security"
        case .agentWorkspace: return "agentWorkspace"
        case .accountSettings: return "accountSettings"
        case .capabilities: return "capabilities"
        case .routeConfig: return "routeConfig"
        case .modelPicker: return "modelPicker"
        case .reasoningEffort: return "reasoningEffort"
        }
    }
}

struct InputBar: View {
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var routeHealth: RouteHealthMonitor
    @ObservedObject var transcriptStore: ChatTranscriptStore
    @ObservedObject var composerStore: ChatComposerStore
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @FocusState var isFocused: Bool
    @State var showingFileImporter = false
    @State var showingPhotoPicker = false
    @State var showingAttachmentOptions = false
    @State var selectedPhotoItems: [PhotosPickerItem] = []
    @State var showingSourceModeOptions = false
    // One enum drives every composer sheet (replaces nine independent
    // `isPresented` flags). Sheet-to-sheet transitions chain through
    // `pendingAfterDismiss` in the sheet's onDismiss instead of a fixed delay.
    @State var activeSheet: InputBarSheet?
    @State private var pendingAfterDismiss: (() -> Void)?
    @StateObject var dictation = VoiceDictation()

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
                DocumentContextIndicator(
                    attachments: composerStore.pendingAttachments,
                    stagingStore: composerStore.attachmentStagingStore
                )
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

            composerRecoveryCards

            if !visibleSlashCommands.isEmpty {
                slashCommandTray
            }

            composerRoutingControls

            composerInputControlsSection
        }
        .safeAreaPadding(.bottom, 8)
        .confirmationDialog(
            "Add attachment",
            isPresented: $showingAttachmentOptions,
            titleVisibility: .visible,
            actions: { attachmentOptionsDialog }
        )
        .confirmationDialog(
            "Source mode",
            isPresented: $showingSourceModeOptions,
            titleVisibility: .visible,
            actions: { sourceModeOptionsDialog },
            message: {
                // Honest per-route framing: web sources render only when the
                // route returns them; the private route may answer from model
                // knowledge and your files alone.
                Text(chatStore.selectedRouteKind == .nearPrivate
                    ? "Web sources appear when the private route returns them; private answers may come from model knowledge and your files. For guaranteed live web grounding, use a Cloud model."
                    : "Choose what grounds the next answer.")
            }
        )
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
            switch result {
            case let .success(urls):
                if urls.count > 5 {
                    chatStore.showBannerForSend("You can attach up to 5 files at once. Added the first 5.")
                }
                for url in urls.prefix(5) {
                    Task { await chatStore.addAttachment(from: url) }
                }
            case let .failure(error):
                chatStore.showBannerForSend("Couldn’t attach files: \(error.localizedDescription)")
            }
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 5,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, items in
            attachPhotoItems(items)
        }
        .sheet(item: $activeSheet, onDismiss: handleSheetDismiss) { sheet in
            sheetContent(for: sheet)
        }
    }

    /// Presents a composer sheet. If one is already up, it dismisses first and
    /// the new sheet is presented from `handleSheetDismiss` — a clean
    /// sheet-to-sheet handoff with no fixed transition delay.
    func presentSheet(_ sheet: InputBarSheet) {
        runAfterCurrentSheet { activeSheet = sheet }
    }

    /// Runs `action` immediately when no sheet is open, otherwise after the
    /// current sheet finishes dismissing.
    func runAfterCurrentSheet(_ action: @escaping () -> Void) {
        if activeSheet == nil {
            action()
        } else {
            pendingAfterDismiss = action
            activeSheet = nil
        }
    }

    private func handleSheetDismiss() {
        guard let pending = pendingAfterDismiss else { return }
        pendingAfterDismiss = nil
        pending()
    }

    @ViewBuilder
    private func sheetContent(for sheet: InputBarSheet) -> some View {
        switch sheet {
        case .camera:
            cameraSheet
        case .projectFiles:
            projectFilesSheet()
        case .security:
            securitySheet
        case .agentWorkspace:
            agentWorkspaceSheet
        case let .accountSettings(deepLink):
            accountSettingsSheet(deepLink: deepLink)
        case .capabilities:
            capabilitiesSheet()
        case .routeConfig:
            composerRouteConfigSheet()
        case let .modelPicker(openingCouncil):
            modelPickerSheet(openingCouncil: openingCouncil)
        case .reasoningEffort:
            reasoningEffortSheet()
        }
    }

    @ViewBuilder
    private var cameraSheet: some View {
        #if canImport(UIKit)
        CameraCaptureView { image in
            activeSheet = nil
            attachCapturedImage(image)
        } onCancel: {
            activeSheet = nil
        }
        #else
        EmptyView()
        #endif
    }

    @ViewBuilder
    private var securitySheet: some View {
        SecurityView()
            .environmentObject(chatStore)
    }

    @ViewBuilder
    private var agentWorkspaceSheet: some View {
        AgentWorkspaceView()
            .environmentObject(chatStore)
    }

    private func accountSettingsSheet(deepLink: AccountSettingsDeepLink?) -> some View {
        AccountSettingsView(
            initialDeepLink: deepLink,
            onRunSetupAgain: {},
            isCurrentChatEmpty: { chatStore.selectedConversation == nil && transcriptStore.messages.isEmpty }
        )
            .environmentObject(sessionStore)
    }

    private func capabilitiesSheet() -> some View {
        CapabilitiesView(
            onOpenAccountSettings: { deepLink in
                presentSheet(.accountSettings(deepLink: deepLink))
            },
            onOpenSecurity: {
                presentSheet(.security)
            },
            onOpenAgentWorkspace: {
                presentSheet(.agentWorkspace)
            },
            onRunSetupAgain: nil
        )
        .environmentObject(chatStore)
        .environmentObject(sessionStore)
    }

    private func projectFilesSheet() -> some View {
        ProjectFilesView(
            projectContextRoutePreview: { chatStore.projectContextRoutePreview },
            addProjectAttachment: { url in await chatStore.addProjectAttachment(from: url) },
            removeProjectAttachment: { attachment in chatStore.removeProjectAttachment(attachment) },
            onOpenConversation: { conversation in
                chatStore.selectConversation(conversation)
            },
            onStagePrompt: { prompt in
                chatStore.draft = prompt
                chatStore.bannerMessage = "Project prompt ready."
            }
        )
    }

    private func composerRouteConfigSheet() -> some View {
        ComposerRouteConfigSheet(
            onChooseModel: {
                presentSheet(.modelPicker(openingCouncil: false))
            },
            onChooseCouncil: {
                presentSheet(.modelPicker(openingCouncil: true))
            },
            onChooseSource: {
                runAfterCurrentSheet { showingSourceModeOptions = true }
            },
            onOpenAccount: {
                presentSheet(.accountSettings(deepLink: .nearCloudKeys))
            },
            onOpenAgent: {
                presentSheet(.agentWorkspace)
            }
        )
        .environmentObject(chatStore)
    }

    private func modelPickerSheet(openingCouncil: Bool) -> some View {
        ModelPickerView(
            openingCouncil: openingCouncil,
            onOpenNearCloudKeys: {
                presentSheet(.accountSettings(deepLink: .nearCloudKeys))
            }
        )
            .environmentObject(chatStore)
    }

    private func reasoningEffortSheet() -> some View {
        ReasoningEffortOptionsSheet {
            presentSheet(.modelPicker(openingCouncil: false))
        }
        .environmentObject(chatStore)
    }

    @ViewBuilder
    private func composerInputBorder(isFocused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(isFocused ? Color.actionPrimary.opacity(0.38) : Color.appBorder, lineWidth: 0.5)
    }

    private var composerInputControlsSection: AnyView {
        let controls = ComposerInputControls(
            draft: draftBinding,
            placeholder: composerPlaceholder,
            canSend: canSend,
            isStreaming: transcriptStore.isStreaming,
            dictation: dictation,
            sendDisabled: sendDisabled,
            sendButtonScale: sendButtonScale,
            reduceMotion: reduceMotion,
            sendButtonAnimation: sendButtonAnimation,
            showAttachmentPicker: $showingAttachmentOptions,
            onSubmit: { chatStore.sendDraft() },
            onSend: { chatStore.sendDraft() },
            onCancel: { chatStore.cancelStream() },
            onUpdateDraft: { chatStore.draft = $0 }
        )
        return AnyView(
            controls
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .glassBackground(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(composerInputBorder(isFocused: isFocused))
        )
    }

private struct ComposerInputControls: View {
    @Binding var draft: String
    let placeholder: String
    let canSend: Bool
    let isStreaming: Bool
    @ObservedObject var dictation: VoiceDictation
    let sendDisabled: Bool
    let sendButtonScale: CGFloat
    let reduceMotion: Bool
    let sendButtonAnimation: Animation?
    let showAttachmentPicker: Binding<Bool>
    let onSubmit: () -> Void
    let onSend: () -> Void
    let onCancel: () -> Void
    let onUpdateDraft: (String) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                AppHaptics.selection()
                showAttachmentPicker.wrappedValue = true
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(isStreaming)
            .accessibilityIdentifier("composer.attach")
            .accessibilityLabel("Add attachment")
            .accessibilityHint("Choose files, photos, camera capture, or pasteboard text.")

            TextField(
                "",
                text: $draft,
                prompt: Text(placeholder)
                    .font(.body)
                    .foregroundColor(Color.textTertiary),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .tokenInputTraits()
            .autocorrectionDisabled()
            .lineLimit(1...4)
            .font(.body)
            .foregroundStyle(Color.textPrimary)
            .onSubmit {
                onSubmit()
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            .disabled(isStreaming)
            .accessibilityIdentifier("composer.input")
            .accessibilityLabel("Message")
            .accessibilityHint(isStreaming ? "Stop the current response before editing the draft." : "Enter a message or slash command.")

            if !isStreaming && (!canSend || dictation.isRecording) {
                Button {
                    AppHaptics.lightImpact()
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
                        onUpdateDraft(transcript)
                    }
                }
            }

            if (canSend && !dictation.isRecording) || isStreaming {
                Button {
                    if isStreaming {
                        AppHaptics.mediumImpact()
                        onCancel()
                    } else {
                        AppHaptics.lightImpact()
                        onSend()
                    }
                } label: {
                    Image(systemName: isStreaming ? "stop.fill" : "arrow.up.circle.fill")
                        .font(.largeTitle.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isStreaming ? Color.proofMismatch : Color.actionPrimary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(sendDisabled)
                .scaleEffect(sendButtonScale)
                .opacity(reduceMotion ? (sendDisabled ? 0.72 : 1) : 1)
                .animation(sendButtonAnimation, value: canSend)
                .animation(sendButtonAnimation, value: isStreaming)
                .accessibilityIdentifier("composer.send")
                .accessibilityLabel(isStreaming ? "Stop response" : "Send message")
                .accessibilityHint(isStreaming ? "Stops the current response." : "Sends the draft and staged attachments.")
            }
        }
    }
}
}
