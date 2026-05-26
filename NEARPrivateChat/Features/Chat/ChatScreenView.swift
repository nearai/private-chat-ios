import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @State private var lastAutoScrollNanoseconds: UInt64 = 0

    var body: some View {
        VStack(spacing: 0) {
            ChatToolbar()
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(Color.appPanelBackground)
            Divider()
                .opacity(0.55)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if chatStore.messages.isEmpty {
                            EmptyChatView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 54)
                                .padding(.bottom, 22)
                        } else {
                            ForEach(MessageTimelineStore.displayItems(from: chatStore.messages)) { item in
                                switch item {
                                case let .message(message):
                                    MessageBubble(message: message)
                                        .id(item.id)
                                case let .council(batchID: _, messages: messages):
                                    CouncilResponseGroup(messages: messages)
                                        .id(item.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                }
                .background(Color.appBackground)
                .task(id: chatStore.selectedConversation?.id) {
                    guard let last = chatStore.messages.last else { return }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    await MainActor.run {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: chatStore.messages) { _, messages in
                    guard let last = messages.last else { return }
                    let now = DispatchTime.now().uptimeNanoseconds
                    let minimumInterval: UInt64 = chatStore.isStreaming ? 250_000_000 : 0
                    guard minimumInterval == 0 || now - lastAutoScrollNanoseconds >= minimumInterval else {
                        return
                    }
                    lastAutoScrollNanoseconds = now
                    if chatStore.isStreaming {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()
                .opacity(0.55)
            InputBar()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.appPanelBackground)
        }
        .background(Color.appBackground)
    }
}

private struct CouncilResponseGroup: View {
    @EnvironmentObject private var chatStore: ChatStore
    let messages: [ChatMessage]
    @State private var selectedMessageID: String?

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
            }

            TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                VStack(spacing: 6) {
                    ForEach(messages) { message in
                        CouncilModelProgressRow(
                            message: message,
                            now: timeline.date,
                            isSelected: message.id == selectedMessage?.id
                        ) {
                            selectedMessageID = message.id
                        }
                    }
                }
            }

            if let selectedMessage {
                MessageBubble(message: selectedMessage)
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
        .onChange(of: messages) { _, updatedMessages in
            guard let selectedMessageID,
                  updatedMessages.contains(where: { $0.id == selectedMessageID }) else {
                self.selectedMessageID = updatedMessages.first?.id
                return
            }
        }
    }

    private var batchID: String? {
        messages.first?.councilBatchID
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
    @State private var showingShare = false
    @State private var showingModels = false
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
        .sheet(isPresented: $showingShare) {
            if let conversation = chatStore.selectedConversation {
                ShareConversationView(conversation: conversation)
                    .environmentObject(chatStore)
            }
        }
        .sheet(isPresented: $showingModels) {
            ModelPickerView()
                .environmentObject(chatStore)
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

    private var regularToolbar: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(chatStore.selectedConversationTitle)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                metadataRow
            }

            Spacer()

            toolbarButtons
        }
    }

    private var compactToolbar: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Button {
                    if chatStore.selectedConversation != nil {
                        showingRename = true
                    }
                } label: {
                    Text(chatStore.selectedConversationTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(chatStore.selectedConversation == nil)
                .accessibilityLabel("Chat title")
                .accessibilityHint(chatStore.selectedConversation == nil ? "" : "Renames this chat.")

                if shouldShowCompactStatusText {
                    Text(compactStatusText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }

            Spacer(minLength: 0)

            modelSelectorButton(maxWidth: 142)

            if chatStore.selectedConversation != nil {
                shareButton
            }

            moreMenuButton
        }
    }

    private var shouldShowCompactStatusText: Bool {
        !chatStore.messages.isEmpty
    }

    private var compactStatusText: String {
        var parts: [String] = []
        if chatStore.selectedRouteUsesNearCloud {
            parts.append("Privacy proxy")
        } else if chatStore.selectedProviderDisplayName == "IronClaw" {
            parts.append("Agent run")
        } else if chatStore.researchModeEnabled {
            parts.append("Private research")
        } else {
            parts.append("Private chat")
        }
        if let project = chatStore.selectedProject {
            parts.append(project.name)
        }
        return parts.joined(separator: " › ")
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

    private var metadataRow: some View {
        HStack(spacing: 8) {
            if chatStore.isCouncilModeEnabled {
                MetadataPill(
                    title: chatStore.activeCouncilRouteSummary,
                    symbolName: "square.grid.2x2",
                    isPrimary: true
                )
            } else {
                MetadataPill(
                    title: chatStore.selectedRouteUsesNearCloud ? "NEAR Cloud" : "Private",
                    symbolName: chatStore.selectedRouteUsesNearCloud ? "cloud" : "lock.shield",
                    isPrimary: true
                )
            }
            if chatStore.selectedRouteUsesNearCloud || (chatStore.isCouncilModeEnabled && chatStore.activeCouncilHasNearCloudRoutes) {
                MetadataPill(title: "Privacy proxy", symbolName: "eye.slash", isPrimary: true)
                MetadataPill(
                    title: chatStore.effectiveAppWebGroundingEnabled ? "App web on" : "App web off",
                    symbolName: chatStore.effectiveAppWebGroundingEnabled ? "globe" : "globe.slash",
                    isPrimary: chatStore.effectiveAppWebGroundingEnabled
                )
            } else {
                MetadataPill(title: chatStore.sourceModeDetail, symbolName: chatStore.sourceModeSymbolName, isPrimary: chatStore.effectiveWebSearchEnabled)
            }
            if chatStore.selectedProviderDisplayName == "NEAR Private" || (chatStore.isCouncilModeEnabled && !chatStore.activeCouncilHasExternalRoutes) {
                MetadataPill(
                    title: chatStore.currentAttestationStatus.userFacingCopy().badge,
                    symbolName: chatStore.currentAttestationStatus.symbolName,
                    isPrimary: false
                )
            }
            if chatStore.selectedProviderDisplayName != "NEAR Private", !chatStore.selectedRouteUsesNearCloud, !chatStore.isCouncilModeEnabled {
                MetadataPill(title: chatStore.selectedProviderDisplayName, symbolName: "point.3.connected.trianglepath.dotted", isPrimary: true)
            }
            if chatStore.selectedModelOption?.isIronclawMobileRuntime == true {
                MetadataPill(title: "Phone tools", symbolName: "iphone", isPrimary: false)
                if chatStore.ironclawRemoteWorkstationAvailable {
                    MetadataPill(title: "Shell handoff", symbolName: "terminal", isPrimary: true)
                }
                MetadataPill(
                    title: chatStore.ironclawRemoteWorkstationAvailable ? "Workstation on" : "Workstation off",
                    symbolName: "terminal",
                    isPrimary: chatStore.ironclawRemoteWorkstationAvailable
                )
            } else if chatStore.selectedModelOption?.isIronclawHostedModel == true {
                MetadataPill(title: "Hosted workstation", symbolName: "terminal", isPrimary: true)
                MetadataPill(title: ironclawToolPillTitle, symbolName: "chevron.left.forwardslash.chevron.right", isPrimary: chatStore.ironclawRemoteWorkstationAvailable)
                if chatStore.ironclawTokenConfigured {
                    MetadataPill(title: "Token saved", symbolName: "key", isPrimary: false)
                }
            }
            if let project = chatStore.selectedProject {
                MetadataPill(title: project.name, symbolName: "folder", isPrimary: false)
                if !chatStore.activeProjectContextAttachments.isEmpty {
                    MetadataPill(title: countLabel(chatStore.activeProjectContextAttachments.count, singular: "file"), symbolName: "paperclip", isPrimary: false)
                }
                if !chatStore.activeProjectContextLinks.isEmpty {
                    MetadataPill(title: countLabel(chatStore.activeProjectContextLinks.count, singular: "link"), symbolName: "link", isPrimary: false)
                }
            }
        }
    }

    private var ironclawToolPillTitle: String {
        guard chatStore.ironclawRemoteWorkstationAvailable else { return "Tools off" }
        return chatStore.ironclawToolNames.isEmpty ? "Shell + git" : "\(chatStore.ironclawToolNames.count) tools"
    }

    private var toolbarButtons: some View {
        HStack(spacing: 8) {
            modelSelectorButton(maxWidth: 150)

            if chatStore.selectedProject != nil {
                projectContextButton
            }

            if shouldShowAgentWorkspaceButton {
                agentWorkspaceButton
            }

            securityButton

            if chatStore.selectedConversation != nil {
                reloadButton

                shareButton
            }

            moreMenuButton
        }
    }

    private func modelSelectorButton(maxWidth: CGFloat) -> some View {
        Button {
            AppHaptics.selection()
            showingModels = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: chatStore.isCouncilModeEnabled ? "square.grid.2x2" : (chatStore.selectedRouteUsesNearCloud ? "cloud" : "cpu"))
                    .font(.caption.weight(.bold))
                Text(chatStore.activeModelDisplayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .opacity(0.68)
            }
            .foregroundStyle(Color.brandBlue)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .frame(maxWidth: maxWidth)
            .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.brandBlue.opacity(0.10), lineWidth: 1)
            }
        }
        .accessibilityLabel(modelSelectorAccessibilityLabel)
        .accessibilityHint("Opens model selection for the next message.")
    }

    private var modelSelectorAccessibilityLabel: String {
        if chatStore.isCouncilModeEnabled {
            return "Select model, LLM Council active, \(chatStore.activeCouncilRouteSummary)"
        }
        return "Select model, currently \(chatStore.activeModelDisplayName)"
    }

    private var projectContextButton: some View {
        Button {
            showingProjectFiles = true
        } label: {
            ToolbarIcon(symbolName: "folder.badge.plus")
        }
        .accessibilityLabel("Project Context")
        .disabled(chatStore.selectedProject == nil)
    }

    private var agentWorkspaceButton: some View {
        Button {
            showingAgentWorkspace = true
        } label: {
            ToolbarIcon(symbolName: "terminal", isPrimary: chatStore.selectedProviderDisplayName == "IronClaw")
        }
        .accessibilityLabel("Agent")
    }

    private var securityButton: some View {
        Button {
            showingSecurity = true
        } label: {
            ToolbarIcon(
                symbolName: chatStore.currentAttestationStatus.symbolName,
                isPrimary: chatStore.currentAttestationStatus.effectiveState() == .valid
            )
        }
        .accessibilityLabel(chatStore.currentAttestationStatus.accessibilityLabel())
        .accessibilityHint(chatStore.currentAttestationStatus.accessibilityHint())
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
                Label("Verification", systemImage: "checkmark.shield")
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
            .disabled(chatStore.messages.isEmpty)
            Button {
                prepareExport(.text)
            } label: {
                Label("Export TXT", systemImage: "doc.plaintext")
            }
            .disabled(chatStore.messages.isEmpty)
            Button {
                prepareExport(.json)
            } label: {
                Label("Export JSON", systemImage: "curlybraces")
            }
            .disabled(chatStore.messages.isEmpty)
            Button {
                showingSignedExportNotice = true
            } label: {
                Label("Export Signed JSON", systemImage: "checkmark.shield")
            }
            .disabled(chatStore.messages.isEmpty)
            Button {
                prepareExport(.pdf)
            } label: {
                Label("Export PDF", systemImage: "doc.richtext")
            }
            .disabled(chatStore.messages.isEmpty)
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
                messages: chatStore.messages,
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
