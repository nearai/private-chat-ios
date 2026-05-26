import SwiftUI

struct MessageBubble: View {
    @EnvironmentObject private var chatStore: ChatStore
    let message: ChatMessage
    @State private var showingArtifact = false
    @State private var showingSecurity = false
    @State private var showingSources = false
    @State private var editingUserMessage: ChatMessage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .user {
                Spacer(minLength: 36)
            } else {
                AssistantAvatar()
                    .padding(.top, 1)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
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

                Group {
                    if message.text.isEmpty && message.isStreaming {
                        HStack(spacing: 8) {
                            TypingDots()
                            Text(message.streamingStatusText)
                                .foregroundStyle(.secondary)
                        }
                    } else if message.role == .assistant {
                        MarkdownMessageText(text: message.text.isEmpty ? " " : message.text, sources: message.sources)
                    } else {
                        Text(message.text.isEmpty ? " " : message.text)
                            .textSelection(.enabled)
                    }
                }
                .font(.body)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .padding(.horizontal, message.role == .user ? 14 : 0)
                .padding(.vertical, message.role == .user ? 11 : 0)
                .background(message.role == .user ? Color.brandBlue : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                            Label("Copy Signed Snippet", systemImage: "checkmark.shield")
                        }

                        Button {
                            chatStore.regenerateResponse(for: message)
                        } label: {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                        }

                        Button {
                            chatStore.saveMessageAsProjectNote(message)
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
                        onRegenerate: { chatStore.regenerateResponse(for: message) },
                        onSave: { chatStore.saveMessageAsProjectNote(message) },
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

                if message.role == .assistant && !message.sources.isEmpty {
                    SearchContextStrip(query: message.searchQuery, sources: message.sources)
                }

                if let answerProofCapsule {
                    Button {
                        showingSecurity = true
                    } label: {
                        ProofCapsule(viewModel: answerProofCapsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open verification details")
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
        .sheet(item: $editingUserMessage) { userMessage in
            EditUserMessageView(message: userMessage)
                .environmentObject(chatStore)
        }
    }

    private var statusBadge: String? {
        switch message.status {
        case "reasoning":
            return "Reasoning"
        case "searching":
            return "Web search"
        case "approval":
            return "Approval"
        case "failed":
            return "Failed"
        default:
            return nil
        }
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

    private var answerProofCapsule: ProofCapsuleViewModel? {
        guard message.role == .assistant,
              !message.isStreaming,
              !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let modelID = message.model else {
            return nil
        }

        switch ChatStore.routeKind(forModelID: modelID) {
        case .nearPrivate:
            let status = AttestationStatus(snapshot: chatStore.attestationSnapshot, selectedModelID: modelID)
            switch status.effectiveState() {
            case .valid, .stale, .mismatch:
                return ProofCapsuleViewModel(status: status, modelID: modelID)
            case .unknown, .unavailable:
                return ProofCapsuleViewModel(
                    state: .private_,
                    title: "Private route",
                    detail: "This answer used the private route. Open Verification when you need a fresh model proof for the turn.",
                    badge: "Private",
                    symbolName: "lock.shield"
                )
            }
        case .nearCloud:
            return ProofCapsuleViewModel(
                state: .proxied,
                title: "Privacy proxy",
                detail: "This answer used the privacy proxy route. It does not carry NEAR Private verification for this turn.",
                badge: "Privacy proxy",
                symbolName: "eye.slash"
            )
        case .ironclawMobile, .ironclawHosted:
            return ProofCapsuleViewModel(
                state: .unverified,
                title: "Agent route",
                detail: "This answer used agent tools. Verification only applies when the underlying model route supplies proof.",
                badge: "Agent",
                symbolName: "terminal"
            )
        }
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
                    Text("This starts a new branch from the original turn.")
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
            return "Waiting for approval"
        }
        if message.status == "searching" {
            return "Gathering context"
        }
        return "Agent running"
    }

    private func detailText(isStale: Bool) -> String? {
        if message.status == "failed" {
            return "The bridge stopped before a final answer. Retry after checking the hosted endpoint."
        }
        if isStale {
            return message.isStreaming
                ? "The hosted run may have stalled. Stop it, then retry from the phone."
                : "The hosted run may have stalled. Retry starts a fresh phone-controlled run."
        }
        if message.pendingApproval != nil || message.status == "approval" {
            return "Approve or deny the requested tool action to continue."
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
            return "lock.shield.fill"
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
    let onRegenerate: () -> Void
    let onSave: () -> Void
    let onOpen: () -> Void
    let onSources: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                actionButton(symbolName: "doc.on.doc", label: "Copy", action: onCopy)
                actionButton(symbolName: "arrow.clockwise", label: "Regenerate", action: onRegenerate)
                if canOpen {
                    actionButton(symbolName: "rectangle.expand.vertical", label: "Open Output", action: onOpen)
                }
                actionButton(symbolName: "checkmark.shield", label: "Copy Signed Snippet", action: onCopySigned)
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
                    .accessibilityLabel("Copy Signed Snippet")

                    Button {
                        chatStore.saveMessageAsProjectNote(message)
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
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
