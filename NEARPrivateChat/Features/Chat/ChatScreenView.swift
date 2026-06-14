import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject private var chatStore: ChatStore

    var body: some View {
        ChatTranscriptView(chatStore: chatStore, transcriptStore: chatStore.transcriptStore)
    }
}

private struct ChatTranscriptView: View {
    @EnvironmentObject private var shareStore: ShareStore
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject var chatStore: ChatStore
    @ObservedObject var transcriptStore: ChatTranscriptStore
    @State private var lastAutoScrollNanoseconds: UInt64 = 0
    @State private var autoScrollPauseUntilNanoseconds: UInt64 = 0
    @State private var streamAutoScrollSuppressed = false
    @State private var isAttachmentDropTargeted = false
    @State private var showingEmptyProjectFiles = false
    @State private var showingEmptyCouncilPicker = false
    @State private var showingAccountSettings = false
    @State private var accountSettingsDeepLink: AccountSettingsDeepLink?

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
                        if let conversation = chatStore.selectedConversation {
                            await shareStore.loadShares(for: conversation, showErrors: false)
                        } else {
                            shareStore.clearConversationShareInfo()
                        }
                        guard let targetID = scrollSignature.targetID else { return }
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        await MainActor.run {
                            proxy.scrollTo(targetID, anchor: scrollSignature.targetAnchor.unitPoint)
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
                            proxy.scrollTo(targetID, anchor: signature.targetAnchor.unitPoint)
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(targetID, anchor: signature.targetAnchor.unitPoint)
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
        .sheet(isPresented: $showingEmptyCouncilPicker) {
            ModelPickerView(
                openingCouncil: true,
                onOpenNearCloudKeys: {
                    accountSettingsDeepLink = .nearCloudKeys
                    showingAccountSettings = true
                }
            )
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
