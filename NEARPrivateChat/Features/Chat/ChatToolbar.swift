import SwiftUI
import UniformTypeIdentifiers

struct ChatToolbar: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var modelCatalogStore: ModelCatalogStore
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var securityStore: SecurityStore
    @EnvironmentObject private var agentStore: AgentStore
    @EnvironmentObject private var conversationStore: ConversationStore
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
            if let conversation = conversationStore.selectedConversation {
                ShareConversationView(conversation: conversation, transcriptStore: transcriptStore)
            }
        }
        .sheet(isPresented: $showingSecurity) {
            SecurityView()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingSharedLink) {
            SharedConversationSheet(
                onOpenForWriting: { snapshot in
                    chatStore.openSharedPreviewForWriting(snapshot)
                },
                onCopyAndContinue: { snapshot in
                    chatStore.cloneConversation(snapshot.conversation)
                }
            )
        }
        .sheet(isPresented: $showingRename) {
            RenameConversationView()
        }
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
                        symbolName: compactSourceModeSymbolName,
                        isPrimary: sourceRoutingSemantics.modelNativeWebToolEnabledByDefault || modelCatalogStore.researchModeEnabled
                    )

                    if let selectedProject = projectStore.selectedProject {
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
                                isPrimary: modelCatalogStore.selectedRouteKind.isIronclawRoute || agentStore.ironclawRemoteWorkstationAvailable
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
        conversationStore.selectedConversationTitle
    }

    private var compactStatusText: String {
        if transcriptStore.messages.isEmpty {
            return "Private by default. Add sources, a Project, or Agent when the task needs them."
        }

        var parts: [String] = []
        if modelCatalogStore.isCouncilModeEnabled {
            parts.append("Council answers")
        } else {
            switch modelCatalogStore.selectedRouteKind {
            case .nearPrivate:
                parts.append(modelCatalogStore.researchModeEnabled ? "Private research" : "Private chat")
            case .nearCloud:
                parts.append("Privacy proxy route")
            case .ironclawMobile:
                parts.append("Phone agent route")
            case .ironclawHosted:
                parts.append("Hosted IronClaw route")
            }
        }

        if let projectName = projectStore.selectedProject?.name.nilIfBlank {
            parts.append(projectName)
        }

        return parts.joined(separator: " · ")
    }

    private var compactRouteTitle: String {
        if modelCatalogStore.isCouncilModeEnabled {
            return "Council \(modelCatalogStore.activeCouncilModels.count)"
        }
        return modelCatalogStore.selectedRouteKind.disclosureTitle
    }

    private var compactRouteSymbolName: String {
        modelCatalogStore.isCouncilModeEnabled ? "square.grid.2x2" : modelCatalogStore.selectedRouteKind.disclosureSymbolName
    }

    private var compactSourceModeTitle: String {
        if modelCatalogStore.researchModeEnabled {
            return "Research"
        }
        switch modelCatalogStore.sourceMode {
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

    private var compactSourceModeSymbolName: String {
        sourceRoutingSemantics.isResearch ? "doc.text.magnifyingglass" : modelCatalogStore.sourceMode.symbolName
    }

    private var sourceRoutingSemantics: ChatSourceRoutingSemantics {
        modelCatalogStore.sourceRoutingSemantics(for: modelCatalogStore.selectedRouteKind)
    }

    private var projectContextSummary: String? {
        let files = sourceRoutingSemantics.attachesProjectFileSourcePack ? projectStore.selectedProjectAttachments.count : 0
        let links = sourceRoutingSemantics.attachesSavedLinkSourcePack ? projectStore.selectedProjectLinks.count : 0
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
        let hasFiles = sourceRoutingSemantics.attachesProjectFileSourcePack && !projectStore.selectedProjectAttachments.isEmpty
        let hasLinks = sourceRoutingSemantics.attachesSavedLinkSourcePack && !projectStore.selectedProjectLinks.isEmpty
        if hasFiles && hasLinks {
            return "rectangle.3.group"
        }
        return hasFiles ? "paperclip" : "link"
    }

    private var compactAgentPillTitle: String {
        switch modelCatalogStore.selectedRouteKind {
        case .ironclawMobile:
            return "Phone Agent"
        case .ironclawHosted:
            return "Hosted IronClaw"
        case .nearPrivate, .nearCloud:
            return "Agent"
        }
    }

    private var compactAttestationButton: some View {
        Button {
            showingSecurity = true
        } label: {
            let status = currentAttestationStatus
            let copy = status.userFacingCopy()
            let isCloudTrust = modelCatalogStore.selectedRouteUsesNearCloud || (modelCatalogStore.isCouncilModeEnabled && modelCatalogStore.activeCouncilHasNearCloudRoutes)
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
        .accessibilityLabel(currentAttestationStatus.accessibilityLabel())
        .accessibilityHint(currentAttestationStatus.accessibilityHint())
    }

    private var currentAttestationStatus: AttestationStatus {
        securityStore.currentAttestationStatus(
            selectedModelID: modelCatalogStore.selectedModel,
            selectedRouteKind: modelCatalogStore.selectedRouteKind,
            isCouncilModeEnabled: modelCatalogStore.isCouncilModeEnabled,
            activeCouncilHasExternalRoutes: modelCatalogStore.activeCouncilHasExternalRoutes
        )
    }

    private func compactAttestationLabel(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "Verified ", with: "")
            .replacingOccurrences(of: " proof", with: "")
    }

    private var reloadButton: some View {
        Button {
            Task {
                if let conversation = conversationStore.selectedConversation {
                    await chatStore.loadMessages(for: conversation)
                }
            }
        } label: {
            ToolbarIcon(symbolName: "arrow.clockwise")
        }
        .accessibilityLabel("Reload Messages")
        .disabled(conversationStore.selectedConversation == nil)
    }

    private var shareButton: some View {
        Button {
            showingShare = true
        } label: {
            ToolbarIcon(symbolName: "square.and.arrow.up", isPrimary: true)
        }
        .accessibilityLabel("Share")
        .disabled(conversationStore.selectedConversation == nil)
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
        ChatToolbarMenuContent(
            transcriptStore: transcriptStore,
            showingShare: $showingShare,
            showingSecurity: $showingSecurity,
            showingSharedLink: $showingSharedLink,
            showingRename: $showingRename,
            showingProjectFiles: $showingProjectFiles,
            showingSignedExportNotice: $showingSignedExportNotice,
            prepareExport: prepareExport,
            copyCurrentTranscript: copyCurrentTranscript
        )
    }

    private func countLabel(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }

    private func prepareExport(_ format: ConversationExportFormat) {
        do {
            exportDocument = try ConversationExportBuilder.document(
                for: conversationStore.selectedConversation,
                messages: transcriptStore.messages,
                format: format,
                signedContext: signedTranscriptContext
            )
            exportContentType = format.contentType
            exportFilename = ConversationExportBuilder.filename(
                for: conversationStore.selectedConversation,
                format: format
            )
            showingExporter = true
        } catch {
            chatStore.bannerMessage = error.localizedDescription
        }
    }

    private func copyCurrentTranscript() {
        switch ConversationTranscriptClipboard.copyTranscript(
            conversation: conversationStore.selectedConversation,
            messages: transcriptStore.messages
        ) {
        case .copied:
            chatStore.bannerMessage = "Transcript copied."
        case .emptyTranscript:
            chatStore.bannerMessage = "No transcript to copy."
        }
    }

    private var signedTranscriptContext: SignedTranscriptExportContext {
        securityStore.signedTranscriptExportContext(
            selectedProviderDisplayName: modelCatalogStore.selectedProviderDisplayName,
            selectedRouteUsesNearCloud: modelCatalogStore.selectedRouteUsesNearCloud,
            selectedModelIsIronclawMobileRuntime: modelCatalogStore.selectedModelOption?.isIronclawMobileRuntime == true,
            sourceRoutingSemantics: sourceRoutingSemantics,
            projectID: projectStore.selectedProjectID
        )
    }

    private var shouldShowAgentWorkspaceButton: Bool {
        modelCatalogStore.selectedProviderDisplayName == "IronClaw" || agentStore.ironclawRemoteWorkstationAvailable
    }
}
