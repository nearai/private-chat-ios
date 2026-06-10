import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

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
    @State var showingCamera = false
    @State var showingAttachmentOptions = false
    @State var selectedPhotoItems: [PhotosPickerItem] = []
    @State var showingProjectFiles = false
    @State var showingSecurity = false
    @State var showingAgentWorkspace = false
    @State var showingAccountSettings = false
    @State var accountSettingsDeepLink: AccountSettingsDeepLink?
    @State var showingCapabilities = false
    @State var showingModelPicker = false
    @State var modelPickerOpeningCouncil = false
    @State var showingSourceModeOptions = false
    @State var showingReasoningEffortOptions = false
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

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    AppHaptics.selection()
                    showingAttachmentOptions = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(transcriptStore.isStreaming)
                .accessibilityIdentifier("composer.attach")
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
                    .lineLimit(1...4)
                    .focused($isFocused)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                    .onSubmit {
                        chatStore.sendDraft()
                        isFocused = false
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                    .disabled(transcriptStore.isStreaming)
                    .accessibilityIdentifier("composer.input")
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
                    .accessibilityIdentifier("composer.send")
                    .accessibilityLabel(transcriptStore.isStreaming ? "Stop response" : "Send message")
                    .accessibilityHint(transcriptStore.isStreaming ? "Stops the current response." : "Sends the draft and staged attachments.")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .glassBackground(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isFocused ? Color.actionPrimary.opacity(0.38) : Color.appBorder, lineWidth: 0.5)
            }
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
            actions: { sourceModeOptionsDialog }
        )
        .confirmationDialog(
            "Reasoning effort",
            isPresented: $showingReasoningEffortOptions,
            titleVisibility: .visible,
            actions: { reasoningEffortOptionsDialog }
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
        .onChange(of: selectedPhotoItems) { _, items in
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
            AccountSettingsView(
                initialDeepLink: accountSettingsDeepLink,
                onRunSetupAgain: {},
                isCurrentChatEmpty: { chatStore.selectedConversation == nil && transcriptStore.messages.isEmpty }
            )
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
}
