import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject private var chatStore: ChatStore

    var body: some View {
        ChatTranscriptView(chatStore: chatStore, transcriptStore: chatStore.transcriptStore)
    }
}

private struct ChatTranscriptView: View {
    @ObservedObject var chatStore: ChatStore
    @ObservedObject var transcriptStore: ChatTranscriptStore
    @State private var lastAutoScrollNanoseconds: UInt64 = 0
    @State private var autoScrollPauseUntilNanoseconds: UInt64 = 0
    @State private var streamAutoScrollSuppressed = false
    @State private var isAttachmentDropTargeted = false
    @State private var showingEmptyProjectFiles = false
    @State private var showingEmptyCouncilPicker = false

    private static let streamingAutoScrollIntervalNanoseconds: UInt64 = 300_000_000
    private static let dragAutoScrollPauseNanoseconds: UInt64 = 1_500_000_000
    private static let maxDroppedAttachments = 5
    private static let attachmentFileContentTypes: [UTType] = [
        .pdf,
        .plainText,
        .text,
        .commaSeparatedText,
        .json,
        UTType(filenameExtension: "tsv") ?? .text,
        UTType(filenameExtension: "xlsx") ?? .data,
        UTType(filenameExtension: "xls") ?? .data,
        .data
    ]
    private static let attachmentDropContentTypes: [UTType] = [.fileURL] + attachmentFileContentTypes

    var body: some View {
        let transcript = transcriptStore.state
        let messages = transcript.messages
        let isStreaming = transcript.isStreaming
        let displayItems = transcript.displayItems
        let scrollSignature = ChatAutoScrollSignature(
            displayItems: displayItems,
            messages: messages,
            isStreaming: isStreaming
        )

        VStack(spacing: 0) {
            ChatToolbar(transcriptStore: transcriptStore)
                .background(Color.appBackground)

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        if messages.isEmpty {
                            GeometryReader { geo in
                                EmptyChatView(
                                    onOpenProject: { showingEmptyProjectFiles = true },
                                    onOpenCouncil: { showingEmptyCouncilPicker = true }
                                )
                                    .frame(width: geo.size.width, height: geo.size.height)
                            }
                            .frame(maxWidth: .infinity, minHeight: 360)
                            .containerRelativeFrame(.vertical)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 18) {
                                ForEach(displayItems) { item in
                                    switch item {
                                    case let .message(message):
                                        MessageBubble(message: message, chatStore: chatStore)
                                            .id(item.id)
                                    case let .council(batchID: _, messages: messages):
                                        CouncilResponseGroup(messages: messages, chatStore: chatStore)
                                            .id(item.id)
                                    }
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 18)
                        }
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { _ in
                                noteUserScrollInteraction()
                            }
                            .onEnded { _ in
                                noteUserScrollInteraction()
                            }
                    )
                    .scrollDismissesKeyboard(.interactively)
                    .background(Color.appBackground)
                    .task(id: chatStore.selectedConversation?.id) {
                        resetAutoScrollState()
                        guard let targetID = scrollSignature.targetID else { return }
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        await MainActor.run {
                            proxy.scrollTo(targetID, anchor: .bottom)
                        }
                    }
                    .onChange(of: isStreaming) { _, isStreaming in
                        if isStreaming {
                            streamAutoScrollSuppressed = false
                            autoScrollPauseUntilNanoseconds = 0
                        }
                    }
                    .onChange(of: scrollSignature) { _, signature in
                        guard let targetID = signature.targetID else { return }
                        let now = DispatchTime.now().uptimeNanoseconds
                        guard shouldAutoScroll(now: now, isStreaming: signature.isStreaming) else { return }
                        lastAutoScrollNanoseconds = now
                        if signature.isStreaming {
                            proxy.scrollTo(targetID, anchor: .bottom)
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(targetID, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()
                    .opacity(0.55)
                InputBar(transcriptStore: transcriptStore, composerStore: chatStore.composerStore)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.appPanelBackground)
            }
            .contentShape(Rectangle())
            .onDrop(of: Self.attachmentDropContentTypes, isTargeted: $isAttachmentDropTargeted) { providers in
                handleAttachmentDrop(providers)
            }
            .overlay {
                if isAttachmentDropTargeted {
                    AttachmentDropTargetOverlay()
                        .padding(18)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.16), value: isAttachmentDropTargeted)
        }
        .background(Color.appBackground)
        .sheet(item: pendingProjectNoteSaveBinding) { message in
            SaveOutputToProjectSheet(message: message)
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingEmptyProjectFiles) {
            ProjectFilesView()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingEmptyCouncilPicker) {
            ModelPickerView(openingCouncil: true)
                .environmentObject(chatStore)
        }
    }

    private var pendingProjectNoteSaveBinding: Binding<ChatMessage?> {
        Binding(
            get: { chatStore.pendingProjectNoteSaveMessage },
            set: { newValue in
                if newValue == nil {
                    chatStore.clearPendingProjectNoteSave()
                }
            }
        )
    }

    private func handleAttachmentDrop(_ providers: [NSItemProvider]) -> Bool {
        let availableSlots = max(0, Self.maxDroppedAttachments - chatStore.composerStore.pendingAttachments.count)
        guard availableSlots > 0 else {
            chatStore.bannerMessage = "Attach up to five files at once."
            return false
        }

        let supportedProviders = Array(providers
            .filter { Self.canLoadDroppedAttachment(from: $0) }
            .prefix(availableSlots))
        guard !supportedProviders.isEmpty else { return false }

        Task {
            for provider in supportedProviders {
                guard let url = await Self.droppedAttachmentURL(from: provider) else { continue }
                await chatStore.addAttachment(from: url)
            }
        }
        return true
    }

    private static func canLoadDroppedAttachment(from provider: NSItemProvider) -> Bool {
        attachmentDropContentTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
    }

    private static func droppedAttachmentURL(from provider: NSItemProvider) async -> URL? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await droppedFileURL(from: provider)
        }

        guard let contentType = attachmentFileContentTypes.first(where: {
            provider.hasItemConformingToTypeIdentifier($0.identifier)
        }) else {
            return nil
        }
        return await droppedFileRepresentationURL(from: provider, contentType: contentType)
    }

    private static func droppedFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                continuation.resume(returning: fileURL(from: item))
            }
        }
    }

    private static func droppedFileRepresentationURL(from provider: NSItemProvider, contentType: UTType) async -> URL? {
        let suggestedName = provider.suggestedName
        return await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            _ = provider.loadInPlaceFileRepresentation(forTypeIdentifier: contentType.identifier) { url, isInPlace, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                if isInPlace {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: copyTemporaryDroppedFile(url, suggestedName: suggestedName, contentType: contentType))
                }
            }
        }
    }

    private static func fileURL(from item: Any?) -> URL? {
        if let url = item as? URL, url.isFileURL {
            return url
        }
        if let data = item as? Data,
           let url = URL(dataRepresentation: data, relativeTo: nil),
           url.isFileURL {
            return url
        }
        if let string = item as? String {
            return fileURL(from: string)
        }
        if let string = item as? NSString {
            return fileURL(from: string as String)
        }
        return nil
    }

    private static func fileURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.isFileURL {
            return url
        }
        return URL(fileURLWithPath: trimmed)
    }

    private static func copyTemporaryDroppedFile(_ url: URL, suggestedName: String?, contentType: UTType) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DroppedChatAttachments", isDirectory: true)
        let destination = directory.appendingPathComponent(
            "\(UUID().uuidString)-\(droppedFilename(for: url, suggestedName: suggestedName, contentType: contentType))",
            isDirectory: false
        )

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private static func droppedFilename(for url: URL, suggestedName: String?, contentType: UTType) -> String {
        let rawName = suggestedName.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? url.lastPathComponent
        let filename = rawName.isEmpty ? "Attachment" : rawName
        guard URL(fileURLWithPath: filename).pathExtension.isEmpty,
              let preferredExtension = contentType.preferredFilenameExtension else {
            return filename
        }
        return "\(filename).\(preferredExtension)"
    }

    private func noteUserScrollInteraction() {
        let now = DispatchTime.now().uptimeNanoseconds
        let pauseUntil = now + Self.dragAutoScrollPauseNanoseconds
        if pauseUntil > autoScrollPauseUntilNanoseconds + 100_000_000 {
            autoScrollPauseUntilNanoseconds = pauseUntil
        }
        if transcriptStore.isStreaming, !streamAutoScrollSuppressed {
            streamAutoScrollSuppressed = true
        }
    }

    private func resetAutoScrollState() {
        lastAutoScrollNanoseconds = 0
        autoScrollPauseUntilNanoseconds = 0
        streamAutoScrollSuppressed = false
    }

    private func shouldAutoScroll(now: UInt64, isStreaming: Bool) -> Bool {
        guard now >= autoScrollPauseUntilNanoseconds else { return false }
        guard !(isStreaming && streamAutoScrollSuppressed) else { return false }
        let minimumInterval = isStreaming ? Self.streamingAutoScrollIntervalNanoseconds : 0
        return minimumInterval == 0 || now - lastAutoScrollNanoseconds >= minimumInterval
    }
}

private struct AttachmentDropTargetOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.actionPrimary.opacity(0.08))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    Color.actionPrimary.opacity(0.72),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 5])
                )

            VStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.actionPrimary)
                    .frame(width: 46, height: 46)
                    .background(Color.actionPrimary.opacity(0.12), in: Circle())

                VStack(spacing: 3) {
                    Text("Drop files to attach")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Up to five files")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

private struct SaveOutputToProjectSheet: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss

    let message: ChatMessage

    @State private var projectName = ""
    @State private var instructions = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Save output", systemImage: "bookmark.fill")
                            .font(.headline)
                        Text("Create a Project for this chat or save into an existing Project.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Create project")
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(Color.textSecondary)

                        TextField("Project name", text: $projectName)
                            .font(.body)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        TextField("Project instructions", text: $instructions, axis: .vertical)
                            .font(.subheadline)
                            .textFieldStyle(.plain)
                            .lineLimit(3...6)
                            .padding(12)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Button {
                            chatStore.createProjectAndSaveMessageAsNote(
                                message,
                                named: projectName,
                                instructions: instructions
                            )
                            dismiss()
                        } label: {
                            Label("Create Project and Save", systemImage: "folder.badge.plus")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.actionPrimary)
                        .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(14)
                    .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.appBorder, lineWidth: 1)
                    }

                    if !chatStore.visibleProjects.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Existing projects")
                                .font(.caption.weight(.semibold))
                                .textCase(.uppercase)
                                .foregroundStyle(Color.textSecondary)

                            ForEach(chatStore.visibleProjects) { project in
                                Button {
                                    chatStore.saveMessageAsProjectNote(message, toProjectID: project.id)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: project.projectIconName)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(project.tintColor)
                                            .frame(width: 34, height: 34)
                                            .background(project.tintBackgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(project.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            Text(project.notes.count == 1 ? "1 note" : "\(project.notes.count) notes")
                                                .font(.caption)
                                                .foregroundStyle(Color.textSecondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "arrow.down.forward.circle")
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                    .padding(12)
                                    .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.appBorder, lineWidth: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.appBackground)
            .navigationTitle("Save to Project")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        chatStore.clearPendingProjectNoteSave()
                        dismiss()
                    }
                }
            }
        }
        .platformMediumDetent()
        .onAppear {
            if projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                projectName = chatStore.suggestedProjectNameForSavedNote(message)
            }
        }
    }
}

private struct ChatAutoScrollSignature: Equatable {
    let targetID: String?
    let messageCount: Int
    let lastTextLength: Int
    let lastStatus: String?
    let isStreaming: Bool

    init(displayItems: [ChatDisplayItem], messages: [ChatMessage], isStreaming: Bool) {
        let lastMessage = messages.last
        self.targetID = displayItems.last?.id
        self.messageCount = messages.count
        self.lastTextLength = lastMessage?.text.count ?? 0
        self.lastStatus = lastMessage?.status
        self.isStreaming = isStreaming
    }
}

private struct CouncilResponseGroup: View {
    let messages: [ChatMessage]
    let chatStore: ChatStore
    @State private var selectedMessageID: String?
    @State private var showingRoom = false

    private var selectedMessage: ChatMessage? {
        let currentID = selectedMessageID ?? preferredMessage?.id
        return messages.first(where: { $0.id == currentID }) ?? messages.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 28, height: 28)
                    .background(Color.brandSky.opacity(0.34), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text("LLM Council")
                        .font(.caption.weight(.semibold))
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if hasRunningModels {
                    Button {
                        if canStopWaiting {
                            chatStore.stopWaitingForCouncil(batchID: batchID)
                        } else {
                            chatStore.cancelStream()
                        }
                    } label: {
                        Label(canStopWaiting ? "Stop waiting" : "Cancel", systemImage: canStopWaiting ? "forward.end.fill" : "xmark")
                            .font(.caption2.weight(.bold))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(canStopWaiting ? Color.brandBlue : .secondary)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background((canStopWaiting ? Color.brandBlue : Color.secondary).opacity(0.09), in: Capsule())
                    .accessibilityHint(canStopWaiting ? "Synthesize from completed Council answers now" : "Cancel the Council run")
                }

                if messages.contains(where: \.hasUsableCouncilAnswer) {
                    Button { showingRoom = true } label: {
                        Label("Room", systemImage: "person.3.fill")
                            .font(.caption2.weight(.bold))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.brandBlue)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(Color.brandBlue.opacity(0.09), in: Capsule())
                    .accessibilityHint("Open the Council room view")
                }
            }

            if hasRunningModels {
                TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                    progressRows(now: timeline.date)
                }
            } else {
                progressRows(now: Date())
            }

            if let selectedMessage {
                CouncilSelectedMessageView(
                    message: selectedMessage,
                    chatStore: chatStore,
                    preferLightweightPreview: hasRunningModels
                )
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.brandBlue.opacity(0.13), lineWidth: 1)
        }
        .onAppear {
            selectedMessageID = selectedMessageID ?? messages.first?.id
        }
        .onChange(of: messageIDs) { _, _ in
            guard let selectedMessageID,
                  messages.contains(where: { $0.id == selectedMessageID }) else {
                self.selectedMessageID = messages.first?.id
                return
            }
        }
        .sheet(isPresented: $showingRoom) {
            CouncilRoomView(
                model: CouncilRoomModel.from(councilMessages: messages),
                supportsTargetedSend: true,
                synthesizeTitle: synthesizeTitle,
                onSend: { text, target in
                    chatStore.sendCouncilRoomFollowUp(text, batchID: batchID, target: target)
                    showingRoom = false
                },
                onSynthesize: {
                    chatStore.synthesizeCouncilBatch(batchID: batchID)
                    showingRoom = false
                }
            )
        }
    }

    @ViewBuilder
    private func progressRows(now: Date) -> some View {
        VStack(spacing: 6) {
            ForEach(messages) { message in
                CouncilModelProgressRow(
                    message: message,
                    now: now,
                    isSelected: message.id == selectedMessage?.id
                ) {
                    selectedMessageID = message.id
                }
            }
        }
    }

    private var batchID: String? {
        messages.first?.councilBatchID
    }

    private var messageIDs: [String] {
        messages.map(\.id)
    }

    private var preferredMessage: ChatMessage? {
        messages.first(where: \.hasUsableCouncilAnswer) ?? messages.first
    }

    private var statusText: String {
        let ready = messages.filter(\.hasUsableCouncilAnswer).count
        let running = messages.filter(\.isStreaming).count
        let failed = messages.filter { $0.status == "failed" }.count
        if running > 0 {
            return ready > 0 ? "\(ready) ready · \(running) still running" : "\(running) models thinking"
        }
        if failed > 0, ready > 0 {
            return "\(ready) ready · \(failed) failed"
        }
        if failed > 0 {
            return "\(failed) failed"
        }
        return ready == messages.count ? "\(messages.count) answers ready" : "\(ready) usable answers"
    }

    private var hasRunningModels: Bool {
        messages.contains(where: \.isStreaming)
    }

    private var canStopWaiting: Bool {
        hasRunningModels && messages.contains(where: \.hasUsableCouncilAnswer)
    }

    private var synthesizeTitle: String? {
        let usableCount = messages.filter(\.hasUsableCouncilAnswer).count
        guard usableCount > 1 else { return nil }
        return hasRunningModels ? "Synthesize now" : "Synthesize again"
    }
}

private struct CouncilSelectedMessageView: View {
    let message: ChatMessage
    let chatStore: ChatStore
    let preferLightweightPreview: Bool

    var body: some View {
        if message.isStreaming {
            StreamingMessageText(message: message)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if preferLightweightPreview {
            CouncilAnswerPreview(message: message)
        } else {
            MessageBubble(message: message, chatStore: chatStore)
        }
    }
}

private struct CouncilAnswerPreview: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: statusSymbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusTint)
                Text(message.modelDisplayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusTint)
            }

            if previewText.isEmpty {
                Text("Waiting for an answer.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(previewText)
                    .font(.callout)
                    .lineSpacing(2)
                    .lineLimit(12)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var previewText: String {
        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
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

    private var statusText: String {
        if message.status == "failed" {
            return "Failed"
        }
        return message.hasUsableCouncilAnswer ? "Ready" : "Pending"
    }

    private var statusSymbolName: String {
        if message.status == "failed" {
            return "exclamationmark.triangle.fill"
        }
        return message.hasUsableCouncilAnswer ? "checkmark.circle.fill" : "circle"
    }

    private var statusTint: Color {
        if message.status == "failed" {
            return .red
        }
        return message.hasUsableCouncilAnswer ? Color.verifiedGreen : .secondary
    }
}

private struct CouncilModelProgressRow: View {
    let message: ChatMessage
    let now: Date
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                Image(systemName: symbolName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tintColor)
                    .frame(width: 24, height: 24)
                    .background(tintColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(message.modelDisplayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(progressText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.brandBlue)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isSelected ? Color.brandBlue.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(message.modelDisplayName), \(progressText)")
    }

    private var symbolName: String {
        if message.status == "failed" {
            return "exclamationmark.triangle.fill"
        }
        if message.isStreaming, message.firstTokenAt != nil {
            return "waveform"
        }
        if message.isStreaming {
            return "hourglass"
        }
        if message.hasUsableCouncilAnswer {
            return "checkmark.circle.fill"
        }
        return "circle"
    }

    private var tintColor: Color {
        if message.status == "failed" {
            return .red
        }
        if message.isStreaming {
            return Color.brandBlue
        }
        if message.hasUsableCouncilAnswer {
            return Color.verifiedGreen
        }
        return .secondary
    }

    private var progressText: String {
        if message.status == "failed" {
            return "Failed"
        }
        if message.isStreaming {
            if let latency = message.firstTokenLatency {
                return "Writing · first token \(formatSeconds(latency))"
            }
            return "Waiting · \(formatSeconds(now.timeIntervalSince(message.createdAt)))"
        }
        if message.hasUsableCouncilAnswer {
            if let latency = message.firstTokenLatency {
                return "Done · first token \(formatSeconds(latency))"
            }
            return "Done"
        }
        return "No answer"
    }

    private func formatSeconds(_ value: TimeInterval) -> String {
        let clamped = max(0, value)
        if clamped < 10 {
            return String(format: "%.1fs", clamped)
        }
        return "\(Int(clamped.rounded()))s"
    }
}

private struct ChatToolbar: View {
    @EnvironmentObject private var chatStore: ChatStore
    @ObservedObject var transcriptStore: ChatTranscriptStore
    @State private var showingShare = false
    @State private var showingSecurity = false
    @State private var showingSharedLink = false
    @State private var showingRename = false
    @State private var showingProjectFiles = false
    @State private var showingAgentWorkspace = false
    @State private var showingExporter = false
    @State private var showingSignedExportNotice = false
    @State private var exportDocument = ConversationExportDocument()
    @State private var exportContentType: UTType = .plainText
    @State private var exportFilename = "near-private-chat.txt"

    var body: some View {
        compactToolbar
        .buttonStyle(.borderless)
        .toolbar {
            // Spec (chat-view.jsx ThreadTopBar): "..." menu sits in the
            // top-right of the nav bar. All the sheet bindings stay on
            // this view so the menu's actions still resolve correctly.
            ToolbarItem(placement: .topBarTrailing) {
                moreMenuButton
            }
        }
        .sheet(isPresented: $showingShare) {
            if let conversation = chatStore.selectedConversation {
                ShareConversationView(conversation: conversation)
                    .environmentObject(chatStore)
            }
        }
        .sheet(isPresented: $showingSecurity) {
            SecurityView()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingSharedLink) {
            SharedConversationSheet()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingRename) {
            RenameConversationView()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingProjectFiles) {
            ProjectFilesView()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingAgentWorkspace) {
            AgentWorkspaceView()
                .environmentObject(chatStore)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                chatStore.bannerMessage = "Conversation exported."
            case let .failure(error):
                chatStore.bannerMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Signed export identity",
            isPresented: $showingSignedExportNotice,
            titleVisibility: .visible
        ) {
            Button("Export Signed JSON") {
                prepareExport(.signedJSON)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Signed JSON is sealed with a stable on-device Keychain identity. That helps recipients verify tampering, but repeated exports from this device can be linked by the signing key id.")
        }
    }

    private var compactToolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(compactTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)

                    Text(compactStatusText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                compactAttestationButton
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    MetadataPill(
                        title: compactRouteTitle,
                        symbolName: compactRouteSymbolName,
                        isPrimary: true
                    )

                    MetadataPill(
                        title: compactSourceModeTitle,
                        symbolName: chatStore.sourceModeSymbolName,
                        isPrimary: chatStore.effectiveWebSearchEnabled || chatStore.researchModeEnabled
                    )

                    if let selectedProject = chatStore.selectedProject {
                        Button {
                            showingProjectFiles = true
                        } label: {
                            MetadataPill(title: selectedProject.name, symbolName: "folder", isPrimary: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open project \(selectedProject.name)")
                        .accessibilityHint("Shows the selected Project context.")
                    }

                    if let projectContextSummary {
                        MetadataPill(
                            title: projectContextSummary,
                            symbolName: projectContextSummarySymbolName,
                            isPrimary: false
                        )
                    }

                    if shouldShowAgentWorkspaceButton {
                        Button {
                            showingAgentWorkspace = true
                        } label: {
                            MetadataPill(
                                title: compactAgentPillTitle,
                                symbolName: "terminal",
                                isPrimary: chatStore.selectedRouteKind.isIronclawRoute || chatStore.ironclawRemoteWorkstationAvailable
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open agent workspace")
                        .accessibilityHint("Shows agent tools and handoff options.")
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollClipDisabled()
        }
        .padding(14)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var compactTitle: String {
        chatStore.selectedConversationTitle
    }

    private var compactStatusText: String {
        if transcriptStore.messages.isEmpty {
            return "Private by default. Add sources, a Project, or Agent when the task needs them."
        }

        var parts: [String] = []
        if chatStore.isCouncilModeEnabled {
            parts.append("Council answers")
        } else {
            switch chatStore.selectedRouteKind {
            case .nearPrivate:
                parts.append(chatStore.researchModeEnabled ? "Private research" : "Private chat")
            case .nearCloud:
                parts.append("Privacy proxy route")
            case .ironclawMobile:
                parts.append("Phone agent route")
            case .ironclawHosted:
                parts.append("Hosted agent route")
            }
        }

        if let projectName = chatStore.selectedProject?.name.nilIfBlank {
            parts.append(projectName)
        }

        return parts.joined(separator: " · ")
    }

    private var compactRouteTitle: String {
        if chatStore.isCouncilModeEnabled {
            return "Council \(chatStore.activeCouncilModels.count)"
        }
        return chatStore.selectedRouteKind.disclosureTitle
    }

    private var compactRouteSymbolName: String {
        chatStore.isCouncilModeEnabled ? "square.grid.2x2" : chatStore.selectedRouteKind.disclosureSymbolName
    }

    private var compactSourceModeTitle: String {
        if chatStore.researchModeEnabled {
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

    private var projectContextSummary: String? {
        let files = chatStore.activeProjectContextAttachments.count
        let links = chatStore.activeProjectContextLinks.count
        var parts: [String] = []
        if files > 0 {
            parts.append(countLabel(files, singular: "file"))
        }
        if links > 0 {
            parts.append(countLabel(links, singular: "link"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var projectContextSummarySymbolName: String {
        let hasFiles = !chatStore.activeProjectContextAttachments.isEmpty
        let hasLinks = !chatStore.activeProjectContextLinks.isEmpty
        if hasFiles && hasLinks {
            return "rectangle.3.group"
        }
        return hasFiles ? "paperclip" : "link"
    }

    private var compactAgentPillTitle: String {
        switch chatStore.selectedRouteKind {
        case .ironclawMobile:
            return "Phone Agent"
        case .ironclawHosted:
            return "Hosted Agent"
        case .nearPrivate, .nearCloud:
            return "Agent"
        }
    }

    private var compactAttestationButton: some View {
        Button {
            showingSecurity = true
        } label: {
            let status = chatStore.currentAttestationStatus
            let copy = status.userFacingCopy()
            let isCloudTrust = chatStore.selectedRouteUsesNearCloud || (chatStore.isCouncilModeEnabled && chatStore.activeCouncilHasNearCloudRoutes)
            let tint = isCloudTrust ? Color.brandBlue : status.tintColor
            HStack(spacing: 5) {
                Image(systemName: isCloudTrust ? "eye.slash" : status.symbolName)
                    .font(.caption.weight(.bold))
                Text(isCloudTrust ? "Privacy proxy" : compactAttestationLabel(copy.badge))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .frame(height: 34)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(0.16), lineWidth: 1)
            }
        }
        .accessibilityLabel(chatStore.currentAttestationStatus.accessibilityLabel())
        .accessibilityHint(chatStore.currentAttestationStatus.accessibilityHint())
    }

    private func compactAttestationLabel(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "Verified ", with: "")
            .replacingOccurrences(of: " proof", with: "")
    }

    private var reloadButton: some View {
        Button {
            Task {
                if let conversation = chatStore.selectedConversation {
                    await chatStore.loadMessages(for: conversation)
                }
            }
        } label: {
            ToolbarIcon(symbolName: "arrow.clockwise")
        }
        .accessibilityLabel("Reload Messages")
        .disabled(chatStore.selectedConversation == nil)
    }

    private var shareButton: some View {
        Button {
            showingShare = true
        } label: {
            ToolbarIcon(symbolName: "square.and.arrow.up", isPrimary: true)
        }
        .accessibilityLabel("Share")
        .disabled(chatStore.selectedConversation == nil)
    }

    private var moreMenuButton: some View {
        Menu {
            moreMenuContent
        } label: {
            ToolbarIcon(symbolName: "ellipsis")
        }
        .accessibilityLabel("More")
    }

    @ViewBuilder
    private var moreMenuContent: some View {
        Section("Navigate") {
            if shouldShowAgentWorkspaceButton {
                Button {
                    chatStore.selectModel(chatStore.ironclawRemoteWorkstationAvailable ? ModelOption.ironclawModelID : ModelOption.ironclawMobileModelID)
                    chatStore.draft = chatStore.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Agent mission: "
                        : "Agent mission: \(chatStore.draft)"
                } label: {
                    Label("Run as agent", systemImage: "terminal")
                }
            }
            Button {
                showingSecurity = true
            } label: {
                Label("Proof", systemImage: "checkmark.shield")
            }
            Button {
                showingProjectFiles = true
            } label: {
                Label("Project Context", systemImage: "folder.badge.gearshape")
            }
            .disabled(chatStore.selectedProject == nil)
            Button {
                showingSharedLink = true
            } label: {
                Label("Open Shared Link", systemImage: "link.badge.plus")
            }
        }

        Section("Edit") {
            Button {
                showingRename = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .disabled(chatStore.selectedConversation == nil)
            Button {
                chatStore.cloneSelectedConversation()
            } label: {
                Label("Branch from here", systemImage: "doc.on.doc")
            }
            .disabled(chatStore.selectedConversation == nil)
        }

        Section("Export") {
            Button {
                showingShare = true
            } label: {
                Label("Share Link", systemImage: "link")
            }
            .disabled(chatStore.selectedConversation == nil)
            Button {
                chatStore.copyCurrentTranscript()
            } label: {
                Label("Copy Transcript", systemImage: "doc.text")
            }
            .disabled(transcriptStore.messages.isEmpty)
            Button {
                prepareExport(.text)
            } label: {
                Label("Export TXT", systemImage: "doc.plaintext")
            }
            .disabled(transcriptStore.messages.isEmpty)
            Button {
                prepareExport(.json)
            } label: {
                Label("Export JSON", systemImage: "curlybraces")
            }
            .disabled(transcriptStore.messages.isEmpty)
            Button {
                showingSignedExportNotice = true
            } label: {
                Label("Export Signed JSON", systemImage: "checkmark.shield")
            }
            .disabled(transcriptStore.messages.isEmpty)
            Button {
                prepareExport(.pdf)
            } label: {
                Label("Export PDF", systemImage: "doc.richtext")
            }
            .disabled(transcriptStore.messages.isEmpty)
        }

        Section("Organize") {
            Button {
                chatStore.createProjectFromSelectedConversation()
            } label: {
                Label("New Project from Chat", systemImage: "folder.badge.plus")
            }
            .disabled(chatStore.selectedConversation == nil)
            Menu {
                Button {
                    chatStore.assignSelectedConversation(to: nil)
                } label: {
                    Label("No Project", systemImage: "tray")
                }
                ForEach(chatStore.projects) { project in
                    Button {
                        chatStore.assignSelectedConversation(to: project.id)
                    } label: {
                        Label(project.name, systemImage: "folder")
                    }
                }
            } label: {
                Label("Move to Project", systemImage: "folder")
            }
            .disabled(chatStore.selectedConversation == nil)
            Button {
                chatStore.togglePinSelectedConversation()
            } label: {
                Label(
                    chatStore.selectedConversation?.isPinned == true ? "Unpin" : "Pin",
                    systemImage: chatStore.selectedConversation?.isPinned == true ? "pin.slash" : "pin"
                )
            }
            .disabled(chatStore.selectedConversation == nil)
            Button {
                chatStore.archiveSelectedConversation()
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .disabled(chatStore.selectedConversation == nil)
        }

        Section("Destructive") {
            Button(role: .destructive) {
                chatStore.deleteSelectedConversation()
            } label: {
                Label("Delete Permanently", systemImage: "trash")
            }
            .disabled(chatStore.selectedConversation == nil)
        }
    }

    private func countLabel(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }

    private func prepareExport(_ format: ConversationExportFormat) {
        do {
            exportDocument = try ConversationExportBuilder.document(
                for: chatStore.selectedConversation,
                messages: transcriptStore.messages,
                format: format,
                signedContext: signedTranscriptContext
            )
            exportContentType = format.contentType
            exportFilename = ConversationExportBuilder.filename(
                for: chatStore.selectedConversation,
                format: format
            )
            showingExporter = true
        } catch {
            chatStore.bannerMessage = error.localizedDescription
        }
    }

    private var signedTranscriptContext: SignedTranscriptExportContext {
        chatStore.signedTranscriptExportContext
    }

    private var shouldShowAgentWorkspaceButton: Bool {
        chatStore.selectedProviderDisplayName == "IronClaw" || chatStore.ironclawRemoteWorkstationAvailable
    }
}

struct MetadataPill: View {
    let title: String
    let symbolName: String
    let isPrimary: Bool

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isPrimary ? Color.brandBlue : .secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isPrimary ? Color.brandBlue.opacity(0.08) : Color.appSecondaryBackground, in: Capsule())
    }
}

struct ToolbarIcon: View {
    let symbolName: String
    var isPrimary = false

    var body: some View {
        Image(systemName: symbolName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isPrimary ? Color.brandBlue : .secondary)
            .frame(width: 34, height: 34)
            .background(isPrimary ? Color.brandBlue.opacity(0.08) : Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
