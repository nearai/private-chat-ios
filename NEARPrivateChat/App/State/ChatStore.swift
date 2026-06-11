import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class ChatStore: ObservableObject {
    private(set) var conversations: [ConversationSummary] {
        get { conversationStore.conversations }
        set { conversationStore.replaceConversations(newValue, shouldCache: !isResettingAccountScopedState) }
    }
    private(set) var models: [ModelOption] {
        get { modelCatalogStore.models }
        set { modelCatalogStore.replaceModels(newValue) }
    }
    private(set) var nearCloudModels: [ModelOption] {
        get { modelCatalogStore.nearCloudModels }
        set { modelCatalogStore.replaceNearCloudModels(newValue) }
    }
    var attestationSnapshot: AttestationSnapshot? { securityStore.attestationSnapshot }
    var attestationFetchErrorMessage: String? { securityStore.attestationFetchErrorMessage }
    var ironclawTokenConfigured: Bool {
        get { agentStore.ironclawTokenConfigured }
        set { agentStore.ironclawTokenConfigured = newValue }
    }
    var ironclawStatusText: String {
        get { agentStore.ironclawStatusText }
        set { agentStore.ironclawStatusText = newValue }
    }
    var ironclawLastVerifiedAt: Date? {
        get { agentStore.ironclawLastVerifiedAt }
        set { agentStore.ironclawLastVerifiedAt = newValue }
    }
    var ironclawToolNames: [String] {
        get { agentStore.ironclawToolNames }
        set { agentStore.ironclawToolNames = newValue }
    }
    var isTestingIntegration: Bool {
        get { agentStore.isTestingIntegration }
        set { agentStore.isTestingIntegration = newValue }
    }
    var nearCloudKeyConfigured: Bool {
        get { accountStore.nearCloudKeyConfigured }
        set { accountStore.nearCloudKeyConfigured = newValue }
    }
    var billingSnapshot: BillingSnapshot? {
        get { accountStore.billingSnapshot }
        set { accountStore.billingSnapshot = newValue }
    }
    var isLoadingBilling: Bool {
        get { accountStore.isLoadingBilling }
        set { accountStore.isLoadingBilling = newValue }
    }
    var isTestingNearCloudKey: Bool {
        get { accountStore.isTestingNearCloudKey }
        set { accountStore.isTestingNearCloudKey = newValue }
    }
    var isConnectingNearCloudAccount: Bool {
        get { accountStore.isConnectingNearCloudAccount }
        set { accountStore.isConnectingNearCloudAccount = newValue }
    }
    var diagnosticChecks: [AppDiagnosticCheck] {
        get { accountStore.diagnosticChecks }
        set { accountStore.diagnosticChecks = newValue }
    }
    var isRunningDiagnostics: Bool {
        get { accountStore.isRunningDiagnostics }
        set { accountStore.isRunningDiagnostics = newValue }
    }
    var isTestingIronclawWorkstation: Bool {
        get { agentStore.isTestingIronclawWorkstation }
        set { agentStore.isTestingIronclawWorkstation = newValue }
    }
    @Published var pendingExternalDeepLink: AppDeepLinkAction?
    @Published var pendingProjectNoteSaveMessage: ChatMessage?
    var pendingHostedHandoffPreflight: HostedIronclawHandoffPreflight? {
        get { agentStore.pendingHostedHandoffPreflight }
        set { agentStore.pendingHostedHandoffPreflight = newValue }
    }
    var selectedConversation: ConversationSummary? {
        get { conversationStore.selectedConversation }
        set { conversationStore.selectedConversation = newValue }
    }
    var selectedProjectID: String? {
        get { projectStore.selectedProjectID }
        set { projectStore.selectProjectID(newValue, persist: !isResettingAccountScopedState) }
    }
    var selectedModel: String {
        get { modelCatalogStore.selectedModel }
        set { modelCatalogStore.selectedModel = newValue }
    }
    private(set) var councilModelIDs: [String] {
        get { modelCatalogStore.councilModelIDs }
        set { modelCatalogStore.councilModelIDs = newValue }
    }
    var webSearchEnabled: Bool {
        get { modelCatalogStore.webSearchEnabled }
        set { modelCatalogStore.webSearchEnabled = newValue }
    }
    var notificationPreferenceEnabled: Bool {
        get { accountStore.notificationPreferenceEnabled }
        set { accountStore.notificationPreferenceEnabled = newValue }
    }
    var appearancePreference: AppAppearancePreference {
        get { accountStore.appearancePreference }
        set { accountStore.appearancePreference = newValue }
    }
    var sourceMode: ChatSourceMode {
        get { modelCatalogStore.sourceMode }
        set { modelCatalogStore.sourceMode = newValue }
    }
    var researchModeEnabled: Bool {
        get { modelCatalogStore.researchModeEnabled }
        set { modelCatalogStore.researchModeEnabled = newValue }
    }
    var systemPrompt: String {
        get { accountStore.systemPrompt }
        set { accountStore.systemPrompt = newValue }
    }
    var soulMarkdown: String {
        get { accountStore.soulMarkdown }
        set {
            accountStore.soulMarkdown = newValue
            soulPromptProfile = SoulPromptComposer.Profile.parse(newValue)
        }
    }
    var largeTextAsFileEnabled: Bool {
        get { accountStore.largeTextAsFileEnabled }
        set { accountStore.largeTextAsFileEnabled = newValue }
    }
    var advancedModelParams: AdvancedModelParams {
        get { accountStore.advancedModelParams }
        set { accountStore.advancedModelParams = newValue }
    }
    var ironclawSettings: IronclawSettings {
        get { agentStore.ironclawSettings }
        set { agentStore.ironclawSettings = newValue }
    }
    @Published private(set) var isLoading = false
    var isLoadingAttestation: Bool { securityStore.isLoadingAttestation }
    private(set) var pinnedModelIDs: [String] {
        get { modelCatalogStore.pinnedModelIDs }
        set { modelCatalogStore.pinnedModelIDs = newValue }
    }
    @Published var bannerMessage: String?

    let conversationStore: ConversationStore
    private let conversationActionCoordinator: ConversationActionCoordinator
    let messageTimelineStore: MessageTimelineStore
    let transcriptStore: ChatTranscriptStore
    let attachmentStagingStore: AttachmentStagingStore
    let composerStore: ChatComposerStore
    let chatSessionCoordinator: ChatSessionCoordinator
    let modelCatalogStore: ModelCatalogStore
    let fileStore: FileStore
    let projectStore: ProjectStore
    let agentStore: AgentStore
    let accountStore: AccountStore
    let securityStore: SecurityStore

    private(set) var projects: [ChatProject] {
        get { projectStore.projects }
        set { projectStore.replaceProjects(newValue, persist: !isResettingAccountScopedState) }
    }

    var remoteFiles: [RemoteFileInfo] {
        fileStore.remoteFiles
    }

    var remoteFilePreview: RemoteFilePreview? {
        fileStore.remoteFilePreview
    }

    var isLoadingRemoteFiles: Bool {
        fileStore.isLoadingRemoteFiles
    }

    var isLoadingRemoteFilePreview: Bool {
        fileStore.isLoadingRemoteFilePreview
    }

    var messages: [ChatMessage] {
        get { transcriptStore.messages }
        set { transcriptStore.messages = newValue }
    }

    var isStreaming: Bool {
        get { transcriptStore.isStreaming }
        set { transcriptStore.isStreaming = newValue }
    }

    var pendingAttachments: [ChatAttachment] {
        get { composerStore.pendingAttachments }
        set {
            composerStore.pendingAttachments = newValue
            persistCurrentDraftIfNeeded()
        }
    }

    var draft: String {
        get { composerStore.draft }
        set {
            let previous = composerStore.draft
            composerStore.draft = newValue
            handleDraftChange(from: previous, to: newValue)
            persistCurrentDraftIfNeeded()
        }
    }

    private(set) var isUploadingAttachment: Bool {
        get { composerStore.isUploadingAttachment }
        set { composerStore.isUploadingAttachment = newValue }
    }

    var routeReadinessIssue: RouteReadinessIssue? {
        get { composerStore.routeReadinessIssue }
        set { composerStore.routeReadinessIssue = newValue }
    }

    private let api: PrivateChatAPI
    /// Per-route circuit breaker consulted by every send pipeline. Shared with
    /// the composer UI through AppEnvironment's environmentObject injection.
    let routeHealth: RouteHealthMonitor
    /// Records the real HTTP status + server message of recent route requests
    /// for the in-app Connection Diagnostics screen.
    let diagnostics: ConnectionDiagnostics
    /// True while a manual or post-login private-session probe is in flight, so
    /// the diagnostics screen can show progress without a separate store.
    @Published private(set) var isProbingSession = false
    private var messageRepository: MessageRepository
    private let messageLoadCoordinator: ChatMessageLoadCoordinator
    let fileService: FileService
    private let ironclawAPI = IronclawAPI()
    /// Best-effort Live Activity for in-progress council briefings and compound
    /// multi-lookup runs. Purely a side-effect surface: every call no-ops when
    /// Live Activities are unavailable and never affects chat logic or results.
    private let agentActivity = AgentActivityController()
    /// Wired by the app to create a scheduled briefing from a "create a tracker…"
    /// prompt (the BriefingStore lives outside ChatStore).
    var onCreateTracker: ((Briefing) -> Void)?
    /// Read handle to the user's trackers, for "what are you tracking?". Wired in
    /// AppEnvironment; nil-safe so previews/tests without a BriefingStore degrade
    /// to an empty list.
    var trackersProvider: (() -> [Briefing])?
    /// On-device personal memory; injected into the model's system prompt so
    /// answers are personalized. Account-scoped, never leaves the device.
    let memoryStore = MemoryStore()
    /// On-device transparency log of what the assistant did (briefing runs,
    /// trackers created). Account-scoped, never leaves the device.
    let activityLog = AgentActivityLog()
    private var soulPromptProfile = SoulPromptComposer.Profile.empty
    /// User control over passive memory (auto-learning durable facts from chat).
    /// A single user-level preference, persisted in UserDefaults; default on.
    var passiveMemoryEnabled: Bool {
        get { settingsPersistence.loadPassiveMemoryEnabled() }
        set { settingsPersistence.savePassiveMemoryEnabled(newValue) }
    }
    /// Privacy mode: when on, attached PDFs are kept entirely on-device (never
    /// uploaded) and only their relevant passages are inlined at send. Default off.
    var keepDocumentsOnDevice: Bool {
        get { settingsPersistence.loadKeepDocumentsOnDevice() }
        set { settingsPersistence.saveKeepDocumentsOnDevice(newValue) }
    }
    private let webGroundingService = WebGroundingService()
    private let ironclawMobileRuntime: IronclawMobileRuntime
    private lazy var sendCoordinator = ChatSendCoordinator(host: self)
    var pendingLargePasteTexts: [String: String] {
        get { attachmentStagingStore.pendingLargePasteTexts }
        set { attachmentStagingStore.replacePendingLargePasteTexts(newValue) }
    }
    var pendingDocumentTexts: [String: String] {
        get { attachmentStagingStore.pendingDocumentTexts }
        set { attachmentStagingStore.replacePendingDocumentTexts(newValue) }
    }
    var pendingSharedFileURLs: [String: URL] {
        get { attachmentStagingStore.pendingSharedFileURLs }
        set { attachmentStagingStore.replacePendingSharedFileURLs(newValue) }
    }
    var pendingNearAccountTrackerSchedule: BriefingSchedule?
    var currentUserMessageMetadata: MessageMetadata?
    private var storageAccountID = "signed-out"
    private let draftScopeStore = ChatDraftScopeStore()
    private var bootstrapInFlightAccountID: String?
    private var lastBootstrappedAccountID: String?
    private var accountBackgroundRefreshTask: Task<Void, Never>?
    private var storeCancellables: Set<AnyCancellable> = []

    nonisolated static let defaultModelID = ModelCatalogStore.defaultModelID
    private static let maxCouncilModels = ModelCatalogStore.maxCouncilModels
    private static let maxConcurrentCouncilStreams = CouncilStreamService.defaultConcurrentStreamLimit
    private static let councilLegNoTokenTimeoutSeconds: TimeInterval = 120
    private static let maxPinnedModels = ModelCatalogStore.maxPinnedModels
    nonisolated private static let maxFileUploadBytes = APIClient.maxUploadBytes
    nonisolated static let maxAttachmentUploadBytes = maxFileUploadBytes
    private static let maxPromptAttachments = 5
    private static let maxProjectAttachments = 12
    private static let streamDeltaFlushNanoseconds: UInt64 = MessageStreamService.textDeltaFlushNanoseconds
    private static let largePasteThresholdBytes = 8 * 1024
    private static let largePasteThresholdCharacters = 5_000
    private static let staleRunningMessageInterval: TimeInterval = 120
    private static let frontierModelMigrationKey = "frontierModelMigrationV1"
    private static let frontierModelUpgradeKey = "frontierModelUpgradeV2"
    private static let glmDefaultMigrationKey = "glmDefaultMigrationV1"
    private static let openWeightDefaultMigrationKey = "openWeightDefaultMigrationV1"
    private let ironclawOpenWeightPreferredModelIDs = [
        ModelOption.nearPrivateDefaultModelID,
        "Qwen/Qwen3.5-122B-A10B",
        "Qwen/Qwen3.6-35B-A3B-FP8",
        "Qwen/Qwen3-30B-A3B-Instruct-2507",
        "Qwen/Qwen3-VL-30B-A3B-Instruct",
        "moonshotai/Kimi-K2-Thinking",
        "moonshotai/Kimi-K2-Instruct",
        "MoonshotAI/Kimi-K2-Instruct",
        "deepseek-ai/DeepSeek-V3.2",
        "deepseek-ai/DeepSeek-V3.1",
        "deepseek-ai/DeepSeek-R1",
        "DeepSeek/DeepSeek-V3.2",
        "DeepSeek/DeepSeek-V3.1"
    ]
    var streamTask: Task<Void, Never>?
    var currentAssistantMessageID: String?
    var currentCouncilAssistantMessageIDs: [String] = []
    #if DEBUG
    private var didStartLiveCouncilDemo = false
    #endif
    var councilStopRequestedBatchID: String?
    private var isNormalizingDraft = false
    private var isResettingAccountScopedState = false
    private var attachmentUploadNotice: String?
    private var deniedOpenWeightModelIDs = Set<String>()

    private typealias CouncilStreamResult = CouncilStreamService.StreamResult
    private typealias CouncilRunOutcome = CouncilStreamService.RunOutcome

    typealias RouteReadinessIssue = ChatRouteReadinessIssue

    var visibleConversations: [ConversationSummary] {
        projectStore.selectedProject == nil ? conversationStore.visibleConversations : projectStore.visibleConversations
    }

    var allVisibleConversations: [ConversationSummary] {
        conversationStore.allVisibleConversations
    }

    var archivedConversations: [ConversationSummary] {
        conversationStore.archivedConversations
    }

    var visibleProjects: [ChatProject] {
        projectStore.visibleProjects
    }

    var archivedProjects: [ChatProject] {
        projectStore.archivedProjects
    }

    var composerState: ComposerState {
        ComposerState(
            draft: draft,
            pendingAttachments: pendingAttachments,
            isStreaming: isStreaming,
            routeReadinessTitle: routeReadinessIssue?.title,
            routeReadinessMessage: routeReadinessIssue?.message
        )
    }

    var selectedProject: ChatProject? {
        projectStore.selectedProject
    }

    var selectedProjectAttachments: [ChatAttachment] {
        selectedProject?.attachments ?? []
    }

    var selectedProjectInstructions: String {
        selectedProject?.instructions ?? ""
    }

    var selectedProjectMemorySummary: String {
        selectedProject?.memorySummary ?? ""
    }

    var selectedProjectNotes: [ProjectNote] {
        selectedProject?.notes ?? []
    }

    var projectContextRoutePreview: ProjectContextRoutePreview? {
        guard let project = selectedProject else { return nil }
        let semantics = sourceRoutingSemantics
        let publicLinkCount = project.links.filter { link in
            URL(string: link.urlString).map(URLSecurity.isPublicHTTPSURL) == true
        }.count
        let routeTitle = isCouncilModeEnabled ? activeCouncilRouteSummary : selectedRouteKind.disclosureTitle
        return ProjectService.projectContextRoutePreview(
            fileCount: project.attachments.count,
            linkCount: publicLinkCount,
            noteCount: project.notes.count,
            localOnlyNoteCount: project.notes.filter(\.isLocalOnly).count,
            hasInstructions: !project.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasMemory: !project.memorySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            semantics: semantics,
            routeTitle: routeTitle,
            allowsLocalOnlyNotes: projectContextAllowsLocalOnlyNotes
        )
    }

    private var projectContextAllowsLocalOnlyNotes: Bool {
        if isCouncilModeEnabled {
            return !activeCouncilHasExternalRoutes
        }
        return selectedRouteKind == .nearPrivate || selectedRouteKind == .ironclawMobile
    }

    func isMessageSavedToSelectedProject(_ message: ChatMessage) -> Bool {
        guard message.role == .assistant else {
            return false
        }
        return projectStore.isOutputSavedToSelectedProject(text: message.text, sourceMessageID: message.id)
    }

    var selectedProjectLinks: [ProjectLink] {
        selectedProject?.links ?? []
    }

    var sourceRoutingSemantics: ChatSourceRoutingSemantics {
        routingSemantics(for: selectedRouteKind)
    }

    var activeProjectContextAttachments: [ChatAttachment] {
        guard sourceRoutingSemantics.attachesProjectFileSourcePack else { return [] }
        return selectedProjectAttachments
    }

    var activeProjectContextLinks: [ProjectLink] {
        sourceRoutingSemantics.attachesSavedLinkSourcePack ? selectedProjectLinks : []
    }

    var effectiveWebSearchEnabled: Bool {
        sourceRoutingSemantics.modelNativeWebToolEnabledByDefault
    }

    var effectiveAppWebGroundingEnabled: Bool {
        sourceRoutingSemantics.appWebGroundingPolicy.isEnabledByDefault
    }

    var sourceModeDetail: String {
        let semantics = sourceRoutingSemantics
        switch semantics.focus {
        case .auto:
            return semantics.modelNativeWebToolEnabledByDefault || semantics.appWebGroundingPolicy.isEnabledByDefault
                ? "Auto · sources when useful"
                : "Auto · project files"
        case .web:
            if semantics.modelNativeWebToolPolicy != .never {
                return "Web"
            }
            return semantics.appWebGroundingPolicy == .never ? "Web · off" : "Web · app search"
        case .links:
            return "Links"
        case .files:
            return "Files"
        case .project:
            if semantics.modelNativeWebToolPolicy != .never {
                return "Project · live sources"
            }
            return semantics.appWebGroundingPolicy == .never ? "Project" : "Project · app sources"
        case .research:
            if semantics.modelNativeWebToolPolicy != .never {
                return "Research · live sources"
            }
            return semantics.appWebGroundingPolicy == .never ? "Research" : "Research · app sources"
        }
    }

    var sourceModeSymbolName: String {
        sourceRoutingSemantics.isResearch ? "doc.text.magnifyingglass" : sourceMode.symbolName
    }

    var selectedConversationTitle: String {
        conversationStore.selectedConversationTitle
    }

    var selectedModelOption: ModelOption? {
        modelCatalogStore.selectedModelOption
    }

    var selectedModelDisplayName: String {
        modelCatalogStore.selectedModelDisplayName
    }

    var activeModelDisplayName: String {
        modelCatalogStore.activeModelDisplayName
    }

    // MARK: - Preferred default model (user override of shipped default)

    /// The user's chosen default model for new chats. `nil` means use the
    /// shipped fallback (`defaultModelID`). Persisted in account-scoped
    /// UserDefaults so multiple accounts on one device can each pick.
    var preferredDefaultModelID: String? {
        get {
            modelCatalogStore.preferredDefaultModelID
        }
        set {
            modelCatalogStore.preferredDefaultModelID = newValue
        }
    }

    /// Resolves the active default model id for new chats, preferring the
    /// user's override when present. No validation against pickerModels —
    /// the catalog may not be loaded yet at boot. Downstream selection
    /// guards handle invalid ids.
    var effectiveDefaultModelID: String {
        if let preferred = preferredDefaultModelID, !preferred.isEmpty {
            return preferred
        }
        return modelCatalogStore.effectiveDefaultModelID
    }

    /// Models eligible to be the user's default — the public picker list,
    /// minus IronClaw runtimes (those route to the agent, not chat) and
    /// the synthesis pseudo-model.
    var preferredDefaultModelCandidates: [ModelOption] {
        modelCatalogStore.preferredDefaultModelCandidates
    }

    var activeCouncilModels: [ModelOption] {
        modelCatalogStore.activeCouncilModels
    }

    var maxCouncilModelCount: Int {
        modelCatalogStore.maxCouncilModelCount
    }

    var councilModelNames: [String] {
        modelCatalogStore.councilModelNames
    }

    var isCouncilModeEnabled: Bool {
        modelCatalogStore.isCouncilModeEnabled
    }

    var activeCouncilHasPrivateRoutes: Bool {
        modelCatalogStore.activeCouncilHasPrivateRoutes
    }

    var activeCouncilHasNearCloudRoutes: Bool {
        modelCatalogStore.activeCouncilHasNearCloudRoutes
    }

    var activeCouncilHasExternalRoutes: Bool {
        modelCatalogStore.activeCouncilHasExternalRoutes
    }

    var activeCouncilRouteSummary: String {
        modelCatalogStore.activeCouncilRouteSummary
    }

    var defaultCouncilModels: [ModelOption] {
        modelCatalogStore.defaultCouncilModels
    }

    var councilCandidateModels: [ModelOption] {
        modelCatalogStore.councilCandidateModels
    }

    var setupRouteDefaults: SetupRouteDefaults {
        SetupRouteDefaults(
            privateModelID: usablePrivateSetupModelID(from: selectedModel) ?? preferredAvailableModel() ?? Self.defaultModelID,
            councilModelIDs: isCouncilModeEnabled ? normalizedCouncilModelIDs(councilModelIDs) : defaultCouncilModelIDs(),
            ironclawMobileModelID: agentModels.contains { $0.id == ModelOption.ironclawMobileModelID }
                ? ModelOption.ironclawMobileModelID
                : nil
        ).normalized
    }

    var councilPresets: [CouncilPresetOption] { modelCatalogStore.councilPresets }

    var featuredPickerModels: [ModelOption] {
        modelCatalogStore.featuredPickerModels
    }

    var pinnedPickerModels: [ModelOption] {
        modelCatalogStore.pinnedPickerModels
    }

    var selectedProviderDisplayName: String {
        modelCatalogStore.selectedProviderDisplayName
    }

    var selectedRouteUsesNearCloud: Bool {
        modelCatalogStore.selectedRouteUsesNearCloud
    }

    var signedTranscriptExportContext: SignedTranscriptExportContext {
        return securityStore.signedTranscriptExportContext(
            selectedProviderDisplayName: selectedProviderDisplayName,
            selectedRouteUsesNearCloud: selectedRouteUsesNearCloud,
            selectedModelIsIronclawMobileRuntime: selectedModelOption?.isIronclawMobileRuntime == true,
            sourceRoutingSemantics: sourceRoutingSemantics,
            projectID: selectedProjectID
        )
    }

    var selectedRouteKind: ChatRouteKind {
        modelCatalogStore.selectedRouteKind
    }

    var currentAttestationStatus: AttestationStatus {
        securityStore.currentAttestationStatus(
            selectedModelID: selectedModel,
            selectedRouteKind: selectedRouteKind,
            isCouncilModeEnabled: isCouncilModeEnabled,
            activeCouncilHasExternalRoutes: activeCouncilHasExternalRoutes
        )
    }

    func assistantTrustMetadata(
        for modelID: String?,
        webSearchUsed: Bool? = nil,
        capturedAt: Date = Date()
    ) -> MessageTrustMetadata {
        let trimmedModelID = modelID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let routeKind = trimmedModelID.map(Self.routeKind(forModelID:)) ?? selectedRouteKind
        let semantics = routingSemantics(for: routeKind)
        let defaultWebSearch = semantics.modelNativeWebToolEnabledByDefault ||
            semantics.appWebGroundingPolicy.isEnabledByDefault
        return securityStore.assistantTrustMetadata(
            for: trimmedModelID,
            routeKind: routeKind,
            sourceMode: sourceMode,
            webSearchUsed: webSearchUsed,
            defaultWebSearchEnabled: defaultWebSearch,
            researchModeEnabled: researchModeEnabled,
            projectContextIncluded: selectedProjectID != nil,
            capturedAt: capturedAt
        )
    }

    private func refreshTrustMetadata(for messageID: String, modelID: String? = nil, webSearchUsed: Bool? = nil) {
        updateMessage(messageID) { message in
            guard message.role == .assistant else { return }
            message.trustMetadata = assistantTrustMetadata(
                for: modelID ?? message.model,
                webSearchUsed: webSearchUsed ?? (!message.sources.isEmpty ? true : nil),
                capturedAt: message.createdAt
            )
        }
    }

    func routingSemantics(for route: ChatRouteKind) -> ChatSourceRoutingSemantics {
        modelCatalogStore.sourceRoutingSemantics(for: route)
    }

    nonisolated static func routeKind(forModelID modelID: String) -> ChatRouteKind {
        RoutePlanner.routeKind(forModelID: modelID)
    }

    nonisolated static func routeReadinessIssue(
        selectedModelID: String,
        requestedCouncilModelIDs: [String],
        isCouncilRequested: Bool,
        nearCloudKeyConfigured: Bool,
        hostedIronclawEndpointUsable: Bool,
        hostedIronclawEndpointMessage: String? = nil
    ) -> RouteReadinessIssue? {
        RoutePlanner.routeReadinessIssue(
            selectedModelID: selectedModelID,
            requestedCouncilModelIDs: requestedCouncilModelIDs,
            isCouncilRequested: isCouncilRequested,
            nearCloudKeyConfigured: nearCloudKeyConfigured,
            hostedIronclawEndpointUsable: hostedIronclawEndpointUsable,
            hostedIronclawEndpointMessage: hostedIronclawEndpointMessage
        )
    }

    nonisolated static func sourceRoutingSemantics(
        sourceMode: ChatSourceMode,
        researchModeEnabled: Bool,
        webSearchEnabled: Bool,
        route: ChatRouteKind
    ) -> ChatSourceRoutingSemantics {
        RoutePlanner.sourceRoutingSemantics(
            sourceMode: sourceMode,
            researchModeEnabled: researchModeEnabled,
            webSearchEnabled: webSearchEnabled,
            route: route
        )
    }

    var ironclawRemoteWorkstationAvailable: Bool {
        ironclawSettings.isEnabled && ironclawSettings.hasUsableHostedEndpoint
    }

    var selectedRouteNotice: String? {
        if let routeReadinessIssue {
            return routeReadinessIssue.message
        }
        if isCouncilModeEnabled {
            return activeCouncilHasNearCloudRoutes
                ? "Council includes NEAR AI Cloud models. Cloud legs use privacy proxy routing; all-private Council lineups can fetch proof reports."
                : "Council is using NEAR Private models. Open Proof when you need a signed private-route report."
        }
        if selectedModelOption?.isIronclawMobileRuntime == true {
            return nil
        }
        if selectedModelOption?.isIronclawHostedModel == true {
            return nil
        }
        if selectedModelOption?.isNearCloudModel == true {
            return "\(selectedModelDisplayName) runs through NEAR AI Cloud with privacy proxy routing. The app can attach web results, project notes, saved links, and extracted context when the prompt needs them."
        }
        return nil
    }

    var emptyStateSubtitle: String {
        if selectedModelOption?.isIronclawMobileRuntime == true {
            return ironclawRemoteWorkstationAvailable
                ? "Use IronClaw Mobile for projects, files, research, and Hosted IronClaw handoff for git, code, shell, and software tasks."
                : "Use IronClaw Mobile for projects, files, research, source links, memory, and NEAR Private inference."
        }
        if selectedModelOption?.isIronclawHostedModel == true {
            return "Run remote git, code, research, and shell-capable Agent work through Hosted IronClaw."
        }
        if isCouncilModeEnabled {
            return activeCouncilHasNearCloudRoutes
                ? "Ask a Council of NEAR Private and NEAR AI Cloud models to compare answers and synthesize the strongest response."
                : "Ask a Council of NEAR Private models to compare answers and synthesize the strongest response."
        }
        if selectedModelOption?.isNearCloudModel == true {
            return "Use \(selectedModelDisplayName) through NEAR AI Cloud with app-supplied web, project notes, saved links, and extracted context when useful."
        }
        if researchModeEnabled && !selectedRouteUsesNearCloud {
            return "Ask with \(selectedModelDisplayName), web search, files, and project context."
        }
        switch sourceMode {
        case .auto:
            return effectiveWebSearchEnabled
                ? "Ask with \(selectedModelDisplayName), web search, files, and project context."
                : "Ask with \(selectedModelDisplayName), files, and project context."
        case .web:
            return "Ask with \(selectedModelDisplayName) and live web search."
        case .links:
            return "Ask with \(selectedModelDisplayName), saved links, and prompt files."
        case .files:
            return "Ask with \(selectedModelDisplayName), project files, and prompt files."
        case .all:
            return "Ask with \(selectedModelDisplayName), web search, files, and saved links."
        }
    }

    var inputPlaceholder: String {
        if isCouncilModeEnabled {
            return effectiveWebSearchEnabled ? "Ask the Council with sources" : "Ask the Council"
        }
        if researchModeEnabled && !selectedRouteUsesNearCloud {
            return "Ask for a researched answer"
        }
        switch selectedProviderDisplayName {
        case "IronClaw":
            return selectedModelOption?.isIronclawMobileRuntime == true ? "Ask IronClaw Mobile" : "Tell the Agent what to run"
        case "NEAR AI Cloud":
            return nearCloudKeyConfigured ? "Ask \(selectedModelDisplayName)" : "Connect NEAR AI Cloud"
        default:
            switch sourceMode {
            case .auto:
                return effectiveWebSearchEnabled ? "Ask with sources" : "Ask privately"
            case .web:
                return "Ask with web search"
            case .links:
                return "Ask from saved links"
            case .files:
                return "Ask about files"
            case .all:
                return "Ask across sources"
            }
        }
    }

    var externalModels: [ModelOption] {
        modelCatalogStore.externalModels
    }

    var agentModels: [ModelOption] {
        modelCatalogStore.agentModels
    }

    var cloudModels: [ModelOption] {
        modelCatalogStore.cloudModels
    }

    private var cloudRouteModels: [ModelOption] {
        modelCatalogStore.cloudRouteModels
    }

    var chatModels: [ModelOption] {
        modelCatalogStore.chatModels
    }

    var currentBillingPlanName: String {
        billingSnapshot?.activeSubscription?.plan ?? "free"
    }

    var hiddenPlanLockedModelCount: Int {
        modelCatalogStore.hiddenPlanLockedModelCount
    }

    var pickerModels: [ModelOption] {
        modelCatalogStore.pickerModels
    }

    var eliteModels: [ModelOption] {
        modelCatalogStore.rankedModels(from: pickerModels.filter { !$0.isOpenWeightCandidate && $0.isEliteModel })
    }

    var openWeightModels: [ModelOption] {
        modelCatalogStore.rankedModels(from: pickerModels.filter { $0.isOpenWeightCandidate })
    }

    var privateModels: [ModelOption] {
        modelCatalogStore.rankedModels(from: pickerModels.filter { !$0.isOpenWeightCandidate && $0.isPrivateVerifiableChatModel && !$0.isEliteModel })
    }

    var standardModels: [ModelOption] {
        modelCatalogStore.rankedModels(from: pickerModels.filter { !$0.isExternalModel && !$0.isOpenWeightCandidate && !$0.isEliteModel && !$0.isPrivateVerifiableChatModel && !$0.isLowerPriorityModel })
    }

    var lowerPriorityModels: [ModelOption] {
        modelCatalogStore.rankedModels(from: pickerModels.filter { !$0.isExternalModel && !$0.isOpenWeightCandidate && $0.isLowerPriorityModel })
    }

    var otherModels: [ModelOption] {
        modelCatalogStore.rankedModels(from: pickerModels.filter { !$0.isExternalModel && !$0.isEliteModel })
    }

    func canUseInCouncil(_ modelID: String) -> Bool {
        modelCatalogStore.canUseInCouncil(modelID)
    }

    func councilIndex(for modelID: String) -> Int? {
        modelCatalogStore.councilIndex(for: modelID)
    }

    func isPinnedModel(_ modelID: String) -> Bool {
        modelCatalogStore.isPinnedModel(modelID)
    }

    func togglePinnedModel(_ modelID: String) {
        modelCatalogStore.togglePinnedModel(modelID)
    }

    func toggleCouncilModel(_ modelID: String) {
        modelCatalogStore.toggleCouncilModel(modelID)
    }

    func useDefaultCouncilLineup() {
        modelCatalogStore.useDefaultCouncilLineup()
    }

    func useCouncilPreset(_ presetID: String) {
        modelCatalogStore.useCouncilPreset(presetID)
    }

    func clearCouncilMode() {
        modelCatalogStore.clearCouncilMode()
    }

    func switchToPrivateFallbackModel() {
        _ = modelCatalogStore.switchToPrivateFallbackModel()
    }

    func performRouteReadinessRecovery(_ action: RouteReadinessIssue.RecoveryAction) {
        switch action {
        case .switchToPrivate:
            switchToPrivateFallbackModel()
        case .editCouncilLineup:
            if defaultCouncilModelIDs().count > 1 {
                useDefaultCouncilLineup()
            } else {
                clearCouncilMode()
                switchToPrivateFallbackModel()
            }
        case .addNearCloudKey:
            showBanner("Connect NEAR AI Cloud in Account, then send again.")
        case .configureIronClawEndpoint:
            showBanner("Connect Hosted IronClaw in Account, then send again.")
        }
    }

    init(
        api: PrivateChatAPI,
        fileService: FileService? = nil,
        fileStore: FileStore? = nil,
        attachmentStagingStore: AttachmentStagingStore? = nil,
        modelCatalogStore: ModelCatalogStore? = nil,
        projectStore: ProjectStore? = nil,
        conversationStore: ConversationStore? = nil,
        agentStore: AgentStore? = nil,
        accountStore: AccountStore? = nil,
        securityStore: SecurityStore? = nil,
        messageRepository: MessageRepository? = nil,
        messageTimelineStore: MessageTimelineStore? = nil,
        routeHealth: RouteHealthMonitor? = nil,
        diagnostics: ConnectionDiagnostics? = nil,
        initialAccountID: String? = nil
    ) {
        self.routeHealth = routeHealth ?? RouteHealthMonitor()
        self.diagnostics = diagnostics ?? ConnectionDiagnostics()
        self.api = api
        storageAccountID = initialAccountID.map { AccountStorageScope.resolvedAccountID(for: $0) } ??
            AccountStorageScope.transientAccountID(prefix: "chat-store")
        draftScopeStore.configure(accountID: storageAccountID)
        let resolvedFileService = fileService ?? FileService(fileAPI: api)
        let resolvedAttachmentStagingStore = attachmentStagingStore ?? AttachmentStagingStore()
        let resolvedMessageTimelineStore = messageTimelineStore ?? MessageTimelineStore()
        let resolvedConversationStore = conversationStore ?? ConversationStore(
            repository: ConversationRepository(api: api)
        )
        self.fileService = resolvedFileService
        self.fileStore = fileStore ?? FileStore(service: resolvedFileService)
        self.attachmentStagingStore = resolvedAttachmentStagingStore
        self.modelCatalogStore = modelCatalogStore ?? ModelCatalogStore()
        self.projectStore = projectStore ?? ProjectStore()
        self.conversationStore = resolvedConversationStore
        self.conversationActionCoordinator = ConversationActionCoordinator(conversationStore: resolvedConversationStore)
        let resolvedAgentStore = agentStore ?? AgentStore(accountID: storageAccountID)
        self.agentStore = resolvedAgentStore
        self.accountStore = accountStore ?? AccountStore(
            settingsAPI: api,
            billingAPI: api,
            modelAPI: api,
            conversationAPI: api,
            modelCatalogStore: self.modelCatalogStore,
            agentStore: resolvedAgentStore,
            accountID: storageAccountID
        )
        self.messageTimelineStore = resolvedMessageTimelineStore
        let resolvedMessageRepository = messageRepository ?? MessageRepository(conversationAPI: api)
        self.messageRepository = resolvedMessageRepository
        self.messageLoadCoordinator = ChatMessageLoadCoordinator(
            repository: resolvedMessageRepository,
            conversationStore: resolvedConversationStore,
            timelineStore: resolvedMessageTimelineStore
        )
        let resolvedSecurityStore = securityStore ?? SecurityStore(attestationAPI: api)
        self.securityStore = resolvedSecurityStore
        let resolvedTranscriptStore = ChatTranscriptStore(timelineStore: resolvedMessageTimelineStore)
        let resolvedComposerStore = ChatComposerStore(attachmentStagingStore: resolvedAttachmentStagingStore)
        self.transcriptStore = resolvedTranscriptStore
        self.composerStore = resolvedComposerStore
        self.chatSessionCoordinator = ChatSessionCoordinator(
            conversationStore: resolvedConversationStore,
            transcriptStore: resolvedTranscriptStore,
            composerStore: resolvedComposerStore,
            projectStore: self.projectStore
        )
        self.ironclawMobileRuntime = IronclawMobileRuntime(api: api)
        self.modelCatalogStore.selectedModel = Self.defaultModelID
        self.modelCatalogStore.councilModelIDs = [Self.defaultModelID]
        self.modelCatalogStore.webSearchEnabled = false
        self.modelCatalogStore.sourceMode = .auto
        self.modelCatalogStore.researchModeEnabled = false
        self.fileStore.bannerHandler = { [weak self] message in
            self?.showBanner(message)
        }
        self.fileStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &storeCancellables)
        self.projectStore.bannerHandler = { [weak self] message in
            self?.showBanner(message)
        }
        self.projectStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &storeCancellables)
        self.conversationStore.bannerHandler = { [weak self] message in
            self?.showBanner(message)
        }
        self.conversationStore.conversationsDidChange = { [weak self] conversations in
            self?.projectStore.replaceConversations(conversations)
        }
        self.conversationStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &storeCancellables)
        self.modelCatalogStore.bannerHandler = { [weak self] message in
            self?.showBanner(message)
        }
        self.modelCatalogStore.routeDidChangeHandler = { [weak self] in
            self?.routeReadinessIssue = nil
            self?.clearAttestationState()
        }
        self.modelCatalogStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &storeCancellables)
        self.agentStore.bannerHandler = { [weak self] message in
            self?.showBanner(message)
        }
        self.agentStore.routeInvalidatedHandler = { [weak self] in
            self?.routeReadinessIssue = nil
        }
        self.agentStore.hostedRouteDisabledHandler = { [weak self] in
            guard let self, self.selectedModelOption?.isIronclawHostedModel == true else { return }
            self.selectedModel = Self.defaultModelID
        }
        self.agentStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &storeCancellables)
        self.accountStore.bannerHandler = { [weak self] message in
            self?.showBanner(message)
        }
        self.accountStore.routeInvalidatedHandler = { [weak self] in
            self?.routeReadinessIssue = nil
        }
        self.accountStore.cloudRouteDisabledHandler = { [weak self] in
            guard let self, self.selectedModelOption?.isNearCloudModel == true else { return }
            self.selectedModel = Self.defaultModelID
        }
        self.accountStore.modelCatalogRefreshHandler = { [weak self] in
            guard let self else { return [] }
            self.deniedOpenWeightModelIDs.removeAll()
            return try await self.api.fetchModels()
        }
        self.accountStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &storeCancellables)
        self.securityStore.bannerHandler = { [weak self] message in
            self?.showBanner(message)
        }
        self.securityStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &storeCancellables)
        self.messageTimelineStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &storeCancellables)
        self.attachmentStagingStore.onDurableStateChange = { [weak self] in
            self?.persistCurrentDraftIfNeeded()
        }
    }

    isolated deinit {
        cancelBackgroundOwners()
    }

    func bootstrap() async {
        #if DEBUG
        if DemoCapture.isEnabled {
            prepareDemoCapture(screen: DemoCapture.initialScreen)
            return
        }
        #endif
        let accountID = storageAccountID
        if bootstrapInFlightAccountID == accountID {
            return
        }
        if lastBootstrappedAccountID == accountID, !models.isEmpty {
            scheduleAccountBackgroundRefresh(for: accountID)
            return
        }

        bootstrapInFlightAccountID = accountID
        let shouldShowBlockingLoader = conversations.isEmpty && models.isEmpty
        if shouldShowBlockingLoader {
            isLoading = true
        }
        defer {
            if shouldShowBlockingLoader {
                isLoading = false
            }
            if bootstrapInFlightAccountID == accountID {
                bootstrapInFlightAccountID = nil
            }
        }

        async let conversationLoad: Void = refreshConversations(showErrors: false)
        async let modelLoad: Void = refreshModels(loadCloudCatalog: nearCloudKeyConfigured)
        async let settingsLoad: Void = refreshUserSettings(showErrors: false)
        _ = await (conversationLoad, modelLoad, settingsLoad)

        guard storageAccountID == accountID else { return }
        ensureSelectedModelIsAvailable(shouldShowBanner: false)
        lastBootstrappedAccountID = accountID
        scheduleAccountBackgroundRefresh(for: accountID)
    }

    func scheduleAccountBackgroundRefresh(for accountID: String? = nil) {
        let resolvedAccountID = accountID ?? storageAccountID
        accountBackgroundRefreshTask?.cancel()
        accountBackgroundRefreshTask = Task { @MainActor [weak self] in
            guard let self, self.storageAccountID == resolvedAccountID else { return }
            await self.refreshBilling(showErrors: false)
            guard !Task.isCancelled, self.storageAccountID == resolvedAccountID else { return }
            if self.ironclawSettings.hasUsableHostedEndpoint {
                await self.refreshIronclawTools()
            }
        }
    }

    func scheduleConversationListRefresh() {
        Task { @MainActor [weak self] in
            await self?.refreshConversations()
        }
    }

    func prepareForAuthenticatedAccount(_ accountID: String?) {
        let resolvedAccountID = AccountStorageScope.resolvedAccountID(for: accountID)
        // Configure memory + activity log up front (even when the account is
        // unchanged) so a fresh signed-out launch still persists them rather
        // than keeping them in RAM until the first account switch.
        memoryStore.configure(accountID: resolvedAccountID)
        activityLog.configure(accountID: resolvedAccountID)
        guard resolvedAccountID != storageAccountID else { return }
        if SettingsPersistence.shouldMigrateStorage(from: storageAccountID, to: resolvedAccountID) {
            SettingsPersistence.migrateAccountScopedStorage(from: storageAccountID, to: resolvedAccountID)
        }
        isResettingAccountScopedState = true
        reset()
        isResettingAccountScopedState = false
        storageAccountID = resolvedAccountID
        loadAccountScopedState()
    }

    func updateCurrentUser(profile: UserProfile?) {
        guard let user = profile?.user else {
            currentUserMessageMetadata = nil
            return
        }

        let authorID = user.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorName = user.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let metadata = MessageMetadata(
            authorID: authorID.isEmpty ? nil : authorID,
            authorName: authorName.isEmpty ? nil : authorName
        )
        currentUserMessageMetadata = metadata.authorID == nil && metadata.authorName == nil ? nil : metadata
    }

    func reset() {
        cancelBackgroundOwners()
        sendCoordinator.reset()
        messageLoadCoordinator.reset()
        bootstrapInFlightAccountID = nil
        lastBootstrappedAccountID = nil
        conversationStore.reset()
        messageTimelineStore.reset()
        modelCatalogStore.reset()
        routeHealth.resetAll()
        diagnostics.reset()
        clearAttestationState()
        pendingExternalDeepLink = nil
        pendingHostedHandoffPreflight = nil
        currentUserMessageMetadata = nil
        routeReadinessIssue = nil
        attachmentStagingStore.resetAll()
        projectStore.reset(persistSelectedProject: false)
        fileStore.reset()
        accountStore.reset()
        draft = ""
        isStreaming = false
        isUploadingAttachment = false
    }

    private func cancelBackgroundOwners() {
        streamTask?.cancel()
        streamTask = nil
        accountBackgroundRefreshTask?.cancel()
        accountBackgroundRefreshTask = nil
        messageLoadCoordinator.cancel()
        agentActivity.end()
        ironclawMobileRuntime.cancel()
        webGroundingService.cancel()
    }

    func resetInteractionDefaults() {
        modelCatalogStore.resetInteractionDefaults()
        projectStore.selectAllProjects()
        accountStore.advancedModelParams = .defaults
        routeReadinessIssue = nil
        clearAttestationState()
        showBanner("Defaults reset.")
    }

    func refreshConversations(showErrors: Bool = true) async {
        await conversationStore.refreshConversations(showErrors: showErrors)
    }

    func refreshModels(loadCloudCatalog: Bool = false) async {
        do {
            deniedOpenWeightModelIDs.removeAll()
            try await modelCatalogStore.refreshModels(
                modelAPI: api,
                loadCloudCatalog: loadCloudCatalog,
                nearCloudAPIKey: loadNearCloudAPIKey()
            )
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func refreshUserSettings(showErrors: Bool = true) async {
        await accountStore.refreshUserSettings(showErrors: showErrors)
    }

    func saveUserSettings(
        systemPrompt: String,
        webSearchEnabled: Bool,
        notificationEnabled: Bool,
        appearancePreference: AppAppearancePreference,
        largeTextAsFileEnabled: Bool,
        advancedParams: AdvancedModelParams
    ) async {
        await accountStore.saveUserSettings(
            systemPrompt: systemPrompt,
            webSearchEnabled: webSearchEnabled,
            notificationEnabled: notificationEnabled,
            appearancePreference: appearancePreference,
            largeTextAsFileEnabled: largeTextAsFileEnabled,
            advancedParams: advancedParams
        )
    }

    func refreshBilling(showErrors: Bool = true) async {
        await accountStore.refreshBilling(showErrors: showErrors)
    }

    /// Opens a conversation by id (e.g. from a CoreSpotlight result) if it's in
    /// the loaded list. No-op otherwise — the app still foregrounds to home.
    func openConversation(byID id: String) {
        guard let conversation = conversationStore.openConversation(byID: id) else { return }
        selectConversation(conversation)
    }

    func selectConversation(_ conversation: ConversationSummary) {
        chatSessionCoordinator.openConversation(
            conversation,
            isStreaming: isStreaming,
            cancelActiveStream: { self.cancelStream() },
            persistCurrentDraft: { self.persistCurrentDraftIfNeeded() },
            scheduleMessageLoad: { self.scheduleMessageLoad(for: $0) },
            transitionDraftScope: { self.transitionDraftScopeToCurrentSelection(loadDraft: true) },
            showBanner: { self.showBanner($0) }
        )
    }

    func startNewConversation() {
        chatSessionCoordinator.startNewConversation(
            isStreaming: isStreaming,
            cancelActiveStream: { self.cancelStream() },
            persistCurrentDraft: { self.persistCurrentDraftIfNeeded() },
            cancelMessageLoad: { self.cancelMessageLoad() },
            transitionDraftScope: { self.transitionDraftScopeToCurrentSelection(loadDraft: true) },
            showBanner: { self.showBanner($0) }
        )
    }

    /// UserDefaults keys an App Intent (Siri/Shortcuts) writes; the app consumes
    /// them on activation. The intents run in-process (main-target App Intents),
    /// so plain UserDefaults is shared — no App Group needed.
    nonisolated static let pendingSiriPromptKey = "pendingSiriPrompt"
    nonisolated static let pendingRunBriefingsKey = "pendingRunBriefings"

    /// Stages a Siri-supplied question into the composer (not auto-sent — the
    /// user reviews it, matching the deep-link "staged but not sent" contract).
    @discardableResult
    func consumePendingSiriPrompt(defaults: UserDefaults = .standard) -> Bool {
        guard let raw = defaults.string(forKey: Self.pendingSiriPromptKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return false
        }
        guard !isStreaming else {
            // Leave the key in place; the next activation retries once the
            // current response finishes. (Clearing here would lose the prompt.)
            showBanner("Finish or cancel the current response before starting a new chat.")
            return false
        }
        defaults.removeObject(forKey: Self.pendingSiriPromptKey)
        startNewConversation()
        draft = String(raw.prefix(AppDeepLinkAction.maxDraftCharacters))
        AppHaptics.selection()
        return true
    }

    /// Stages text/URL handed off by the "Send to Private Chat" share extension
    /// into the composer (not auto-sent — same staged-but-not-sent contract as
    /// the Siri bridge and deep links). Reads the App Group hand-off file,
    /// clears it so the item is staged once, and returns whether anything was
    /// staged. `fileURL` is injectable so tests don't need the real container.
    @discardableResult
    func consumePendingSharedItem(
        fileURL: URL? = PendingShareStore.defaultFileURL()
    ) async -> Bool {
        guard let item = PendingShareStore.read(from: fileURL) else { return false }
        guard !isStreaming else {
            // Leave the file in place; the next activation can retry once the
            // current response finishes.
            showBanner("Finish or cancel the current response before starting a new chat.")
            return false
        }
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sharedFiles = item.attachments.compactMap { attachment -> (attachment: PendingSharedAttachment, url: URL)? in
            guard let url = PendingShareStore.fileURL(for: attachment, handoffFileURL: fileURL),
                  FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }
            return (attachment, url)
        }
        guard !text.isEmpty || !sharedFiles.isEmpty else { return false }
        startNewConversation()
        draft = String(
            (text.isEmpty ? "Turn these shared files into useful actions I can approve." : text)
                .prefix(AppDeepLinkAction.maxDraftCharacters)
        )
        for sharedFile in sharedFiles {
            guard let attachment = stageSharedFileAttachment(
                sharedFile.url,
                displayName: sharedFile.attachment.fileName,
                byteCount: sharedFile.attachment.byteCount
            ) else { continue }
            await stageExtractedTextForSharedFileIfAvailable(
                sharedFile.url,
                attachment: attachment
            )
        }
        persistCurrentDraftIfNeeded()
        PendingShareStore.clear(fileURL)
        AppHaptics.selection()
        return true
    }

    private func stageExtractedTextForSharedFileIfAvailable(
        _ url: URL,
        attachment: ChatAttachment
    ) async {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        let fileExtension = url.pathExtension.lowercased()
        let extractedText: String?
        if fileExtension == "csv" || fileExtension == "tsv" {
            extractedText = DocumentTextExtractor.extractedDelimitedTableText(
                from: url,
                fileSize: fileSize
            )?.text
        } else if fileExtension == "xlsx" {
            extractedText = DocumentTextExtractor.extractedSpreadsheetTableText(
                from: url,
                fileSize: fileSize
            )?.text
        } else if fileExtension == "pdf" {
            extractedText = await DocumentTextExtractor.extractPDFText(from: url, fileSize: fileSize)?.text
        } else {
            extractedText = await VisionTextExtractor.extractedImageTextIfAvailable(
                from: url,
                fileExtension: fileExtension
            )
        }
        guard let extractedText,
              !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        attachmentStagingStore.stageDocumentText(
            String(extractedText.prefix(AttachmentStagingStore.maxStagedDocumentChars)),
            for: attachment.id
        )
    }

    func stagedDocumentText(for attachmentID: String) -> String? {
        attachmentStagingStore.documentText(for: attachmentID)
    }

    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        guard let action = AppDeepLinkAction.parse(url) else { return false }
        guard !isStreaming else {
            showBanner("Finish or cancel the current response before opening this shortcut.")
            return true
        }
        pendingExternalDeepLink = action
        showBanner("Review the shortcut before opening it.")
        return true
    }

    func confirmPendingExternalDeepLink() {
        guard let action = pendingExternalDeepLink else { return }
        pendingExternalDeepLink = nil
        applyExternalDeepLink(action)
    }

    func cancelPendingExternalDeepLink() {
        pendingExternalDeepLink = nil
    }

    var pendingExternalDeepLinkDescription: String {
        guard let action = pendingExternalDeepLink else { return "" }
        let route: String
        switch action.route {
        case .ask:
            route = "a new chat"
        case .agent:
            route = "an IronClaw Mobile agent"
        case .verified:
            route = "a private chat with proof"
        }
        let source = action.sourceMode.map { " Source: \($0.title)." } ?? ""
        let research = action.researchMode ? " Research mode will be enabled." : ""
        let hostedBridge = action.hostedBridgeImport.map { bridge in
            let host = bridge.host ?? "Hosted IronClaw"
            let token = bridge.authToken == nil ? "" : " Token will be saved."
            let thread = bridge.threadID == nil ? "" : " Thread reuse will be configured."
            let enabled = bridge.isEnabled ? " Agent connection for \(host) will be saved and enabled." : " Agent connection for \(host) will be saved."
            return "\(enabled)\(token)\(thread)"
        } ?? ""
        let prompt = action.draft == nil ? " No prompt will be added." : " A prompt will be staged but not sent."
        return "Open \(route).\(source)\(research)\(hostedBridge)\(prompt)"
    }

    private func applyExternalDeepLink(_ action: AppDeepLinkAction) {
        startNewConversation()
        routeReadinessIssue = nil
        if let sourceMode = action.sourceMode {
            self.sourceMode = sourceMode
        }
        researchModeEnabled = action.researchMode
        if action.sourceMode == .web || action.sourceMode == .all || action.researchMode {
            webSearchEnabled = true
        }
        if let draft = action.draft {
            self.draft = draft
        }
        let importedBridgeValidationMessage = applyHostedBridgeImportIfPresent(action.hostedBridgeImport)

        switch action.route {
        case .ask:
            if importedBridgeValidationMessage == nil {
                showBanner(action.draft == nil ? "New chat ready." : "Prompt ready.")
            }
        case .agent:
            selectedModel = ModelOption.ironclawMobileModelID
            councilModelIDs = []
            clearAttestationState()
            if importedBridgeValidationMessage == nil {
                showBanner(action.draft == nil ? "IronClaw Mobile ready." : "IronClaw prompt ready.")
            }
        case .verified:
            if let modelID = preferredAvailableModel(), !Self.isExternalModel(modelID) {
                selectedModel = modelID
            } else if Self.isExternalModel(selectedModel) {
                selectedModel = Self.defaultModelID
            }
            councilModelIDs = []
            clearAttestationState()
            if importedBridgeValidationMessage == nil {
                showBanner(action.draft == nil ? "Private chat with proof ready." : "Private prompt with proof ready.")
            }
        }
        conversationStore.requestOpenSelectedConversation()
    }

    @discardableResult
    private func applyHostedBridgeImportIfPresent(_ bridgeImport: AppDeepLinkAction.HostedBridgeImport?) -> String? {
        guard let bridgeImport else { return nil }
        let trimmedEndpoint = bridgeImport.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedThreadID = bridgeImport.threadID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let validationMessage = IronclawSettings(
            isEnabled: bridgeImport.isEnabled,
            baseURL: trimmedEndpoint,
            threadID: trimmedThreadID
        ).endpointValidationMessage

        saveIronclawIntegration(
            isEnabled: bridgeImport.isEnabled,
            baseURL: trimmedEndpoint,
            authToken: bridgeImport.authToken ?? "",
            threadID: trimmedThreadID
        )

        return validationMessage
    }

    func selectModel(_ modelID: String) {
        let wasSelected = modelCatalogStore.selectModel(modelID)
        guard wasSelected else { return }
        let selectedOption = chatModels.first(where: { $0.id == modelID })
        if selectedOption?.isNearCloudModel == true, !nearCloudKeyConfigured {
            showBanner("Using \(selectedOption?.displayName ?? modelDisplayName(for: modelID)). Connect NEAR AI Cloud in Account before sending.")
        } else {
            showBanner("Using \(modelDisplayName(for: modelID)).")
        }
    }

    func setReasoningEffort(_ effort: ModelReasoningEffort) {
        advancedModelParams = AdvancedModelParams(
            temperature: advancedModelParams.temperature,
            topP: advancedModelParams.topP,
            maxTokens: advancedModelParams.maxTokens,
            reasoningEffort: effort
        ).sanitized
        showBanner(effort == .automatic ? "Reasoning effort set to Auto." : "Reasoning effort set to \(effort.title).")
    }

    func toggleWebSearch() {
        modelCatalogStore.setWebSearchEnabled(!webSearchEnabled)
        showBanner(webSearchEnabled ? "Web search enabled." : "Web search disabled.")
    }

    func selectSourceMode(_ mode: ChatSourceMode) {
        let wasResearchModeEnabled = researchModeEnabled
        modelCatalogStore.setSourceMode(mode)
        showBanner(wasResearchModeEnabled ? "Focus: \(mode.title)." : "Focus: \(mode.title).")
    }

    func toggleResearchMode() {
        guard !selectedRouteUsesNearCloud else {
            showBanner("Research focus needs a NEAR Private route or app-side web grounding.")
            return
        }
        modelCatalogStore.setResearchModeEnabled(!researchModeEnabled)
        showBanner(researchModeEnabled ? "Research focus on." : "Research focus off.")
    }

    func saveIronclawIntegration(
        isEnabled: Bool,
        baseURL: String,
        authToken: String,
        threadID: String
    ) {
        agentStore.saveIronclawIntegration(
            isEnabled: isEnabled,
            baseURL: baseURL,
            authToken: authToken,
            threadID: threadID
        )
    }

    func disconnectIronclaw() {
        agentStore.disconnectIronclaw()
    }

    func saveNearCloudAPIKey(_ apiKey: String) {
        accountStore.saveNearCloudAPIKey(apiKey)
    }

    func connectNearCloudAccount() async -> Bool {
        await accountStore.connectNearCloudAccount()
    }

    func connectNearCloudAPIKey(_ apiKey: String) async -> Bool {
        await accountStore.connectNearCloudAPIKey(apiKey)
    }

    func clearNearCloudAPIKey() {
        accountStore.clearNearCloudAPIKey()
    }

    func testIronclawConnection() async {
        await agentStore.testIronclawConnection()
    }

    func testIronclawWorkstation() async {
        await agentStore.testIronclawWorkstation()
    }

    func refreshIronclawTools() async {
        await agentStore.refreshIronclawTools()
    }

    func runDiagnostics() async {
        await accountStore.runDiagnostics()
    }

    func selectAllChats() {
        chatSessionCoordinator.selectAllChats(
            persistCurrentDraft: { self.persistCurrentDraftIfNeeded() },
            transitionDraftScope: { self.transitionDraftScopeToCurrentSelection(loadDraft: true) }
        )
    }

    func setupProfileSnapshot(_ rawProfile: UserSetupProfile) -> UserSetupProfile {
        var profile = rawProfile.normalizedForDefaults
        profile.routeDefaults = resolvedSetupRouteDefaults(for: profile)
        return profile
    }

    func applySetupProfile(_ rawProfile: UserSetupProfile) {
        let profile = setupProfileSnapshot(rawProfile)
        let routeDefaults = resolvedSetupRouteDefaults(for: profile)
        let readiness = AppSetupReadinessSnapshot(
            modelCatalogLoaded: !models.isEmpty || routeDefaults.councilModelIDs.count > 1,
            privateModelAvailable: pickerModels.contains { !$0.isExternalModel },
            defaultCouncilModelCount: max(defaultCouncilModels.count, routeDefaults.councilModelIDs.count),
            ironclawMobileAvailable: agentModels.contains { $0.id == ModelOption.ironclawMobileModelID },
            hostedIronclawAvailable: ironclawRemoteWorkstationAvailable,
            nearCloudKeyConfigured: nearCloudKeyConfigured
        )
        let plan = AppSetupPlan(profile: profile, readiness: readiness, routeDefaults: routeDefaults)
        webSearchEnabled = profile.wantsWeb
        sourceMode = plan.focusMode
        researchModeEnabled = profile.useCases.contains(.research) && plan.modelRoute != .ironclaw
        if soulMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            soulMarkdown = SetupSoulPromptBuilder.markdown(for: profile)
        }

        let requestedCouncilModelIDs = plan.modelRoute == .council ? routeDefaults.councilModelIDs : []
        switch plan.modelRoute {
        case .ironclaw:
            selectedModel = routeDefaults.preferredIronclawModelID(readiness: readiness) ?? ModelOption.ironclawMobileModelID
            councilModelIDs = []
        case .council:
            councilModelIDs = requestedCouncilModelIDs
            selectedModel = requestedCouncilModelIDs.first ?? preferredAvailableModel() ?? Self.defaultModelID
        case .privateModel:
            selectedModel = usablePrivateSetupModelID(from: routeDefaults.privateModelID) ??
                preferredAvailableModel() ??
                Self.defaultModelID
            councilModelIDs = canUseInCouncil(selectedModel) ? [selectedModel] : []
        }

        if let projectName = profile.setupStarterProjectName {
            let project = projectStore.ensureProject(named: projectName, includeConversationID: nil)
            projectStore.selectProjectID(project.id)
            _ = projectStore.updateInstructionsIfEmpty(
                projectID: project.id,
                instructions: profile.setupProjectInstructions
            )
            _ = projectStore.seedSetupMetadata(projectID: project.id, profile: profile, plan: plan)
        } else if profile.contextStyle == .simple {
            projectStore.selectAllProjects()
        }

        let shouldSeedStarterDraft = shouldSeedSetupStarterDraft(for: profile)
        if let draft = profile.firstRunDraft, shouldSeedStarterDraft {
            startNewConversation()
            self.draft = draft
            conversationStore.requestOpenSelectedConversation()
            showBanner(setupAppliedBanner(for: plan, profile: profile, openedDraft: true))
        } else {
            showBanner(setupAppliedBanner(for: plan, profile: profile, openedDraft: false))
        }
    }

    private func resolvedSetupRouteDefaults(for profile: UserSetupProfile) -> SetupRouteDefaults {
        let stored = profile.routeDefaults.normalized
        let fallback = setupRouteDefaults
        let privateModelID = usablePrivateSetupModelID(from: stored.privateModelID) ??
            usablePrivateSetupModelID(from: fallback.privateModelID) ??
            preferredAvailableModel() ??
            Self.defaultModelID
        let councilIDs = setupCouncilRouteModelIDs(
            stored.councilModelIDs.isEmpty ? fallback.councilModelIDs : stored.councilModelIDs
        )
        let ironclawMobileModelID =
            stored.ironclawMobileModelID == ModelOption.ironclawMobileModelID &&
            agentModels.contains { $0.id == ModelOption.ironclawMobileModelID }
            ? ModelOption.ironclawMobileModelID
            : fallback.ironclawMobileModelID

        return SetupRouteDefaults(
            privateModelID: privateModelID,
            councilModelIDs: councilIDs,
            ironclawMobileModelID: ironclawMobileModelID
        ).normalized
    }

    private func usablePrivateSetupModelID(from modelID: String?) -> String? {
        guard let trimmed = modelID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              Self.routeKind(forModelID: trimmed) == .nearPrivate else {
            return nil
        }
        return trimmed
    }

    private func setupCouncilRouteModelIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for modelID in ids {
            let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !trimmed.isEmpty,
                  Self.routeKind(forModelID: trimmed) != .ironclawHosted,
                  Self.routeKind(forModelID: trimmed) != .ironclawMobile,
                  seen.insert(key).inserted else {
                continue
            }
            normalized.append(trimmed)
            if normalized.count == Self.maxCouncilModels {
                break
            }
        }
        return normalized
    }

    private func setupAppliedBanner(for plan: AppSetupPlan, profile: UserSetupProfile, openedDraft: Bool) -> String {
        if profile.wantsIronclaw, plan.modelRoute != .ironclaw {
            return openedDraft
                ? "Setup applied. Private prompt ready while Agent tools stay unavailable."
                : "Setup applied. Private route is ready while Agent tools stay unavailable."
        }
        if profile.wantsCouncil, plan.modelRoute != .council {
            return openedDraft
                ? "Setup applied. Private prompt ready while Council finishes loading."
                : "Setup applied. Private route is ready while Council finishes loading."
        }

        switch plan.modelRoute {
        case .ironclaw:
            return openedDraft ? "Setup applied. Agent prompt ready." : "Setup applied. Agent route ready."
        case .council:
            return openedDraft ? "Setup applied. Council prompt ready." : "Setup applied. Council route ready."
        case .privateModel:
            return openedDraft ? "Setup applied. First prompt ready." : "Setup applied."
        }
    }

    private func shouldSeedSetupStarterDraft(for profile: UserSetupProfile) -> Bool {
        if !profile.normalizedGoalText.isEmpty {
            return true
        }
        let hasDraftText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasDraftText || !pendingAttachments.isEmpty || !pendingLargePasteTexts.isEmpty {
            return false
        }
        return messages.isEmpty
    }

    func selectProject(_ project: ChatProject) {
        chatSessionCoordinator.selectProject(
            project,
            availableConversations: conversations,
            persistCurrentDraft: { self.persistCurrentDraftIfNeeded() },
            scheduleMessageLoad: { self.scheduleMessageLoad(for: $0) },
            cancelMessageLoad: { self.cancelMessageLoad() },
            transitionDraftScope: { self.transitionDraftScopeToCurrentSelection(loadDraft: true) }
        )
    }

    func createProject(
        named name: String,
        instructions: String = "",
        iconName: String = ProjectIcon.folder.symbolName,
        paletteName: String = ProjectPalette.sky.rawValue
    ) {
        _ = projectStore.createProject(
            named: name,
            conversationID: selectedConversation?.id,
            instructions: instructions,
            iconName: iconName,
            paletteName: paletteName
        )
    }

    func createProjectFromSelectedConversation() {
        guard let selectedConversation else {
            showBanner("Open a chat first.")
            return
        }
        createProject(named: selectedConversation.title)
    }

    func updateProject(
        _ projectID: String,
        name: String,
        iconName: String,
        paletteName: String,
        instructions: String? = nil
    ) {
        projectStore.updateProject(
            projectID,
            name: name,
            iconName: iconName,
            paletteName: paletteName,
            instructions: instructions
        )
    }

    func archiveProject(_ project: ChatProject) {
        chatSessionCoordinator.archiveProject(
            project,
            transitionDraftScope: { self.transitionDraftScopeToCurrentSelection(loadDraft: true) }
        )
    }

    func unarchiveProject(_ project: ChatProject) {
        projectStore.unarchiveProject(project)
    }

    func updateSelectedProjectInstructions(_ instructions: String) {
        projectStore.updateSelectedProjectInstructions(instructions)
    }

    func updateSelectedProjectMemory(_ memory: String) {
        projectStore.updateSelectedProjectMemory(memory)
    }

    func addSelectedProjectLink(title: String, url rawURL: String) {
        projectStore.addSelectedProjectLink(title: title, url: rawURL)
    }

    func addSelectedProjectNote(title: String, text: String, isLocalOnly: Bool = false) {
        projectStore.addSelectedProjectNote(title: title, text: text, isLocalOnly: isLocalOnly)
    }

    func updateSelectedProjectNote(_ note: ProjectNote, title: String, text: String, isLocalOnly: Bool) {
        projectStore.updateSelectedProjectNote(note, title: title, text: text, isLocalOnly: isLocalOnly)
    }

    func deleteProjectLink(_ link: ProjectLink) {
        projectStore.deleteProjectLink(link)
    }

    func saveMessageAsProjectNote(_ message: ChatMessage) {
        guard message.role == .assistant else { return }
        guard selectedProjectID != nil else {
            pendingProjectNoteSaveMessage = message
            showBanner("Create or choose a project to save this output.")
            return
        }
        _ = projectStore.saveOutputAsProjectNote(text: message.text, sourceMessageID: message.id)
    }

    func requestProjectNoteSave(for message: ChatMessage) {
        guard message.role == .assistant else { return }
        guard !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showBanner("No output to save.")
            return
        }
        pendingProjectNoteSaveMessage = message
    }

    func saveMessageAsProjectNote(_ message: ChatMessage, toProjectID projectID: String) {
        guard message.role == .assistant else { return }
        guard projects.contains(where: { $0.id == projectID && !$0.isArchived }) else {
            showBanner("Project not found.")
            return
        }
        if projectStore.saveOutputAsProjectNote(text: message.text, sourceMessageID: message.id, toProjectID: projectID) {
            clearPendingProjectNoteSave()
        }
    }

    func createProjectAndSaveMessageAsNote(
        _ message: ChatMessage,
        named name: String,
        instructions: String = ""
    ) {
        guard message.role == .assistant else { return }
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            showBanner("No output to save.")
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showBanner("Name the project first.")
            return
        }

        _ = projectStore.createProjectAndSaveOutputAsNote(
            text: message.text,
            sourceMessageID: message.id,
            named: trimmed,
            conversationID: selectedConversation?.id,
            instructions: instructions
        )
        clearPendingProjectNoteSave()
    }

    func clearPendingProjectNoteSave() {
        pendingProjectNoteSaveMessage = nil
    }

    func suggestedProjectNameForSavedNote(_ message: ChatMessage) -> String {
        if let conversationTitle = selectedConversation?.title.trimmingCharacters(in: .whitespacesAndNewlines),
           !conversationTitle.isEmpty,
           conversationTitle.localizedCaseInsensitiveCompare("New chat") != .orderedSame {
            return String(conversationTitle.prefix(64))
        }
        return ProjectService.noteTitle(from: message.text)
    }

    func deleteProjectNote(_ note: ProjectNote) {
        projectStore.deleteProjectNote(note)
    }

    func assignSelectedConversation(to projectID: String?) {
        guard let selectedConversation else { return }
        assign(conversationID: selectedConversation.id, to: projectID)
    }

    func assign(conversationID: String, to projectID: String?) {
        projectStore.assign(conversationID: conversationID, to: projectID)
    }

    func addAttachment(from url: URL, displayName: String? = nil) async {
        switch FileStore.promptAttachmentLimit(
            pendingCount: pendingAttachments.count,
            projectContextCount: activeProjectContextAttachments.count,
            maxPromptAttachments: Self.maxPromptAttachments,
            maxContextAttachments: Self.maxProjectAttachments
        ) {
        case .allowed:
            break
        case let .blocked(message):
            showBanner(message)
            return
        }

        attachmentUploadNotice = nil
        if let attachment = await uploadAttachment(from: url) {
            var attachment = attachment
            if let displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !displayName.isEmpty {
                attachment.name = displayName
            }
            let notice = attachmentUploadNotice
            attachmentUploadNotice = nil
            attachmentStagingStore.appendPromptAttachment(attachment)
            registerUploadedAttachment(attachment)
            showBanner(notice ?? "Attached \(attachment.name).")
        }
    }

    func stageTextAttachment(_ text: String, suggestedName: String = "pasted-text.txt") {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showBanner("Clipboard has no text to attach.")
            return
        }
        switch FileStore.promptAttachmentLimit(
            pendingCount: pendingAttachments.count,
            projectContextCount: activeProjectContextAttachments.count,
            maxPromptAttachments: Self.maxPromptAttachments,
            maxContextAttachments: Self.maxProjectAttachments
        ) {
        case .allowed:
            break
        case let .blocked(message):
            showBanner(message)
            return
        }
        guard trimmed.utf8.count <= Self.maxFileUploadBytes else {
            showBanner("Text paste exceeds the 10 MB file cap.")
            return
        }
        stageLargePasteForSend(trimmed, suggestedName: suggestedName)
    }

    private func stageSharedFileAttachment(
        _ url: URL,
        displayName: String,
        byteCount: Int?
    ) -> ChatAttachment? {
        switch FileStore.promptAttachmentLimit(
            pendingCount: pendingAttachments.count,
            projectContextCount: activeProjectContextAttachments.count,
            maxPromptAttachments: Self.maxPromptAttachments,
            maxContextAttachments: Self.maxProjectAttachments
        ) {
        case .allowed:
            break
        case let .blocked(message):
            showBanner(message)
            return nil
        }
        return attachmentStagingStore.stageSharedFileAttachment(
            url,
            displayName: displayName,
            byteCount: byteCount
        )
    }

    func addProjectAttachment(from url: URL) async {
        guard selectedProjectID != nil else {
            showBanner("Select a project first.")
            return
        }
        switch FileStore.projectAttachmentLimit(
            projectAttachmentCount: selectedProjectAttachments.count,
            maxProjectAttachments: Self.maxProjectAttachments
        ) {
        case .allowed:
            break
        case let .blocked(message):
            showBanner(message)
            return
        }

        attachmentUploadNotice = nil
        if let attachment = await uploadAttachment(from: url) {
            let notice = attachmentUploadNotice
            attachmentUploadNotice = nil
            let localDocumentText = attachmentStagingStore.documentText(for: attachment.id)
            projectStore.addAttachmentToSelectedProject(
                attachment,
                maxAttachments: Self.maxProjectAttachments,
                notice: notice,
                localDocumentText: localDocumentText
            )
            registerUploadedAttachment(attachment)
        }
    }

    func refreshRemoteFiles(showErrors: Bool = true) async {
        await fileStore.refreshRemoteFiles(showErrors: showErrors)
    }

    func previewRemoteFile(_ file: RemoteFileInfo) async {
        await fileStore.previewRemoteFile(file)
    }

    func attachRemoteFileToPrompt(_ file: RemoteFileInfo) {
        let attachment = file.attachment
        guard !pendingAttachments.contains(where: { $0.id == attachment.id }) else {
            showBanner("\(attachment.name) is already attached.")
            return
        }
        switch FileStore.promptAttachmentLimit(
            pendingCount: pendingAttachments.count,
            projectContextCount: activeProjectContextAttachments.count,
            maxPromptAttachments: Self.maxPromptAttachments,
            maxContextAttachments: Self.maxProjectAttachments
        ) {
        case .allowed:
            break
        case let .blocked(message):
            showBanner(message)
            return
        }
        attachmentStagingStore.appendPromptAttachment(attachment)
        showBanner("Attached \(attachment.name).")
    }

    func addRemoteFileToSelectedProject(_ file: RemoteFileInfo) {
        guard selectedProjectID != nil else {
            showBanner("Select a project first.")
            return
        }

        let attachment = file.attachment
        guard !selectedProjectAttachments.contains(where: { $0.id == attachment.id }) else {
            showBanner("\(attachment.name) is already in this project.")
            return
        }
        switch FileStore.projectAttachmentLimit(
            projectAttachmentCount: selectedProjectAttachments.count,
            maxProjectAttachments: Self.maxProjectAttachments
        ) {
        case .allowed:
            break
        case let .blocked(message):
            showBanner(message)
            return
        }

        projectStore.addAttachmentToSelectedProject(attachment, maxAttachments: Self.maxProjectAttachments)
    }

    func deleteRemoteFile(_ file: RemoteFileInfo) async {
        guard let deletedFileID = await fileStore.deleteRemoteFile(file) else { return }
        attachmentStagingStore.removePromptAttachments(withID: deletedFileID)
        projectStore.removeAttachmentFromAllProjects(id: deletedFileID)
    }

    private func registerUploadedAttachment(_ attachment: ChatAttachment) {
        fileStore.registerUploadedAttachment(attachment)
    }

    func removeProjectAttachment(_ attachment: ChatAttachment) {
        projectStore.removeAttachmentFromSelectedProject(attachment)
    }

    private func uploadAttachment(from url: URL) async -> ChatAttachment? {
        isUploadingAttachment = true
        defer { isUploadingAttachment = false }

        do {
            let result = try await fileService.uploadAttachment(
                from: url,
                keepDocumentsOnDevice: keepDocumentsOnDevice
            )
            if let stagedDocumentText = result.stagedDocumentText {
                attachmentStagingStore.stageDocumentText(stagedDocumentText.text, for: stagedDocumentText.attachmentID)
            }
            attachmentUploadNotice = result.notice
            return result.attachment
        } catch {
            showBanner(error.localizedDescription)
            return nil
        }
    }

    private func handleDraftChange(from previous: String, to current: String) {
        guard !isNormalizingDraft, !draftScopeStore.isSuppressingPersistence else { return }

        var currentValue = current
        let normalizedValue = Self.normalizedDraftInput(current)
        if normalizedValue != current {
            isNormalizingDraft = true
            draft = normalizedValue
            isNormalizingDraft = false
            currentValue = normalizedValue
        }

        guard largeTextAsFileEnabled,
              !isUploadingAttachment,
              attachmentStagingStore.shouldPromoteLargePaste(
                previous: previous,
                current: currentValue,
                thresholdBytes: Self.largePasteThresholdBytes,
                thresholdCharacters: Self.largePasteThresholdCharacters
              ) else {
            return
        }
        switch FileStore.promptAttachmentLimit(
            pendingCount: pendingAttachments.count,
            projectContextCount: activeProjectContextAttachments.count,
            maxPromptAttachments: Self.maxPromptAttachments,
            maxContextAttachments: Self.maxProjectAttachments
        ) {
        case .allowed:
            break
        case let .blocked(message):
            showBanner(message)
            return
        }
        guard currentValue.utf8.count <= Self.maxFileUploadBytes else {
            showBanner("Large paste exceeds the 10 MB file cap.")
            return
        }

        isNormalizingDraft = true
        draft = ""
        isNormalizingDraft = false

        stageLargePasteForSend(currentValue)
    }

    private func stageLargePasteForSend(_ text: String, suggestedName: String? = nil) {
        _ = attachmentStagingStore.stageLargePasteForSend(text, suggestedName: suggestedName)
        showBanner("Text staged. It uploads only when you send.")
    }

    func applyPromptSourcePrivacyOverride(_ override: PromptSourcePrivacyOverride) {
        guard !override.isEmpty else { return }
        if override.blocksWeb {
            webSearchEnabled = false
            researchModeEnabled = false
        }
        if override.prefersFileOnly, sourceMode != .files {
            sourceMode = .files
        }
        guard override.requiresPrivateRoute else { return }
        if isCouncilModeEnabled {
            councilModelIDs = []
        }
        if selectedRouteKind != .nearPrivate,
           let privateModel = preferredAvailableModel() {
            selectedModel = privateModel
            clearAttestationState()
            showBanner("Kept this turn on the private route.")
        }
    }

    func resolvePromptAttachmentsForSend(_ promptAttachments: [ChatAttachment]) async throws -> [ChatAttachment] {
        let resolution = try await attachmentStagingStore.resolvePromptAttachmentsForSend(
            promptAttachments,
            fileService: fileService
        )
        for uploadedAttachment in resolution.uploadedAttachments {
            registerUploadedAttachment(uploadedAttachment)
        }
        return resolution.attachments
    }

    func removePendingAttachment(_ attachment: ChatAttachment) {
        attachmentStagingStore.removePromptAttachment(attachment)
        showBanner("Attachment removed.")
    }

    func confirmPendingDelete() {
        Task {
            await conversationActionCoordinator.confirmPendingDelete(
                selectedConversationID: selectedConversation?.id,
                removeLocalMessages: { self.removeLocalMessages(for: $0) },
                removeConversationFromProjects: { self.projectStore.removeConversationFromAllProjects($0) },
                startNewConversation: { self.startNewConversation() },
                showBanner: { self.showBanner($0) }
            )
        }
    }

    func cloneConversation(_ conversation: ConversationSummary) {
        Task {
            await conversationActionCoordinator.cloneConversation(
                conversation,
                selectedProjectID: selectedProjectID,
                assignToProject: { self.assign(conversationID: $0, to: $1) },
                loadMessages: { await self.loadMessages(for: $0, preferCached: false) },
                refreshConversations: { await self.refreshConversations() },
                showBanner: { self.showBanner($0) }
            )
        }
    }

    func archiveConversation(_ conversation: ConversationSummary) {
        Task {
            await conversationActionCoordinator.archiveConversation(
                conversation,
                selectedConversationID: selectedConversation?.id,
                refreshConversations: { await self.refreshConversations() },
                startNewConversation: { self.startNewConversation() },
                showBanner: { self.showBanner($0) }
            )
        }
    }

    func togglePinConversation(_ conversation: ConversationSummary) {
        Task {
            await conversationActionCoordinator.togglePinConversation(
                conversation,
                refreshConversations: { await self.refreshConversations() },
                showBanner: { self.showBanner($0) }
            )
        }
    }

    private func clearAttestationState() {
        securityStore.clearAttestationState()
    }

    func refreshAttestationReport() async {
        await securityStore.refreshAttestationReport(
            selectedModelID: selectedModel,
            selectedRouteKind: selectedRouteKind,
            isCouncilModeEnabled: isCouncilModeEnabled,
            activeCouncilHasExternalRoutes: activeCouncilHasExternalRoutes
        )
    }

    func openSharedPreviewForWriting(_ snapshot: SharedConversationSnapshot) {
        chatSessionCoordinator.openWritablePreview(
            conversation: snapshot.conversation,
            messages: snapshot.messages,
            canWrite: snapshot.canWrite,
            cancelMessageLoad: { [weak self] in self?.cancelMessageLoad() },
            showBanner: { [weak self] message in self?.showBanner(message) }
        )
    }

    func loadMessages(for conversation: ConversationSummary, preferCached: Bool = true) async {
        await messageLoadCoordinator.loadMessages(
            for: conversation,
            preferCached: preferCached,
            callbacks: messageLoadCallbacks()
        )
    }

    func scheduleMessageLoad(for conversation: ConversationSummary, preferCached: Bool = true) {
        messageLoadCoordinator.scheduleMessagesLoad(
            for: conversation,
            preferCached: preferCached,
            callbacks: messageLoadCallbacks()
        )
    }

    private func cancelMessageLoad() {
        messageLoadCoordinator.cancel()
    }

    func selectResponseVariant(_ responseID: String) {
        guard !isStreaming else { return }
        guard let conversation = selectedConversation else { return }
        messageTimelineStore.selectResponseVariant(responseID, for: conversation.id)
        scheduleMessageLoad(for: conversation, preferCached: false)
    }

    nonisolated static func mergedMessages(remoteMessages: [ChatMessage], localCache: [ChatMessage]?) -> [ChatMessage] {
        MessageRepository.mergedMessages(remoteMessages: remoteMessages, localCache: localCache)
    }

    private func messageLoadCallbacks() -> ChatMessageLoadCoordinatorCallbacks {
        ChatMessageLoadCoordinatorCallbacks(
            restoreSelectedModel: { [weak self] messages in
                self?.restoreSelectedModel(from: messages)
            },
            refreshExternalLatestResponse: { [weak self] conversationID in
                await self?.refreshIronclawLatestResponse(for: conversationID)
            },
            showBanner: { [weak self] message in
                self?.showBanner(message)
            }
        )
    }

    private func restoreSelectedModel(from loadedMessages: [ChatMessage]) {
        guard let modelID = loadedMessages.reversed().first(where: { message in
            message.role == .assistant &&
                message.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        })?.model,
            chatModels.contains(where: { $0.id == modelID }),
            selectedModel != modelID else {
            return
        }
        selectedModel = modelID
    }

    private func refreshIronclawLatestResponse(for conversationID: String) async {
        let settings = ironclawSettingsForConversation(conversationID)
        let threadID = settings.threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !threadID.isEmpty else { return }

        do {
            guard settings.hasUsableHostedEndpoint else { return }
            guard let response = try await ironclawAPI.fetchLatestResponse(
                settings: settings,
                authToken: loadIronclawAuthToken(),
                threadID: threadID
            )?.trimmingCharacters(in: .whitespacesAndNewlines), !response.isEmpty else {
                return
            }
            guard selectedConversation?.id == conversationID else { return }
            guard !Self.isTransportOnlyGatewayText(response) else {
                if let index = messages.lastIndex(where: { $0.role == .assistant && $0.model == ModelOption.ironclawModelID }) {
                    messages[index].text = Self.gatewayStatusFailureMessage
                    messages[index].status = "failed"
                    messages[index].isStreaming = false
                    saveLocalMessages(for: conversationID)
                }
                return
            }

            if let failureMessage = Self.localFailureMessage(from: response) {
                if let index = messages.lastIndex(where: { $0.role == .assistant && $0.model == ModelOption.ironclawModelID }) {
                    messages[index].text = failureMessage
                    messages[index].status = "failed"
                    messages[index].isStreaming = false
                    saveLocalMessages(for: conversationID)
                }
                return
            }

            guard let index = messages.lastIndex(where: { $0.role == .assistant && $0.model == ModelOption.ironclawModelID }),
                  messages[index].text != response else {
                return
            }

            messages[index].text = response
            messages[index].status = "completed"
            messages[index].isStreaming = false
            saveLocalMessages(for: conversationID)
            showBanner("IronClaw output refreshed.")
        } catch {
            showBanner(Self.displayFailureMessage(error.localizedDescription))
        }
    }

    /// Seeds the composer with a widget's scoped follow-up question so the user
    /// can edit or send it. The conversation already carries the widget's answer
    /// as context, so the existing send flow handles the follow-up naturally.
    func composeWidgetFollowUp(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft = trimmed
        AppHaptics.selection()
    }

    func createTracker(fromWidgetAction action: WidgetActionItem) {
        guard let draft = action.appActionDraft() else {
            showBanner("This action cannot become a tracker yet.")
            return
        }
        guard draft.isReady else {
            let missing = draft.missingFields.prefix(3).joined(separator: ", ")
            showBanner("Add \(missing) before saving this tracker.")
            if let command = draft.command {
                self.draft = command
                AppHaptics.selection()
            }
            return
        }

        let briefing = Briefing(
            title: draft.title,
            prompt: draft.prompt,
            schedule: draft.schedule,
            kind: .customPrompt
        )
        onCreateTracker?(briefing)
        activityLog.record("Created tracker “\(draft.title)” from action card · \(draft.confirmation)")

        let sourceLine = draft.source.map { "\nSource: \($0)" } ?? ""
        let message = ChatLocalIntentTranscriptWriter.assistantMessage(
            text: "Created a tracker — **\(draft.confirmation)**. It runs on schedule and lands in Trackers; open it any time to Run now, change, or delete it.\(sourceLine)"
        )
        messages.append(message)
        if let conversationID = selectedConversation?.id {
            saveLocalMessages(for: conversationID)
        }
        showBanner("Tracker created.")
        AppHaptics.selection()
    }

    /// The agentic Daily Brief: active automations and their latest approved
    /// results, composed into one digest. Shared by the on-demand "brief me"
    /// intent and the scheduled .dailyBrief automation.
    private func briefDigestWidget() async -> MessageWidget? {
        let trackers = trackersProvider?() ?? []
        return BriefDigest.compose(trackers: trackers, market: [])
    }

    func runBriefing(_ briefing: Briefing) async -> BriefingRunOutcome {
        // Conditional trackers are gated: evaluate the threshold against live
        // data and only deliver on a met run, so the rest of the pipeline
        // (latestResult + notification) fires exactly when it should.
        if let condition = briefing.condition {
            return await runConditionalBriefing(briefing, condition: condition)
        }

        // The Daily Brief is a client-side digest of existing automation state.
        // Other non-conditional briefings, including legacy live-data kinds,
        // route through the model so facts, sources, and presentation are not
        // hardcoded in the app.
        if briefing.kind == .dailyBrief {
            guard let digest = await briefDigestWidget() else { return .quiet }
            return .delivered(digest)
        }

        // A council briefing runs several models + a synthesis on each scheduled
        // run; a plain one runs a single model.
        if briefing.council {
            return await runCouncilBriefing(briefing)
        }
        return await runSingleModelBriefing(briefing)
    }

    /// Evaluates a conditional tracker against live price data. The threshold
    /// gate is deterministic and local; fired-alert presentation routes through
    /// the model with a value-only metric fallback so notifications are not lost.
    /// Quiet checks are intentionally not logged so the log stays meaningful.
    private func runConditionalBriefing(_ briefing: Briefing, condition: BriefingCondition) async -> BriefingRunOutcome {
        // A "stock:" coinID prefix marks an equity alert (Yahoo); otherwise crypto.
        let isStock = condition.coinID.hasPrefix("stock:")
        let stockSymbol = isStock ? String(condition.coinID.dropFirst("stock:".count)) : ""
        let price: Double? = isStock
            ? await LiveDataService.stockUSDPrice(symbol: stockSymbol)
            : await LiveDataService.coinUSDPrice(coinID: condition.coinID)
        guard let price else {
            // Couldn't fetch — don't fire on missing data, but say why.
            return .failed("Could not fetch the current \(condition.symbol) price to check this alert. It will retry on the next run.")
        }
        guard condition.isSatisfied(by: price) else { return .quiet }
        let priceLabel = LiveDataService.usdPriceString(price)
        activityLog.record("Alert fired — \(condition.summary) (now \(priceLabel))")

        let prompt = """
        A scheduled alert fired.

        Alert: \(condition.summary)
        Checked value: \(priceLabel)
        Symbol: \(condition.symbol)

        Explain what happened concisely, include the checked value, and say what the next useful action is. If current context or sources are needed, use web search. Do not imply the app hardcoded the answer; present this as a model-routed alert follow-up based on the threshold check.
        """
        let alertBriefing = Briefing(
            title: "\(condition.symbol) alert",
            prompt: prompt,
            schedule: briefing.schedule,
            kind: .customPrompt,
            council: briefing.council
        )
        let modelOutcome = briefing.council
            ? await runCouncilBriefing(alertBriefing)
            : await runSingleModelBriefing(alertBriefing)
        if case let .delivered(modelWidget) = modelOutcome {
            return .delivered(modelWidget)
        }

        // The alert DID fire; even if the model follow-up failed, deliver the
        // deterministic threshold result so the notification is not lost.
        return .delivered(MessageWidget(
            kind: .metric,
            title: "\(condition.symbol) alert",
            time: "just now",
            metric: WidgetMetric(
                label: "\(condition.symbol) / USD",
                value: priceLabel,
                delta: condition.summary,
                trend: condition.comparator == .below ? .down : .up,
                caption: "alert triggered"
            )
        ))
    }

    private struct BriefingTextStreamResult {
        var text: String?
        var failureMessage: String?
    }

    /// One headless model turn → its full text, with private-model fallback when
    /// a selected route is temporarily blocked or unavailable.
    private func streamBriefingTextResult(
        model: String,
        prompt: String,
        conversationID: String,
        webSearchEnabled: Bool,
        attachments: [ChatAttachment] = []
    ) async -> BriefingTextStreamResult {
        var currentModel = model
        var unavailableModels = Set<String>()
        var lastFailureMessage: String?
        var fallbackHops = 0

        if !routeHealth.shouldAttempt(modelID: model) {
            let notice = routeHealth.restrictionNotice(for: Self.routeKind(forModelID: model))
            return BriefingTextStreamResult(text: nil, failureMessage: notice)
        }

        while true {
            final class TextSink: @unchecked Sendable { var text = "" }
            let sink = TextSink()
            let route = Self.routeKind(forModelID: currentModel)
            do {
                if Self.isExternalModel(currentModel) {
                    // Cloud/proxy model IDs are NOT valid on the private streamer.
                    // A proxy follow-up that lands here must hit the Cloud
                    // completion API, or it silently fails on the private route.
                    sink.text = try await cloudBriefingText(
                        modelID: currentModel,
                        prompt: prompt,
                        webSearchEnabled: webSearchEnabled,
                        attachments: attachments
                    )
                } else {
                    try await api.streamResponse(
                        model: currentModel,
                        text: prompt,
                        attachments: [],
                        conversationID: conversationID,
                        previousResponseID: nil,
                        webSearchEnabled: webSearchEnabled,
                        systemPrompt: activeSystemPrompt(memoryForModel: currentModel),
                        onEvent: { event in
                            switch event {
                            case let .textDelta(delta):
                                sink.text += delta
                            case let .itemDone(text):
                                if sink.text.isEmpty, let text { sink.text = text }
                            default:
                                break
                            }
                        }
                    )
                }
                routeHealth.recordSuccess(modelID: currentModel)
                diagnostics.recordSuccess(route: route, modelID: currentModel)
                let trimmed = sink.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return BriefingTextStreamResult(text: nil, failureMessage: "The model returned no visible output.")
                }
                return BriefingTextStreamResult(text: trimmed, failureMessage: nil)
            } catch {
                routeHealth.recordFailure(modelID: currentModel, error: error)
                diagnostics.record(route: route, modelID: currentModel, error: error)
                lastFailureMessage = Self.displayFailureMessage(error.localizedDescription)
                unavailableModels.insert(currentModel)
                guard !Self.isExternalModel(currentModel),
                      Self.isRecoverableModelError(error),
                      fallbackHops < 1,
                      !routeHealth.isTripped(Self.routeKind(forModelID: currentModel)),
                      let fallbackModel = preferredAvailableModel(excluding: unavailableModels),
                      fallbackModel != currentModel else {
                    return BriefingTextStreamResult(text: nil, failureMessage: lastFailureMessage)
                }
                fallbackHops += 1
                currentModel = fallbackModel
            }
        }
    }

    /// One headless model turn → its full text (nil on failure / empty output).
    private func streamBriefingText(
        model: String,
        prompt: String,
        conversationID: String,
        webSearchEnabled: Bool,
        attachments: [ChatAttachment] = []
    ) async -> String? {
        let result = await streamBriefingTextResult(
            model: model,
            prompt: prompt,
            conversationID: conversationID,
            webSearchEnabled: webSearchEnabled,
            attachments: attachments
        )
        return result.text
    }

    /// Renders briefing model output into a widget (structured if the model
    /// produced a near-widget block, else a generic text card).
    private func briefingWidget(from text: String, title: String) -> MessageWidget? {
        let extraction = MessageWidget.extract(from: text)
        if let widget = extraction.widget { return widget }
        let summary = extraction.cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return nil }
        return MessageWidget(kind: .generic, title: title, time: "just now", note: String(summary.prefix(600)))
    }

    private func runSingleModelBriefing(_ briefing: Briefing) async -> BriefingRunOutcome {
        let runModelID = effectiveDefaultModelID
        // Fail fast (zero network) while the route's breaker is open; the
        // backoff schedules the retry.
        if !routeHealth.shouldAttempt(modelID: runModelID),
           let notice = routeHealth.restrictionNotice(for: Self.routeKind(forModelID: runModelID)) {
            return .failed(notice)
        }
        // A cloud-routed run doesn't need (and must not depend on) a private
        // conversation — creating one fails exactly when the private session is
        // broken, which is when a cloud default model should still work.
        let conversationID: String
        if Self.isExternalModel(runModelID) {
            conversationID = ""
        } else if let conversation = try? await api.createConversation(title: briefing.title) {
            conversationID = conversation.id
        } else {
            return .failed("Could not start a private conversation for this run. Check your connection or sign in again, then run it now.")
        }
        let result = await streamBriefingTextResult(
            model: runModelID,
            prompt: briefing.prompt,
            conversationID: conversationID,
            webSearchEnabled: true,
            attachments: activeProjectContextAttachments
        )
        guard let text = result.text else {
            return .failed(result.failureMessage)
        }
        guard let widget = briefingWidget(from: text, title: briefing.title) else {
            return .failed("The model returned no usable output for this run.")
        }
        return .delivered(widget)
    }

    /// Answers a follow-up in a briefing thread by routing the question through
    /// the model with the delivery's text as context. Private route only,
    /// consistent with the app's privacy posture.
    /// Picks the model a briefing follow-up should use: the briefing's own
    /// route (first healthy council member for council briefings, else the
    /// effective default private model).
    private func briefingFollowUpModelID(for briefing: Briefing) -> String {
        if briefing.council,
           let healthyMember = defaultCouncilModelIDs().first(where: { routeHealth.shouldAttempt(modelID: $0) }) {
            return healthyMember
        }
        return effectiveDefaultModelID
    }

    func answerBriefingFollowUp(
        question: String,
        context: String,
        briefing: Briefing,
        viaProxyModelID: String? = nil
    ) async -> BriefingFollowUpResult {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else { return .failure(nil) }

        let followUpModelID = viaProxyModelID ?? briefingFollowUpModelID(for: briefing)
        // Tripped private route: don't burn a doomed call — fail with the
        // notice and carry the proxy option so the thread can offer one tap.
        if viaProxyModelID == nil,
           !routeHealth.shouldAttempt(modelID: followUpModelID),
           let notice = routeHealth.restrictionNotice(for: Self.routeKind(forModelID: followUpModelID)) {
            var failure = BriefingFollowUpResult.failure(notice)
            failure.proxyModelID = modelCatalogStore.preferredPrivacyProxyModel(nearCloudKeyConfigured: nearCloudKeyConfigured)
            return failure
        }

        // A Cloud/proxy follow-up doesn't need (and shouldn't depend on) a
        // private conversation — creating one would fail on a broken private
        // session, the exact case the proxy exists to work around.
        let conversationID: String
        if Self.isExternalModel(followUpModelID) {
            conversationID = ""
        } else if let conversation = try? await api.createConversation(title: "Briefing follow-up") {
            conversationID = conversation.id
        } else {
            return .failure("Could not create a briefing follow-up thread. Sign in again, then retry.")
        }
        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt: String
        if trimmedContext.isEmpty {
            prompt = trimmedQuestion
        } else {
            prompt = """
            Here is a briefing I received:

            \"\"\"
            \(trimmedContext)
            \"\"\"

            My follow-up: \(trimmedQuestion)

            Answer concisely. Use web search for anything time-sensitive and cite sources.
            """
        }
        let result = await streamBriefingTextResult(
            model: followUpModelID,
            prompt: prompt,
            conversationID: conversationID,
            webSearchEnabled: true,
            attachments: activeProjectContextAttachments
        )
        if let text = result.text {
            return .success(text: text)
        }
        var failure = BriefingFollowUpResult.failure(result.failureMessage)
        if viaProxyModelID == nil {
            failure.proxyModelID = modelCatalogStore.preferredPrivacyProxyModel(nearCloudKeyConfigured: nearCloudKeyConfigured)
        }
        return failure
    }

    /// Runs a council (several models in the default lineup) on the briefing
    /// prompt, then synthesizes one answer — the scheduled equivalent of the
    /// live Council. Falls back to a single model if fewer than two are usable.
    private func runCouncilBriefing(_ briefing: Briefing) async -> BriefingRunOutcome {
        // Members on a tripped route are skipped up front; with fewer than two
        // healthy members the run degrades to a single healthy model.
        let modelIDs = defaultCouncilModelIDs().filter { routeHealth.shouldAttempt(modelID: $0) }
        guard modelIDs.count > 1 else {
            return await runSingleModelBriefing(briefing)
        }
        guard let conversation = try? await api.createConversation(title: briefing.title) else {
            return .failed("Could not start a private conversation for this run. Check your connection or sign in again, then run it now.")
        }

        // Best-effort Live Activity for the council run: one step per model plus
        // a final synthesis step. Side-effect only — the returned widget below is
        // identical whether or not the Activity ever appears.
        let totalSteps = modelIDs.count + 1
        agentActivity.start(title: briefing.title, total: totalSteps)

        var responses: [(String, String)] = []
        var firstFailureMessage: String?
        var stepsDone = 0
        for modelID in modelIDs {
            let displayName = modelDisplayName(for: modelID)
            agentActivity.update(stage: "Asking \(displayName)", completed: stepsDone)
            let result = await streamBriefingTextResult(
                model: modelID,
                prompt: briefing.prompt,
                conversationID: conversation.id,
                webSearchEnabled: true,
                attachments: activeProjectContextAttachments
            )
            if let text = result.text {
                responses.append((displayName, text))
            } else if firstFailureMessage == nil {
                firstFailureMessage = result.failureMessage
            }
            stepsDone += 1
            agentActivity.update(stage: "Asking \(displayName)", completed: stepsDone)
        }
        guard let first = responses.first else {
            agentActivity.end()
            return .failed(firstFailureMessage)
        }
        guard responses.count > 1 else {
            agentActivity.end()
            guard let widget = briefingWidget(from: first.1, title: briefing.title) else {
                return .failed("The council returned no usable output for this run.")
            }
            return .delivered(widget)
        }

        agentActivity.update(stage: "Synthesizing", completed: modelIDs.count)
        let synthesisPrompt = CouncilStreamService.synthesisPrompt(
            originalPrompt: briefing.prompt,
            routedPrompt: briefing.prompt,
            responses: responses
        )
        let synthesized = await streamBriefingText(
            model: modelIDs.first ?? Self.defaultModelID,
            prompt: synthesisPrompt,
            conversationID: conversation.id,
            webSearchEnabled: false
        )
        agentActivity.update(stage: "Synthesizing", completed: totalSteps)
        agentActivity.end()
        guard let widget = briefingWidget(from: synthesized ?? first.1, title: briefing.title) else {
            return .failed("The council returned no usable output for this run.")
        }
        return .delivered(widget)
    }

    private func localIntentExecutionEnvironment() -> ChatLocalIntentExecutor.Environment {
        ChatLocalIntentExecutor.Environment(
            memoryStore: memoryStore,
            activityLog: activityLog,
            trackers: { [weak self] in self?.trackersProvider?() ?? [] },
            createTracker: { [weak self] briefing in self?.onCreateTracker?(briefing) },
            setPassiveMemoryEnabled: { [weak self] enabled in self?.passiveMemoryEnabled = enabled },
            setKeepDocumentsOnDevice: { [weak self] onDevice in self?.keepDocumentsOnDevice = onDevice },
            searchHistory: { [weak self] query in
                guard let self else { return [] }
                return ConversationHistorySearch.search(
                    query: query,
                    cache: self.loadLocalMessageCache(),
                    conversations: self.conversations
                )
            },
            scheduleReminder: { reminder in
                BriefingStore.schedulePersonalReminder(title: reminder.title, date: reminder.date)
            }
        )
    }

    /// Handles explicit app-control prompts locally, such as creating trackers,
    /// saving memory, or showing the user's current tracker digest.
    func handleQuickIntent(_ intent: QuickIntent, prompt: String) {
        let model = selectedModel
        messages.append(ChatLocalIntentTranscriptWriter.userMessage(text: prompt, model: model))

        func appendAssistant(text: String, widget: MessageWidget? = nil, streaming: Bool = false) -> String {
            ChatLocalIntentTranscriptWriter.appendAssistant(
                text: text,
                messages: &messages,
                widget: widget,
                streaming: streaming
            )
        }

        let priorUserText = messages.filter { $0.role == .user }.dropLast().last?.text
        if let result = ChatLocalIntentExecutor.execute(
            intent: intent,
            prompt: prompt,
            priorUserText: priorUserText,
            environment: localIntentExecutionEnvironment()
        ) {
            if let schedule = result.pendingNearAccountTrackerSchedule {
                pendingNearAccountTrackerSchedule = schedule
            }
            _ = appendAssistant(text: result.assistantText)
            if result.shouldHaptic {
                AppHaptics.selection()
            }
            return
        }

        switch intent {
        default:
            let id = appendAssistant(text: "", streaming: true)
            currentAssistantMessageID = id
            isStreaming = true
            // Track the fetch in streamTask so cancelStream() can stop it, and
            // bail after the await if cancelled so we don't overwrite the turn
            // cancelStream() already finalized.
            streamTask = Task { [weak self] in
                guard let self else { return }
                let widget = await ChatLocalIntentWidgetService.widget(for: intent) {
                    await self.briefDigestWidget()
                }
                guard !Task.isCancelled else { return }
                self.updateMessage(id) { message in
                    message.isStreaming = false
                    message.status = "completed"
                    if let widget {
                        message.widget = widget
                    } else {
                        message.text = ChatLocalIntentResponseFormatter.fetchFailed
                    }
                }
                self.currentAssistantMessageID = nil
                self.isStreaming = false
                self.streamTask = nil
            }
        }
    }

    /// Handles a compound local prompt if the dispatcher allows one. Data
    /// lookup compounds route through the model instead of this path.
    func handleCompoundIntent(_ intents: [QuickIntent], prompt: String) {
        let model = selectedModel
        messages.append(ChatLocalIntentTranscriptWriter.userMessage(text: prompt, model: model))
        let pendingID = ChatLocalIntentTranscriptWriter.appendAssistant(
            text: "Working on \(intents.count) lookups…",
            messages: &messages,
            streaming: true
        )
        currentAssistantMessageID = pendingID
        isStreaming = true

        // Best-effort Live Activity for the compound run. Side-effect only:
        // none of these calls affect the messages produced below.
        agentActivity.start(title: "Working on \(intents.count) lookups", total: intents.count)

        streamTask = Task { [weak self] in
            guard let self else { return }
            var produced = false
            var completed = 0
            for intent in intents {
                if Task.isCancelled { break }
                let widget = await ChatLocalIntentWidgetService.widget(for: intent) {
                    await self.briefDigestWidget()
                }
                guard !Task.isCancelled else { break }
                completed += 1
                self.agentActivity.update(stage: "Lookup \(completed) of \(intents.count)", completed: completed)
                guard let widget else { continue }
                produced = true
                let message = ChatLocalIntentTranscriptWriter.assistantMessage(
                    text: "",
                    widget: widget
                )
                self.messages.append(message)
            }
            guard !Task.isCancelled else {
                self.agentActivity.end()
                return
            }
            self.updateMessage(pendingID) { message in
                message.isStreaming = false
                message.status = "completed"
                message.text = produced ? "" : ChatLocalIntentResponseFormatter.compoundFetchFailed
            }
            if produced { self.messages.removeAll { $0.id == pendingID } }
            self.currentAssistantMessageID = nil
            self.isStreaming = false
            self.streamTask = nil
            self.agentActivity.end()
        }
    }

    func completePendingNearAccountTracker(account: String, schedule: BriefingSchedule, prompt: String) {
        pendingNearAccountTrackerSchedule = nil
        let model = selectedModel
        messages.append(ChatLocalIntentTranscriptWriter.userMessage(text: prompt, model: model))
        let result = ChatLocalIntentExecutor.completePendingNearAccountTracker(
            account: account,
            schedule: schedule,
            environment: localIntentExecutionEnvironment(),
            structured: true
        )
        messages.append(ChatLocalIntentTranscriptWriter.assistantMessage(
            text: result.assistantText
        ))
        if result.shouldHaptic {
            AppHaptics.selection()
        }
    }

    /// Passively records durable self-facts the user disclosed in an ordinary
    /// turn — no "remember" keyword needed. Silent by design (it never injects a
    /// chat reply) but logged to the activity log so the user can audit what was
    /// auto-learned, and stored as `.inferred` so recall labels it. Only genuinely
    /// new facts are logged; re-stating a known fact is a no-op.
    func captureInferredMemory(from text: String) {
        ChatLocalIntentExecutor.captureInferredMemory(
            from: text,
            memoryStore: memoryStore,
            activityLog: activityLog,
            isEnabled: passiveMemoryEnabled
        )
    }

    func sendDraft() {
        sendCoordinator.sendDraft()
    }

    func confirmHostedHandoff(_ preflight: HostedIronclawHandoffPreflight) {
        sendCoordinator.confirmHostedHandoff(preflight)
    }

    func cancelHostedHandoff() {
        sendCoordinator.cancelHostedHandoff()
    }

    func hostedHandoffPreflightIfNeeded(
        text: String,
        promptAttachments: [ChatAttachment]
    ) -> HostedIronclawHandoffPreflight? {
        agentStore.hostedHandoffPreflight(
            text: text,
            promptAttachments: promptAttachments,
            selectedModelID: selectedModel,
            promptNeedsHostedWorkstation: Self.promptNeedsRemoteWorkstation(text),
            projectDisclosure: projectStore.selectedHostedHandoffDisclosure
        )
    }

    func currentRouteReadinessIssue(
        for text: String,
        appendUserMessage: Bool = true
    ) -> RouteReadinessIssue? {
        let promptWantsCouncil = Self.promptRequestsCouncil(text)
        let councilRequested = appendUserMessage &&
            (isCouncilModeEnabled || councilModelIDs.count > 1 || promptWantsCouncil)
        let requestedCouncilIDs: [String]
        if councilRequested {
            if promptWantsCouncil, !isCouncilModeEnabled, councilModelIDs.count <= 1 {
                requestedCouncilIDs = defaultCouncilModelIDs()
            } else {
                requestedCouncilIDs = requestCouncilModelIDs(for: selectedModel)
            }
        } else {
            requestedCouncilIDs = []
        }

        return Self.routeReadinessIssue(
            selectedModelID: selectedModel,
            requestedCouncilModelIDs: requestedCouncilIDs,
            isCouncilRequested: councilRequested,
            nearCloudKeyConfigured: nearCloudKeyConfigured,
            hostedIronclawEndpointUsable: ironclawRemoteWorkstationAvailable,
            hostedIronclawEndpointMessage: hostedIronclawReadinessMessage
        )
    }

    private var hostedIronclawReadinessMessage: String? {
        if ironclawSettings.hasUsableHostedEndpoint, !ironclawSettings.isEnabled {
            return "Turn on Hosted IronClaw in Account before sending."
        }
        return ironclawSettings.endpointValidationMessage
    }

    func blockSendForRouteReadiness(_ issue: RouteReadinessIssue) {
        routeReadinessIssue = issue
        showBanner(issue.title)
    }

    private func sendResolvedDraft(
        text: String,
        promptAttachments: [ChatAttachment],
        pendingLargePasteTextsSnapshot: [String: String],
        pendingSharedFileURLsSnapshot: [String: URL]
    ) async {
        await sendCoordinator.sendResolvedDraftForBridge(
            text: text,
            promptAttachments: promptAttachments,
            pendingLargePasteTextsSnapshot: pendingLargePasteTextsSnapshot,
            pendingSharedFileURLsSnapshot: pendingSharedFileURLsSnapshot
        )
    }

    func cancelStream() {
        sendCoordinator.cancelStream()
    }

    /// One-tap disclosed retry of a restricted private turn via the privacy
    /// proxy. The user's selected model is unchanged.
    func acceptProxyRetry() {
        sendCoordinator.acceptProxyRetry()
    }

    func declineProxyRetry() {
        sendCoordinator.declineProxyRetry()
    }

    /// Manual "Try private now" — clears the private route's cooldown so the
    /// next send probes it immediately.
    func retryPrivateRouteNow() {
        routeHealth.resetRoute(.nearPrivate)
        showBanner("Private route re-enabled — the next message will try it.")
    }

    func stopWaitingForCouncil(batchID: String?) {
        guard let batchID, isStreaming else {
            return
        }
        let activeMessages = currentCouncilAssistantMessageIDs.compactMap { messageID in
            messages.first(where: { $0.id == messageID && $0.councilBatchID == batchID })
        }
        guard !activeMessages.isEmpty else {
            showBanner("That Council batch is not running.")
            return
        }
        if activeMessages.allSatisfy({ Self.isCouncilSynthesisModelID($0.model) }) {
            cancelStream()
            showBanner("Stopped Council synthesis.")
            return
        }
        councilStopRequestedBatchID = batchID
        showBanner("Stopping slow Council legs. Completed answers will be synthesized.")
    }

    func sendCouncilRoomFollowUp(_ text: String, batchID: String?, target: CouncilTarget) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isStreaming else {
            showBanner("Wait for the current run to finish first.")
            return
        }
        guard let conversation = selectedConversation else {
            showBanner("Open a Council conversation first.")
            return
        }

        let batchMessages = councilMessages(for: batchID)
        let modelIDs: [String]
        switch target {
        case .room:
            modelIDs = Self.councilBatchModelIDs(from: batchMessages, batchID: batchID)
        case let .model(id):
            modelIDs = [id]
        }
        guard !modelIDs.isEmpty else {
            showBanner("No Council model is available for this follow-up.")
            return
        }
        guard councilRoutesAreReady(modelIDs) else { return }

        let previousResponseID: String?
        let previousAnswer: String?
        switch target {
        case .room:
            previousResponseID = Self.latestCouncilResponseID(in: batchMessages)
            previousAnswer = nil
        case let .model(id):
            previousResponseID = Self.latestResponseID(in: batchMessages, modelID: id)
            previousAnswer = Self.latestAnswerText(in: batchMessages, modelID: id)
        }

        routeReadinessIssue = nil
        streamTask = Task { [weak self] in
            await self?.runCouncilRoomFollowUp(
                text: trimmed,
                target: target,
                conversation: conversation,
                modelIDs: modelIDs,
                previousResponseID: previousResponseID,
                previousAnswer: previousAnswer
            )
        }
    }

    func synthesizeCouncilBatch(batchID: String?) {
        guard let batchID else {
            showBanner("Open a Council batch first.")
            return
        }
        if isStreaming {
            stopWaitingForCouncil(batchID: batchID)
            return
        }
        guard let conversation = selectedConversation else {
            showBanner("Open a Council conversation first.")
            return
        }
        let batchMessages = councilMessages(for: batchID)
        let modelIDs = Self.councilBatchModelIDs(from: batchMessages, batchID: batchID)
        let successfulResults = Self.councilStreamResults(from: batchMessages, batchID: batchID)
        guard successfulResults.count > 1, !modelIDs.isEmpty else {
            showBanner("Need at least two completed Council answers to synthesize.")
            return
        }
        guard councilRoutesAreReady([successfulResults.first?.modelID ?? selectedModel]) else { return }

        let originalPrompt = Self.councilBatchPrompt(from: batchMessages) ?? "Synthesize this Council batch."
        routeReadinessIssue = nil
        streamTask = Task { [weak self] in
            guard let self else { return }
            self.isStreaming = true
            self.currentAssistantMessageID = nil
            self.currentCouncilAssistantMessageIDs = []
            let previousResponseID = Self.latestCouncilResponseID(in: batchMessages)
            defer {
                self.isStreaming = false
                self.currentAssistantMessageID = nil
                self.currentCouncilAssistantMessageIDs = []
                self.councilStopRequestedBatchID = nil
                self.streamTask = nil
            }
            await self.synthesizeCouncilTurn(
                prompt: originalPrompt,
                routedPrompt: originalPrompt,
                conversationID: conversation.id,
                previousResponseID: previousResponseID,
                batchID: batchID,
                modelIDs: modelIDs,
                successfulResults: successfulResults
            )
            self.saveLocalMessages(for: conversation.id)
            self.scheduleConversationListRefresh()
            self.showBanner("Council synthesis updated.")
        }
    }

    private func councilMessages(for batchID: String?) -> [ChatMessage] {
        guard let batchID, !batchID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return messages.filter { $0.councilBatchID == batchID }
    }

    private func councilRoutesAreReady(_ modelIDs: [String]) -> Bool {
        let needsNearCloud = modelIDs.contains { Self.routeKind(forModelID: $0) == .nearCloud }
        if needsNearCloud, !nearCloudKeyConfigured {
            showBanner("Connect NEAR AI Cloud in Account before asking that Council model.")
            return false
        }
        let needsHosted = modelIDs.contains { $0 == ModelOption.ironclawModelID }
        if needsHosted, !ironclawRemoteWorkstationAvailable {
            showBanner(hostedIronclawReadinessMessage ?? "Configure Hosted IronClaw before asking that Council model.")
            return false
        }
        return true
    }

    nonisolated static func councilBatchModelIDs(from messages: [ChatMessage], batchID: String?) -> [String] {
        CouncilStreamService.batchModelIDs(from: messages, batchID: batchID)
    }

    nonisolated static func councilBatchPrompt(from messages: [ChatMessage]) -> String? {
        CouncilStreamService.batchPrompt(from: messages)
    }

    nonisolated static func councilTargetedPrompt(
        text: String,
        modelDisplayName: String,
        previousAnswer: String? = nil
    ) -> String {
        CouncilStreamService.targetedPrompt(
            text: text,
            modelDisplayName: modelDisplayName,
            previousAnswer: previousAnswer
        )
    }

    private static func councilStreamResults(from messages: [ChatMessage], batchID: String) -> [CouncilStreamResult] {
        CouncilStreamService.streamResults(from: messages, batchID: batchID)
    }

    private static func latestCouncilResponseID(in messages: [ChatMessage]) -> String? {
        CouncilStreamService.latestCouncilResponseID(in: messages)
    }

    private static func latestResponseID(in messages: [ChatMessage], modelID: String) -> String? {
        CouncilStreamService.latestResponseID(in: messages, modelID: modelID)
    }

    private static func latestAnswerText(in messages: [ChatMessage], modelID: String) -> String? {
        CouncilStreamService.latestAnswerText(in: messages, modelID: modelID)
    }

    nonisolated private static func isCouncilSynthesisModelID(_ modelID: String?) -> Bool {
        CouncilStreamService.isSynthesisModelID(modelID)
    }

    func copySignedSnippet(for message: ChatMessage) {
        guard message.role == .assistant,
              !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showBanner("No assistant answer to sign.")
            return
        }

        do {
            let snippetMessages = signedSnippetMessages(endingAt: message)
            let data = try ConversationExportBuilder.signedTranscriptData(
                conversation: selectedConversation,
                messages: snippetMessages,
                context: signedTranscriptExportContext
            )
            guard let json = String(data: data, encoding: .utf8) else {
                showBanner("Could not encode signed snippet.")
                return
            }
            Clipboard.copy(json)
            showBanner("Device-signed snippet copied. Verifies export integrity, not answer truth; device key ID may link repeated exports.")
        } catch {
            showBanner(Self.displayFailureMessage(error.localizedDescription))
        }
    }

    private func signedSnippetMessages(endingAt message: ChatMessage) -> [ChatMessage] {
        guard let messageIndex = messages.firstIndex(where: { $0.id == message.id }) else {
            return [message]
        }

        var snippet: [ChatMessage] = []
        if let userIndex = messages[..<messageIndex].lastIndex(where: { $0.role == .user }) {
            snippet.append(messages[userIndex])
        }
        snippet.append(message)
        return snippet
    }

    func regenerateResponse(for message: ChatMessage) {
        sendCoordinator.regenerateResponse(for: message)
    }

    func editAndResend(_ message: ChatMessage, replacementText: String) {
        sendCoordinator.editAndResend(message, replacementText: replacementText)
    }

    typealias PromptSourcePrivacyOverride = ChatPromptSourcePrivacyOverride

    nonisolated static func promptSourcePrivacyOverride(
        for prompt: String,
        hasAttachments: Bool = false
    ) -> PromptSourcePrivacyOverride {
        RoutePlanner.promptSourcePrivacyOverride(for: prompt, hasAttachments: hasAttachments)
    }

    private func send(
        _ text: String,
        attachments: [ChatAttachment],
        previousResponseIDOverride: String? = nil,
        initiator: String? = nil,
        appendUserMessage: Bool = true
    ) async -> Bool {
        await sendCoordinator.sendForBridge(
            text,
            attachments: attachments,
            previousResponseIDOverride: previousResponseIDOverride,
            initiator: initiator,
            appendUserMessage: appendUserMessage
        )
    }

    private enum CouncilLegWaitEvent {
        case finished
        case firstToken
        case noTokenTimeout
    }

    private func streamCouncilLegWithNoTokenTimeout(
        modelID: String,
        text: String,
        attachments: [ChatAttachment],
        conversationID: String,
        previousResponseID: String?,
        initiator: String,
        assistantMessageID: String
    ) async throws {
        let timeoutSeconds = Self.councilLegNoTokenTimeoutSeconds
        try await withThrowingTaskGroup(of: CouncilLegWaitEvent.self) { group in
            group.addTask { @MainActor [weak self] in
                guard let self else { throw CancellationError() }
                try await self.streamResponse(
                    model: modelID,
                    text: text,
                    attachments: attachments,
                    conversationID: conversationID,
                    previousResponseID: previousResponseID,
                    initiator: initiator,
                    assistantMessageID: assistantMessageID
                )
                return .finished
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { throw CancellationError() }
                let startedAt = Date()
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    if self.messages.first(where: { $0.id == assistantMessageID })?.firstTokenAt != nil {
                        return .firstToken
                    }
                    if Date().timeIntervalSince(startedAt) >= timeoutSeconds {
                        return .noTokenTimeout
                    }
                }
                throw CancellationError()
            }

            while let event = try await group.next() {
                switch event {
                case .finished:
                    group.cancelAll()
                    return
                case .firstToken:
                    continue
                case .noTokenTimeout:
                    group.cancelAll()
                    throw CouncilStreamService.NoTokenTimeoutError(seconds: Int(timeoutSeconds.rounded()))
                }
            }
        }
    }

    func sendCouncilTurn(
        text: String,
        routedText: String,
        attachments: [ChatAttachment],
        conversation: ConversationSummary,
        modelIDs: [String],
        previousResponseID: String?,
        initiator: String
    ) async throws {
        let batchID = "council-\(UUID().uuidString)"
        let userMessage = ChatMessage(
            id: "local-user-\(UUID().uuidString)",
            role: .user,
            text: text,
            model: selectedModel,
            createdAt: Date(),
            status: "completed",
            responseID: nil,
            previousResponseID: previousResponseID,
            councilBatchID: batchID,
            isStreaming: false,
            attachments: attachments,
            metadata: currentUserMessageMetadata
        )
        let assistantMessages = modelIDs.enumerated().map { offset, modelID in
            let createdAt = Date().addingTimeInterval(Double(offset) * 0.01)
            return ChatMessage(
                id: "local-council-\(offset)-\(UUID().uuidString)",
                role: .assistant,
                text: "",
                model: modelID,
                createdAt: createdAt,
                status: "streaming",
                responseID: nil,
                previousResponseID: previousResponseID,
                councilBatchID: batchID,
                isStreaming: true,
                trustMetadata: assistantTrustMetadata(for: modelID, capturedAt: createdAt)
            )
        }
        let assistantIDByModel = zip(modelIDs, assistantMessages.map(\.id)).reduce(into: [String: String]()) { mapping, pair in
            if mapping[pair.0] == nil {
                mapping[pair.0] = pair.1
            }
        }

        currentAssistantMessageID = nil
        currentCouncilAssistantMessageIDs = assistantMessages.map(\.id)
        messages.append(userMessage)
        messages.append(contentsOf: assistantMessages)
        showBanner("LLM Council running \(modelIDs.count) models.")

        let outcome = await withTaskGroup(of: CouncilStreamResult.self, returning: CouncilRunOutcome.self) { group in
            var pendingModelIDs = modelIDs

            func enqueueModel(_ modelID: String) {
                guard let assistantID = assistantIDByModel[modelID] else { return }
                group.addTask { @MainActor [weak self] in
                    guard let self else {
                        return CouncilStreamResult(
                            modelID: modelID,
                            messageID: assistantID,
                            didComplete: false,
                            failureSummary: "The app released the request before it completed.",
                            errorKind: .transportError
                        )
                    }

                    // A tripped route fails the leg instantly with the
                    // restriction copy — no 30-40s doomed stream per member.
                    if !self.routeHealth.shouldAttempt(modelID: modelID),
                       let notice = self.routeHealth.restrictionNotice(for: Self.routeKind(forModelID: modelID)) {
                        await self.apply(
                            streamEvent: .failed(notice),
                            conversationID: conversation.id,
                            assistantMessageID: assistantID
                        )
                        return CouncilStreamResult(
                            modelID: modelID,
                            messageID: assistantID,
                            didComplete: false,
                            failureSummary: notice,
                            errorKind: CouncilStreamService.errorKind(forFailureSummary: notice)
                        )
                    }

                    do {
                        try Task.checkCancellation()
                        try await self.streamCouncilLegWithNoTokenTimeout(
                            modelID: modelID,
                            text: routedText,
                            attachments: attachments,
                            conversationID: conversation.id,
                            previousResponseID: previousResponseID,
                            initiator: initiator,
                            assistantMessageID: assistantID
                        )
                        self.finishAssistantMessage(assistantID)
                        self.routeHealth.recordSuccess(modelID: modelID)
                        return CouncilStreamResult(
                            modelID: modelID,
                            messageID: assistantID,
                            didComplete: true,
                            failureSummary: nil
                        )
                    } catch is CancellationError {
                        await self.apply(
                            streamEvent: .failed("Cancelled."),
                            conversationID: conversation.id,
                            assistantMessageID: assistantID
                        )
                        return CouncilStreamResult(
                            modelID: modelID,
                            messageID: assistantID,
                            didComplete: false,
                            failureSummary: "cancelled"
                        )
                    } catch {
                        self.routeHealth.recordFailure(modelID: modelID, error: error)
                        let errorKind = CouncilStreamService.errorKind(for: error)
                        let summary = Self.modelFailureSummary(error)
                        await self.apply(
                            streamEvent: .failed(summary),
                            conversationID: conversation.id,
                            assistantMessageID: assistantID
                        )
                        return CouncilStreamResult(
                            modelID: modelID,
                            messageID: assistantID,
                            didComplete: false,
                            failureSummary: summary,
                            errorKind: errorKind
                        )
                    }
                }
            }

            let initialTaskCount = min(Self.maxConcurrentCouncilStreams, pendingModelIDs.count)
            for _ in 0..<initialTaskCount {
                enqueueModel(pendingModelIDs.removeFirst())
            }

            group.addTask { @MainActor [weak self] in
                await self?.waitForCouncilStopSignal(batchID: batchID) ?? .stopSignal(batchID: batchID)
            }

            var collected: [CouncilStreamResult] = []
            var stoppedEarly = false
            while collected.count < modelIDs.count, let result = await group.next() {
                if result.isStopSignal {
                    stoppedEarly = true
                    group.cancelAll()
                    continue
                }
                collected.append(result)
                if !stoppedEarly, !pendingModelIDs.isEmpty {
                    enqueueModel(pendingModelIDs.removeFirst())
                }
            }
            group.cancelAll()
            return CouncilRunOutcome(results: collected, stoppedEarly: stoppedEarly)
        }

        try Task.checkCancellation()
        let results = outcome.results
        let successfulResults = results.filter { result in
            result.didComplete &&
                (messages.first(where: { $0.id == result.messageID })?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        }
        if successfulResults.count > 1 {
            await synthesizeCouncilTurn(
                prompt: text,
                routedPrompt: routedText,
                conversationID: conversation.id,
                previousResponseID: previousResponseID,
                batchID: batchID,
                modelIDs: modelIDs,
                successfulResults: successfulResults
            )
        }

        let failureCount = results.filter { !$0.didComplete }.count
        if outcome.stoppedEarly, successfulResults.count > 1 {
            showBanner("Council stopped waiting and synthesized \(successfulResults.count) answers.")
        } else if outcome.stoppedEarly, successfulResults.count == 1 {
            showBanner("Council stopped waiting with one usable answer.")
        } else if successfulResults.isEmpty {
            showBanner("No council model returned a usable answer.")
        } else if failureCount > 0 {
            showBanner("Council finished: \(successfulResults.count) answered, \(failureCount) failed.")
        } else {
            showBanner("Council finished with \(successfulResults.count) answers.")
        }
        // Council member + synthesis turns exist only locally (the server's
        // /items feed never returns them) — persist or they vanish on re-open.
        saveLocalMessages(for: conversation.id)
        scheduleConversationListRefresh()
    }

    private func runCouncilRoomFollowUp(
        text: String,
        target: CouncilTarget,
        conversation: ConversationSummary,
        modelIDs: [String],
        previousResponseID: String?,
        previousAnswer: String?
    ) async {
        isStreaming = true
        currentAssistantMessageID = nil
        currentCouncilAssistantMessageIDs = []
        defer {
            isStreaming = false
            currentAssistantMessageID = nil
            currentCouncilAssistantMessageIDs = []
            councilStopRequestedBatchID = nil
            streamTask = nil
        }

        do {
            switch target {
            case .room:
                try await sendCouncilTurn(
                    text: text,
                    routedText: text,
                    attachments: [],
                    conversation: conversation,
                    modelIDs: modelIDs,
                    previousResponseID: previousResponseID,
                    initiator: "council_room_followup"
                )
            case let .model(id):
                try await sendTargetedCouncilFollowUp(
                    text: text,
                    modelID: id,
                    conversation: conversation,
                    previousResponseID: previousResponseID,
                    previousAnswer: previousAnswer
                )
            }
            saveLocalMessages(for: conversation.id)
            scheduleConversationListRefresh()
        } catch is CancellationError {
            cancelStream()
        } catch {
            showBanner(Self.displayFailureMessage(error.localizedDescription))
        }
    }

    private func sendTargetedCouncilFollowUp(
        text: String,
        modelID: String,
        conversation: ConversationSummary,
        previousResponseID: String?,
        previousAnswer: String?
    ) async throws {
        let batchID = "council-target-\(UUID().uuidString)"
        let modelName = modelDisplayName(for: modelID)
        let userMessage = ChatMessage(
            id: "local-user-\(UUID().uuidString)",
            role: .user,
            text: "To \(modelName): \(text)",
            model: modelID,
            createdAt: Date(),
            status: "completed",
            responseID: nil,
            previousResponseID: previousResponseID,
            councilBatchID: batchID,
            isStreaming: false,
            metadata: currentUserMessageMetadata
        )
        let assistantID = "local-council-target-\(UUID().uuidString)"
        let assistantCreatedAt = Date().addingTimeInterval(0.01)
        let assistantMessage = ChatMessage(
            id: assistantID,
            role: .assistant,
            text: "",
            model: modelID,
            createdAt: assistantCreatedAt,
            status: "streaming",
            responseID: nil,
            previousResponseID: previousResponseID,
            councilBatchID: batchID,
            isStreaming: true,
            trustMetadata: assistantTrustMetadata(for: modelID, capturedAt: assistantCreatedAt)
        )
        messages.append(userMessage)
        messages.append(assistantMessage)
        currentCouncilAssistantMessageIDs = [assistantID]
        showBanner("Asking \(modelName).")

        do {
            try await streamCouncilLegWithNoTokenTimeout(
                modelID: modelID,
                text: Self.councilTargetedPrompt(
                    text: text,
                    modelDisplayName: modelName,
                    previousAnswer: previousAnswer
                ),
                attachments: [],
                conversationID: conversation.id,
                previousResponseID: previousResponseID,
                initiator: "council_room_targeted_followup",
                assistantMessageID: assistantID
            )
            finishAssistantMessage(assistantID)
            showBanner("\(modelName) answered.")
        } catch {
            await apply(
                streamEvent: .failed(Self.modelFailureSummary(error)),
                conversationID: conversation.id,
                assistantMessageID: assistantID
            )
            throw error
        }
    }

    private func waitForCouncilStopSignal(batchID: String) async -> CouncilStreamResult {
        while !Task.isCancelled {
            if councilStopRequestedBatchID == batchID {
                return .stopSignal(batchID: batchID)
            }
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                break
            }
        }
        return .stopSignal(batchID: batchID)
    }

    private func synthesizeCouncilTurn(
        prompt: String,
        routedPrompt: String,
        conversationID: String,
        previousResponseID: String?,
        batchID: String?,
        modelIDs: [String],
        successfulResults: [CouncilStreamResult]
    ) async {
        let resultByModel = successfulResults.reduce(into: [String: CouncilStreamResult]()) { mapping, result in
            if mapping[result.modelID] == nil {
                mapping[result.modelID] = result
            }
        }
        let responses = modelIDs.compactMap { modelID -> (String, String)? in
            guard let result = resultByModel[modelID],
                  let message = messages.first(where: { $0.id == result.messageID }),
                  !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return (modelDisplayName(for: modelID), message.text)
        }
        let councilSources = Self.uniqueSources(successfulResults.flatMap { result -> [WebSearchSource] in
            messages.first(where: { $0.id == result.messageID })?.sources ?? []
        })
        guard responses.count > 1 else { return }

        removeFailedCouncilSynthesisMessages(batchID: batchID)
        let synthesisID = "local-council-synthesis-\(UUID().uuidString)"
        let synthesisCreatedAt = Date().addingTimeInterval(0.2)
        let synthesisMessage = ChatMessage(
            id: synthesisID,
            role: .assistant,
            text: "",
            model: ModelOption.llmCouncilSynthesisModelID,
            createdAt: synthesisCreatedAt,
            status: "streaming",
            responseID: nil,
            previousResponseID: previousResponseID,
            councilBatchID: batchID,
            isStreaming: true,
            searchQuery: prompt,
            sources: councilSources,
            trustMetadata: assistantTrustMetadata(
                for: ModelOption.llmCouncilSynthesisModelID,
                webSearchUsed: !councilSources.isEmpty,
                capturedAt: synthesisCreatedAt
            )
        )
        currentCouncilAssistantMessageIDs.append(synthesisID)
        messages.append(synthesisMessage)

        // Synthesis routes to the first HEALTHY successful member (cloud legs
        // are immune to a tripped private route), else any healthy preferred
        // model. With no healthy route at all, fail fast with the retry hint.
        let synthesisModelID = successfulResults.first(where: { routeHealth.shouldAttempt(modelID: $0.modelID) })?.modelID
            ?? preferredAvailableModel(excluding: Set<String>()).flatMap { routeHealth.shouldAttempt(modelID: $0) ? $0 : nil }
        guard let synthesisModelID else {
            let notice = routeHealth.restrictionNotice(for: .nearPrivate)
                ?? "No healthy model route is available right now."
            await apply(
                streamEvent: .failed("\(notice) Tap “Synthesize again” to retry."),
                conversationID: conversationID,
                assistantMessageID: synthesisID
            )
            return
        }
        let synthesisPrompt = CouncilStreamService.synthesisPrompt(
            originalPrompt: prompt,
            routedPrompt: routedPrompt,
            responses: responses
        )
        var attemptsRemaining = 2
        while attemptsRemaining > 0 {
            attemptsRemaining -= 1
            do {
                try await streamResponse(
                    model: synthesisModelID,
                    text: synthesisPrompt,
                    attachments: [],
                    conversationID: conversationID,
                    previousResponseID: previousResponseID,
                    initiator: "llm_council_synthesis",
                    assistantMessageID: synthesisID
                )
                finishAssistantMessage(synthesisID)
                return
            } catch {
                // One automatic retry for transient transport drops (the
                // connection often dies right after three long member streams).
                if attemptsRemaining > 0, Self.isTransientTransportError(error), !Task.isCancelled {
                    updateMessage(synthesisID) { message in
                        message.text = ""
                        message.status = "streaming"
                        message.isStreaming = true
                    }
                    try? await Task.sleep(nanoseconds: Self.synthesisRetryDelayNanoseconds)
                    continue
                }
                await apply(
                    streamEvent: .failed("\(Self.modelFailureSummary(error)) Tap “Synthesize again” to retry."),
                    conversationID: conversationID,
                    assistantMessageID: synthesisID
                )
                return
            }
        }
    }

    private func removeFailedCouncilSynthesisMessages(batchID: String?) {
        guard let batchID else { return }
        let removableIDs = Set(messages.compactMap { message -> String? in
            guard message.councilBatchID == batchID,
                  Self.isCouncilSynthesisModelID(message.model),
                  message.status.lowercased() == "failed" else {
                return nil
            }
            return message.id
        })
        guard !removableIDs.isEmpty else { return }
        messages.removeAll { removableIDs.contains($0.id) }
        currentCouncilAssistantMessageIDs.removeAll { removableIDs.contains($0) }
    }

    /// Mutable for tests/harness: the pause before the single synthesis retry.
    nonisolated(unsafe) static var synthesisRetryDelayNanoseconds: UInt64 = 1_500_000_000

    private static func isTransientTransportError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return [.networkConnectionLost, .timedOut, .cannotConnectToHost, .networkConnectionLost].contains(urlError.code)
        }
        if case let APIError.status(code, message) = error {
            if [408, 502, 503, 504].contains(code) { return true }
            return message.lowercased().contains("response stream ended early")
        }
        return false
    }

    /// Lightweight, no-token probe of the private session: hits `/v1/users/me`
    /// with the stored session token. Succeeds only when the private route truly
    /// accepts the session, so a wallet login that returns a non-session token
    /// surfaces here (401/403) instead of being discovered on the first chat.
    /// Records the real outcome into `diagnostics`.
    @discardableResult
    func probePrivateSession() async -> ConnectionDiagnostics.Outcome? {
        guard !isProbingSession else { return diagnostics.lastPrivateOutcome }
        isProbingSession = true
        defer { isProbingSession = false }
        do {
            _ = try await api.fetchProfile()
            diagnostics.recordSuccess(route: .nearPrivate, modelID: "session-probe")
        } catch {
            diagnostics.record(route: .nearPrivate, modelID: "session-probe", error: error)
        }
        return diagnostics.lastPrivateOutcome
    }

    func streamResponseWithFallback(
        initialModel: String,
        text: String,
        attachments: [ChatAttachment],
        conversationID: String,
        previousResponseID: String?,
        initiator: String
    ) async throws -> String {
        var currentModel = initialModel
        var unavailableModels = Set<String>()
        var fallbackHops = 0

        if !routeHealth.shouldAttempt(modelID: initialModel),
           let notice = routeHealth.restrictionNotice(for: Self.routeKind(forModelID: initialModel)) {
            throw RouteHealthError.routeRestricted(notice)
        }

        while true {
            do {
                try await streamResponse(
                    model: currentModel,
                    text: text,
                    attachments: attachments,
                    conversationID: conversationID,
                    previousResponseID: previousResponseID,
                    initiator: initiator,
                    assistantMessageID: currentAssistantMessageID
                )
                routeHealth.recordSuccess(modelID: currentModel)
                diagnostics.recordSuccess(route: Self.routeKind(forModelID: currentModel), modelID: currentModel)
                return currentModel
            } catch {
                routeHealth.recordFailure(modelID: currentModel, error: error)
                diagnostics.record(route: Self.routeKind(forModelID: currentModel), modelID: currentModel, error: error)
                unavailableModels.insert(currentModel)
                // One fallback hop max: walking the whole catalog against a
                // restricted route amplified the very rate limit it hit.
                guard !Self.isExternalModel(currentModel),
                      Self.isRecoverableModelError(error),
                      fallbackHops < 1,
                      !routeHealth.isTripped(Self.routeKind(forModelID: currentModel)),
                      let fallbackModel = preferredAvailableModel(excluding: unavailableModels),
                      fallbackModel != currentModel else {
                    throw error
                }

                fallbackHops += 1
                selectedModel = fallbackModel
                updateCurrentExchange(to: fallbackModel)
                showBanner("\(modelDisplayName(for: currentModel)) stalled. Retrying with \(modelDisplayName(for: fallbackModel)).")
                currentModel = fallbackModel
            }
        }
    }

    private func streamResponse(
        model: String,
        text: String,
        attachments: [ChatAttachment],
        conversationID: String,
        previousResponseID: String?,
        initiator: String = "new_message",
        assistantMessageID: String? = nil
    ) async throws {
        if model == ModelOption.ironclawMobileModelID {
            try await streamIronclawMobileRuntime(
                text: text,
                attachments: attachments,
                conversationID: conversationID,
                previousResponseID: previousResponseID,
                assistantMessageID: assistantMessageID
            )
            return
        }

        if Self.routeKind(forModelID: model) == .nearCloud {
            let webContext = try await appWebGroundingContextIfNeeded(
                model: model,
                text: text,
                conversationID: conversationID,
                assistantMessageID: assistantMessageID
            )
            try await streamNearCloudModel(
                modelID: model,
                text: text,
                attachments: attachments,
                conversationID: conversationID,
                webContext: webContext,
                assistantMessageID: assistantMessageID
            )
            return
        }

        if model == ModelOption.ironclawModelID {
            let settings = ironclawSettingsForConversation(conversationID)
            guard settings.isEnabled, settings.hasUsableHostedEndpoint else {
                let message = settings.hasUsableHostedEndpoint
                    ? "Turn on Hosted IronClaw in Account before sending."
                    : settings.endpointValidationMessage ?? "Add a Hosted IronClaw URL first."
                throw APIError.status(0, message)
            }
            let webContext = try await appWebGroundingContextIfNeeded(
                model: model,
                text: text,
                conversationID: conversationID,
                assistantMessageID: assistantMessageID
            )
            let documentAttachments = attachments.filter { !$0.isLocalOnly }
            await attachmentStagingStore.ensureDocumentTextsAvailable(for: documentAttachments, using: fileService)
            try await ironclawAPI.streamPrompt(
                prompt: ironclawPrompt(for: text, attachments: attachments, webContext: webContext),
                attachments: attachments,
                settings: settings,
                authToken: loadIronclawAuthToken(),
                onResolvedThreadID: { [weak self] threadID in
                    self?.agentStore.rememberIronclawThreadID(threadID, for: conversationID)
                }
            ) { [weak self] event in
                await self?.apply(streamEvent: event, conversationID: conversationID, assistantMessageID: assistantMessageID)
            }
            return
        }

        try await api.streamResponse(
            model: model,
            text: text,
            attachments: attachments,
            conversationID: conversationID,
            previousResponseID: previousResponseID,
            webSearchEnabled: shouldEnableModelNativeWebTool(model: model, prompt: text),
            systemPrompt: activeSystemPrompt(memoryForModel: model),
            advancedParams: advancedModelParams,
            initiator: initiator,
            visibleOutputTimeout: visibleOutputTimeout(for: model)
        ) { [weak self] event in
            await self?.apply(streamEvent: event, conversationID: conversationID, assistantMessageID: assistantMessageID)
        }
    }

    /// Non-streaming Cloud completion for headless briefing runs and proxy
    /// follow-ups. Mirrors `streamNearCloudModel`'s routing but returns the text
    /// instead of applying stream events, so `streamBriefingTextResult` can use
    /// it for cloud/proxy model IDs that the private streamer can't serve.
    private func cloudBriefingText(
        modelID: String,
        prompt: String,
        webSearchEnabled: Bool,
        attachments: [ChatAttachment] = []
    ) async throws -> String {
        guard let apiKey = loadNearCloudAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw APIError.status(401, "Connect NEAR AI Cloud in Account to use \(modelDisplayName(for: modelID)).")
        }
        guard let cloudModelID = nearCloudUnderlyingModelID(for: modelID) else {
            throw APIError.status(400, "That NEAR AI Cloud model route is not valid.")
        }
        // Headless app web grounding, mirroring the live streamNearCloudModel
        // path: the completion API has no native search, and briefing/follow-up
        // prompts tell the model to cite current sources. Best-effort — a failed
        // search degrades to the no-web prompt instead of failing the run.
        var webContext: WebGroundingContext?
        if webSearchEnabled,
           let groundingPrompt = WebGroundingService.searchPrompt(for: prompt, priorUserTexts: []) {
            let searchMode = WebGroundingService.searchMode(for: groundingPrompt)
            webContext = try? await webGroundingService.search(
                for: groundingPrompt,
                preferNews: searchMode.prefersNews(
                    researchModeEnabled: false,
                    needsLiveWeb: Self.promptNeedsLiveWeb(groundingPrompt)
                )
            )
        }
        let webAugmentedPrompt: String
        if let webContext {
            webAugmentedPrompt = """
            \(prompt)

            Live web context supplied by the iOS app:
            \(webContext.promptSection)

            Use this search context for current facts and cite sources by name. Do not say you cannot browse; the app has already fetched the web context.
            """
        } else {
            webAugmentedPrompt = prompt
        }
        let documentAttachments = attachments.filter { !$0.isLocalOnly }
        await attachmentStagingStore.ensureDocumentTextsAvailable(for: documentAttachments, using: fileService)
        let finalPrompt = attachmentStagingStore.documentAugmentedPrompt(
            webAugmentedPrompt,
            question: prompt,
            attachments: documentAttachments
        )
        let response = try await api.fetchNearCloudChatCompletion(
            apiKey: apiKey,
            model: cloudModelID,
            prompt: finalPrompt,
            systemPrompt: nearCloudSystemPrompt(
                modelID: modelID,
                modelDisplayName: modelDisplayName(for: modelID),
                hasWebContext: webContext != nil
            ),
            advancedParams: advancedModelParams
        )
        return Self.cleanedNearCloudResponse(response)
    }

    private func streamNearCloudModel(
        modelID: String,
        text: String,
        attachments: [ChatAttachment],
        conversationID: String,
        webContext: WebGroundingContext?,
        assistantMessageID: String? = nil
    ) async throws {
        guard let apiKey = loadNearCloudAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw APIError.status(401, "Connect NEAR AI Cloud in Account to use \(modelDisplayName(for: modelID)).")
        }
        guard let cloudModelID = nearCloudUnderlyingModelID(for: modelID) else {
            throw APIError.status(400, "That NEAR AI Cloud model route is not valid.")
        }

        await apply(streamEvent: .reasoningStarted, conversationID: conversationID, assistantMessageID: assistantMessageID)
        let documentAttachments = attachments.filter { !$0.isLocalOnly }
        await attachmentStagingStore.ensureDocumentTextsAvailable(for: documentAttachments, using: fileService)
        let prompt = attachmentStagingStore.documentAugmentedPrompt(
            nearCloudPrompt(for: text, attachments: attachments, webContext: webContext),
            question: text,
            attachments: documentAttachments
        )
        let response = try await api.fetchNearCloudChatCompletion(
            apiKey: apiKey,
            model: cloudModelID,
            prompt: prompt,
            systemPrompt: nearCloudSystemPrompt(modelID: modelID, modelDisplayName: modelDisplayName(for: modelID), hasWebContext: webContext != nil),
            advancedParams: advancedModelParams
        )
        await apply(streamEvent: .textDelta(Self.cleanedNearCloudResponse(response)), conversationID: conversationID, assistantMessageID: assistantMessageID)
        await apply(streamEvent: .completed(responseID: nil), conversationID: conversationID, assistantMessageID: assistantMessageID)
    }

    private func streamIronclawMobileRuntime(
        text: String,
        attachments: [ChatAttachment],
        conversationID: String,
        previousResponseID: String?,
        assistantMessageID: String? = nil
    ) async throws {
        let promptAttachments = promptOnlyAttachments(from: attachments)
        let initialSnapshot = mobileWorkspaceSnapshot(
            conversationID: conversationID,
            promptAttachments: promptAttachments
        )
        let actionPlan = IronclawMobilePlanner.plan(prompt: text, snapshot: initialSnapshot)
        let toolResults = await executeIronclawMobileToolCalls(
            actionPlan.calls,
            conversationID: conversationID,
            promptAttachments: promptAttachments
        )
        if !toolResults.isEmpty {
            await apply(
                streamEvent: .textDelta(AgentStore.ironclawToolResultMarkdown(toolResults)),
                conversationID: conversationID,
                assistantMessageID: assistantMessageID
            )
        }

        if Self.promptNeedsRemoteWorkstation(text), ironclawRemoteWorkstationAvailable {
            updateCurrentExchange(to: ModelOption.ironclawModelID, shouldClearText: false)
            selectedModel = ModelOption.ironclawModelID
            let handoffMessage = """
            **Hosted IronClaw handoff**
            This needs hosted git/code/shell/research tools, so I am running it through Hosted IronClaw. Local iOS project actions above stay attached to this run.

            """
            await apply(streamEvent: .textDelta(handoffMessage), conversationID: conversationID, assistantMessageID: assistantMessageID)
            showBanner("IronClaw Mobile handed this to Hosted IronClaw.")
            do {
                try await streamResponse(
                    model: ModelOption.ironclawModelID,
                    text: text,
                    attachments: attachments,
                    conversationID: conversationID,
                    previousResponseID: nil,
                    assistantMessageID: assistantMessageID
                )
                return
            } catch {
                await apply(
                    streamEvent: .textDelta("\n\nHosted IronClaw failed: \(Self.displayFailureMessage(error.localizedDescription))"),
                    conversationID: conversationID,
                    assistantMessageID: assistantMessageID
                )
                throw error
            }
        }

        let webContext = try await appWebGroundingContextIfNeeded(
            model: ModelOption.ironclawMobileModelID,
            text: text,
            conversationID: conversationID,
            assistantMessageID: assistantMessageID
        )
        let documentAttachments = attachments.filter { !$0.isLocalOnly }
        await attachmentStagingStore.ensureDocumentTextsAvailable(for: documentAttachments, using: fileService)
        let mobileModelPrompt = attachmentStagingStore.documentAugmentedPrompt(
            AgentStore.normalizedIronclawPrompt(text),
            question: text,
            attachments: documentAttachments
        )
        var unavailableModels = Set<String>()
        var modelFailures: [String: String] = [:]

        while let baseModel = preferredIronclawBaseModel(excluding: unavailableModels) {
            // The agent's base models ride the private route; a tripped breaker
            // fails fast instead of walking every open-weight model.
            guard routeHealth.shouldAttempt(modelID: baseModel) else {
                let notice = routeHealth.restrictionNotice(for: Self.routeKind(forModelID: baseModel))
                    ?? "The private route is temporarily busy. Try again in a moment."
                throw APIError.status(403, notice)
            }
            do {
                try await ironclawMobileRuntime.streamTurn(
                    prompt: mobileModelPrompt,
                    attachments: attachments,
                    context: mobileProjectContext(promptAttachments: attachments),
                    baseModel: baseModel,
                    conversationID: conversationID,
                    previousResponseID: previousResponseID,
                    webSearchEnabled: shouldEnableModelNativeWebTool(
                        model: ModelOption.ironclawMobileModelID,
                        prompt: text,
                        appWebContext: webContext
                    ),
                    systemPrompt: activeSystemPrompt(memoryForModel: ModelOption.ironclawMobileModelID),
                    toolResults: toolResults,
                    webContext: webContext
                ) { [weak self] event in
                    await self?.apply(streamEvent: event, conversationID: conversationID, assistantMessageID: assistantMessageID)
                }
                return
            } catch {
                routeHealth.recordFailure(modelID: baseModel, error: error)
                unavailableModels.insert(baseModel)
                modelFailures[baseModel] = Self.modelFailureSummary(error)
                if Self.isModelPlanError(error) {
                    deniedOpenWeightModelIDs.insert(baseModel)
                }
                guard Self.isRecoverableModelError(error), !routeHealth.isTripped(Self.routeKind(forModelID: baseModel)) else {
                    throw error
                }
                guard preferredIronclawBaseModel(excluding: unavailableModels) != nil else {
                    let failureMessage = Self.openWeightFailureMessage(
                        modelFailures: modelFailures,
                        modelName: { [weak self] in self?.modelDisplayName(for: $0) ?? $0 }
                    )
                    if !toolResults.isEmpty {
                        await apply(
                            streamEvent: .textDelta("\n\nThe local iPhone actions completed, but \(failureMessage)"),
                            conversationID: conversationID,
                            assistantMessageID: assistantMessageID
                        )
                        return
                    }
                    throw APIError.status(403, failureMessage)
                }

                resetCurrentAssistantForRetry(preserving: AgentStore.ironclawToolResultMarkdown(toolResults))
                showBanner("IronClaw skipped \(modelDisplayName(for: baseModel)): \(Self.modelFailureSummary(error))")
            }
        }

        throw APIError.status(503, "IronClaw Mobile could not find an available open-weight NEAR Private model.")
    }

    private func appWebGroundingContextIfNeeded(
        model: String,
        text: String,
        conversationID: String,
        assistantMessageID: String? = nil
    ) async throws -> WebGroundingContext? {
        let currentGroundingPrompt = Self.webGroundingPrompt(from: text)
        guard let groundingPrompt = WebGroundingService.searchPrompt(
            for: currentGroundingPrompt,
            priorUserTexts: priorUserGroundingPrompts(excludingCurrentText: text)
        ) else {
            return nil
        }
        guard shouldUseAppWebGrounding(model: model, prompt: groundingPrompt) else {
            return nil
        }

        let query = WebGroundingService.query(from: groundingPrompt)
        await apply(streamEvent: .webSearchStarted(query: query), conversationID: conversationID, assistantMessageID: assistantMessageID)
        do {
            let searchMode = WebGroundingService.searchMode(for: groundingPrompt)
            let context = try await webGroundingService.search(
                for: groundingPrompt,
                preferNews: searchMode.prefersNews(
                    researchModeEnabled: researchModeEnabled,
                    needsLiveWeb: Self.promptNeedsLiveWeb(groundingPrompt)
                )
            )
            await apply(
                streamEvent: .webSearchCompleted(query: context.query, sources: context.sources),
                conversationID: conversationID,
                assistantMessageID: assistantMessageID
            )
            return context
        } catch {
            await apply(streamEvent: .webSearchCompleted(query: query, sources: []), conversationID: conversationID, assistantMessageID: assistantMessageID)
            throw APIError.status(0, "Web search failed before the model call: \(error.localizedDescription)")
        }
    }

    /// Prior prompts eligible to substitute for a low-signal follow-up's web
    /// query. Restricted to turns the user sent on non-private routes: a prompt
    /// deliberately asked on the private route must never be shipped to
    /// device-side search engines because a later "try again" needed a query.
    /// Messages without a recorded model are excluded for the same reason.
    private func priorUserGroundingPrompts(excludingCurrentText text: String) -> [String] {
        var userTexts = messages.compactMap { message -> String? in
            guard message.role == .user,
                  let model = message.model,
                  Self.routeKind(forModelID: model) != .nearPrivate else { return nil }
            return message.text
        }
        if userTexts.last == text {
            userTexts.removeLast()
        }
        return userTexts.map(Self.webGroundingPrompt(from:))
    }

    private static func webGroundingPrompt(from text: String) -> String {
        if let brief = AgentStore.agentMissionBrief(from: text) {
            return brief
        }
        return AgentStore.strippedAgentLaunchPrefix(from: text)
    }

    private func shouldEnableModelNativeWebTool(
        model: String,
        prompt: String,
        appWebContext: WebGroundingContext? = nil
    ) -> Bool {
        let privacyBlocksWeb = Self.promptSourcePrivacyOverride(for: prompt).blocksWeb
        let semantics = routingSemantics(for: Self.routeKind(forModelID: model))
        return ChatWebGroundingDecision.shouldEnableNativeWebTool(
            semantics: semantics,
            benefitsFromSearch: Self.promptBenefitsFromAppSearch(prompt),
            needsFreshFacts: Self.promptNeedsLiveWeb(prompt),
            privacyBlocksWeb: privacyBlocksWeb,
            appWebContextPresent: appWebContext != nil
        )
    }

    private func shouldUseAppWebGrounding(model: String, prompt: String) -> Bool {
        let route = Self.routeKind(forModelID: model)
        let semantics = routingSemantics(for: route)
        return ChatWebGroundingDecision.shouldUseAppGrounding(
            route: route,
            semantics: semantics,
            benefitsFromSearch: Self.promptBenefitsFromAppSearch(prompt),
            needsFreshFacts: Self.promptNeedsLiveWeb(prompt),
            privacyBlocksWeb: Self.promptSourcePrivacyOverride(for: prompt).blocksWeb,
            promptNeedsRemoteWorkstation: model == ModelOption.ironclawModelID && Self.promptNeedsRemoteWorkstation(prompt)
        )
    }

    private func ironclawPrompt(
        for text: String,
        attachments: [ChatAttachment],
        webContext: WebGroundingContext?
    ) -> String {
        let prompt = AgentStore.normalizedIronclawPrompt(text)
        let workstationInstructions = Self.ironclawWorkstationInstructions(for: prompt)
        let appContext = hostedIronclawContextSection(promptAttachments: promptOnlyAttachments(from: attachments))
        guard let webContext else {
            guard !workstationInstructions.isEmpty || !appContext.isEmpty else {
                return prompt
            }
            return """
            \(workstationInstructions)
            \(appContext)

            User request:
            \(prompt)
            """
        }
        let scopedWorkstationInstructions = workstationInstructions.isEmpty ? "" : """

        \(workstationInstructions)
        """
        let scopedAppContext = appContext.isEmpty ? "" : """

        \(appContext)
        """
        let date = Date.now.formatted(date: .complete, time: .omitted)
        return """
        Current date: \(date).
        \(scopedWorkstationInstructions)
        \(scopedAppContext)

        User request:
        \(prompt)

        \(webContext.promptSection)

        Instructions:
        - Use the app-side web results above as the live search context.
        - Do not say you cannot perform web searches; the search has already been performed by the app.
        - Cite concrete sources by title or domain when making current factual claims.
        - If the search context is insufficient, say exactly what is missing, then answer from available context.
        """
    }

    private func hostedIronclawContextSection(promptAttachments: [ChatAttachment]) -> String {
        ChatPromptContextBuilder.hostedIronclawContextSection(
            selectedProject: selectedProject,
            promptAttachments: promptAttachments,
            sourceModeDetail: sourceModeDetail,
            documentText: { [attachmentStagingStore] attachmentID in
                attachmentStagingStore.documentText(for: attachmentID)
            }
        )
    }

    private static func ironclawWorkstationInstructions(for prompt: String) -> String {
        guard promptNeedsRemoteWorkstation(prompt) else {
            return ""
        }
        return """
        IronClaw iOS coding-agent task.
        Please run the requested Hosted IronClaw task now.
        You MUST use hosted tools before answering. For git, code, shell, tests, files, repo setup, or filesystem requests, call shell, file, grep, or apply_patch first.
        When calling shell, pass the JSON parameter named command, singular, containing one shell script string.
        If a tool call fails because of parameter shape, retry the same turn with the corrected parameter before giving a final answer.
        Do not answer "I am not sure" when a local tool can be run. If a tool is unavailable, say exactly which local tool failed.
        Use shell for repo setup, file creation, git status, tests, and capability checks. Use grep/read_file/apply_patch for targeted inspection and edits when those tools are available.
        Keep hosted runs phone-safe and bounded: use shallow clones when cloning public repos, inspect before installing, prefer focused tests over full suites, wrap long commands with timeout when available, and stop to report if setup or tests look likely to exceed a few minutes.
        If the request asks for current research, news, citations, or web evidence, call nearai_web_search first. Do not use the http tool for web search; use it only when the user supplied a specific URL that must be fetched.
        Before editing a repo, inspect the tree and git status. After editing, run the smallest useful test/check and show git diff/status.
        Format the final answer for a phone screen: lead with Result, then concise sections for Evidence when research was used, Commands, Changed Files, Tests, Risk, and Next Actions. Wrap raw command output in fenced text blocks only when it helps.
        Do not commit or emphasize generated artifacts such as __pycache__, build folders, node_modules, DerivedData, or caches unless the user explicitly asks.
        Do not use http, GitHub, tool_install, package installers, external network, or IP probes unless the user explicitly asks for that class of work.
        If a credential is truly required, request the exact credential and continue after the credential gate resolves.
        """
    }

    

    func ensureConversation(for firstMessage: String, attachments: [ChatAttachment]) async throws -> ConversationSummary {
        if let selectedConversation {
            return selectedConversation
        }

        let title = Self.initialConversationTitle(from: firstMessage, attachments: attachments)
        var created = try await conversationStore.createConversation(title: title)
        if created.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            created.metadata = ConversationMetadata(title: title)
            conversationStore.insertOrReplace(created, atFront: true)
        }
        if selectedProjectID != nil {
            assign(conversationID: created.id, to: selectedProjectID)
        }
        return created
    }

    private static func initialConversationTitle(from firstMessage: String, attachments: [ChatAttachment]) -> String {
        if let agentMissionTitle = agentMissionConversationTitle(from: firstMessage) {
            return clippedTitle(agentMissionTitle)
        }

        let normalizedMessage = firstMessage
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedMessage.isEmpty else {
            if let firstAttachment = attachments.first, attachments.count == 1 {
                return clippedTitle("Review \(firstAttachment.name)")
            }
            if !attachments.isEmpty {
                return "Review \(attachments.count) files"
            }
            return "New conversation"
        }

        // Short greetings and conversational openers shouldn't become
        // literal titles ("hello", "hi", "what's up today?") — they don't
        // describe the topic. Use a placeholder and let the backend's
        // `titleUpdated` SSE event drop the real summary in once the
        // model answers.
        let lowered = normalizedMessage.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!,'\""))
        let greetingOpeners: Set<String> = [
            "hello", "hi", "hey", "hiya", "howdy", "yo",
            "sup", "wassup", "what's up", "whats up", "whatsup",
            "what's up today", "whats up today",
            "morning", "good morning", "good afternoon", "good evening",
            "gm", "gn", "lol"
        ]
        if greetingOpeners.contains(lowered) || lowered.count <= 3 {
            return "New chat"
        }

        let withoutInstructions = strippedStarterInstruction(from: normalizedMessage)
        let title = withoutInstructions.trimmingCharacters(in: CharacterSet(charactersIn: "#*` ").union(.whitespacesAndNewlines))
        return clippedTitle(title.isEmpty ? normalizedMessage : title)
    }

    private static func agentMissionConversationTitle(from text: String) -> String? {
        let missionMarkers = ["Hosted IronClaw Mission:", "Agent Mission:"]
        guard missionMarkers.contains(where: { text.localizedCaseInsensitiveContains($0) }) else {
            return nil
        }
        let lines = text.components(separatedBy: .newlines)
        let missionTitle = lines
            .first { line in
                missionMarkers.contains { line.range(of: $0, options: [.caseInsensitive]) != nil }
            }?
            .components(separatedBy: ":")
            .dropFirst()
            .joined(separator: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let brief = AgentStore.agentMissionBrief(from: text)
        if let missionTitle, !missionTitle.isEmpty,
           let brief, !brief.isEmpty {
            return "\(missionTitle): \(brief)"
        }
        if let brief, !brief.isEmpty {
            return brief
        }
        if let missionTitle, !missionTitle.isEmpty {
            return "Agent: \(missionTitle)"
        }
        return nil
    }

    private static func strippedStarterInstruction(from text: String) -> String {
        let separators = [
            "? Use ",
            ". Use ",
            "? Cite ",
            ". Cite ",
            "? Please ",
            ". Please ",
            "? Include ",
            ". Include "
        ]

        for separator in separators {
            if let range = text.range(of: separator, options: [.caseInsensitive]) {
                let punctuationEnd = text.index(after: range.lowerBound)
                let prefix = String(text[..<punctuationEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                if prefix.count >= 12 {
                    return prefix
                }
            }
        }
        return text
    }

    private static func clippedTitle(_ rawTitle: String, maxLength: Int = 64) -> String {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "New conversation" }
        guard title.count > maxLength else { return title }

        let prefix = String(title.prefix(maxLength))
        if let lastSpace = prefix.lastIndex(where: { $0 == " " }), prefix.distance(from: prefix.startIndex, to: lastSpace) > 24 {
            return String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return prefix.trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func apply(streamEvent event: ResponseStreamEvent, conversationID: String) async {
        await apply(streamEvent: event, conversationID: conversationID, assistantMessageID: currentAssistantMessageID)
    }

    private func apply(
        streamEvent event: ResponseStreamEvent,
        conversationID: String,
        assistantMessageID: String?
    ) async {
        guard ChatStreamEventGate.canApply(
            selectedConversationID: selectedConversation?.id,
            eventConversationID: conversationID
        ) else { return }
        messageTimelineStore.apply(
            streamEvent: event,
            conversationID: conversationID,
            assistantMessageID: assistantMessageID
        ) { [weak self] conversationID, title in
            self?.conversationStore.setTitle(title, for: conversationID)
        }
    }

    @discardableResult
    private func updateMessage(_ messageID: String, mutate: (inout ChatMessage) -> Void) -> Bool {
        messageTimelineStore.updateMessage(messageID, mutate: mutate)
    }

    private func finishAssistantMessage(_ messageID: String) {
        messageTimelineStore.finishAssistantMessage(messageID) { [weak self] message in
            self?.assistantTrustMetadata(
                for: message.model,
                webSearchUsed: !message.sources.isEmpty ? true : nil,
                capturedAt: message.createdAt
            )
        }
    }

    private func appendBufferedTextDelta(_ delta: String, to messageID: String) {
        messageTimelineStore.apply(
            streamEvent: .textDelta(delta),
            conversationID: selectedConversation?.id ?? "",
            assistantMessageID: messageID
        )
    }

    private func pendingTextDeltaFlushNanoseconds() -> UInt64 {
        Self.streamDeltaFlushNanoseconds
    }

    private func flushPendingTextDelta(for messageID: String) {
        messageTimelineStore.flushPendingTextDelta(for: messageID)
    }

    private func flushPendingTextDeltas() {
        // Delta buffering moved to MessageTimelineStore in Phase 8.
    }

    private func cancelPendingTextDeltaFlushes() {
        messageTimelineStore.cancelPendingTextDeltaFlushes()
    }

    func resolveIronclawApproval(
        messageID: String,
        approval: IronclawPendingGate,
        action: IronclawApprovalAction
    ) {
        guard !isStreaming else { return }
        streamTask = Task { [weak self] in
            await self?.resolveIronclawApprovalAction(messageID: messageID, approval: approval, action: action)
        }
    }

    func resolveIronclawCredential(
        messageID: String,
        approval: IronclawPendingGate,
        token: String
    ) {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isStreaming, !trimmedToken.isEmpty else { return }
        streamTask = Task { [weak self] in
            await self?.resolveIronclawCredentialAction(messageID: messageID, approval: approval, token: trimmedToken)
        }
    }

    private func resolveIronclawApprovalAction(
        messageID: String,
        approval: IronclawPendingGate,
        action: IronclawApprovalAction
    ) async {
        guard let conversationID = selectedConversation?.id else { return }
        isStreaming = true
        currentAssistantMessageID = messageID
        defer {
            isStreaming = false
            currentAssistantMessageID = nil
            streamTask = nil
        }

        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        let settings = ironclawSettingsForConversation(conversationID)

        messages[index].pendingApproval = nil
        messages[index].isStreaming = action != .deny
        messages[index].status = action == .deny ? "failed" : "reasoning"
        if action == .deny {
            messages[index].text = approval.isAuthenticationGate ?
                "Cancelled \(approval.authenticationDisplayName) authentication." :
                "Denied \(approval.toolName) approval."
        }
        saveLocalMessages(for: conversationID)

        do {
            try await ironclawAPI.resolveGate(
                settings: settings,
                authToken: loadIronclawAuthToken(),
                approval: approval,
                action: action
            )

            guard action != .deny else {
                showBanner(approval.isAuthenticationGate ? "IronClaw authentication cancelled." : "IronClaw approval denied.")
                saveLocalMessages(for: conversationID)
                return
            }

            await ironclawAPI.waitForThread(
                settings: settings,
                authToken: loadIronclawAuthToken(),
                threadID: approval.threadID,
                runID: approval.runID ?? ""
            ) { [weak self] event in
                await self?.apply(streamEvent: event, conversationID: conversationID)
            }

            guard selectedConversation?.id == conversationID else { return }
            if let resolvedIndex = messages.firstIndex(where: { $0.id == messageID }) {
                messages[resolvedIndex].isStreaming = false
                if messages[resolvedIndex].status != "failed", messages[resolvedIndex].status != "approval" {
                    messages[resolvedIndex].status = "completed"
                }
            }
            saveLocalMessages(for: conversationID)
        } catch {
            let displayError = Self.displayFailureMessage(error.localizedDescription)
            if let errorIndex = messages.firstIndex(where: { $0.id == messageID }) {
                messages[errorIndex].isStreaming = false
                messages[errorIndex].status = "failed"
                if messages[errorIndex].text.isEmpty {
                    messages[errorIndex].text = displayError
                }
            }
            showBanner(displayError)
            saveLocalMessages(for: conversationID)
        }
    }

    private func resolveIronclawCredentialAction(
        messageID: String,
        approval: IronclawPendingGate,
        token: String
    ) async {
        guard let conversationID = selectedConversation?.id else { return }
        isStreaming = true
        currentAssistantMessageID = messageID
        defer {
            isStreaming = false
            currentAssistantMessageID = nil
            streamTask = nil
        }

        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        let settings = ironclawSettingsForConversation(conversationID)

        messages[index].pendingApproval = nil
        messages[index].isStreaming = true
        messages[index].status = "reasoning"
        saveLocalMessages(for: conversationID)

        do {
            try await ironclawAPI.submitGateCredential(
                settings: settings,
                authToken: loadIronclawAuthToken(),
                approval: approval,
                token: token
            )

            await ironclawAPI.waitForThread(
                settings: settings,
                authToken: loadIronclawAuthToken(),
                threadID: approval.threadID,
                runID: approval.runID ?? ""
            ) { [weak self] event in
                await self?.apply(streamEvent: event, conversationID: conversationID)
            }

            guard selectedConversation?.id == conversationID else { return }
            if let resolvedIndex = messages.firstIndex(where: { $0.id == messageID }) {
                messages[resolvedIndex].isStreaming = false
                if messages[resolvedIndex].status != "failed", messages[resolvedIndex].status != "approval" {
                    messages[resolvedIndex].status = "completed"
                }
            }
            saveLocalMessages(for: conversationID)
        } catch {
            let displayError = Self.displayFailureMessage(error.localizedDescription)
            if let errorIndex = messages.firstIndex(where: { $0.id == messageID }) {
                messages[errorIndex].pendingApproval = approval
                messages[errorIndex].isStreaming = false
                messages[errorIndex].status = "approval"
                if messages[errorIndex].text.isEmpty {
                    messages[errorIndex].text = displayError
                }
            }
            showBanner(displayError)
            saveLocalMessages(for: conversationID)
        }
    }

    private func ironclawSettingsForConversation(_ conversationID: String) -> IronclawSettings {
        agentStore.ironclawSettings(for: conversationID)
    }

    private func withLoading(_ work: () async -> Void) async {
        isLoading = true
        defer { isLoading = false }
        await work()
    }

    private func updateDiagnostic(title: String, detail: String, state: AppDiagnosticCheck.State) {
        if let index = diagnosticChecks.firstIndex(where: { $0.title == title }) {
            diagnosticChecks[index].detail = detail
            diagnosticChecks[index].state = state
        } else {
            diagnosticChecks.append(AppDiagnosticCheck(title: title, detail: detail, state: state))
        }
    }

    func showBanner(_ message: String) {
        bannerMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if bannerMessage == message {
                bannerMessage = nil
            }
        }
    }

    private func loadAccountScopedState() {
        modelCatalogStore.configure(accountID: storageAccountID)
        agentStore.configure(accountID: storageAccountID)
        accountStore.configure(accountID: storageAccountID)
        soulPromptProfile = SoulPromptComposer.Profile.parse(soulMarkdown)
        conversationStore.configure(accountID: storageAccountID)
        messageRepository.configure(accountID: storageAccountID)
        messageLoadCoordinator.configure(accountID: storageAccountID)
        draftScopeStore.configure(accountID: storageAccountID)
        projectStore.configure(accountID: storageAccountID)
        projectStore.replaceConversations(conversations)
        messageTimelineStore.reset()
        transitionDraftScopeToCurrentSelection(loadDraft: true)

    }

    private var settingsPersistence: SettingsPersistence {
        SettingsPersistence(accountID: storageAccountID)
    }

    private var currentDraftScopeID: String {
        draftScopeStore.currentScopeID(
            selectedConversationID: selectedConversation?.id,
            selectedProjectID: selectedProjectID
        )
    }

    func transitionDraftScopeToCurrentSelection(loadDraft: Bool) {
        draftScopeStore.transition(to: currentDraftScopeID, loadDraft: loadDraft) { persistedState in
            draft = persistedState.text
            pendingAttachments = persistedState.attachments
            pendingLargePasteTexts = persistedState.pendingLargePasteTexts
            pendingDocumentTexts = persistedState.pendingDocumentTexts
        }
    }

    private func persistCurrentDraftIfNeeded() {
        let state = DraftPersistence.DraftState(
            text: draft,
            attachments: pendingAttachments,
            pendingLargePasteTexts: pendingLargePasteTexts,
            pendingDocumentTexts: pendingDocumentTexts
        )
        draftScopeStore.persistIfNeeded(state, isResettingAccountScopedState: isResettingAccountScopedState) {
            showBanner("Draft state could not be saved securely.")
        }
    }

    func discardActiveDraft() {
        draftScopeStore.removeCurrentScope()
    }

    private func loadIronclawAuthToken() -> String? {
        agentStore.loadIronclawAuthToken()
    }

    private func loadNearCloudAPIKey() -> String? {
        accountStore.loadNearCloudAPIKey()
    }

    private func loadLocalMessages(for conversationID: String) -> [ChatMessage]? {
        messageRepository.loadLocalMessages(for: conversationID)
    }

    func cachedConversationPreview(for conversationID: String) -> String? {
        messageRepository.cachedConversationPreview(
            for: conversationID,
            selectedConversationID: selectedConversation?.id,
            currentMessages: messages
        )
    }

    private func loadLocalMessageCache() -> [String: [ChatMessage]] {
        messageRepository.loadLocalMessageCache()
    }

    private func saveProjects() {
        projectStore.persistProjects()
    }

    func saveLocalMessages(for conversationID: String) {
        if !messageRepository.saveLocalMessages(messages, for: conversationID) {
            showBanner("Local message cache could not be saved securely.")
        }
    }

    private func removeLocalMessages(for conversationID: String) {
        if !messageRepository.removeLocalMessages(for: conversationID) {
            showBanner("Local message cache could not be updated securely.")
        }
        agentStore.removeIronclawThreadID(for: conversationID)
    }

    nonisolated static func isExternalModel(_ modelID: String) -> Bool {
        MessageRepository.isExternalModel(modelID)
    }

    nonisolated private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else {
                continue
            }
            output.append(trimmed)
        }
        return output
    }

    nonisolated static func promptNeedsLiveWeb(_ prompt: String) -> Bool {
        RoutePlanner.promptNeedsLiveWeb(prompt)
    }

    private static func promptRequestsCouncil(_ prompt: String) -> Bool {
        RoutePlanner.promptRequestsCouncil(prompt)
    }

    nonisolated static func promptNeedsRemoteWorkstation(_ prompt: String) -> Bool {
        RoutePlanner.promptNeedsRemoteWorkstation(prompt)
    }

    nonisolated static func modelAfterHostedAutoRoute(
        selectedModelID: String,
        text: String,
        hostedIronclawAvailable: Bool
    ) -> String {
        RoutePlanner.modelAfterHostedAutoRoute(
            selectedModelID: selectedModelID,
            text: text,
            hostedIronclawAvailable: hostedIronclawAvailable
        )
    }

    func phoneAgentMissionPromptIfNeeded(for text: String) -> String? {
        guard selectedModel == ModelOption.ironclawModelID || selectedModel == ModelOption.ironclawMobileModelID else {
            return nil
        }
        guard Self.promptNeedsRemoteWorkstation(text) else {
            return nil
        }
        return AgentStore.phoneAgentMissionPrompt(for: text)
    }

    func organizePhoneAgentConversationIfNeeded(
        conversation: ConversationSummary,
        originalText: String,
        routedText: String
    ) {
        guard selectedModel == ModelOption.ironclawModelID || selectedModel == ModelOption.ironclawMobileModelID else {
            return
        }
        guard Self.promptNeedsRemoteWorkstation(originalText) || Self.promptNeedsRemoteWorkstation(routedText) else {
            return
        }
        guard let detectedRepoURL = AgentStore.firstRepoURL(in: "\(originalText)\n\(routedText)"),
              let projectName = AgentStore.repoProjectName(from: detectedRepoURL) else {
            return
        }
        let repoRootURL = AgentStore.repoRootURL(from: detectedRepoURL) ?? detectedRepoURL

        let project: ChatProject
        if let selectedProject {
            project = selectedProject
            projectStore.assign(conversationID: conversation.id, to: selectedProject.id)
        } else {
            project = projectStore.ensureProject(named: projectName, includeConversationID: conversation.id)
        }

        projectStore.addLinkIfNeeded(
            projectID: project.id,
            title: projectName,
            urlString: repoRootURL.absoluteString
        )
        if detectedRepoURL.absoluteString != repoRootURL.absoluteString {
            projectStore.addLinkIfNeeded(
                projectID: project.id,
                title: AgentStore.repoTaskLinkTitle(from: detectedRepoURL, projectName: projectName),
                urlString: detectedRepoURL.absoluteString
            )
        }

        projectStore.updateInstructionsIfEmpty(
            projectID: project.id,
            instructions: "Repo-backed Agent Project. Use saved repo, issue, PR, and source links for follow-up research, code edits, tests, and triage for \(projectName)."
        )
    }

    private static func promptBenefitsFromAppSearch(_ prompt: String) -> Bool {
        let lowercased = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if promptNeedsLiveWeb(lowercased) {
            return true
        }
        let questionPrefixes = [
            "what did ",
            "what happened",
            "what has ",
            "what is ",
            "who is ",
            "who are ",
            "when did ",
            "where did ",
            "why did ",
            "how did ",
            "tell me about "
        ]
        return questionPrefixes.contains { lowercased.hasPrefix($0) }
    }

    private func preferredAvailableModel(excluding unavailableModel: String? = nil) -> String? {
        preferredAvailableModel(excluding: unavailableModel.map { Set([$0]) } ?? Set<String>())
    }

    func routeCurrentPromptIfNeeded(_ text: String, attachments: [ChatAttachment]) {
        let sourceOverride = Self.promptSourcePrivacyOverride(for: text, hasAttachments: !attachments.isEmpty)
        applyPromptSourcePrivacyOverride(sourceOverride)
        if !sourceOverride.requiresPrivateRoute {
            if modelCatalogStore.routeToHostedIronclawIfNeeded(
                text: text,
                hostedIronclawAvailable: ironclawRemoteWorkstationAvailable
            ) {
                return
            }
        }

        if !sourceOverride.requiresPrivateRoute, modelCatalogStore.routeCouncilIfNeeded(for: text) {
            return
        }

        guard !sourceOverride.blocksWeb else { return }
        _ = modelCatalogStore.routeToPrivateForNativeWebIfNeeded(
            text: text,
            shouldUseAppWebGrounding: shouldUseAppWebGrounding(model: selectedModel, prompt: text)
        )
    }

    func ensureSelectedModelIsAvailable(shouldShowBanner: Bool) {
        modelCatalogStore.ensureSelectedModelIsAvailable(shouldShowBanner: shouldShowBanner)
    }

    private func isCouncilEligible(_ model: ModelOption) -> Bool {
        modelCatalogStore.isCouncilEligible(model)
    }

    private func normalizedCouncilModels(from ids: [String]) -> [ModelOption] {
        modelCatalogStore.normalizedCouncilModels(from: ids)
    }

    private func normalizedCouncilModelIDs(_ ids: [String]) -> [String] {
        modelCatalogStore.normalizedCouncilModelIDs(ids)
    }

    private func canPreserveCouncilModelID(_ modelID: String) -> Bool {
        modelCatalogStore.canPreserveCouncilModelID(modelID)
    }

    private func normalizeCouncilSelection() {
        modelCatalogStore.normalizeCouncilSelection()
    }

    private func defaultCouncilModelIDs() -> [String] {
        modelCatalogStore.defaultCouncilModelIDs()
    }

    private static func model(_ model: ModelOption, matchesCandidateID candidateID: String) -> Bool {
        ModelCatalogStore.model(model, matchesCandidateID: candidateID)
    }

    func requestCouncilModelIDs(for requestModel: String) -> [String] {
        modelCatalogStore.requestCouncilModelIDs(for: requestModel)
    }

    private func preferredAvailableModel(excluding unavailableModels: Set<String>) -> String? {
        modelCatalogStore.preferredAvailableModel(excluding: unavailableModels)
    }

    private func preferredIronclawBaseModel(excluding unavailableModels: Set<String>) -> String? {
        let availableModels = chatModels.filter {
            $0.isOpenWeightCandidate && !deniedOpenWeightModelIDs.contains($0.id)
        }
        let availableIDs = Set(availableModels.map(\.id))
        let prioritizedIDs = ironclawOpenWeightPreferredModelIDs + rankedModels(from: availableModels).map(\.id)

        return prioritizedIDs.first { modelID in
            availableIDs.contains(modelID) &&
                !unavailableModels.contains(modelID)
        } ?? rankedModels(from: availableModels).first(where: { !unavailableModels.contains($0.id) })?.id
    }

    private func visibleOutputTimeout(for model: String) -> TimeInterval? {
        MessageStreamService.visibleOutputTimeout(for: model)
    }

    private func modelDisplayName(for modelID: String) -> String {
        chatModels.first(where: { $0.id == modelID })?.displayName ??
            modelID.split(separator: "/").last.map(String.init) ??
            modelID
    }

    private func nearCloudUnderlyingModelID(for modelID: String) -> String? {
        if let model = chatModels.first(where: { $0.id == modelID }),
           let cloudModelID = model.nearCloudUnderlyingModelID {
            return cloudModelID
        }
        guard modelID.hasPrefix(ModelOption.nearCloudModelPrefix) else { return nil }
        let cloudID = String(modelID.dropFirst(ModelOption.nearCloudModelPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cloudID.isEmpty ? nil : cloudID
    }

    private static func shouldMigrateStoredModel(_ modelID: String?) -> Bool {
        guard let modelID else { return false }
        let lowercased = modelID.lowercased()
        return lowercased == "openai/gpt-oss-120b" ||
            lowercased == "openai/gpt-5" ||
            lowercased == "openai/gpt-5.1" ||
            lowercased == "openai/gpt-5.2" ||
            lowercased == "openai/gpt-4.1" ||
            lowercased == "google/gemini-2.5-pro" ||
            lowercased == "anthropic/claude-opus-4-5" ||
            lowercased == "anthropic/claude-sonnet-4-5" ||
            lowercased.contains("/o3") ||
            lowercased.contains("/o4-mini") ||
            lowercased.contains("mini") ||
            lowercased.contains("nano") ||
            lowercased.contains("lite") ||
            lowercased.contains("flash")
    }

    private static func shouldUpgradeStoredFrontierModel(_ modelID: String?) -> Bool {
        guard let modelID else { return false }
        return [
            "openai/gpt-5",
            "openai/gpt-5.1",
            "openai/gpt-5.2",
            "openai/gpt-5.4"
        ].contains(modelID.lowercased())
    }

    private static func shouldMigrateClosedProviderModel(_ modelID: String?) -> Bool {
        guard let modelID else { return false }
        let lowercased = modelID.lowercased()
        guard !lowercased.hasPrefix("ironclaw/"),
              !lowercased.hasPrefix("openai/gpt-oss") else {
            return false
        }
        return lowercased.hasPrefix("openai/") ||
            lowercased.hasPrefix("anthropic/") ||
            lowercased.hasPrefix("google/") ||
            lowercased.hasPrefix("x-ai/") ||
            lowercased.hasPrefix("mistral/")
    }

    private func rankedModels(from source: [ModelOption]) -> [ModelOption] {
        modelCatalogStore.rankedModels(from: source)
    }

    private func updateCurrentExchange(to model: String, shouldClearText: Bool = true) {
        guard let currentAssistantMessageID,
              let assistantIndex = messages.firstIndex(where: { $0.id == currentAssistantMessageID }) else {
            return
        }

        messages[assistantIndex].model = model
        messages[assistantIndex].trustMetadata = assistantTrustMetadata(
            for: model,
            capturedAt: messages[assistantIndex].createdAt
        )
        if shouldClearText {
            messages[assistantIndex].text = ""
        }
        messages[assistantIndex].status = "streaming"
        messages[assistantIndex].isStreaming = true

        if assistantIndex > messages.startIndex {
            let userIndex = messages.index(before: assistantIndex)
            if messages[userIndex].role == .user {
                messages[userIndex].model = model
            }
        }
    }

    private func resetCurrentAssistantForRetry(preserving preservedText: String = "") {
        guard let currentAssistantMessageID,
              let index = messages.firstIndex(where: { $0.id == currentAssistantMessageID }) else {
            return
        }

        flushPendingTextDelta(for: currentAssistantMessageID)
        messages[index].text = preservedText
        messages[index].status = "streaming"
        messages[index].responseID = nil
        messages[index].isStreaming = true
        messages[index].searchQuery = nil
        messages[index].sources = []
        messages[index].pendingApproval = nil
    }

    private func executeIronclawMobileToolCalls(
        _ calls: [IronclawMobileToolCall],
        conversationID: String,
        promptAttachments: [ChatAttachment]
    ) async -> [IronclawMobileToolResult] {
        guard !calls.isEmpty else { return [] }

        var results: [IronclawMobileToolResult] = []
        for call in calls {
            switch call.name {
            case IronclawMobileToolNames.workspaceSnapshot:
                let snapshot = mobileWorkspaceSnapshot(
                    conversationID: conversationID,
                    promptAttachments: promptAttachments
                )
                results.append(IronclawMobileToolResult(
                    callName: call.name,
                    status: .completed,
                    summary: "Read the current iPhone Project/chat state.",
                    detail: snapshot.summary
                ))

            case IronclawMobileToolNames.runtimeCapabilities:
                results.append(IronclawMobileToolResult(
                    callName: call.name,
                    status: .completed,
                    summary: "Loaded the IronClaw Mobile capability manifest.",
                    detail: AgentStore.ironclawMobileCapabilityDetail
                ))

            case IronclawMobileToolNames.projectCreate:
                guard let name = call.arguments["name"], !name.isEmpty else {
                    results.append(.init(callName: call.name, status: .failed, summary: "Missing project name.", detail: nil))
                    continue
                }
                let project = ensureMobileProject(named: name, includeConversationID: conversationID)
                results.append(.init(
                    callName: call.name,
                    status: .completed,
                    summary: "Created or selected project \"\(project.name)\".",
                    detail: nil
                ))

            case IronclawMobileToolNames.projectSelect:
                guard let name = call.arguments["name"], !name.isEmpty else {
                    results.append(.init(callName: call.name, status: .failed, summary: "Missing project name.", detail: nil))
                    continue
                }
                guard let index = projectIndex(matching: name) else {
                    results.append(.init(callName: call.name, status: .failed, summary: "Project \"\(name)\" was not found.", detail: nil))
                    continue
                }
                _ = projectStore.selectProject(projects[index])
                results.append(.init(
                    callName: call.name,
                    status: .completed,
                    summary: "Selected project \"\(projects[index].name)\".",
                    detail: nil
                ))

            case IronclawMobileToolNames.projectAddPromptFiles:
                results.append(addPromptFilesToSelectedProject(promptAttachments))

            case IronclawMobileToolNames.projectAddLink:
                results.append(addProjectLinkFromIronclaw(call))

            case IronclawMobileToolNames.projectSetInstructions:
                results.append(setProjectInstructionsFromIronclaw(call))

            case IronclawMobileToolNames.projectUpdateMemory:
                results.append(updateProjectMemoryFromIronclaw(call))

            case IronclawMobileToolNames.projectSaveNote:
                results.append(saveProjectNoteFromIronclaw(call))

            case IronclawMobileToolNames.conversationMoveToProject:
                guard let projectName = call.arguments["project_name"], !projectName.isEmpty else {
                    results.append(.init(callName: call.name, status: .failed, summary: "Missing project name.", detail: nil))
                    continue
                }
                let allowCreate = call.arguments["create_if_missing"] == "true"
                let project: ChatProject
                if let index = projectIndex(matching: projectName) {
                    project = projects[index]
                } else if allowCreate {
                    project = ensureMobileProject(named: projectName, includeConversationID: nil)
                } else {
                    results.append(.init(callName: call.name, status: .failed, summary: "Project \"\(projectName)\" was not found.", detail: nil))
                    continue
                }
                assign(conversationID: conversationID, to: project.id)
                _ = projectStore.selectProject(project)
                results.append(.init(
                    callName: call.name,
                    status: .completed,
                    summary: "Moved this chat into project \"\(project.name)\".",
                    detail: nil
                ))

            case IronclawMobileToolNames.conversationRename:
                guard let title = call.arguments["title"], !title.isEmpty else {
                    results.append(.init(callName: call.name, status: .failed, summary: "Missing conversation title.", detail: nil))
                    continue
                }
                do {
                    try await conversationStore.renameConversation(id: conversationID, title: title)
                    await refreshConversations()
                    results.append(.init(
                        callName: call.name,
                        status: .completed,
                        summary: "Renamed this chat to \"\(title)\".",
                        detail: nil
                    ))
                } catch {
                    results.append(.init(
                        callName: call.name,
                        status: .failed,
                        summary: Self.displayFailureMessage(error.localizedDescription),
                        detail: nil
                    ))
                }

            case IronclawMobileToolNames.conversationPinSet:
                let pinned = call.arguments["pinned"] == "true"
                do {
                    try await conversationStore.setPinState(pinned, conversationID: conversationID)
                    await refreshConversations()
                    results.append(.init(
                        callName: call.name,
                        status: .completed,
                        summary: "\(pinned ? "Pinned" : "Unpinned") this chat.",
                        detail: nil
                    ))
                } catch {
                    results.append(.init(
                        callName: call.name,
                        status: .failed,
                        summary: Self.displayFailureMessage(error.localizedDescription),
                        detail: nil
                    ))
                }

            case IronclawMobileToolNames.conversationArchiveSet:
                let archived = call.arguments["archived"] == "true"
                do {
                    try await conversationStore.setArchiveState(archived, conversationID: conversationID)
                    await refreshConversations()
                    results.append(.init(
                        callName: call.name,
                        status: .completed,
                        summary: "\(archived ? "Archived" : "Unarchived") this chat.",
                        detail: nil
                    ))
                } catch {
                    results.append(.init(
                        callName: call.name,
                        status: .failed,
                        summary: Self.displayFailureMessage(error.localizedDescription),
                        detail: nil
                    ))
                }

            case IronclawMobileToolNames.webSearchSet:
                let enabled = call.arguments["enabled"] == "true"
                webSearchEnabled = enabled
                results.append(.init(
                    callName: call.name,
                    status: .completed,
                    summary: "Turned web search \(enabled ? "on" : "off").",
                    detail: nil
                ))

            case IronclawMobileToolNames.sourceModeSet:
                guard let rawMode = call.arguments["mode"],
                      let mode = ChatSourceMode(rawValue: rawMode) else {
                    results.append(.init(callName: call.name, status: .failed, summary: "Missing or invalid focus.", detail: nil))
                    continue
                }
                selectSourceMode(mode)
                results.append(.init(
                    callName: call.name,
                    status: .completed,
                    summary: "Set focus to \(sourceModeDetail).",
                    detail: nil
                ))

            case IronclawMobileToolNames.researchModeSet:
                let enabled = call.arguments["enabled"] == "true"
                researchModeEnabled = enabled
                results.append(.init(
                    callName: call.name,
                    status: .completed,
                    summary: "Turned research focus \(enabled ? "on" : "off").",
                    detail: nil
                ))

            default:
                results.append(.init(
                    callName: call.name,
                    status: .skipped,
                    summary: "This tool is not implemented in the iOS runtime yet.",
                    detail: nil
                ))
            }
        }
        return results
    }

    private func mobileWorkspaceSnapshot(
        conversationID: String,
        promptAttachments: [ChatAttachment]
    ) -> IronclawMobileWorkspaceSnapshot {
        IronclawMobileWorkspaceSnapshot(
            selectedConversationID: conversationID,
            selectedConversationTitle: selectedConversationTitle,
            selectedProjectID: selectedProjectID,
            selectedProjectName: selectedProject?.name,
            projects: projects.map { project in
                IronclawMobileWorkspaceSnapshot.Project(
                    id: project.id,
                    name: project.name,
                    conversationCount: project.conversationIDs.count,
                    fileNames: project.attachments.map(\.name),
                    linkCount: project.links.count,
                    noteCount: project.notes.count,
                    hasInstructions: !project.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    hasMemory: !project.memorySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            },
            visibleConversationTitles: visibleConversations.map(\.title),
            archivedConversationCount: archivedConversations.count,
            webSearchEnabled: routingSemantics(for: .ironclawMobile).modelNativeWebToolEnabledByDefault ||
                routingSemantics(for: .ironclawMobile).appWebGroundingPolicy.isEnabledByDefault,
            promptFileNames: promptAttachments.map(\.name)
        )
    }

    private func mobileProjectContext(promptAttachments: [ChatAttachment]) -> IronclawMobileProjectContext {
        ChatPromptContextBuilder.mobileProjectContext(
            selectedProject: selectedProject,
            selectedProjectAttachments: selectedProjectAttachments,
            promptAttachments: promptAttachments
        )
    }

    func promptOnlyAttachments(from attachments: [ChatAttachment]) -> [ChatAttachment] {
        let projectAttachmentIDs = Set(selectedProjectAttachments.map(\.id))
        return attachments.filter { !projectAttachmentIDs.contains($0.id) }
    }

    private func ensureMobileProject(named rawName: String, includeConversationID conversationID: String?) -> ChatProject {
        projectStore.ensureProject(named: rawName, includeConversationID: conversationID)
    }

    private func projectIndex(matching rawName: String) -> Int? {
        projectStore.projectIndex(matching: rawName)
    }

    private func addProjectLinkFromIronclaw(_ call: IronclawMobileToolCall) -> IronclawMobileToolResult {
        guard let rawURL = call.arguments["url"] else {
            return .init(callName: call.name, status: .failed, summary: "Missing or non-public HTTPS link URL.", detail: nil)
        }
        let title = call.arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ironclawResult(callName: call.name, projectResult: projectStore.addSourceLinkToSelectedProject(title: title, url: rawURL))
    }

    private func setProjectInstructionsFromIronclaw(_ call: IronclawMobileToolCall) -> IronclawMobileToolResult {
        let instructions = call.arguments["instructions"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ironclawResult(callName: call.name, projectResult: projectStore.setSelectedProjectInstructionsForTool(instructions))
    }

    private func updateProjectMemoryFromIronclaw(_ call: IronclawMobileToolCall) -> IronclawMobileToolResult {
        let memory = call.arguments["memory"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let shouldAppend = call.arguments["append"] != "false"
        return ironclawResult(callName: call.name, projectResult: projectStore.updateSelectedProjectMemoryForTool(memory, append: shouldAppend))
    }

    private func saveProjectNoteFromIronclaw(_ call: IronclawMobileToolCall) -> IronclawMobileToolResult {
        let text = call.arguments["text"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = call.arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ironclawResult(callName: call.name, projectResult: projectStore.saveToolNoteToSelectedProject(title: title, text: text))
    }

    private func addPromptFilesToSelectedProject(_ promptAttachments: [ChatAttachment]) -> IronclawMobileToolResult {
        let result = projectStore.addPromptFilesToSelectedProject(promptAttachments, maxAttachments: Self.maxProjectAttachments)
        return ironclawResult(
            callName: IronclawMobileToolNames.projectAddPromptFiles,
            projectResult: ProjectToolMutationResult(status: result.status, summary: result.summary, detail: result.detail)
        )
    }

    private func ironclawResult(callName: String, projectResult: ProjectToolMutationResult) -> IronclawMobileToolResult {
        let status: IronclawMobileToolResult.Status
        switch projectResult.status {
        case .failed:
            status = .failed
        case .skipped:
            status = .skipped
        case .completed:
            status = .completed
        }
        return .init(
            callName: callName,
            status: status,
            summary: projectResult.summary,
            detail: projectResult.detail
        )
    }

    func activeAttachments(promptAttachments: [ChatAttachment]) -> [ChatAttachment] {
        let baseAttachments = sourceRoutingSemantics.attachesProjectFileSourcePack
            ? selectedProjectAttachments + promptAttachments
            : promptAttachments
        var seen = Set<String>()
        return baseAttachments.filter { attachment in
            if seen.contains(attachment.id) {
                return false
            }
            seen.insert(attachment.id)
            return true
        }
    }

    private func currentAssistantTextIsEmpty() -> Bool {
        guard let currentAssistantMessageID,
              let index = messages.firstIndex(where: { $0.id == currentAssistantMessageID }) else {
            return true
        }
        return messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isRecoverableModelError(_ error: Error) -> Bool {
        isModelPlanError(error) || isModelAccessError(error) || isModelTimeoutError(error)
    }

    private static func modelFailureSummary(_ error: Error) -> String {
        if let urlError = error as? URLError,
           let mapped = MessageRepository.transportFailureMessage(urlError) {
            return mapped
        }
        let rawMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        let message = displayFailureMessage(rawMessage)
        let normalized = message.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return "request failed"
        }
        return String(normalized.prefix(180))
    }

    private static func openWeightFailureMessage(
        modelFailures: [String: String],
        modelName: (String) -> String
    ) -> String {
        let base = "No open-weight NEAR Private model returned a response for this turn."
        guard !modelFailures.isEmpty else {
            return "\(base) Refresh models or sign in again, then retry."
        }

        let details = modelFailures
            .sorted { lhs, rhs in lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending }
            .prefix(5)
            .map { "\(modelName($0.key)): \($0.value)" }
            .joined(separator: "; ")
        return "\(base) Tried \(details)."
    }

    private static func isModelPlanError(_ error: Error) -> Bool {
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        let lowercased = message.lowercased()
        return lowercased.contains("not available in your plan") ||
            lowercased.contains("model") && lowercased.contains("not available")
    }

    private static func isModelAccessError(_ error: Error) -> Bool {
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        let lowercased = message.lowercased()
        return lowercased.contains("access denied") ||
            lowercased.contains("temporarily restricted") ||
            lowercased.contains("forbidden") ||
            lowercased.contains("not authorized") ||
            lowercased.contains("permission") && lowercased.contains("model")
    }

    private static func isModelTimeoutError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.code == .timedOut || urlError.code == .networkConnectionLost
        }
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        let lowercased = message.lowercased()
        return lowercased.contains("timed out") ||
            lowercased.contains("timeout") ||
            lowercased.contains("still reasoning without visible output") ||
            lowercased.contains("network connection was lost")
    }

    static func localFailureMessage(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawMessage: String?
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            rawMessage = (object["error"] as? String) ?? (object["message"] as? String) ?? (object["detail"] as? String)
        } else if isRawToolFailureText(trimmed) {
            rawMessage = trimmed
        } else {
            rawMessage = nil
        }

        return rawMessage.map(displayFailureMessage)
    }

    private static func normalizedMessages(_ messages: [ChatMessage], assumingStreamLost: Bool) -> [ChatMessage] {
        MessageRepository.normalizedMessages(messages, assumingStreamLost: assumingStreamLost)
    }

    private static var gatewayStatusFailureMessage: String {
        "IronClaw accepted the request, but Hosted IronClaw only returned gateway status instead of a final answer. Start or repair the Agent connection, then retry."
    }

    private static var staleRunFailureMessage: String {
        "This run was interrupted or timed out before visible output arrived. Retry the message with a reachable model or Agent connection."
    }

    private static func isTransportOnlyGatewayText(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return normalized == "accepted" ||
            normalized == "running" ||
            normalized == "queued" ||
            (normalized.contains("accepted") && normalized.contains("gateway")) ||
            (normalized.contains("running") && normalized.contains("configured gateway"))
    }

    // Single source of failure copy: MessageRepository owns the raw-error →
    // user-facing mapping; this forwards so banner and timeline copy can't drift.
    static func displayFailureMessage(_ rawValue: String) -> String {
        MessageRepository.displayFailureMessage(rawValue)
    }

    private static func isRawToolFailureText(_ text: String) -> Bool {
        let lowercased = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowercased.isEmpty else { return false }
        return lowercased.contains("tool error") ||
            lowercased.contains("tool '") ||
            lowercased.contains("tool \"")
    }

    static func normalizedDraftInput(_ text: String) -> String {
        text
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(
                of: #"(^|[\s\(\[\{])(?:–|—|−)(?=[A-Za-z0-9])"#,
                with: "$1--",
                options: .regularExpression
            )
    }

    func activeSystemPromptForTesting(model: String? = nil) -> String {
        activeSystemPrompt(memoryForModel: model)
    }

    private func activeSystemPrompt(memoryForModel model: String? = nil) -> String {
        let route = model.map(RoutePlanner.routeKind(forModelID:)) ?? .nearCloud
        let soulPrompt = SoulPromptComposer.promptBlock(profile: soulPromptProfile, route: route)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let formatPrompt = SoulPromptComposer.markdownFormatContract.trimmingCharacters(in: .whitespacesAndNewlines)
        // Cap the user's advanced system-prompt field at source; MessageAPI
        // fences + re-caps the full composed block before it reaches the wire.
        let userPrompt = Self.clipped(
            systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            maxCharacters: 4_000
        )
        let modePrompt = ChatPromptContextBuilder.sourceModeInstructions(
            semantics: sourceRoutingSemantics,
            webSearchEnabled: webSearchEnabled
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        // Personal memory is injected ONLY for the private near.ai route — never
        // cloud, council cloud legs, or hosted/IronClaw routes — so on-device
        // facts never leave for a third-party cloud.
        let memoryAllowed = route == .nearPrivate
        let memoryPrompt = memoryAllowed
            ? (memoryStore.contextBlock()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            : ""
        let requestedPrompt = researchModeEnabled ? Self.researchModeInstructions(appendingTo: userPrompt) : userPrompt
        let basePrompt = [soulPrompt, formatPrompt, memoryPrompt, requestedPrompt, modePrompt]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard let project = selectedProject else {
            return basePrompt
        }
        guard sourceRoutingSemantics.attachesSavedLinkSourcePack ||
            sourceRoutingSemantics.attachesProjectFileSourcePack ||
            sourceRoutingSemantics.isResearch else {
            return basePrompt
        }

        let projectInstructions = project.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectMemory = project.memorySummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectLinks = shouldIncludeProjectLinksInPrompt ? project.links
            .filter { URL(string: $0.urlString).map(URLSecurity.isPublicHTTPSURL) == true }
            .prefix(12)
            .map { link in
                "- \(link.displayTitle): \(link.urlString)"
            }
            .joined(separator: "\n") : ""
        let projectNotes = ProjectService.projectNotesForPrompt(project.notes, allowLocalOnly: memoryAllowed)
            .prefix(6)
            .map { note in
                "- \(note.title): \(Self.clipped(note.text, maxCharacters: 900))"
            }
            .joined(separator: "\n")
        guard !projectInstructions.isEmpty || !projectMemory.isEmpty || !projectLinks.isEmpty || !projectNotes.isEmpty else {
            return basePrompt
        }

        var projectSections: [String] = []
        if !projectInstructions.isEmpty {
            projectSections.append("""
            Instructions:
            \(projectInstructions)
            """)
        }
        if !projectMemory.isEmpty {
            projectSections.append("""
            Memory:
            \(projectMemory)
            """)
        }
        if !projectLinks.isEmpty {
            projectSections.append("""
            Source links:
            \(projectLinks)
            """)
        }
        if !projectNotes.isEmpty {
            projectSections.append("""
            Saved notes:
            \(projectNotes)
            """)
        }
        let projectPrompt = """
        Project "\(project.name)" context:
        \(projectSections.joined(separator: "\n\n"))
        """
        guard !basePrompt.isEmpty else {
            return projectPrompt
        }
        return """
        \(basePrompt)

        \(projectPrompt)
        """
    }

    private var shouldIncludeProjectLinksInPrompt: Bool {
        guard selectedProject?.links.isEmpty == false else { return false }
        return sourceRoutingSemantics.attachesSavedLinkSourcePack
    }

    private static func researchModeInstructions(appendingTo userPrompt: String) -> String {
        let researchPrompt = """
        Research focus:
        - Prefer current information and call web search when available.
        - Start with the direct answer, then give dated evidence and source-backed reasoning.
        - Separate confirmed facts from inference.
        - End with a compact "Sources checked" section when sources are available.
        - If web tools are unavailable, say that clearly before answering from available context.
        """
        guard !userPrompt.isEmpty else {
            return researchPrompt
        }
        return """
        \(userPrompt)

        \(researchPrompt)
        """
    }

    private static func noteTitle(from text: String) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first?
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Saved output"
        let clippedTitle = String(firstLine.prefix(64)).trimmingCharacters(in: .whitespacesAndNewlines)
        return clippedTitle.isEmpty ? "Saved output" : clippedTitle
    }

    private static func clipped(_ text: String, maxCharacters: Int) -> String {
        ChatPromptContextBuilder.clipped(text, maxCharacters: maxCharacters)
    }

    private func nearCloudPrompt(
        for text: String,
        attachments: [ChatAttachment],
        webContext: WebGroundingContext?
    ) -> String {
        ChatPromptContextBuilder.nearCloudPrompt(
            text: text,
            attachments: attachments,
            webContext: webContext,
            messages: messages
        )
    }

    private func nearCloudSystemPrompt(modelID: String, modelDisplayName: String, hasWebContext: Bool) -> String {
        let userPrompt = activeSystemPrompt(memoryForModel: modelID)
        return ChatPromptContextBuilder.nearCloudSystemPrompt(
            modelDisplayName: modelDisplayName,
            hasWebContext: hasWebContext,
            userPrompt: userPrompt
        )
    }

    private static func cleanedNearCloudResponse(_ response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let lowercased = trimmed.lowercased()
        let looksLikeToolCall = lowercased.contains("default_api:web_search") ||
            lowercased.contains("<tool_call") ||
            lowercased.contains("</tool_call>") ||
            (lowercased.hasPrefix("call {") && lowercased.contains("web_search")) ||
            (lowercased.contains("\"call\"") && lowercased.contains("web_search"))

        guard looksLikeToolCall else { return trimmed }
        return "The NEAR AI Cloud model emitted tool-call markup instead of a normal answer. The iOS app handles web and project context before the model call; ask again and the route will use supplied context directly."
    }

    private static func chatMessages(from items: [ConversationItem], preferredResponseID: String? = nil) -> [ChatMessage] {
        MessageRepository.chatMessages(from: items, preferredResponseID: preferredResponseID)
    }

    private static func uniqueSources(_ sources: [WebSearchSource]) -> [WebSearchSource] {
        MessageRepository.uniqueSources(sources)
    }

    private static func inferredSources(from text: String) -> [WebSearchSource] {
        MessageRepository.inferredSources(from: text)
    }

    #if DEBUG
    #if canImport(UIKit)
    private var didStageReleaseGateFixture = false

    /// ReleaseGate seam: the system file picker cannot be driven headlessly,
    /// so a fixture PDF with a known sentinel is generated at runtime and
    /// attached through the REAL extraction + upload pipeline when the app is
    /// launched with -NEARReleaseGateFixture.
    func stageReleaseGateFixturePDF() async {
        guard !didStageReleaseGateFixture else { return }
        didStageReleaseGateFixture = true
        let body = """
        Hexagon Series B Term Sheet (Release Gate Fixture)

        Key verification fact: ZEPHYR-7 thermal margin is 42 percent.
        The raise is $4M on a $40M cap with a 1x non-participating preference.
        Obligations: monthly investor reporting; 60-day exclusivity window.
        """
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let data = renderer.pdfData { context in
            context.beginPage()
            body.draw(
                in: CGRect(x: 48, y: 48, width: 516, height: 700),
                withAttributes: [.font: UIFont.systemFont(ofSize: 14)]
            )
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("release-gate-term-sheet.pdf")
        try? data.write(to: url)
        await addAttachment(from: url)
    }
    #endif

    func prepareDemoCapture(screen: DemoCaptureScreen = .home) {
        cancelBackgroundOwners()
        isLoading = false
        isStreaming = false
        isUploadingAttachment = false
        bannerMessage = nil

        let data = Self.demoCaptureData(now: Date())
        models = data.models
        nearCloudModels = data.nearCloudModels
        projectStore.replaceProjects([data.project], persist: false)
        conversations = data.conversations
        fileStore.reset()
        securityStore.replaceAttestationSnapshot(data.attestation)
        ironclawSettings = IronclawSettings(
            isEnabled: true,
            baseURL: "https://ironclaw-demo.near.ai",
            threadID: "demo-thread-ironclaw-prs"
        )
        ironclawTokenConfigured = true
        ironclawStatusText = "Hosted IronClaw ready"
        ironclawLastVerifiedAt = Date().addingTimeInterval(-90)
        ironclawToolNames = ["read_files", "edit_code", "run_tests", "github"]
        nearCloudKeyConfigured = true
        billingSnapshot = nil
        routeReadinessIssue = nil
        attachmentStagingStore.resetAll()
        projectStore.selectProjectID(data.project.id, persist: false)
        selectedModel = Self.defaultModelID
        councilModelIDs = data.models
            .filter { !$0.isIronclawModel }
            .prefix(Self.maxCouncilModels)
            .map(\.id)
        webSearchEnabled = false
        sourceMode = .auto
        researchModeEnabled = false
        advancedModelParams = .defaults
        systemPrompt = ""
        soulMarkdown = ""

        switch screen {
        case .onboarding:
            selectedConversation = nil
            messages = []
            draft = ""
        case .login:
            selectedConversation = nil
            messages = []
            draft = ""
        case .home:
            selectedConversation = nil
            messages = []
            draft = ""
        case .fileAttach:
            selectedConversation = nil
            messages = []
            pendingAttachments = data.project.attachments
            sourceMode = .files
            draft = "Update this project plan based on the latest IronClaw PRs."
        case .composer:
            selectedConversation = nil
            messages = []
            projectStore.selectProjectID(nil, persist: false)
            pendingAttachments = []
            pendingSharedFileURLs = [:]
            councilModelIDs = [Self.defaultModelID]
            sourceMode = .auto
            webSearchEnabled = false
            draft = "Turn this screenshot or file into actions I can approve."
        case .agent:
            selectedConversation = nil
            messages = []
            selectedModel = ModelOption.ironclawModelID
            councilModelIDs = []
            sourceMode = .all
            draft = "Use the attached project plan and latest nearai/ironclaw PRs to update the plan."
        case .ironclaw:
            selectedConversation = data.agentConversation
            messages = data.agentMessages
            selectedModel = ModelOption.ironclawModelID
            councilModelIDs = []
            sourceMode = .all
            draft = ""
        case .ironclawThinking:
            selectedConversation = data.agentConversation
            messages = data.agentMessages
            selectedModel = ModelOption.ironclawModelID
            councilModelIDs = []
            sourceMode = .all
            draft = ""
        case .glmResult:
            selectedConversation = data.glmConversation
            messages = data.glmMessages
            selectedModel = Self.defaultModelID
            councilModelIDs = []
            projectStore.selectProjectID(nil, persist: false)
            sourceMode = .web
            webSearchEnabled = true
            draft = ""
        case .verification:
            selectedConversation = data.glmConversation
            messages = data.glmMessages
            selectedModel = Self.defaultModelID
            councilModelIDs = []
            projectStore.selectProjectID(nil, persist: false)
            draft = ""
        case .models:
            selectedConversation = data.glmConversation
            messages = data.glmMessages
            selectedModel = Self.defaultModelID
            councilModelIDs = []
            projectStore.selectProjectID(nil, persist: false)
            draft = ""
        case .widgets:
            selectedConversation = data.glmConversation
            messages = Self.demoWidgetMessages(now: Date())
            selectedModel = Self.defaultModelID
            councilModelIDs = []
            projectStore.selectProjectID(nil, persist: false)
            sourceMode = .web
            webSearchEnabled = true
            draft = ""
        case .generativeChat:
            // Drives the REAL prompt through normal send routing. Override the
            // prompt with NEAR_DEMO_PROMPT to capture a specific chat flow.
            selectedConversation = data.primaryConversation
            projectStore.selectProjectID(nil, persist: false)
            messages = []
            draft = DemoCapture.demoPrompt ?? "What should I track from this project plan every morning?"
            sendDraft()
        case .chatStarters:
            // Empty new chat with council off so the default live-data starter
            // chips show current data/tracker examples without seeding Home.
            selectedConversation = nil
            projectStore.selectProjectID(nil, persist: false)
            messages = []
            councilModelIDs = [Self.defaultModelID]
            selectedModel = Self.defaultModelID
            draft = ""
        case .councilBriefingLive:
            // Runs a REAL scheduled council briefing against the backend using an
            // env-injected session token (DebugBackend). Verifies end-to-end that
            // "using council" trackers do real multi-model work on a schedule.
            selectedConversation = nil
            projectStore.selectProjectID(nil, persist: false)
            messages = []
            draft = ""
            if !didStartLiveCouncilDemo {
                didStartLiveCouncilDemo = true
                Task { @MainActor [weak self] in
                    await self?.runLiveCouncilBriefingDemo()
                }
            }
        case .chatFailure:
            // Failure-state QA surface: one successful turn next to a failed
            // turn, so proof/action affordances can be compared side by side.
            selectedConversation = data.glmConversation
            messages = Self.demoFailureMessages(now: Date())
            selectedModel = Self.defaultModelID
            councilModelIDs = []
            projectStore.selectProjectID(nil, persist: false)
            draft = ""
        case .trackerFailure, .markdownGallery:
            selectedConversation = nil
            messages = []
            draft = ""
        case .chat, .briefingBuilder, .councilOutput, .cloudModels, .council, .councilRoom, .threaded, .liveData, .project, .share:
            selectedConversation = data.primaryConversation
            messages = data.messages
            draft = ""
        }
    }

    #if DEBUG
    /// Drives a real scheduled council briefing against the backend (token via
    /// DebugBackend) and renders its synthesized result inline for verification.
    @MainActor
    private func runLiveCouncilBriefingDemo() async {
        if let key = DebugBackend.cloudKey {
            saveNearCloudAPIKey(key)
        }
        // Load real models directly. NOT bootstrap() — it short-circuits to
        // prepareDemoCapture in demo mode, which would re-enter this case and
        // recursively spawn runs (the source of the earlier 502 storm).
        await refreshModels(loadCloudCatalog: nearCloudKeyConfigured)
        selectedConversation = ConversationSummary(
            id: "live-council-demo",
            createdAt: Date().timeIntervalSince1970,
            metadata: ConversationMetadata(title: "Council briefing")
        )
        messages = [
            ChatMessage(
                id: "live-council-user",
                role: .user,
                text: "Set up a daily briefing that summarizes today's most important AI developments — using council.",
                model: nil,
                createdAt: Date(),
                status: "completed",
                responseID: nil,
                isStreaming: false
            ),
            ChatMessage(
                id: "live-council-pending",
                role: .assistant,
                text: "Running the council…",
                model: ModelOption.llmCouncilSynthesisModelID,
                createdAt: Date(),
                status: "searching",
                responseID: nil,
                isStreaming: true
            )
        ]
        let briefing = Briefing(
            title: "AI briefing",
            prompt: "In 3 short bullets, summarize today's most important AI developments. Keep it under 100 words total.",
            schedule: .daily(hour: 8, minute: 0),
            kind: .customPrompt,
            council: true
        )
        let outcome = await runBriefing(briefing)
        updateMessage("live-council-pending") { message in
            message.isStreaming = false
            message.status = "completed"
            if case let .delivered(widget) = outcome {
                message.widget = widget
                message.text = ""
            } else {
                message.text = "Council produced no result — check sign-in, models, or network."
            }
        }
    }

    /// One successful answer (proof footer + actions) followed by a failed turn
    /// (red Failed + Retry only) — the canonical trust-surface contrast.
    static func demoFailureMessages(now: Date) -> [ChatMessage] {
        [
            ChatMessage(
                id: "df-u1",
                role: .user,
                text: "Summarize this term sheet and extract the obligations.",
                model: nil,
                createdAt: now.addingTimeInterval(-300),
                status: "completed",
                responseID: nil,
                isStreaming: false
            ),
            ChatMessage(
                id: "df-a1",
                role: .assistant,
                text: "Short version: a $4M raise on a $40M cap, 1x non-participating preference, monthly reporting, and a 60-day exclusivity window. The binding obligations sit in sections 4 and 7.",
                model: Self.defaultModelID,
                createdAt: now.addingTimeInterval(-295),
                status: "completed",
                responseID: "df-a1-r",
                isStreaming: false
            ),
            ChatMessage(
                id: "df-u2",
                role: .user,
                text: "Turn those obligations into a checklist with owners.",
                model: nil,
                createdAt: now.addingTimeInterval(-60),
                status: "completed",
                responseID: nil,
                isStreaming: false
            ),
            ChatMessage(
                id: "df-a2",
                role: .assistant,
                text: "The private route is temporarily busy. Use the privacy proxy for this turn, or retry private in a moment.",
                model: Self.defaultModelID,
                createdAt: now.addingTimeInterval(-55),
                status: "failed",
                responseID: nil,
                isStreaming: false
            )
        ]
    }

    static func demoWidgetMessages(now: Date) -> [ChatMessage] {
        func user(_ id: String, _ text: String, _ offset: TimeInterval) -> ChatMessage {
            ChatMessage(id: id, role: .user, text: text, model: nil, createdAt: now.addingTimeInterval(offset), status: "completed", responseID: nil, isStreaming: false)
        }
        func assistant(_ id: String, _ text: String, _ offset: TimeInterval, widget: MessageWidget) -> ChatMessage {
            ChatMessage(id: id, role: .assistant, text: text, model: Self.defaultModelID, createdAt: now.addingTimeInterval(offset), status: "completed", responseID: "\(id)-r", isStreaming: false, widget: widget)
        }
        return [
            user("dw-u1", "What's in today's news?", -600),
            assistant("dw-a1", "Three stories leading today, weighted to what you track.", -595, widget: .demoNewsBrief),
            user("dw-u2", "Compare SEV-SNP and TDX for our TEE.", -420),
            assistant("dw-a2", "Both give you memory encryption and attestation; they differ on isolation and live migration.", -415, widget: .demoComparison),
            user("dw-u3", "How's ETH doing right now?", -300),
            assistant("dw-a3", "ETH slipped below your $3,180 threshold in the last hour.", -295, widget: .demoChart)
        ]
    }
    #endif

    private struct DemoCaptureData {
        let project: ChatProject
        let conversations: [ConversationSummary]
        let glmConversation: ConversationSummary
        let primaryConversation: ConversationSummary
        let agentConversation: ConversationSummary
        let glmMessages: [ChatMessage]
        let messages: [ChatMessage]
        let agentMessages: [ChatMessage]
        let models: [ModelOption]
        let nearCloudModels: [ModelOption]
        let attestation: AttestationSnapshot
    }

    private static func demoCaptureData(now: Date) -> DemoCaptureData {
        let projectID = "demo-project-ironclaw-pr-plan"
        let conversationID = "demo-conversation-iran-council"
        let glmConversationID = "demo-conversation-glm-private"
        let councilBatchID = "demo-council-iran-status"
        let demoCloudClaudeSonnet46 = ModelOption.nearCloudModelID(for: "anthropic/claude-sonnet-4-6")
        let demoCloudClaudeOpus46 = ModelOption.nearCloudModelID(for: "anthropic/claude-opus-4-6")
        let demoCloudQwen3635 = ModelOption.nearCloudModelID(for: "Qwen/Qwen3.6-35B-A3B-FP8")
        let demoCloudQwen3627 = ModelOption.nearCloudModelID(for: "Qwen/Qwen3.6-27B-FP8")
        let created = now.addingTimeInterval(-11 * 60)
        let project = ChatProject(
            id: projectID,
            name: "IronClaw Reborn Plan",
            createdAt: created.addingTimeInterval(-3600),
            conversationIDs: [glmConversationID, conversationID],
            attachments: [
                ChatAttachment(id: "demo-file-reborn-project-plan", name: "reborn-project-plan.md", kind: "txt", bytes: 42_000),
                ChatAttachment(id: "demo-file-pr-snapshot", name: "latest-ironclaw-prs.json", kind: "json", bytes: 19_000)
            ],
            instructions: "Update plans from live GitHub evidence. Group work by lifecycle, SSE/replay, and first-party GitHub WASM extension.",
            memorySummary: "The plan tracks IronClaw Reborn lifecycle work, SSE replay reliability, and first-party GitHub extension installability.",
            links: [
                ProjectLink(
                    id: "demo-link-ironclaw-prs",
                    title: "nearai/ironclaw pull requests",
                    urlString: "https://github.com/nearai/ironclaw/pulls",
                    createdAt: created.addingTimeInterval(60)
                )
            ],
            notes: [
                ProjectNote(
                    id: "demo-note-reborn-plan",
                    title: "Reborn plan update",
                    text: "Fold #4066, #4065, and #4064 into the project plan before the next release review.",
                    createdAt: created.addingTimeInterval(120)
                )
            ],
            iconName: ProjectIcon.folder.symbolName,
            paletteName: ProjectPalette.sky.rawValue
        )

        let glmConversation = ConversationSummary(
            id: glmConversationID,
            createdAt: created.addingTimeInterval(120).timeIntervalSince1970,
            metadata: ConversationMetadata(title: "Iran war status today")
        )
        let primaryConversation = ConversationSummary(
            id: conversationID,
            createdAt: created.timeIntervalSince1970,
            metadata: ConversationMetadata(title: "Iran war Council view")
        )
        let agentConversation = ConversationSummary(
            id: "demo-conversation-ironclaw-run",
            createdAt: created.addingTimeInterval(-300).timeIntervalSince1970,
            metadata: ConversationMetadata(title: "IronClaw PR plan update")
        )
        let earlierConversation = ConversationSummary(
            id: "demo-conversation-council-pricing",
            createdAt: created.addingTimeInterval(-86_400).timeIntervalSince1970,
            metadata: ConversationMetadata(title: "Model routing comparison")
        )
        let apExplainerSource = WebSearchSource(type: "web", url: "https://apnews.com/article/b1659232611edc10808612e30647c17d", title: "AP: What we know about the emerging deal to end the Iran war", publishedAt: "May 25, 2026")
        let pbsExplainerSource = WebSearchSource(type: "web", url: "https://www.pbs.org/newshour/world/what-we-know-and-dont-know-about-the-emerging-deal-to-end-the-iran-war", title: "PBS/AP: Emerging deal to end the Iran war", publishedAt: "May 25, 2026")
        let bostonAPSource = WebSearchSource(type: "web", url: "https://www.boston.com/news/politics/2026/05/24/trump-says-a-deal-with-iran-and-opening-of-strait-of-hormuz-are-largely-negotiated/", title: "Boston.com/AP: Deal and Hormuz reopening largely negotiated", publishedAt: "May 24, 2026")
        let apDealSource = WebSearchSource(type: "web", url: "https://apnews.com/article/1c283f26d037102cc5e6f798546d0e59", title: "AP: Trump says Iran deal is largely negotiated", publishedAt: "May 23, 2026")
        let apStrikesSource = WebSearchSource(type: "web", url: "https://apnews.com/article/01a13e9a63ece786a0a7fa4933dbf09b", title: "AP: U.S. military reports self-defense strikes in Iran", publishedAt: "May 25, 2026")
        let apHezbollahSource = WebSearchSource(type: "web", url: "https://apnews.com/article/9e3ba96982cd082f030a1a556cd57785", title: "AP: Israel strikes Hezbollah sites as ceasefire pressure continues", publishedAt: "May 25, 2026")
        let iranSources = [
            apExplainerSource,
            pbsExplainerSource,
            bostonAPSource,
            apDealSource,
            apStrikesSource,
            apHezbollahSource
        ]
        let glmCouncilSources = [apExplainerSource, pbsExplainerSource]
        let qwenCouncilSources = [bostonAPSource, apDealSource]
        let opusCouncilSources = [apStrikesSource, apHezbollahSource]
        let prSources = [
            WebSearchSource(type: "project_file", url: "https://near.ai/demo/reborn-project-plan.md", title: "reborn-project-plan.md"),
            WebSearchSource(type: "web", url: "https://github.com/nearai/ironclaw/pull/4066", title: "#4066 Wire Reborn extension lifecycle registry"),
            WebSearchSource(type: "web", url: "https://github.com/nearai/ironclaw/pull/4065", title: "#4065 Fix Reborn SSE replay fallback"),
            WebSearchSource(type: "web", url: "https://github.com/nearai/ironclaw/pull/4064", title: "#4064 Install GitHub WASM extension through Reborn lifecycle")
        ]
        let glmUserMessage = ChatMessage(
            id: "demo-user-glm-private",
            role: .user,
            text: "Is the war in Iran ending as of today?",
            model: nil,
            createdAt: created.addingTimeInterval(122),
            status: "completed",
            responseID: nil,
            isStreaming: false,
            attachments: []
        )
        let glmPrivateAnswer = ChatMessage(
            id: "demo-assistant-glm-private-answer",
            role: .assistant,
            text: """
            Short answer: it looks closer to ending, but I would not call it over yet.

            As of today, U.S., Iranian, and mediator statements point to a near-final framework that would end the war, gradually reopen the Strait of Hormuz, and start a longer negotiation period [1][2][3][4]. That is materially better than an active escalation cycle.

            The reason I would stay cautious is that the deal is still described as a framework, not a fully implemented settlement. The remaining gaps include wording, sequencing, sanctions/frozen funds, the Strait of Hormuz, and follow-on nuclear talks [3][4]. There are also live military and regional spillover risks, including reported U.S. self-defense strikes and Israel-Hezbollah pressure, which can still derail a broader de-escalation [5][6].

            My read: the war is in an endgame phase, not a finished peace. Watch for three confirmations: a signed announcement, verified reopening steps in the Strait, and a sustained pause in related regional strikes.
            """,
            model: Self.defaultModelID,
            createdAt: created.addingTimeInterval(130),
            firstTokenAt: created.addingTimeInterval(131.1),
            status: "completed",
            responseID: "demo-response-glm-private",
            isStreaming: false,
            searchQuery: "Is the war in Iran ending as of today?",
            sources: iranSources,
            attachments: []
        )
        let userMessage = ChatMessage(
            id: "demo-user-risk-summary",
            role: .user,
            text: "Is the war in Iran ending as of today?",
            model: nil,
            createdAt: created,
            status: "completed",
            responseID: nil,
            isStreaming: false,
            attachments: []
        )
        let synthesisMessage = ChatMessage(
            id: "demo-assistant-council-synthesis",
            role: .assistant,
            text: """
            ## Direct answer
            The best answer is: not over, but closer to an off-ramp. GLM 5.1 reads the AP/PBS overview as evidence that a deal is emerging [1][2]. Claude Sonnet 4.6 focuses on whether the reported framework and Strait of Hormuz terms actually get implemented [3][4]. Qwen 3.6 keeps the caution high because fresh military activity and the Israel-Hezbollah front can still break the diplomatic track [5][6].

            ## What the council agrees on
            Nobody should say the war is already over. The supported statement is narrower: talks appear close to an agreement, but the outcome still depends on a signed/finalized deal, implementation of the Hormuz reopening, and containment of related military fronts [1][3][5][6].

            ## How the models vary
            - GLM 5.1: weighs the broad AP/PBS explainer coverage and calls this a possible endgame, not a settled peace [1][2].
            - Claude Sonnet 4.6: reads the deal-specific reporting as an implementation checklist: final text, Hormuz reopening, and follow-on negotiations [3][4].
            - Qwen 3.6: reads the security reporting as a warning that diplomacy is still exposed to military and regional shocks [5][6].

            ## Disagreements or uncertainty
            The disagreement is about confidence. GLM 5.1 is the most optimistic because the overview reporting points to a possible deal. Claude Sonnet 4.6 is conditional because a framework is not the same as implementation. Qwen 3.6 is the least willing to call it ending while strike reports and spillover risks remain live.
            """,
            model: ModelOption.llmCouncilSynthesisModelID,
            createdAt: created.addingTimeInterval(18),
            firstTokenAt: created.addingTimeInterval(19.2),
            status: "completed",
            responseID: "demo-response-synthesis",
            councilBatchID: councilBatchID,
            isStreaming: false,
            searchQuery: "Is the war in Iran ending as of today?",
            sources: iranSources
        )
        let glmMessage = ChatMessage(
            id: "demo-assistant-glm",
            role: .assistant,
            text: """
            ## GLM 5.1
            The AP/PBS overview supports "possible endgame," not "ended" [1][2]. I would answer that the war appears closer to a diplomatic off-ramp, but the claim should stay bounded until there is a final agreement and visible implementation.
            """,
            model: Self.defaultModelID,
            createdAt: created.addingTimeInterval(19),
            firstTokenAt: created.addingTimeInterval(20.2),
            status: "completed",
            responseID: "demo-response-glm",
            councilBatchID: councilBatchID,
            isStreaming: false,
            searchQuery: "Is the war in Iran ending as of today?",
            sources: glmCouncilSources
        )
        let qwenLargeMessage = ChatMessage(
            id: "demo-assistant-qwen-large",
            role: .assistant,
            text: """
            ## Claude Sonnet 4.6
            The deal-specific reporting makes this an implementation question [1][2]. If the framework is finalized and the Strait of Hormuz reopening actually starts, then "ending" becomes plausible. If those milestones slip, the headline is only diplomatic momentum.
            """,
            model: demoCloudClaudeSonnet46,
            createdAt: created.addingTimeInterval(20),
            firstTokenAt: created.addingTimeInterval(21.7),
            status: "completed",
            responseID: "demo-response-qwen-large",
            councilBatchID: councilBatchID,
            isStreaming: false,
            searchQuery: "Is the war in Iran ending as of today?",
            sources: qwenCouncilSources
        )
        let opusMessage = ChatMessage(
            id: "demo-assistant-opus",
            role: .assistant,
            text: """
            ## Qwen 3.6
            I would be careful with the word "ending." Diplomatic signals can coexist with active coercion. Fresh strike reporting and the Israel-Hezbollah front mean the safer answer is: negotiations may be near an off-ramp, but the conflict is not reliably settled yet [1][2].
            """,
            model: demoCloudQwen3635,
            createdAt: created.addingTimeInterval(21),
            firstTokenAt: created.addingTimeInterval(22.4),
            status: "completed",
            responseID: "demo-response-opus",
            councilBatchID: councilBatchID,
            isStreaming: false,
            searchQuery: "Is the war in Iran ending as of today?",
            sources: opusCouncilSources
        )
        let agentUserMessage = ChatMessage(
            id: "demo-user-ironclaw",
            role: .user,
            text: "Use this attached project plan and the latest nearai/ironclaw PRs to update the plan. Show what changed and why.",
            model: nil,
            createdAt: created.addingTimeInterval(280),
            status: "completed",
            responseID: nil,
            isStreaming: false,
            attachments: project.attachments
        )
        let agentRunMessage = ChatMessage(
            id: "demo-assistant-ironclaw-result",
            role: .assistant,
            text: """
            IronClaw output

            Inputs
            - Attached plan: reborn-project-plan.md [1]
            - Latest open PRs checked: #4066, #4065, #4064 [2][3][4]

            What changed in the plan
            1. Added a new "Extension lifecycle registry" milestone from #4066. It covers search, install, activate, remove, shared active-extension registry, host-internal filtering, and dynamic WASM credentials [2].
            2. Moved "SSE replay reliability" from polish to release-blocker because #4065 fixes replay_unavailable behavior, projection rebases, and lifecycle event replay ordering [3].
            3. Added "First-party GitHub WASM installability" as a dependent milestone from #4064. It brings the GitHub extension catalog, manifest/schema/prompt assets, host-internal github.comment_issue, and first-party WASM build support [4].

            Updated project plan
            - Phase 1: Land generic Reborn lifecycle registry (#4066).
            - Phase 2: Stabilize SSE replay fallback and runtime-event replay (#4065).
            - Phase 3: Install and activate the first-party GitHub WASM extension through the new lifecycle (#4064).
            - Phase 4: Run integration QA: search -> install -> activate -> hidden host-internal tools -> dynamic credentials -> SSE replay after reconnect.

            Risks found
            - #4064 stacks on #4066, so GitHub extension QA should wait until the generic lifecycle registry is stable.
            - #4065 touches replay semantics across event projections and streams, so reconnect testing needs to be explicit.
            - Host-internal capability filtering appears in both #4066 and #4064; duplicate assumptions should be reviewed before merge.

            Final recommendation
            Treat the three PRs as one release train: lifecycle registry first, replay reliability second, GitHub extension installability third. The updated plan is ready for review.
            """,
            model: ModelOption.ironclawModelID,
            createdAt: Date().addingTimeInterval(-34),
            firstTokenAt: Date().addingTimeInterval(-31),
            status: "completed",
            responseID: "demo-response-ironclaw-result",
            isStreaming: false,
            searchQuery: "nearai/ironclaw latest open PRs project plan update",
            sources: prSources,
            attachments: project.attachments
        )

        let models = [
            demoModel(Self.defaultModelID, displayName: "GLM 5.1", description: "Default NEAR Private model with proof support.", verifiable: true),
            demoModel(demoCloudClaudeSonnet46, displayName: "Claude Sonnet 4.6", description: "Anthropic long-context model through the NEAR AI Cloud privacy proxy.", verifiable: false),
            demoModel(demoCloudClaudeOpus46, displayName: "Claude Opus 4.6", description: "Anthropic coding and agent model through the NEAR AI Cloud privacy proxy.", verifiable: false),
            demoModel(demoCloudQwen3635, displayName: "Qwen 3.6 35B A3B FP8", description: "Qwen reasoning model through the NEAR AI Cloud privacy proxy.", verifiable: false),
            demoModel(demoCloudQwen3627, displayName: "Qwen 3.6 27B FP8", description: "Qwen dense model through the NEAR AI Cloud privacy proxy.", verifiable: false),
            demoModel(ModelOption.ironclawMobileModelID, displayName: "IronClaw Mobile", description: "Phone-safe agent runtime.", verifiable: false),
            demoModel(ModelOption.ironclawModelID, displayName: "Hosted IronClaw", description: "Connected Hosted IronClaw.", verifiable: false)
        ]
        let nearCloudModels = models.filter { $0.isNearCloudModel }
        let attestation = AttestationSnapshot(
            nonce: "demo-\(Int(now.timeIntervalSince1970))",
            signingAlgorithm: "ed25519 + Intel TDX quote",
            model: "NEAR Private default",
            coveredModelIDs: [Self.defaultModelID],
            fetchedAt: now.addingTimeInterval(-45),
            chatGatewayAddress: "tee-gateway.near.ai",
            cloudGatewayAddress: nil,
            modelAttestationCount: 1,
            prettyJSON: """
            {
              "nonce": "demo-\(Int(now.timeIntervalSince1970))",
              "gateway": "tee-gateway.near.ai",
              "model": "NEAR Private default",
              "covered_models": [
                "\(Self.defaultModelID)"
              ],
              "quote": "demo-intel-tdx-quote",
              "signature": "demo-ed25519-signature"
            }
            """
        )
        return DemoCaptureData(
            project: project,
            conversations: [glmConversation, primaryConversation, agentConversation, earlierConversation],
            glmConversation: glmConversation,
            primaryConversation: primaryConversation,
            agentConversation: agentConversation,
            glmMessages: [glmUserMessage, glmPrivateAnswer],
            messages: [userMessage, synthesisMessage, glmMessage, qwenLargeMessage, opusMessage],
            agentMessages: [agentUserMessage, agentRunMessage],
            models: models,
            nearCloudModels: nearCloudModels,
            attestation: attestation
        )
    }

    private static func demoModel(
        _ id: String,
        displayName: String,
        description: String,
        verifiable: Bool
    ) -> ModelOption {
        ModelOption(
            modelID: id,
            publicModel: !verifiable,
            metadata: ModelOption.Metadata(
                verifiable: verifiable,
                contextLength: 131_072,
                modelDisplayName: displayName,
                modelDescription: description,
                modelIcon: nil,
                aliases: [displayName]
            )
        )
    }
    #endif
}
