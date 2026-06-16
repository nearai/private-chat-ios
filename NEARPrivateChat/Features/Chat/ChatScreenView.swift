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
    @State private var showingFindBar = false
    @State private var findQuery = ""
    @State private var findScrollTarget: String? = nil
    // Geometry-driven tail visibility: the bottom sentinel's maxY in the scroll
    // coordinate space vs the viewport height. LazyVStack onAppear/onDisappear
    // tracks lazy realization, not visibility, so it cannot drive this reliably.
    @State private var bottomSentinelMaxY: CGFloat = .greatestFiniteMagnitude
    @State private var transcriptViewportHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// True when the transcript tail is on screen (or within a small threshold).
    /// Optimistically true until geometry reports, so a freshly opened
    /// conversation does not flash the jump button.
    private var isNearBottom: Bool {
        guard transcriptViewportHeight > 0,
              bottomSentinelMaxY != .greatestFiniteMagnitude else { return true }
        return bottomSentinelMaxY <= transcriptViewportHeight + Self.nearBottomThreshold
    }

    private var trimmedFindQuery: String {
        findQuery.trimmingCharacters(in: .whitespaces)
    }

    private func findMatches(_ text: String) -> Bool {
        let q = trimmedFindQuery
        guard !q.isEmpty else { return false }
        return text.localizedCaseInsensitiveContains(q)
    }

    private func displayItemMatchesFind(_ item: ChatDisplayItem) -> Bool {
        switch item {
        case let .message(message):
            return findMatches(message.text)
        case let .council(_, messages):
            return messages.contains { findMatches($0.text) }
        }
    }

    // Match against display items, not raw messages: council answers collapse
    // into a single `.council` item keyed by batchID, so the scroll anchor for a
    // council match is the batchID — using message.id would scroll to nothing.
    private func findMatchIDs(in displayItems: [ChatDisplayItem]) -> [String] {
        guard !trimmedFindQuery.isEmpty else { return [] }
        return displayItems.filter { displayItemMatchesFind($0) }.map { $0.id }
    }

    // Active match gets a stronger tint than the other matches (Safari-style).
    private func findHighlightColor(itemID: String, matches: Bool) -> Color {
        guard showingFindBar, matches else { return .clear }
        return itemID == findScrollTarget ? Color.orange.opacity(0.20) : Color.orange.opacity(0.08)
    }

    private static let streamingAutoScrollIntervalNanoseconds: UInt64 = 300_000_000
    private static let dragAutoScrollPauseNanoseconds: UInt64 = 1_500_000_000
    private static let bottomAnchorID = "chat-bottom-anchor"
    private static let transcriptScrollSpace = "chatTranscriptScroll"
    // Tail counts as "on screen" when within this much of the viewport bottom.
    private static let nearBottomThreshold: CGFloat = 120
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
            ChatToolbar(
                transcriptStore: transcriptStore,
                showingFindBar: $showingFindBar
            )
            .background(Color.appBackground)
            if showingFindBar {
                let matchIDs = findMatchIDs(in: displayItems)
                let curIdx = matchIDs.firstIndex(of: findScrollTarget ?? "") ?? 0
                ChatFindBar(
                    query: $findQuery,
                    matchCount: matchIDs.count,
                    matchIndex: matchIDs.isEmpty ? 0 : max(0, min(curIdx, matchIDs.count - 1)),
                    onPrev: {
                        let ids = findMatchIDs(in: transcriptStore.state.displayItems)
                        guard !ids.isEmpty else { return }
                        let cur = ids.firstIndex(of: findScrollTarget ?? "") ?? 0
                        findScrollTarget = ids[(cur - 1 + ids.count) % ids.count]
                    },
                    onNext: {
                        let ids = findMatchIDs(in: transcriptStore.state.displayItems)
                        guard !ids.isEmpty else { return }
                        let cur = ids.firstIndex(of: findScrollTarget ?? "") ?? 0
                        findScrollTarget = ids[(cur + 1) % ids.count]
                    },
                    onDismiss: {
                        showingFindBar = false
                        findQuery = ""
                        findScrollTarget = nil
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

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
                                            .background(
                                                findHighlightColor(itemID: item.id, matches: findMatches(message.text)),
                                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            )
                                    case let .council(batchID: _, messages: messages):
                                        CouncilResponseGroup(messages: messages, chatStore: chatStore)
                                            .id(item.id)
                                            .background(
                                                findHighlightColor(
                                                    itemID: item.id,
                                                    matches: messages.contains(where: { findMatches($0.text) })
                                                ),
                                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            )
                                    }
                                }

                                // Bottom anchor: the scrollTo target for the
                                // jump-to-latest action. Tail-visibility is NOT
                                // measured here — a lazy child de-realizes when
                                // scrolled away; see the LazyVStack background.
                                Color.clear
                                    .frame(height: 1)
                                    .id(Self.bottomAnchorID)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 18)
                            // Measure the content bottom from the LazyVStack
                            // CONTAINER (always realized, unlike its tail rows),
                            // so the jump button's visibility survives scroll-up.
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: ChatBottomSentinelKey.self,
                                        value: geo.frame(in: .named(Self.transcriptScrollSpace)).maxY
                                    )
                                }
                            )
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
                    .coordinateSpace(name: Self.transcriptScrollSpace)
                    .overlay {
                        GeometryReader { viewport in
                            Color.clear.preference(
                                key: ChatViewportHeightKey.self,
                                value: viewport.size.height
                            )
                        }
                        .allowsHitTesting(false)
                    }
                    .onPreferenceChange(ChatBottomSentinelKey.self) { bottomSentinelMaxY = $0 }
                    .onPreferenceChange(ChatViewportHeightKey.self) { transcriptViewportHeight = $0 }
                    .overlay(alignment: .bottomTrailing) {
                        // Scoped animation container: animates only on the
                        // isNearBottom/findBar flip, never sweeping transcript
                        // content changes into the spring.
                        Group {
                            // Standard scroll-to-bottom semantics: shown whenever
                            // the literal tail is off screen. Works for council
                            // tails too — the jump targets the always-present
                            // bottom anchor regardless of the auto-scroll anchor.
                            // While a stream is auto-following (user has NOT
                            // scrolled up), the tail is pinned for them, so the
                            // button stays hidden — this also avoids flicker as
                            // content grows past the threshold between auto-scroll
                            // ticks. It returns the moment they scroll up.
                            if !isNearBottom && !messages.isEmpty && !showingFindBar
                                && !(isStreaming && !streamAutoScrollSuppressed) {
                                JumpToLatestButton(isStreaming: isStreaming) {
                                    AppHaptics.selection()
                                    let jump = { proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom) }
                                    if reduceMotion {
                                        jump()
                                    } else {
                                        withAnimation(.easeOut(duration: 0.28)) { jump() }
                                    }
                                    // Returning to the tail re-arms stream following:
                                    // clear the scroll-up suppression so new tokens
                                    // auto-scroll again. Only zero the pause window
                                    // while streaming — on the idle path the user's
                                    // own drag-pause should stand.
                                    streamAutoScrollSuppressed = false
                                    if isStreaming {
                                        autoScrollPauseUntilNanoseconds = 0
                                    }
                                }
                                .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                            }
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 14)
                        .animation(
                            reduceMotion ? .easeInOut(duration: 0.14) : .spring(response: 0.32, dampingFraction: 0.82),
                            value: isNearBottom
                        )
                        .animation(.easeInOut(duration: 0.16), value: showingFindBar)
                    }
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
                    .onChange(of: findScrollTarget) { _, targetID in
                        guard let id = targetID else { return }
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                    .onChange(of: findQuery) { _, _ in
                        let ids = findMatchIDs(in: transcriptStore.state.displayItems)
                        if let first = ids.first {
                            findScrollTarget = first
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(first, anchor: .center)
                            }
                        } else {
                            findScrollTarget = nil
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
        .animation(.easeInOut(duration: 0.18), value: showingFindBar)
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
        // A freshly opened conversation scrolls to its tail, so assume bottom
        // (isNearBottom is optimistically true on the sentinel marker) until the
        // first geometry callback reports the real position.
        bottomSentinelMaxY = .greatestFiniteMagnitude
    }

    private func shouldAutoScroll(now: UInt64, isStreaming: Bool) -> Bool {
        guard now >= autoScrollPauseUntilNanoseconds else { return false }
        guard !(isStreaming && streamAutoScrollSuppressed) else { return false }
        let minimumInterval = isStreaming ? Self.streamingAutoScrollIntervalNanoseconds : 0
        return minimumInterval == 0 || now - lastAutoScrollNanoseconds >= minimumInterval
    }
}

/// Floating control that scrolls the transcript back to the latest message.
/// Shown only when the tail is off screen; carries a live indicator when a
/// response is streaming below the fold so the user knows there is new content.
private struct JumpToLatestButton: View {
    let isStreaming: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "arrow.down")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.brandAccent, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 2)

                if isStreaming {
                    Circle()
                        .fill(Color.proofVerifiedText)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.appBackground, lineWidth: 2))
                        .offset(x: 3, y: -3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scroll to latest")
        .accessibilityValue(isStreaming ? "Response in progress below" : "")
        .accessibilityIdentifier("chat.jumpToLatest")
    }
}

private struct ChatBottomSentinelKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

private struct ChatViewportHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
