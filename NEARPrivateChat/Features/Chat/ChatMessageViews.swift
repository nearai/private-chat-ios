import EventKit
import SwiftUI
import UniformTypeIdentifiers

struct MessageBubble: View {
    let message: ChatMessage
    let chatStore: ChatStore
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

                if message.role == .assistant && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !message.isStreaming {
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
                    Label("Failed", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
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
        if chatStore.shouldShowSharedAuthorNames, message.role == .user { return true }
        return false
    }

    private var headerTitle: String {
        if message.role == .user {
            if chatStore.shouldShowSharedAuthorNames {
                return message.authorDisplayLabel ?? "User"
            }
            return "You"
        }
        return message.modelDisplayName
    }

    private var authorBadgeTitle: String? {
        guard chatStore.shouldShowSharedAuthorNames, message.role != .user else {
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
        guard message.role == .assistant,
              !message.isStreaming,
              !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
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

private struct AgentThinkingShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerPhase: CGFloat = 0
    let statusText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 24, height: 24)
                    .background(Color.brandBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 7) {
                shimmerBar(widthFraction: 0.92)
                shimmerBar(widthFraction: 0.68)
            }
            .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.brandBlue.opacity(0.14), lineWidth: 1)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                shimmerPhase = 1
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusText)
    }

    private func shimmerBar(widthFraction: CGFloat) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.appBorder.opacity(0.45))
                .overlay {
                    if !reduceMotion {
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.58),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.46)
                        .offset(x: (shimmerPhase * proxy.size.width * 1.65) - proxy.size.width * 0.55)
                    }
                }
                .mask(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .frame(height: 9)
        .frame(maxWidth: widthFraction == 1 ? .infinity : 420 * widthFraction)
    }
}

struct StreamingMessageText: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(message.streamingStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(Self.streamingLengthText(from: message.text))
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(Self.streamingPreview(from: message.text))
                .lineSpacing(2)
                .lineLimit(12)
                .textSelection(.enabled)
        }
    }

    private static func streamingPreview(from rawText: String) -> String {
        let text = MessageWidget.strippedStreamingPreview(rawText)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return " " }
        let cappedText: String
        let isCapped: Bool
        if trimmed.utf8.count > 4_000 {
            cappedText = String(trimmed.suffix(4_000))
            isCapped = true
        } else {
            cappedText = trimmed
            isCapped = false
        }
        let lines = cappedText
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let preview = lines.isEmpty ? cappedText : lines.suffix(12).joined(separator: "\n")
        return isCapped ? "...\n\(preview)" : preview
    }

    private static func streamingLengthText(from text: String) -> String {
        let byteCount = text.utf8.count
        guard byteCount >= 10_000 else {
            return "\(text.count) chars"
        }
        return "~\(byteCount / 1_000)k chars"
    }
}

private struct AttestedMessageChip: View {
    let status: AttestationStatus
    let modelID: String?

    var body: some View {
        let isCovered = status.coverage(for: modelID) == .covered
        let copy = status.userFacingCopy()
        Label(copy.badge, systemImage: status.symbolName)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isCovered ? Color.verifiedGreen : status.tintColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(status.tintColor.opacity(0.10), in: Capsule())
            .accessibilityHint(copy.detail)
    }
}

private struct ResponseVariantPicker: View {
    let variant: MessageBranchVariant
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            variantButton(
                symbolName: "chevron.left",
                responseID: variant.previousResponseID,
                label: "Previous response variant"
            )

            Text("Response \(variant.displayIndex) of \(variant.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            variantButton(
                symbolName: "chevron.right",
                responseID: variant.nextResponseID,
                label: "Next response variant"
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.appPanelBackground, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.appBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Response variant \(variant.displayIndex) of \(variant.count)")
    }

    private func variantButton(symbolName: String, responseID: String?, label: String) -> some View {
        Button {
            if let responseID {
                onSelect(responseID)
            }
        } label: {
            Image(systemName: symbolName)
                .font(.caption.weight(.bold))
                .frame(width: 24, height: 24)
                .foregroundStyle(responseID == nil ? Color.secondary.opacity(0.45) : Color.brandBlue)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(responseID == nil)
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct EditUserMessageView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    let message: ChatMessage
    @State private var prompt: String

    init(message: ChatMessage) {
        self.message = message
        _prompt = State(initialValue: message.text)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Edit prompt", text: $prompt, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(5...12)
                        .padding(10)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } header: {
                    Text("Edit Prompt")
                } footer: {
                    Text("Starts a new branch from the original turn.")
                }

                if !message.attachments.isEmpty {
                    Section("Kept Files") {
                        ForEach(message.attachments) { attachment in
                            Label {
                                Text(attachment.name)
                                    .lineLimit(1)
                            } icon: {
                                Image(systemName: attachment.systemImageName)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Edit Message")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        chatStore.editAndResend(message, replacementText: prompt)
                        dismiss()
                    }
                    .disabled(trimmedPrompt.isEmpty && message.attachments.isEmpty)
                }
            }
        }
        .platformMediumDetent()
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct AgentRunStatusStrip: View {
    let message: ChatMessage
    let toolCount: Int
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        TimelineView(.periodic(from: message.createdAt, by: 1)) { context in
            let isStale = isStaleRun(now: context.date)
            HStack(spacing: 8) {
                Image(systemName: symbolName(isStale: isStale))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tintColor(isStale: isStale))
                    .frame(width: 24, height: 24)
                    .background(tintColor(isStale: isStale).opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title(isStale: isStale))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(elapsedText(now: context.date))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let detail = detailText(isStale: isStale) {
                        Text(detail)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                if isStale && message.isStreaming {
                    Button(action: onCancel) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop stalled IronClaw run")
                } else if message.status == "failed" || isStale {
                    Button(action: onRetry) {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.brandBlue)
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retry IronClaw run")
                }
            }
            .padding(9)
            .frame(maxWidth: 520, alignment: .leading)
            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tintColor(isStale: isStale).opacity(message.status == "failed" || isStale ? 0.24 : 0.16), lineWidth: 1)
            }
        }
    }

    private func title(isStale: Bool) -> String {
        if message.status == "failed" {
            return "Run stopped"
        }
        if isStale {
            return "No output received"
        }
        if message.pendingApproval != nil || message.status == "approval" {
            return "Agent needs input"
        }
        if message.status == "searching" {
            return "Gathering context"
        }
        return "Agent running"
    }

    private func detailText(isStale: Bool) -> String? {
        if message.status == "failed" {
            return "Hosted IronClaw stopped before a final answer. Check the Agent connection, then retry."
        }
        if isStale {
            return message.isStreaming
                ? "The hosted run may have stalled. Stop it, then retry from the phone."
                : "The hosted run may have stalled. Retry starts a fresh phone-controlled run."
        }
        if message.pendingApproval != nil || message.status == "approval" {
            return "Review the tool request below to continue the run."
        }
        return nil
    }

    private func symbolName(isStale: Bool) -> String {
        if message.status == "failed" {
            return "exclamationmark.triangle.fill"
        }
        if isStale {
            return "clock.badge.exclamationmark"
        }
        if message.pendingApproval != nil || message.status == "approval" {
            return "hand.tap.fill"
        }
        return "arrow.triangle.2.circlepath"
    }

    private func tintColor(isStale: Bool) -> Color {
        if message.status == "failed" { return .red }
        if isStale { return .orange }
        return Color.brandBlue
    }

    private func elapsedText(now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(message.createdAt))
        if message.status == "failed" {
            return "after \(Self.compactDuration(elapsed))"
        }
        if isStaleRun(now: now) {
            return "for \(Self.compactDuration(elapsed))"
        }
        if message.pendingApproval != nil || message.status == "approval" {
            return "paused \(Self.compactDuration(elapsed))"
        }
        return Self.compactDuration(elapsed)
    }

    private func isStaleRun(now: Date) -> Bool {
        guard message.pendingApproval == nil,
              message.status != "failed" else {
            return false
        }
        let activeStatuses = ["reasoning", "searching", "running", "queued", "in_progress"]
        guard message.isStreaming || activeStatuses.contains(message.status.lowercased()) else {
            return false
        }
        return now.timeIntervalSince(message.createdAt) > 2 * 60
    }

    private static func compactDuration(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded(.down))
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        return "\(minutes / 60)h"
    }
}

private struct AssistantInlineActions: View {
    let canSaveToProject: Bool
    let isSavedToProject: Bool
    let canOpen: Bool
    let sourceCount: Int
    let onCopy: () -> Void
    let onCopySigned: () -> Void
    let onExport: (ConversationExportFormat) -> Void
    let onRegenerate: () -> Void
    let onSave: () -> Void
    let onOpen: () -> Void
    let onSources: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                actionButton(symbolName: "doc.on.doc", label: "Copy", action: onCopy)
                exportMenu
                actionButton(symbolName: "arrow.clockwise", label: "Regenerate", action: onRegenerate)
                if canOpen {
                    actionButton(symbolName: "rectangle.expand.vertical", label: "Open Output", action: onOpen)
                }
                actionButton(symbolName: "checkmark.shield", label: "Copy Device-Signed Snippet", action: onCopySigned)
                saveButton
                if sourceCount > 0 {
                    Button(action: onSources) {
                        HStack(spacing: 7) {
                            ZStack {
                                Circle()
                                    .fill(Color.trustVerified.opacity(0.20))
                                Image(systemName: "link")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.trustVerified)
                            }
                            .frame(width: 24, height: 24)
                            Text(sourceButtonLabel)
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                        .frame(height: 34)
                        .padding(.horizontal, 8)
                        .background(Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(sourceCount == 1 ? "Open source" : "Open \(sourceCount) sources")
                }
            }
        }
        .scrollClipDisabled()
        .padding(.top, 2)
    }

    private var exportMenu: some View {
        Menu {
            Button {
                onExport(.markdown)
            } label: {
                Label("Markdown", systemImage: "doc.plaintext")
            }
            Button {
                onExport(.pdf)
            } label: {
                Label("PDF", systemImage: "doc.richtext")
            }
            Button {
                onExport(.docx)
            } label: {
                Label("Word Document", systemImage: "doc")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.title3.weight(.regular))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color.clear, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Export Answer")
    }

    private var saveButton: some View {
        Button(action: onSave) {
            Image(systemName: saveSymbolName)
                .font(.title3.weight(.regular))
                .foregroundStyle(saveForeground)
                .frame(width: 34, height: 34)
                .background(saveBackground, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isSavedToProject)
        .accessibilityLabel(saveAccessibilityLabel)
    }

    private var sourceButtonLabel: String {
        "\(sourceCount) source\(sourceCount == 1 ? "" : "s")"
    }

    private func actionButton(symbolName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.title3.weight(.regular))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color.clear, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var saveLabel: String {
        if isSavedToProject {
            return "Saved"
        }
        return canSaveToProject ? "Save" : "Project"
    }

    private var saveSymbolName: String {
        if isSavedToProject {
            return "checkmark"
        }
        return canSaveToProject ? "bookmark.fill" : "bookmark"
    }

    private var saveForeground: Color {
        isSavedToProject || canSaveToProject ? Color.brandBlue : .secondary
    }

    private var saveBackground: Color {
        isSavedToProject || canSaveToProject ? Color.brandBlue.opacity(0.10) : Color.appSecondaryBackground
    }

    private var saveAccessibilityLabel: String {
        if isSavedToProject {
            return "Saved to Project"
        }
        return canSaveToProject ? "Save to Project" : "Select a Project to Save"
    }
}

private struct ArtifactOutputView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    let message: ChatMessage

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.brandBlue)
                            .frame(width: 32, height: 32)
                            .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.modelDisplayName)
                                .font(.headline.weight(.semibold))
                            Text(message.createdAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }

                    Divider()

                    MarkdownMessageText(text: message.text, sources: message.sources)
                        .font(.body)

                    if !message.sources.isEmpty {
                        SearchContextStrip(query: message.searchQuery, sources: message.sources)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.appBackground)
            .navigationTitle("Output")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Clipboard.copy(message.text)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("Copy Output")

                    Button {
                        chatStore.copySignedSnippet(for: message)
                    } label: {
                        Image(systemName: "checkmark.shield")
                    }
                    .accessibilityLabel("Copy Device-Signed Snippet")

                    Button {
                        chatStore.requestProjectNoteSave(for: message)
                    } label: {
                        Image(systemName: "bookmark")
                    }
                    .accessibilityLabel("Save Output to Project")
                }
            }
        }
    }
}

private extension ChatMessage {
    var isArtifactCandidate: Bool {
        guard role == .assistant, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return text.count > 1_200 ||
            text.contains("```") ||
            text.contains("\n|") ||
            text.localizedCaseInsensitiveContains("# ")
    }
}


struct AssistantAvatar: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.brandBlue.opacity(0.10))
            Image(systemName: "lock.shield.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.brandBlue)
        }
        .frame(width: 30, height: 30)
    }
}

private struct MessageAttachmentStrip: View {
    let attachments: [ChatAttachment]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(attachments) { attachment in
                Label {
                    Text(attachment.name)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: attachment.systemImageName)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

// MARK: - Claude Design Source Carousel

/// Snap-paged source carousel rendered above a web-grounded assistant reply.
/// Spec: 280×88 cards, 16r, panel bg, 1px border, 20px favicon, numbered
/// circular badge (white on action), 2-line 15pt SemiBold title, 13pt domain.
struct SourceCarousel: View {
    let sources: [WebSearchSource]
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                    SourceCard(index: index + 1, source: source)
                        .onTapGesture { onSelect(index) }
                }
            }
            .padding(.trailing, 24)
        }
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(sources.count) source\(sources.count == 1 ? "" : "s")")
    }
}

private struct SourceCard: View {
    let index: Int
    let source: WebSearchSource

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                FaviconBadge(source: source)
                Text(source.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 2)
                Spacer(minLength: 0)
                Text(source.displaySubtitle)
                    .font(.footnote)
                    .fontWeight(.regular)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 280, height: 88, alignment: .topLeading)
            .padding(12)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 1)
            }

            Text("\(index)")
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.actionPrimary, in: Circle())
                .padding(12)
        }
        .frame(width: 304, height: 112, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityLabel("Source \(index), \(source.displayTitle), \(source.host)")
    }
}

private struct FaviconBadge: View {
    let source: WebSearchSource

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.appSecondaryBackground)
            fallback
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var fallback: some View {
        Text(source.sourceInitials.prefix(1))
            .font(.caption)
            .fontWeight(.heavy)
            .foregroundStyle(Color.textSecondary)
    }
}

// MARK: - Claude Design Proof Footer

struct VerifiedFooterViewModel {
    let state: ProofState
    let badge: String
    let model: String
    let sourceCount: Int
    let ago: String
    let symbolName: String
    let tintColor: Color
    let detail: String
}

struct VerifiedFooterButton: View {
    let viewModel: VerifiedFooterViewModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: footerSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(footerTint)
                Text(footerText)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open proof details")
        .accessibilityValue(viewModel.detail)
    }

    private var footerSymbol: String {
        switch viewModel.state {
        case .verified:
            return "checkmark.seal.fill"
        case .stale:
            return "clock.badge.exclamationmark"
        case .mismatch:
            return "exclamationmark.shield.fill"
        case .verifying:
            return "arrow.triangle.2.circlepath"
        default:
            return viewModel.symbolName
        }
    }

    private var footerTint: Color {
        switch viewModel.state {
        case .verified:
            return Color.proofVerified
        case .stale:
            return Color.proofStale
        case .mismatch:
            return Color.proofMismatch
        default:
            return viewModel.tintColor
        }
    }

    private var footerText: String {
        // For route/model proof and non-answer-bound states keep the badge so users see
        // "Proof report" / "Stale" / "Privacy proxy" without answer-level overclaiming.
        var pieces: [String] = []
        switch viewModel.state {
        case .verified:
            pieces.append("Proof checked")
        case .stale:
            pieces.append("Proof stale")
        case .mismatch:
            pieces.append("Not covered")
        case .verifying:
            pieces.append("Checking proof")
        default:
            pieces.append(viewModel.badge)
        }
        pieces.append(viewModel.model)
        if viewModel.sourceCount > 0 {
            pieces.append("\(viewModel.sourceCount) source\(viewModel.sourceCount == 1 ? "" : "s")")
        }
        pieces.append("\(viewModel.ago) ago")
        return pieces.joined(separator: " · ")
    }
}

enum ChatTimeFormatter {
    static func relativeShort(from date: Date, now: Date = Date()) -> String {
        let delta = max(0, now.timeIntervalSince(date))
        if delta < 5 { return "now" }
        if delta < 60 { return "\(Int(delta))s" }
        let minutes = Int(delta / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 7 { return "\(days)d" }
        let weeks = days / 7
        if weeks < 5 { return "\(weeks)w" }
        let months = days / 30
        if months < 12 { return "\(months)mo" }
        return "\(days / 365)y"
    }
}

// Lightweight `view.if(cond) { ... }` modifier so we can branch the user
// bubble styling without an Either-view explosion.
extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - Claude Design Source Sheet (per-source half-sheet)

/// Identifies which carousel card was tapped so SwiftUI can drive an
/// `item:`-style sheet without losing identity between presentations.
struct SourceSheetPresentation: Identifiable {
    let index: Int
    let source: WebSearchSource

    var id: String { "\(index)-\(source.id)" }
}

/// Per-source half-sheet. Spec: partial detent over the chat thread, glass
/// chrome (sheet container) with solid content inside. Header is the
/// favicon + domain; body is title (17/22 SemiBold), author/date row (13/18
/// text-2), and a snippet block (15/22, surface-2 background) with the
/// cited span highlighted in --proof-stale yellow when we have one. No
/// Proof badge — route/model evidence is not answer-bound until messages carry proof metadata.
struct SourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let index: Int
    let source: WebSearchSource

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(source.displayTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let metaLine, !metaLine.isEmpty {
                        Text(metaLine)
                            .font(.footnote)
                            .fontWeight(.regular)
                            .foregroundStyle(Color.textSecondary)
                    }

                    if let snippet = source.snippetFallback {
                        Text(snippet)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineSpacing(7)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }

            actionStack
        }
        .background(Color.appPanelBackground)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            FaviconBadge(source: source)
            Text(source.host)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(height: 44)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var actionStack: some View {
        VStack(spacing: 4) {
            Button {
                if let url = source.safeURL { openURL(url) }
            } label: {
                HStack(spacing: 6) {
                    Text("Open in Safari")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.actionPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(source.safeURL == nil)

            Button {
                if let url = source.safeURL { Clipboard.copy(url.absoluteString) }
            } label: {
                Text("Copy link")
                    .font(.headline)
                    .foregroundStyle(Color.actionPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.plain)
            .disabled(source.safeURL == nil)

            Button {
                Clipboard.copy(source.citationCopyText)
            } label: {
                Text("Copy citation")
                    .font(.headline)
                    .foregroundStyle(Color.actionPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    private var metaLine: String? {
        var parts: [String] = []
        if let published = source.publishedAt?.trimmingCharacters(in: .whitespacesAndNewlines), !published.isEmpty {
            parts.append(published)
        }
        if parts.isEmpty { return nil }
        return parts.joined(separator: " · ")
    }
}

private extension WebSearchSource {
    var snippetFallback: String? {
        snippetPreview
    }
}

// MARK: - Generative widget cards
//
// Renders a MessageWidget as a native card whose shape matches the answer:
// chart, metric, comparison table, or news digest. Each card carries a meta
// strip (freshness + source + time) and a micro-composer for scoped follow-up.
// Chrome matches SourceCard / IronclawApprovalCard: panel bg, 16r, 1px border.

struct MessageWidgetCard: View {
    let widget: MessageWidget
    var onFollowUp: ((String) -> Void)? = nil
    var onCreateAppAction: ((WidgetActionItem) -> Void)? = nil

    var body: some View {
        WidgetShell(
            title: widget.title,
            time: widget.time,
            freshness: widget.freshness,
            followUpPlaceholder: widget.followUp,
            onFollowUp: onFollowUp
        ) {
            switch widget.kind {
            case .chart:
                if let chart = widget.chart { WidgetChartBody(chart: chart) }
            case .metric:
                if let metric = widget.metric { WidgetMetricBody(metric: metric) }
            case .comparison:
                if let comparison = widget.comparison { WidgetComparisonBody(comparison: comparison) }
            case .newsBrief:
                if let brief = widget.newsBrief { WidgetNewsBriefBody(brief: brief) }
            case .actionPlan:
                if let plan = widget.actionPlan {
                    WidgetActionPlanBody(
                        plan: plan,
                        onFollowUp: onFollowUp,
                        onCreateAppAction: onCreateAppAction
                    )
                }
            case .generic:
                if let note = widget.note { WidgetGenericBody(note: note) }
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
    }
}

private struct WidgetShell<Content: View>: View {
    let title: String?
    let time: String?
    let freshness: WidgetFreshness?
    let followUpPlaceholder: String?
    var onFollowUp: ((String) -> Void)? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if title != nil || time != nil {
                HStack(spacing: 8) {
                    Image(systemName: "seal.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(freshness == .stale ? Color.proofStale : Color.proofVerified)
                    if let title {
                        Text(title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let time {
                        Text(time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider().overlay(Color.appHairline)
            }

            content
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)

            if onFollowUp != nil {
                Button {
                    onFollowUp?(followUpPlaceholder ?? "Tell me more about this")
                } label: {
                    HStack(spacing: 8) {
                        Text(followUpPlaceholder ?? "Ask about this…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.actionPrimary)
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 8)
                    .frame(height: 38)
                    .background(Color.appSecondaryBackground, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .accessibilityLabel("Ask a follow-up about this widget")
            }
        }
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }
}

// MARK: Widget bodies

private struct WidgetChartBody: View {
    let chart: WidgetChart

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    if let label = chart.label {
                        Text(label.uppercased())
                            .font(.caption2.weight(.medium))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                    }
                    if let value = chart.value {
                        Text(value)
                            .font(.system(.title2, design: .monospaced).weight(.bold))
                            .foregroundStyle(.primary)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    if let delta = chart.delta {
                        Text(delta)
                            .font(.system(.subheadline, design: .monospaced).weight(.medium))
                            .foregroundStyle(widgetTrendColor(chart.trend))
                    }
                    if let timeframe = chart.timeframe {
                        Text(timeframe)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if chart.points.count > 1 {
                ZStack {
                    WidgetSparklineFill(points: chart.points)
                        .fill(
                            LinearGradient(
                                colors: [widgetTrendColor(chart.trend).opacity(0.18), widgetTrendColor(chart.trend).opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    WidgetSparkline(points: chart.points)
                        .stroke(widgetTrendColor(chart.trend), style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 64)
            }

            if let caption = chart.caption {
                HStack(spacing: 6) {
                    Circle()
                        .fill(widgetTrendColor(chart.trend))
                        .frame(width: 6, height: 6)
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct WidgetMetricBody: View {
    let metric: WidgetMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label = metric.label {
                Text(label.uppercased())
                    .font(.caption2.weight(.medium))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }
            Text(metric.value)
                .font(.system(.title, design: .monospaced).weight(.bold))
                .foregroundStyle(.primary)
            if let delta = metric.delta {
                Text(delta)
                    .font(.system(.subheadline, design: .monospaced).weight(.medium))
                    .foregroundStyle(widgetTrendColor(metric.trend))
            }
            if let caption = metric.caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct WidgetComparisonBody: View {
    let comparison: WidgetComparison

    private var columnCount: Int { max(comparison.columns.count, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let subtitle = comparison.subtitle {
                Text(subtitle.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                // Header row
                HStack(alignment: .top, spacing: 8) {
                    Text("")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(comparison.columns.enumerated()), id: \.offset) { _, col in
                        Text(col)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 6)

                ForEach(Array(comparison.rows.enumerated()), id: \.offset) { _, row in
                    Divider().overlay(Color.appHairline)
                    HStack(alignment: .top, spacing: 8) {
                        Text(row.label)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(0..<columnCount, id: \.self) { i in
                            let cell = i < row.cells.count ? row.cells[i] : WidgetComparisonCell(text: "—", tone: .off)
                            Text(cell.text)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(widgetToneColor(cell.tone))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

private struct WidgetNewsBriefBody: View {
    let brief: WidgetNewsBrief

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let heading = brief.heading {
                Text(heading.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(brief.stories.enumerated()), id: \.offset) { _, story in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Color.textSecondary)
                        .frame(width: 4, height: 4)
                        .padding(.top, 7)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(story.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 4) {
                            ForEach(Array(story.sources.enumerated()), id: \.offset) { _, src in
                                WidgetSourceDot(source: src)
                            }
                            if let tag = story.tag {
                                Text(tag)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 2)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct WidgetActionPlanBody: View {
    let plan: WidgetActionPlan
    var onFollowUp: ((String) -> Void)? = nil
    var onCreateAppAction: ((WidgetActionItem) -> Void)? = nil
    @State private var selectedAction: WidgetActionItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let heading = widgetNonBlank(plan.heading) {
                Text(heading)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let summary = widgetNonBlank(plan.summary) {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(plan.actions.indices, id: \.self) { index in
                    if index > 0 {
                        Divider().overlay(Color.appHairline)
                    }
                    WidgetActionRow(
                        action: plan.actions[index],
                        onFollowUp: onFollowUp,
                        onPreview: { selectedAction = $0 }
                    )
                        .padding(.vertical, 9)
                }
            }
        }
        .sheet(item: $selectedAction) { action in
            WidgetActionCandidatePreviewSheet(
                action: action,
                canStageCommand: onFollowUp != nil,
                onStageCommand: { command in
                    selectedAction = nil
                    onFollowUp?(command)
                },
                onCreateAppAction: { action in
                    selectedAction = nil
                    onCreateAppAction?(action)
                }
            )
        }
    }
}

private struct WidgetActionRow: View {
    let action: WidgetActionItem
    var onFollowUp: ((String) -> Void)? = nil
    var onPreview: ((WidgetActionItem) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(action.title.isEmpty ? "Action" : action.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                let metadata = metadataText
                if !metadata.isEmpty {
                    Text(metadata)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(tint)
                        .lineLimit(2)
                }

                if let detail = widgetNonBlank(action.detail) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !action.missingFields.isEmpty {
                    Text("Needs: \(action.missingFields.prefix(3).joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(2)
                }
            }

            if widgetNonBlank(action.command) != nil, onFollowUp != nil {
                Spacer(minLength: 6)
                Button {
                    onPreview?(action)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.actionPrimary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stage action")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onPreview?(action)
        }
        .accessibilityAction(named: "Preview") {
            onPreview?(action)
        }
    }

    private var normalizedType: String {
        (action.type ?? "")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var metadataText: String {
        [
            widgetNonBlank(action.type),
            widgetNonBlank(action.schedule),
            widgetNonBlank(action.recurrence),
            widgetNonBlank(action.time),
            widgetNonBlank(action.source)
        ]
        .compactMap { $0 }
        .prefix(4)
        .joined(separator: " · ")
    }

    private var symbolName: String {
        if normalizedType.contains("calendar") || normalizedType.contains("invite") {
            return "calendar.badge.plus"
        }
        if normalizedType.contains("reminder") {
            return "bell.badge"
        }
        if normalizedType.contains("tracker") || normalizedType.contains("brief") || normalizedType.contains("watch") {
            return "dot.radiowaves.left.and.right"
        }
        if normalizedType.contains("decision") {
            return "checkmark.seal"
        }
        if normalizedType.contains("risk") {
            return "exclamationmark.triangle"
        }
        if normalizedType.contains("question") {
            return "questionmark.circle"
        }
        if normalizedType.contains("interest") {
            return "sparkles"
        }
        return "checklist"
    }

    private var tint: Color {
        widgetToneColor(action.tone)
    }
}

private struct WidgetActionCandidatePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let action: WidgetActionItem
    let canStageCommand: Bool
    let onStageCommand: (String) -> Void
    let onCreateAppAction: ((WidgetActionItem) -> Void)?
    @State private var isSavingSystemAction = false
    @State private var systemActionStatus: String?

    var body: some View {
        let systemDraft = action.systemActionDraft()
        let appDraft = action.appActionDraft()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(action.title.isEmpty ? "Action" : action.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = widgetNonBlank(action.detail) {
                            Text(detail)
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    WidgetActionCandidateFieldList(action: action)

                    WidgetAppActionSection(
                        draft: appDraft,
                        canCreate: onCreateAppAction != nil,
                        onCreate: {
                            onCreateAppAction?(action)
                            dismiss()
                        }
                    )

                    WidgetSystemActionSection(
                        action: action,
                        draft: systemDraft,
                        isSaving: isSavingSystemAction,
                        status: systemActionStatus,
                        onSave: { draft in
                            saveSystemAction(draft)
                        }
                    )

                    if let command = widgetNonBlank(action.command) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Stage in Chat")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                            Text(command)
                                .font(.footnote)
                                .foregroundStyle(Color.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.appBorder, lineWidth: 0.5)
                                }
                        }
                    }
                }
                .padding(18)
            }
            .background(Color.appBackground)
            .navigationTitle("Review Before Creating")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if canStageCommand, let command = widgetNonBlank(action.command) {
                        Button("Stage") {
                            onStageCommand(command)
                        }
                    }
                }
            }
        }
        .platformMediumDetent()
    }

    private func saveSystemAction(_ draft: WidgetSystemActionDraft) {
        guard !isSavingSystemAction else { return }
        isSavingSystemAction = true
        systemActionStatus = nil
        Task {
            do {
                let message = try await WidgetSystemActionWriter.shared.save(draft)
                await MainActor.run {
                    systemActionStatus = message
                    isSavingSystemAction = false
                }
            } catch {
                await MainActor.run {
                    systemActionStatus = error.localizedDescription
                    isSavingSystemAction = false
                }
            }
        }
    }
}

private struct WidgetAppActionSection: View {
    let draft: WidgetAppActionDraft?
    let canCreate: Bool
    let onCreate: () -> Void

    var body: some View {
        guard let draft else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text("Create in App")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)

                if draft.isReady {
                    Button {
                        onCreate()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.subheadline.weight(.semibold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Create Tracker")
                                    .font(.subheadline.weight(.semibold))
                                Text(draft.schedule.scheduleLabel)
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.actionPrimary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.actionPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCreate)
                    .accessibilityLabel("Create tracker")
                } else {
                    Label("Needs \(draft.missingFields.prefix(3).joined(separator: ", ")) before it can be saved as a tracker.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        )
    }
}

private struct WidgetSystemActionSection: View {
    let action: WidgetActionItem
    let draft: WidgetSystemActionDraft?
    let isSaving: Bool
    let status: String?
    let onSave: (WidgetSystemActionDraft) -> Void

    var body: some View {
        guard action.systemActionKind != nil else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text("Add to Phone")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)

                if let draft {
                    Button {
                        onSave(draft)
                    } label: {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: draft.kind == .calendarEvent ? "calendar.badge.plus" : "bell.badge")
                                    .font(.subheadline.weight(.semibold))
                            }
                            Text(draft.kind == .calendarEvent ? "Add to Calendar" : "Add Reminder")
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                            Text(draft.startDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.actionPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                } else {
                    Label("Needs an exact date and time before adding to iOS.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if let status = widgetNonBlank(status) {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        )
    }
}

@MainActor
private final class WidgetSystemActionWriter {
    static let shared = WidgetSystemActionWriter()
    private let eventStore = EKEventStore()

    func save(_ draft: WidgetSystemActionDraft) async throws -> String {
        switch draft.kind {
        case .calendarEvent:
            try await requestCalendarAccess()
            guard let calendar = eventStore.defaultCalendarForNewEvents else {
                throw WidgetSystemActionWriterError.noDefaultCalendar
            }
            let event = EKEvent(eventStore: eventStore)
            event.calendar = calendar
            event.title = draft.title
            event.startDate = draft.startDate
            event.endDate = draft.endDate ?? draft.startDate.addingTimeInterval(30 * 60)
            event.notes = draft.notes
            event.location = draft.location
            if let rule = recurrenceRule(from: draft.recurrence) {
                event.addRecurrenceRule(rule)
            }
            try eventStore.save(event, span: .futureEvents, commit: true)
            return "Added to Calendar."
        case .reminder:
            try await requestReminderAccess()
            guard let calendar = eventStore.defaultCalendarForNewReminders() else {
                throw WidgetSystemActionWriterError.noDefaultReminderList
            }
            let reminder = EKReminder(eventStore: eventStore)
            reminder.calendar = calendar
            reminder.title = draft.title
            reminder.notes = draft.notes
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: draft.startDate
            )
            if let rule = recurrenceRule(from: draft.recurrence) {
                reminder.addRecurrenceRule(rule)
            }
            try eventStore.save(reminder, commit: true)
            return "Added to Reminders."
        }
    }

    private func requestCalendarAccess() async throws {
        let granted: Bool = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            eventStore.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
        guard granted else { throw WidgetSystemActionWriterError.accessDenied("Calendar") }
    }

    private func requestReminderAccess() async throws {
        let granted: Bool = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            eventStore.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
        guard granted else { throw WidgetSystemActionWriterError.accessDenied("Reminders") }
    }

    private func recurrenceRule(from value: String?) -> EKRecurrenceRule? {
        guard let value = widgetNonBlank(value)?.lowercased() else { return nil }
        if value.contains("weekday") || value.contains("weekdays") || value.contains("mon-fri") || value.contains("monday to friday") {
            let weekdays = [
                EKRecurrenceDayOfWeek(.monday),
                EKRecurrenceDayOfWeek(.tuesday),
                EKRecurrenceDayOfWeek(.wednesday),
                EKRecurrenceDayOfWeek(.thursday),
                EKRecurrenceDayOfWeek(.friday)
            ]
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                daysOfTheWeek: weekdays,
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: nil
            )
        }
        let frequency: EKRecurrenceFrequency
        if value.contains("month") {
            frequency = .monthly
        } else if value.contains("week") {
            frequency = .weekly
        } else if value.contains("year") || value.contains("annual") {
            frequency = .yearly
        } else if value.contains("daily") || value.contains("day") {
            frequency = .daily
        } else {
            return nil
        }
        return EKRecurrenceRule(recurrenceWith: frequency, interval: 1, end: nil)
    }
}

private enum WidgetSystemActionWriterError: LocalizedError {
    case accessDenied(String)
    case noDefaultCalendar
    case noDefaultReminderList

    var errorDescription: String? {
        switch self {
        case let .accessDenied(scope):
            return "\(scope) access was not granted."
        case .noDefaultCalendar:
            return "No writable default calendar is available."
        case .noDefaultReminderList:
            return "No writable default reminders list is available."
        }
    }
}

private struct WidgetActionCandidateFieldList: View {
    let action: WidgetActionItem

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                if index > 0 {
                    Divider().overlay(Color.appHairline)
                        .padding(.leading, 40)
                }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: field.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.actionPrimary)
                        .frame(width: 28, height: 28)
                        .background(Color.actionTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(field.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                        Text(field.value)
                            .font(.subheadline)
                            .foregroundStyle(Color.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 0.5)
        }
    }

    private var fields: [WidgetActionCandidateField] {
        var result: [WidgetActionCandidateField] = []
        func append(_ title: String, _ value: String?, _ symbolName: String) {
            guard let value = widgetNonBlank(value) else { return }
            result.append(WidgetActionCandidateField(title: title, value: value, symbolName: symbolName))
        }
        append("Type", action.type, "tag")
        append("Schedule", action.schedule, "calendar")
        append("Date", action.date, "calendar.badge.clock")
        append("Time", action.time, "clock")
        append("Duration", action.duration, "timer")
        append("Recurrence", action.recurrence, "repeat")
        append("Timezone", action.timezone, "globe")
        append("Source", action.source, "doc.text.magnifyingglass")
        append("Location", action.location, "mappin.and.ellipse")
        if !action.attendees.isEmpty {
            result.append(WidgetActionCandidateField(
                title: "Attendees",
                value: action.attendees.joined(separator: ", "),
                symbolName: "person.2"
            ))
        }
        if !action.missingFields.isEmpty {
            result.append(WidgetActionCandidateField(
                title: "Needs",
                value: action.missingFields.joined(separator: ", "),
                symbolName: "exclamationmark.triangle"
            ))
        }
        if let confidence = action.confidence {
            result.append(WidgetActionCandidateField(
                title: "Confidence",
                value: "\(Int((confidence * 100).rounded()))%",
                symbolName: "gauge"
            ))
        }
        if result.isEmpty {
            result.append(WidgetActionCandidateField(
                title: "Status",
                value: "Preview only",
                symbolName: "eye"
            ))
        }
        return result
    }
}

private struct WidgetActionCandidateField {
    let title: String
    let value: String
    let symbolName: String
}

private struct WidgetGenericBody: View {
    let note: String

    var body: some View {
        // Render the note as Markdown (bold, lists, etc.) instead of raw text —
        // briefing results and other generic widgets carry **bold**/numbered
        // lists that must not show literal asterisks.
        MarkdownMessageText(text: note)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct WidgetSourceDot: View {
    let source: WidgetNewsSource

    var body: some View {
        Text(source.label.prefix(1).uppercased())
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 14, height: 14)
            .background(dotColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var dotColor: Color {
        if let hex = source.color, let c = widgetColor(fromHex: hex) { return c }
        return Color.actionPrimary
    }
}

// MARK: Sparkline shapes

private struct WidgetSparkline: Shape {
    let points: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        let minV = points.min() ?? 0
        let maxV = points.max() ?? 1
        let range = maxV - minV
        let stepX = rect.width / CGFloat(points.count - 1)
        for (i, v) in points.enumerated() {
            let x = rect.minX + CGFloat(i) * stepX
            let norm = range == 0 ? 0.5 : CGFloat((v - minV) / range)
            let y = rect.maxY - norm * rect.height
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

private struct WidgetSparklineFill: Shape {
    let points: [Double]

    func path(in rect: CGRect) -> Path {
        var path = WidgetSparkline(points: points).path(in: rect)
        guard !path.isEmpty else { return path }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: Widget helpers

private func widgetTrendColor(_ trend: WidgetTrend?) -> Color {
    switch trend {
    case .up: return .proofVerified
    case .down: return .proofMismatch
    default: return .textSecondary
    }
}

private func widgetToneColor(_ tone: WidgetTone?) -> Color {
    switch tone {
    case .good: return .proofVerified
    case .warn: return .proofStale
    case .bad: return .proofMismatch // red — matches the chart card's down-delta
    case .off: return .secondary
    default: return .primary
    }
}

private func widgetNonBlank(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

private func widgetColor(fromHex hex: String) -> Color? {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
    return Color(
        red: Double((value >> 16) & 0xFF) / 255,
        green: Double((value >> 8) & 0xFF) / 255,
        blue: Double(value & 0xFF) / 255
    )
}
