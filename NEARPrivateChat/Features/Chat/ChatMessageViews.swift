import SwiftUI
import UniformTypeIdentifiers

struct AssistantMessagePresentationPolicy {
    static func widgetForDisplay(_ widget: MessageWidget?, sources: [WebSearchSource]) -> MessageWidget? {
        guard let widget else { return nil }
        guard widget.kind == .newsBrief, !sources.isEmpty else { return widget }
        guard let brief = widget.newsBrief, !brief.stories.isEmpty else { return widget }
        if newsBriefStoriesAreSourceGrounded(brief, sources: sources) {
            return widget
        }
        return sourceBackedNewsWidget(from: sources, fallback: widget)
    }

    static func visibleCompletedText(_ text: String, widget: MessageWidget?) -> String? {
        guard widget?.kind == .newsBrief else {
            return text.isEmpty ? " " : text
        }
        return nil
    }

    static func shouldShowSourceCarousel(sources: [WebSearchSource], widget: MessageWidget?) -> Bool {
        guard !sources.isEmpty else { return false }
        guard widget?.kind == .newsBrief else { return true }
        return !widgetHasInlineStorySources(widget)
    }

    private static func widgetHasInlineStorySources(_ widget: MessageWidget?) -> Bool {
        widget?.newsBrief?.stories.contains { story in
            story.sources.contains { source in
                !source.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    source.domain?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }
        } == true
    }

    private static func sourceBackedNewsWidget(from sources: [WebSearchSource], fallback: MessageWidget) -> MessageWidget? {
        var seenTitles = Set<String>()
        let stories = sources.compactMap { source -> WidgetNewsStory? in
            let title = source.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let normalizedTitle = normalizedWidgetTitle(title)
            guard seenTitles.insert(normalizedTitle).inserted else { return nil }
            return WidgetNewsStory(
                title: title,
                tag: source.sourceBadgeLabel,
                sources: [
                    WidgetNewsSource(
                        label: SourceFaviconResolver.fallbackMark(for: source.host, fallback: source.sourceInitials),
                        domain: source.host
                    )
                ],
                url: source.url
            )
        }
        .prefix(3)
        guard !stories.isEmpty else { return nil }
        return MessageWidget(
            kind: .newsBrief,
            title: fallback.title ?? "Live web sources",
            freshness: fallback.freshness,
            time: fallback.time,
            followUp: fallback.followUp,
            newsBrief: WidgetNewsBrief(
                heading: "Live web · \(sources.count) source\(sources.count == 1 ? "" : "s")",
                stories: Array(stories)
            )
        )
    }

    private static func newsBriefStoriesAreSourceGrounded(_ brief: WidgetNewsBrief, sources: [WebSearchSource]) -> Bool {
        guard !sources.isEmpty else { return false }
        return brief.stories.allSatisfy { story in
            let title = story.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return false }
            if let storyURL = story.url.flatMap(WebSearchSource.sanitizedURLString),
               sources.contains(where: { $0.url == storyURL }) {
                return true
            }
            let candidateSources = sourceCandidates(for: story, sources: sources)
            return candidateSources.contains { source in
                titlesHaveGroundingOverlap(storyTitle: title, sourceTitle: source.displayTitle)
            }
        }
    }

    private static func sourceCandidates(for story: WidgetNewsStory, sources: [WebSearchSource]) -> [WebSearchSource] {
        let storyHosts = Set(story.sources.compactMap { source -> String? in
            SourceFaviconResolver.canonicalSourceDomain(from: source.domain) ??
                SourceFaviconResolver.canonicalSourceDomain(from: source.label)
        })
        guard !storyHosts.isEmpty else { return sources }
        let matching = sources.filter { source in
            guard let sourceHost = SourceFaviconResolver.canonicalSourceDomain(from: source.host) else {
                return false
            }
            return storyHosts.contains(sourceHost)
        }
        return matching.isEmpty ? sources : matching
    }

    private static func titlesHaveGroundingOverlap(storyTitle: String, sourceTitle: String) -> Bool {
        let storyTokens = normalizedTitleTokens(storyTitle)
        let sourceTokens = normalizedTitleTokens(sourceTitle)
        guard !storyTokens.isEmpty, !sourceTokens.isEmpty else { return false }
        let overlap = storyTokens.intersection(sourceTokens).count
        let storyCoverage = Double(overlap) / Double(storyTokens.count)
        return (overlap >= 3 && storyCoverage >= 0.55) ||
            (overlap >= 2 && storyCoverage >= 0.50 && min(storyTokens.count, sourceTokens.count) <= 5)
    }

    private static func normalizedWidgetTitle(_ title: String) -> String {
        normalizedTitleTokens(title).sorted().joined(separator: " ")
    }

    private static func normalizedTitleTokens(_ title: String) -> Set<String> {
        let rawTokens = title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
        let stopwords: Set<String> = [
            "the", "and", "for", "with", "from", "after", "over", "into", "that",
            "this", "latest", "headline", "headlines", "development", "developments",
            "updates", "update", "news", "today", "says", "said", "its", "are", "was"
        ]
        return Set(rawTokens.compactMap { token in
            var value = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !stopwords.contains(value) else { return nil }
            if value.count > 4, value.hasSuffix("s") {
                value.removeLast()
            }
            guard value.count > 2 || value == "ai" || value == "us" else { return nil }
            return value
        })
    }
}

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
                                .foregroundStyle(badge == "Failed" ? .red : Color.brandAccent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background((badge == "Failed" ? Color.red.opacity(0.08) : Color.brandAccent.opacity(0.08)), in: Capsule())
                        }
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
                        } else if message.isBriefingNoResult {
                            BriefingNoResultCard(
                                title: briefingNoResultPresentation.title,
                                detail: briefingNoResultPresentation.detail,
                                onRetry: { chatStore.regenerateResponse(for: message) },
                                onCopy: { Clipboard.copy(message.text) }
                            )
                        } else if message.status == "failed" {
                            AssistantFailureRecoveryCard(
                                title: failedPresentation.title,
                                detail: failedPresentation.detail,
                                routeLabel: failedPresentation.routeLabel,
                                primaryTitle: failedRetryTitle,
                                primarySymbolName: "arrow.clockwise",
                                secondaryTitle: failedSecondaryActionTitle,
                                secondarySymbolName: failedSecondaryActionSymbolName,
                                onPrimary: retryFailedMessage,
                                onSecondary: retryFailedMessageViaProxy
                            )
                        } else {
                            if let visibleText = renderedAssistantMessageText {
                                HStack(alignment: .top, spacing: 0) {
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(Color.brandAccent.opacity(0.55))
                                        .frame(width: 3)
                                    MarkdownMessageText(text: visibleText, sources: message.sources)
                                        .padding(.leading, 8)
                                }
                            }
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

                if message.role == .assistant, let widget = displayWidget, !message.isStreaming {
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
                    MessageAttachmentStrip(
                        attachments: message.attachments,
                        fetchImageContent: { fileID in
                            await chatStore.fetchAttachmentContent(fileID: fileID)
                        }
                    )
                }

                if message.canShowAssistantInlineActions {
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

                if message.role == .assistant, !message.projectFiles.isEmpty, !message.isStreaming {
                    let conversationID = chatStore.selectedConversation?.id ?? ""
                    let resolvedSettings = chatStore.ironclawSettingsForConversation(conversationID)
                    let resolvedThreadID = resolvedSettings.threadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? (chatStore.agentStore.loadIronclawThreadID(for: conversationID) ?? "")
                        : resolvedSettings.threadID
                    if !resolvedThreadID.isEmpty {
                        ProjectFileChipsView(
                            files: message.projectFiles,
                            threadID: resolvedThreadID,
                            settings: resolvedSettings,
                            authToken: chatStore.loadIronclawAuthToken(),
                            ironclawAPI: chatStore.ironclawAPI
                        )
                    }
                }

                if message.status == "gate_denied" {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.shield.fill")
                            .foregroundStyle(.red)
                        Text("Access denied")
                            .foregroundStyle(.red)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.red.opacity(0.25), lineWidth: 1)
                    }
                    .accessibilityIdentifier("message.gateDenied")
                }

                if message.status == "failed", !message.shouldShowAgentRunStatus, !shouldUseFailureRecoveryCard {
                    HStack(spacing: 10) {
                        Label("Failed", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("message.failedRow")
                        Button {
                            retryFailedMessage()
                        } label: {
                            Label(failedRetryTitle, systemImage: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("message.retry")

                        if shouldShowProxyRetryAction {
                            Button {
                                retryFailedMessageViaProxy()
                            } label: {
                                Label(proxyRetryActionTitle, systemImage: proxyRetryActionSymbolName)
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(Color.actionPrimary)
                            .accessibilityIdentifier("message.recovery.proxy")
                        }
                    }
                }

                if message.status == "cancelled", message.role == .assistant, !message.isStreaming {
                    HStack(spacing: 12) {
                        Label("Stopped", systemImage: "stop.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            chatStore.regenerateResponse(for: message)
                        } label: {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("message.regenerateStopped")
                    }
                }

                if message.role == .assistant, shouldShowSourceCarousel {
                    SourceChipRow(sources: message.sources) { tappedIndex in
                        tappedSource = SourceSheetPresentation(
                            index: tappedIndex,
                            source: message.sources[tappedIndex]
                        )
                    }
                }

                if let footerViewModel = verifiedFooterViewModel {
                    VerifiedFooterButton(viewModel: footerViewModel) {
                        showingSecurity = true
                    }
                }
            }
            .frame(maxWidth: message.role == .user ? 560 : 740, alignment: message.role == .user ? .trailing : .leading)
            .accessibilityIdentifier("message.\(message.role == .user ? "user" : "assistant")")

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
                chatStore.bannerMessage = MessageRepository.displayFailureMessage(error.localizedDescription)
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
        case "gate_denied":
            return "Access denied"
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

    private var proxyRetryOffer: ProxyRetryOffer? {
        guard let offer = chatStore.composerStore.proxyRetryOffer,
              offer.id == message.id else {
            return nil
        }
        return offer
    }

    private var renderedMessageText: String {
        let text = message.text.isEmpty ? " " : message.text
        guard message.role == .assistant else { return text }
        if message.status == "failed" {
            return MessageRepository.displayFailureMessage(text)
        }
        guard !message.isStreaming,
              message.widget == nil,
              let extraction = displayWidgetExtraction,
              extraction.widget != nil else {
            return text
        }
        return extraction.cleanedText.isEmpty ? " " : extraction.cleanedText
    }

    private var renderedAssistantMessageText: String? {
        AssistantMessagePresentationPolicy.visibleCompletedText(
            renderedMessageText,
            widget: displayWidget
        )
    }

    private var shouldShowSourceCarousel: Bool {
        AssistantMessagePresentationPolicy.shouldShowSourceCarousel(
            sources: message.sources,
            widget: displayWidget
        )
    }

    private var displayWidget: MessageWidget? {
        guard message.role == .assistant, !message.isStreaming else { return nil }
        if let widget = message.widget {
            return AssistantMessagePresentationPolicy.widgetForDisplay(widget, sources: message.sources)
        }
        return AssistantMessagePresentationPolicy.widgetForDisplay(displayWidgetExtraction?.widget, sources: message.sources)
    }

    private var displayWidgetExtraction: (widget: MessageWidget?, cleanedText: String)? {
        guard message.role == .assistant,
              !message.isStreaming,
              message.status != "failed",
              message.widget == nil else {
            return nil
        }
        let extraction = MessageWidget.extract(from: message.text)
        return extraction.widget == nil ? nil : extraction
    }

    // Split the "Title - detail" no-result line into a heading + sentence so
    // the error card reads like the other rounded cards instead of one run-on.
    private var briefingNoResultPresentation: (title: String, detail: String) {
        let raw = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = raw.range(of: " - ") else {
            return (raw.isEmpty ? "Council produced no result" : raw,
                    "Check sign-in, models, or network.")
        }
        let title = String(raw[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
        var detail = String(raw[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
        if let first = detail.first {
            detail = first.uppercased() + detail.dropFirst()
        }
        if !detail.isEmpty, !detail.hasSuffix(".") {
            detail += "."
        }
        return (title.isEmpty ? "Council produced no result" : title, detail)
    }

    private var isFailedPrivateRouteMessage: Bool {
        FailedMessageRecoveryPolicy.isFailedPrivateRouteMessage(message)
    }

    private var failedRetryTitle: String {
        isFailedPrivateRouteMessage ? "Retry private" : "Retry"
    }

    private var shouldUseFailureRecoveryCard: Bool {
        message.role == .assistant && message.status == "failed"
    }

    private var failedPresentation: AssistantFailurePresentation {
        AssistantFailurePresentation(
            message: message,
            nearCloudKeyConfigured: chatStore.nearCloudKeyConfigured
        )
    }

    private var failedSecondaryActionTitle: String? {
        failedPresentation.secondaryActionTitle
    }

    private var failedSecondaryActionSymbolName: String {
        failedPresentation.secondaryActionSymbolName
    }

    private var shouldShowProxyRetryAction: Bool {
        FailedMessageRecoveryPolicy.shouldShowProxyRetryAction(
            message: message,
            proxyRetryOffer: proxyRetryOffer
        )
    }

    private var proxyRetryActionTitle: String {
        if let offer = proxyRetryOffer, offer.proxyModelID == nil {
            return "Add Cloud key"
        }
        return chatStore.nearCloudKeyConfigured ? "Use privacy proxy" : "Add Cloud key"
    }

    private var proxyRetryActionSymbolName: String {
        proxyRetryActionTitle == "Add Cloud key" ? "key" : "eye.slash"
    }

    private func retryFailedMessage() {
        if message.councilBatchID?.isEmpty == false {
            chatStore.retryFailedCouncilMemberNow(for: message)
        } else if isFailedPrivateRouteMessage {
            chatStore.retryFailedPrivateResponseNow(for: message)
        } else {
            chatStore.regenerateResponse(for: message)
        }
    }

    private func retryFailedMessageViaProxy() {
        if let offer = proxyRetryOffer {
            if offer.proxyModelID == nil {
                chatStore.declineProxyRetry()
                chatStore.performRouteReadinessRecovery(.addNearCloudKey)
            } else {
                chatStore.acceptProxyRetry()
            }
            return
        }

        guard chatStore.nearCloudKeyConfigured else {
            chatStore.performRouteReadinessRecovery(.addNearCloudKey)
            return
        }
        chatStore.retryFailedResponseViaPrivacyProxy(for: message)
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
            chatStore.bannerMessage = MessageRepository.displayFailureMessage(error.localizedDescription)
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

enum FailedMessageRecoveryPolicy {
    static func isFailedPrivateRouteMessage(_ message: ChatMessage) -> Bool {
        guard message.status == "failed", message.role == .assistant else { return false }
        if let modelID = message.model, ChatStore.routeKind(forModelID: modelID) == .nearPrivate {
            return true
        }
        return message.text.localizedCaseInsensitiveContains("private route")
    }

    static func shouldShowProxyRetryAction(
        message: ChatMessage,
        proxyRetryOffer: ProxyRetryOffer?
    ) -> Bool {
        guard isFailedPrivateRouteMessage(message),
              proxyRetryOffer != nil else {
            return false
        }
        return true
    }
}

struct AssistantFailurePresentation: Equatable {
    let title: String
    let detail: String
    let routeLabel: String
    let secondaryActionTitle: String?
    let secondaryActionSymbolName: String

    init(message: ChatMessage, nearCloudKeyConfigured: Bool) {
        let compact = MessageRepository.displayFailureMessage(message.text)
        let lowercased = "\(message.text) \(compact)".lowercased()
        let isPrivate = FailedMessageRecoveryPolicy.isFailedPrivateRouteMessage(message)
        let isRateLimited = lowercased.contains("rate-limited") ||
            lowercased.contains("temporarily restricted") ||
            lowercased.contains("temporarily busy") ||
            lowercased.contains("private route limited") ||
            lowercased.contains("failed to check rate limit")
        let isAuth = lowercased.contains("authorization") ||
            lowercased.contains("sign in") ||
            lowercased.contains("authenticated") ||
            lowercased.contains("session token")

        if isPrivate && isRateLimited {
            title = "Private route needs a moment"
            detail = "The private route rejected this turn for the current session. Retry private when the route cools down, or use Cloud once for this answer."
            routeLabel = message.modelDisplayName
            secondaryActionTitle = nearCloudKeyConfigured ? "Use Cloud once" : "Add Cloud key"
            secondaryActionSymbolName = nearCloudKeyConfigured ? "eye.slash" : "key"
        } else if isPrivate && isAuth {
            title = "Sign in again"
            detail = "The private route did not accept this session. Refresh sign-in, then retry the private answer."
            routeLabel = message.modelDisplayName
            secondaryActionTitle = nil
            secondaryActionSymbolName = "key"
        } else {
            title = "Answer stopped"
            detail = compact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "The request failed before a final answer arrived. Retry when the route is reachable."
                : compact
            routeLabel = message.modelDisplayName
            secondaryActionTitle = nil
            secondaryActionSymbolName = "eye.slash"
        }
    }
}

private struct AssistantFailureRecoveryCard: View {
    let title: String
    let detail: String
    let routeLabel: String
    let primaryTitle: String
    let primarySymbolName: String
    let secondaryTitle: String?
    let secondarySymbolName: String
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.proofStaleText)
                    .frame(width: 30, height: 30)
                    .background(Color.proofStale.opacity(0.14), in: RoundedRectangle.app(AppRadius.control))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text(detail)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 7) {
                Label(routeLabel, systemImage: "lock.shield")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle.app(AppRadius.pill))

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button(action: onPrimary) {
                    Label(primaryTitle, systemImage: primarySymbolName)
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
                .minimumTouchTarget()
                .foregroundStyle(Color.actionPrimary)
                .background(Color.actionFill.opacity(0.72), in: RoundedRectangle.app(AppRadius.pill))
                .accessibilityIdentifier("message.retry")

                if let secondaryTitle {
                    Button(action: onSecondary) {
                        Label(secondaryTitle, systemImage: secondarySymbolName)
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(.plain)
                    .minimumTouchTarget()
                    .foregroundStyle(Color.proofStaleText)
                    .background(Color.proofStale.opacity(0.12), in: RoundedRectangle.app(AppRadius.pill))
                    .accessibilityIdentifier("message.recovery.proxy")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.proofStale.opacity(0.055), in: RoundedRectangle.app(AppRadius.control))
        .overlay {
            RoundedRectangle.app(AppRadius.control)
                .stroke(Color.proofStale.opacity(0.24), lineWidth: 1)
        }
    }
}

/// A scheduled briefing that ran but produced nothing to deliver. Matches the
/// rounded-card system (tint + glyph + heading) instead of a bare line, and
/// carries Retry alongside Copy.
private struct BriefingNoResultCard: View {
    let title: String
    let detail: String
    let onRetry: () -> Void
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.proofStaleText)
                    .frame(width: 30, height: 30)
                    .background(Color.proofStale.opacity(0.14), in: RoundedRectangle.app(AppRadius.control))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text(detail)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
                .minimumTouchTarget()
                .foregroundStyle(Color.actionPrimary)
                .background(Color.actionFill.opacity(0.72), in: RoundedRectangle.app(AppRadius.pill))
                .accessibilityIdentifier("briefing.noResult.retry")

                Button(action: onCopy) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
                .minimumTouchTarget()
                .foregroundStyle(Color.textSecondary)
                .background(Color.appSecondaryBackground, in: RoundedRectangle.app(AppRadius.pill))
                .accessibilityIdentifier("briefing.noResult.copy")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.proofStale.opacity(0.055), in: RoundedRectangle.app(AppRadius.control))
        .overlay {
            RoundedRectangle.app(AppRadius.control)
                .stroke(Color.proofStale.opacity(0.24), lineWidth: 1)
        }
        .accessibilityIdentifier("briefing.noResult.card")
    }
}
