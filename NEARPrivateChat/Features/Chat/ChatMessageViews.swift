import SwiftUI
import UniformTypeIdentifiers

struct MessageBubble: View {
    let message: ChatMessage
    let chatStore: ChatStore
    @EnvironmentObject private var shareStore: ShareStore
    @State private var showingArtifact = false
    @State private var showingAnswerExporter = false
    @State private var showingSecurity = false
    @State private var showingSources = false
    @State private var answerExportDocument = ConversationExportDocument()
    @State private var answerExportContentType: UTType = .plainText
    @State private var answerExportFilename = "near-private-chat-answer.md"
    @State private var tappedSource: SourceSheetPresentation?
    @State private var editingUserMessage: ChatMessage?
    @State private var lastInputRequestID: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .user {
                Spacer(minLength: 36)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                if shouldShowHeader {
                    HStack(spacing: 6) {
                        Text(headerTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let authorBadgeTitle {
                            MetadataPill(title: authorBadgeTitle, symbolName: "person.crop.circle", isPrimary: false)
                        }
                        if message.role == .assistant, let badge = statusBadge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(badge == "Failed" ? .red : Color.brandBlue)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background((badge == "Failed" ? Color.red.opacity(0.08) : Color.brandBlue.opacity(0.08)), in: Capsule())
                        }
                    }
                }

                if message.role == .assistant && !message.sources.isEmpty {
                    SourceCarousel(sources: message.sources) { tappedIndex in
                        tappedSource = SourceSheetPresentation(
                            index: tappedIndex,
                            source: message.sources[tappedIndex]
                        )
                    }
                }

                Group {
                    if message.text.isEmpty && message.isStreaming {
                        if message.isAgentRouteMessage {
                            AgentThinkingShimmer(statusText: message.streamingStatusText)
                        } else {
                            HStack(spacing: 8) {
                                TypingDots()
                                Text(message.streamingStatusText)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if message.role == .assistant {
                        if message.isStreaming {
                            StreamingMessageText(message: message)
                        } else {
                            MarkdownMessageText(text: message.text.isEmpty ? " " : message.text, sources: message.sources)
                        }
                    } else {
                        Text(message.text.isEmpty ? " " : message.text)
                            .font(.body)
                            .lineSpacing(7)
                            .textSelection(.enabled)
                    }
                }
                .if(message.role == .user) { view in
                    view
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .if(message.role != .user) { view in
                    view
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 0)
                        .padding(.vertical, 0)
                }
                .contextMenu {
                    Button {
                        Clipboard.copy(message.text)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }

                    if message.role == .assistant {
                        Button {
                            chatStore.copySignedSnippet(for: message)
                        } label: {
                            Label("Copy Device-Signed Snippet", systemImage: "checkmark.shield")
                        }

                        Button {
                            prepareAnswerExport(.markdown)
                        } label: {
                            Label("Export Markdown", systemImage: "doc.plaintext")
                        }

                        Button {
                            prepareAnswerExport(.pdf)
                        } label: {
                            Label("Export PDF", systemImage: "doc.richtext")
                        }

                        Button {
                            prepareAnswerExport(.docx)
                        } label: {
                            Label("Export Word Document", systemImage: "doc")
                        }

                        Button {
                            chatStore.regenerateResponse(for: message)
                        } label: {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                        }

                        Button {
                            chatStore.requestProjectNoteSave(for: message)
                        } label: {
                            Label(
                                chatStore.isMessageSavedToSelectedProject(message) ? "Saved to Project" : "Save to Project",
                                systemImage: chatStore.isMessageSavedToSelectedProject(message) ? "checkmark.circle" : "bookmark"
                            )
                        }
                        .disabled(chatStore.isMessageSavedToSelectedProject(message))
                    } else {
                        Button {
                            editingUserMessage = message
                        } label: {
                            Label("Edit & Branch", systemImage: "pencil")
                        }
                    }
                }

                if message.role == .assistant, let widget = message.widget, !message.isStreaming {
                    MessageWidgetCard(widget: widget) { followUp in
                        chatStore.composeWidgetFollowUp(followUp)
                    } onCreateAppAction: { action in
                        chatStore.createTracker(fromWidgetAction: action)
                    }
                }

                if message.role == .assistant,
                   let branchVariant = message.branchVariant,
                   branchVariant.count > 1,
                   !message.isStreaming {
                    ResponseVariantPicker(variant: branchVariant) { responseID in
                        chatStore.selectResponseVariant(responseID)
                    }
                }

                if message.shouldShowAgentRunStatus {
                    AgentRunStatusStrip(message: message, toolCount: chatStore.ironclawToolNames.count) {
                        chatStore.regenerateResponse(for: message)
                    } onCancel: {
                        chatStore.cancelStream()
                    }
                }

                if !message.attachments.isEmpty {
                    MessageAttachmentStrip(attachments: message.attachments)
                }

                if message.canShowAssistantActions {
                    AssistantInlineActions(
                        canSaveToProject: chatStore.selectedProject != nil,
                        isSavedToProject: chatStore.isMessageSavedToSelectedProject(message),
                        canOpen: message.isArtifactCandidate,
                        sourceCount: message.sources.count,
                        onCopy: { Clipboard.copy(message.text) },
                        onCopySigned: { chatStore.copySignedSnippet(for: message) },
                        onExport: { prepareAnswerExport($0) },
                        onRegenerate: { chatStore.regenerateResponse(for: message) },
                        onSave: { chatStore.requestProjectNoteSave(for: message) },
                        onOpen: { showingArtifact = true },
                        onSources: { showingSources = true }
                    )
                }

                if let pendingApproval = message.pendingApproval {
                    IronclawApprovalCard(messageID: message.id, approval: pendingApproval)
                        .environmentObject(chatStore)
                }

                if message.status == "failed", !message.shouldShowAgentRunStatus {
                    HStack(spacing: 12) {
                        Label("Failed", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Button {
                            chatStore.regenerateResponse(for: message)
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if let footerViewModel = verifiedFooterViewModel {
                    VerifiedFooterButton(viewModel: footerViewModel) {
                        showingSecurity = true
                    }
                }
            }
            .frame(maxWidth: message.role == .user ? 560 : 740, alignment: message.role == .user ? .trailing : .leading)

            if message.role != .user {
                Spacer(minLength: 36)
            }
        }
        .sheet(isPresented: $showingArtifact) {
            ArtifactOutputView(message: message)
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingSecurity) {
            SecurityView()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingSources) {
            SourcesDetailView(query: message.searchQuery, sources: message.sources)
        }
        .sheet(item: $tappedSource) { presentation in
            SourceSheet(index: presentation.index + 1, source: presentation.source)
        }
        .sheet(item: $editingUserMessage) { userMessage in
            EditUserMessageView(message: userMessage)
                .environmentObject(chatStore)
        }
        .fileExporter(
            isPresented: $showingAnswerExporter,
            document: answerExportDocument,
            contentType: answerExportContentType,
            defaultFilename: answerExportFilename
        ) { result in
            switch result {
            case .success:
                chatStore.bannerMessage = "Answer exported."
            case let .failure(error):
                chatStore.bannerMessage = error.localizedDescription
            }
        }
        .onAppear {
            lastInputRequestID = message.pendingApproval?.id
        }
        .onChange(of: message.pendingApproval?.id) { _, newValue in
            guard let newValue, newValue != lastInputRequestID else { return }
            lastInputRequestID = newValue
            AppHaptics.mediumImpact()
        }
    }

    private var statusBadge: String? {
        switch message.status {
        case "reasoning":
            return "Reasoning"
        case "searching":
            return "Web search"
        case "approval":
            return "Needs input"
        case "failed":
            return "Failed"
        default:
            return nil
        }
    }

    // Spec: assistant messages render without the redundant model header
    // because the model is already named in the proof footer. User
    // messages similarly hide "You" — the bubble side already carries that.
    // Show the row only when we have an actual status badge, shared author
    // attribution, or a live streaming status to surface.
    private var shouldShowHeader: Bool {
        if let badge = statusBadge, !badge.isEmpty { return true }
        if authorBadgeTitle != nil { return true }
        if shareStore.shouldShowSharedAuthorNames, message.role == .user { return true }
        return false
    }

    private var headerTitle: String {
        if message.role == .user {
            if shareStore.shouldShowSharedAuthorNames {
                return message.authorDisplayLabel ?? "User"
            }
            return "You"
        }
        return message.modelDisplayName
    }

    private var authorBadgeTitle: String? {
        guard shareStore.shouldShowSharedAuthorNames, message.role != .user else {
            return nil
        }
        return message.authorDisplayLabel
    }

    private func prepareAnswerExport(_ format: ConversationExportFormat) {
        do {
            answerExportDocument = try ConversationExportBuilder.selectedAnswerDocument(
                for: chatStore.selectedConversation,
                messages: [message],
                answerID: message.id,
                format: format
            )
            answerExportContentType = format.contentType
            answerExportFilename = selectedAnswerFilename(format: format)
            showingAnswerExporter = true
        } catch {
            chatStore.bannerMessage = error.localizedDescription
        }
    }

    private func selectedAnswerFilename(format: ConversationExportFormat) -> String {
        let fullName = ConversationExportBuilder.filename(for: chatStore.selectedConversation, format: format)
        let base = (fullName as NSString).deletingPathExtension
        return "\(base)-answer.\(format.fileExtension)"
    }

    private var verifiedFooterViewModel: VerifiedFooterViewModel? {
        guard let proof = answerProofCapsule else { return nil }
        return VerifiedFooterViewModel(
            state: proof.state,
            badge: proof.badge,
            model: message.modelDisplayName,
            sourceCount: message.sources.count,
            ago: ChatTimeFormatter.relativeShort(from: message.createdAt),
            symbolName: proof.symbolName,
            tintColor: proof.tintColor,
            detail: proof.detail
        )
    }

    private var answerProofCapsule: ProofCapsuleViewModel? {
        guard message.canShowAnswerProofFooter,
              let modelID = message.model else {
            return nil
        }

        if let proof = message.trustMetadata?.proof {
            return ProofCapsuleViewModel(
                state: proof.state,
                title: proof.title,
                detail: proof.detail,
                badge: proof.badge,
                symbolName: proof.symbolName
            )
        }

        switch ChatStore.routeKind(forModelID: modelID) {
        case .nearPrivate:
            let status = AttestationStatus(snapshot: chatStore.attestationSnapshot, selectedModelID: modelID)
            switch status.effectiveState() {
            case .valid:
                return ProofCapsuleViewModel(
                    state: .private_,
                    title: "Current route proof",
                    detail: "The current proof report matches this route/model now. It was not captured with or cryptographically bound to this answer.",
                    badge: "Current route proof",
                    symbolName: "lock.shield"
                )
            case .stale, .mismatch:
                return ProofCapsuleViewModel(status: status, modelID: modelID)
            case .unknown, .unavailable:
                return ProofCapsuleViewModel(
                    state: .private_,
                    title: "Private route",
                    detail: "This answer used the private route. Open Proof when you need a fresh route/model report.",
                    badge: "Private",
                    symbolName: "lock.shield"
                )
            }
        case .nearCloud:
            return ProofCapsuleViewModel(
                state: .proxied,
                title: "Privacy proxy",
                detail: "This answer was anonymized through the NEAR AI Cloud privacy proxy. Anonymized turns do not carry NEAR Private proof.",
                badge: "Privacy proxy",
                symbolName: "eye.slash"
            )
        case .ironclawMobile, .ironclawHosted:
            return ProofCapsuleViewModel(
                state: .unverified,
                title: "Agent route",
                detail: "This answer used Agent tools. Proof applies only when the underlying model route supplies it.",
                badge: "Agent",
                symbolName: "terminal"
            )
        }
    }
}
