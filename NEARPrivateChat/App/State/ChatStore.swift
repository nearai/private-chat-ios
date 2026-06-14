import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class ChatStore: ObservableObject {
    var conversations: [ConversationSummary] {
        get { conversationStore.conversations }
        set { conversationStore.replaceConversations(newValue, shouldCache: !isResettingAccountScopedState) }
    }
    var models: [ModelOption] {
        get { modelCatalogStore.models }
        set { modelCatalogStore.replaceModels(newValue) }
    }
    var nearCloudModels: [ModelOption] {
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
    var selectedProjectID: String? {
        get { projectStore.selectedProjectID }
        set { projectStore.selectProjectID(newValue, persist: !isResettingAccountScopedState) }
    }
    var selectedModel: String {
        get { modelCatalogStore.selectedModel }
        set { modelCatalogStore.selectedModel = newValue }
    }
    var councilModelIDs: [String] {
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
    @Published var isLoading = false
    var isLoadingAttestation: Bool { securityStore.isLoadingAttestation }
    private(set) var pinnedModelIDs: [String] {
        get { modelCatalogStore.pinnedModelIDs }
        set { modelCatalogStore.pinnedModelIDs = newValue }
    }
    @Published var bannerMessage: String?

    let conversationStore: ConversationStore
    let conversationActionCoordinator: ConversationActionCoordinator
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

    var isUploadingAttachment: Bool {
        get { composerStore.isUploadingAttachment }
        set { composerStore.isUploadingAttachment = newValue }
    }

    var routeReadinessIssue: RouteReadinessIssue? {
        get { composerStore.routeReadinessIssue }
        set { composerStore.routeReadinessIssue = newValue }
    }

    let api: PrivateChatAPI
    /// Per-route circuit breaker consulted by every send pipeline. Shared with
    /// the composer UI through AppEnvironment's environmentObject injection.
    let routeHealth: RouteHealthMonitor
    /// Records the real HTTP status + server message of recent route requests
    /// for the in-app Connection Diagnostics screen.
    let diagnostics: ConnectionDiagnostics
    /// True while a manual or post-login private-session probe is in flight, so
    /// the diagnostics screen can show progress without a separate store.
    @Published var isProbingSession = false
    var messageRepository: MessageRepository
    let messageLoadCoordinator: ChatMessageLoadCoordinator
    let fileService: FileService
    let ironclawAPI = IronclawAPI()
    /// Best-effort Live Activity for in-progress council briefings and compound
    /// multi-lookup runs. Purely a side-effect surface: every call no-ops when
    /// Live Activities are unavailable and never affects chat logic or results.
    let agentActivity = AgentActivityController()
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
    var soulPromptProfile = SoulPromptComposer.Profile.empty
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
    let webGroundingService = WebGroundingService()
    let ironclawMobileRuntime: IronclawMobileRuntime
    lazy var sendCoordinator = ChatSendCoordinator(host: self)
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
    var storageAccountID = "signed-out"
    let draftScopeStore = ChatDraftScopeStore()
    private var bootstrapInFlightAccountID: String?
    private var lastBootstrappedAccountID: String?
    private var accountBackgroundRefreshTask: Task<Void, Never>?
    private var storeCancellables: Set<AnyCancellable> = []

    nonisolated static let defaultModelID = ModelCatalogStore.defaultModelID
    static let maxCouncilModels = ModelCatalogStore.maxCouncilModels
    static let maxConcurrentCouncilStreams = CouncilStreamService.defaultConcurrentStreamLimit
    static let councilLegNoTokenTimeoutSeconds: TimeInterval = 120
    private static let maxPinnedModels = ModelCatalogStore.maxPinnedModels
    nonisolated static let maxFileUploadBytes = APIClient.maxUploadBytes
    nonisolated static let maxAttachmentUploadBytes = maxFileUploadBytes
    static let maxPromptAttachments = 5
    static let maxProjectAttachments = 12
    static let largePasteThresholdBytes = 8 * 1024
    static let largePasteThresholdCharacters = 5_000
    private static let staleRunningMessageInterval: TimeInterval = 120
    private static let frontierModelMigrationKey = "frontierModelMigrationV1"
    private static let frontierModelUpgradeKey = "frontierModelUpgradeV2"
    private static let glmDefaultMigrationKey = "glmDefaultMigrationV1"
    private static let openWeightDefaultMigrationKey = "openWeightDefaultMigrationV1"
    let ironclawOpenWeightPreferredModelIDs = [
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
    var didStartLiveCouncilDemo = false
    #if canImport(UIKit)
    var didStageReleaseGateFixture = false
    #endif
    #endif
    var councilStopRequestedBatchID: String?
    var isNormalizingDraft = false
    var isResettingAccountScopedState = false
    private var attachmentUploadNotice: String?
    var deniedOpenWeightModelIDs = Set<String>()

    typealias CouncilStreamResult = CouncilStreamService.StreamResult
    typealias CouncilRunOutcome = CouncilStreamService.RunOutcome

    typealias RouteReadinessIssue = ChatRouteReadinessIssue

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
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &storeCancellables)
        self.projectStore.bannerHandler = { [weak self] message in
            self?.showBanner(message)
        }
        self.projectStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &storeCancellables)
        self.conversationStore.bannerHandler = { [weak self] message in
            self?.showBanner(message)
        }
        self.conversationStore.conversationsDidChange = { [weak self] conversations in
            self?.projectStore.replaceConversations(conversations)
        }
        self.conversationStore.objectWillChange
            .receive(on: RunLoop.main)
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
            .receive(on: RunLoop.main)
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
            .receive(on: RunLoop.main)
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
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &storeCancellables)
        self.securityStore.bannerHandler = { [weak self] message in
            self?.showBanner(message)
        }
        self.securityStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &storeCancellables)
        self.messageTimelineStore.objectWillChange
            .receive(on: RunLoop.main)
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
            await self?.refreshConversations(showErrors: false)
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

    func resetConnectionStateForCredentialChange() {
        routeHealth.resetAll()
        diagnostics.reset()
        routeReadinessIssue = nil
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

    func cancelBackgroundOwners() {
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

    func refreshModels(loadCloudCatalog: Bool = false) async {
        do {
            deniedOpenWeightModelIDs.removeAll()
            try await modelCatalogStore.refreshModels(
                modelAPI: api,
                loadCloudCatalog: loadCloudCatalog,
                nearCloudAPIKey: loadNearCloudAPIKey()
            )
        } catch {
            showBanner(Self.displayFailureMessage(error.localizedDescription))
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
            showBanner(Self.displayFailureMessage(error.localizedDescription))
            return nil
        }
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

    func messageLoadCallbacks() -> ChatMessageLoadCoordinatorCallbacks {
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

}
