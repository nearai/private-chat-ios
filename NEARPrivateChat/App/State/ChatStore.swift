import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var conversations: [ConversationSummary] = []
    @Published private(set) var models: [ModelOption] = []
    @Published private(set) var nearCloudModels: [ModelOption] = []
    @Published private(set) var projects: [ChatProject] = []
    @Published private(set) var shareInfo: ConversationSharesListResponse?
    @Published private(set) var attestationSnapshot: AttestationSnapshot?
    @Published private(set) var attestationFetchErrorMessage: String?
    @Published private(set) var ironclawTokenConfigured = false
    @Published private(set) var ironclawStatusText = "Not connected"
    @Published private(set) var ironclawLastVerifiedAt: Date?
    @Published private(set) var ironclawToolNames: [String] = []
    @Published private(set) var isTestingIntegration = false
    @Published private(set) var nearCloudKeyConfigured = false
    @Published private(set) var billingSnapshot: BillingSnapshot?
    @Published private(set) var isLoadingBilling = false
    @Published private(set) var isTestingNearCloudKey = false
    @Published private(set) var isConnectingNearCloudAccount = false
    @Published private(set) var diagnosticChecks: [AppDiagnosticCheck] = []
    @Published private(set) var isRunningDiagnostics = false
    @Published private(set) var isTestingIronclawWorkstation = false
    @Published private(set) var sharedWithMe: [SharedConversationInfo] = []
    @Published private(set) var remoteFiles: [RemoteFileInfo] = []
    @Published private(set) var remoteFilePreview: RemoteFilePreview?
    @Published private(set) var shareGroups: [ShareGroupInfo] = []
    @Published private(set) var openSelectedConversationToken: UUID?
    @Published var sharedPreview: SharedConversationSnapshot?
    @Published var pendingDeleteConversation: ConversationSummary?
    @Published var pendingExternalDeepLink: AppDeepLinkAction?
    @Published var pendingHostedHandoffPreflight: HostedIronclawHandoffPreflight?
    @Published var selectedConversation: ConversationSummary?
    @Published var selectedProjectID: String? {
        didSet {
            guard !isResettingAccountScopedState else { return }
            if let selectedProjectID {
                UserDefaults.standard.set(selectedProjectID, forKey: scopedDefaultsKey(Self.selectedProjectDefaultsKey))
            } else {
                UserDefaults.standard.removeObject(forKey: scopedDefaultsKey(Self.selectedProjectDefaultsKey))
            }
        }
    }
    @Published var selectedModel: String {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: scopedDefaultsKey(Self.selectedModelDefaultsKey))
        }
    }
    @Published private(set) var councilModelIDs: [String] = [] {
        didSet {
            UserDefaults.standard.set(councilModelIDs, forKey: scopedDefaultsKey(Self.councilModelDefaultsKey))
        }
    }
    @Published var webSearchEnabled: Bool {
        didSet {
            UserDefaults.standard.set(webSearchEnabled, forKey: scopedDefaultsKey(Self.webSearchDefaultsKey))
        }
    }
    @Published private(set) var notificationPreferenceEnabled = false
    @Published private(set) var appearancePreference: AppAppearancePreference = .system
    @Published var sourceMode: ChatSourceMode = .auto {
        didSet {
            UserDefaults.standard.set(sourceMode.rawValue, forKey: scopedDefaultsKey(Self.sourceModeDefaultsKey))
        }
    }
    @Published var researchModeEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(researchModeEnabled, forKey: scopedDefaultsKey(Self.researchModeDefaultsKey))
        }
    }
    @Published var systemPrompt: String {
        didSet {
            saveProtectedText(systemPrompt, filename: Self.systemPromptCacheFilename, legacyDefaultsKey: scopedDefaultsKey(Self.systemPromptDefaultsKey))
        }
    }
    @Published var largeTextAsFileEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(largeTextAsFileEnabled, forKey: scopedDefaultsKey(Self.largeTextAsFileDefaultsKey))
        }
    }
    @Published var advancedModelParams: AdvancedModelParams = .defaults {
        didSet {
            saveAdvancedModelParams(advancedModelParams.sanitized)
        }
    }
    @Published var ironclawSettings = IronclawSettings.default {
        didSet {
            saveIronclawSettings(ironclawSettings)
        }
    }
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingShareInfo = false
    @Published private(set) var isLoadingAttestation = false
    @Published private(set) var isLoadingSharedPreview = false
    @Published private(set) var isLoadingSharedWithMe = false
    @Published private(set) var isLoadingRemoteFiles = false
    @Published private(set) var isLoadingRemoteFilePreview = false
    @Published private(set) var isLoadingShareGroups = false
    @Published private(set) var pinnedModelIDs: [String] = [] {
        didSet {
            guard !isResettingAccountScopedState else { return }
            UserDefaults.standard.set(pinnedModelIDs, forKey: scopedDefaultsKey(Self.pinnedModelDefaultsKey))
        }
    }
    @Published var bannerMessage: String?

    let transcriptStore = ChatTranscriptStore()
    let composerStore = ChatComposerStore()

    private(set) var messages: [ChatMessage] {
        get { transcriptStore.messages }
        set { transcriptStore.messages = newValue }
    }

    private(set) var isStreaming: Bool {
        get { transcriptStore.isStreaming }
        set { transcriptStore.isStreaming = newValue }
    }

    private(set) var pendingAttachments: [ChatAttachment] {
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

    private(set) var routeReadinessIssue: RouteReadinessIssue? {
        get { composerStore.routeReadinessIssue }
        set { composerStore.routeReadinessIssue = newValue }
    }

    private let api: PrivateChatAPI
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
    /// User control over passive memory (auto-learning durable facts from chat).
    /// A single user-level preference, persisted in UserDefaults; default on.
    var passiveMemoryEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.passiveMemoryDefaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.passiveMemoryDefaultsKey) }
    }
    private static let passiveMemoryDefaultsKey = "passiveMemoryEnabled"
    /// Privacy mode: when on, attached PDFs are kept entirely on-device (never
    /// uploaded) and only their relevant passages are inlined at send. Default off.
    var keepDocumentsOnDevice: Bool {
        get { UserDefaults.standard.bool(forKey: Self.keepDocumentsOnDeviceDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.keepDocumentsOnDeviceDefaultsKey) }
    }
    private static let keepDocumentsOnDeviceDefaultsKey = "keepDocumentsOnDevice"
    private let webGroundingService = WebGroundingService()
    private let ironclawMobileRuntime: IronclawMobileRuntime
    private var selectedResponseVariantByConversationID: [String: String] = [:]
    private var pendingLargePasteTexts: [String: String] = [:] {
        didSet {
            persistCurrentDraftIfNeeded()
        }
    }
    /// On-device extracted text for attached PDFs, keyed by the attachment id, so
    /// a question about the doc can inline only the most-relevant passages (local
    /// RAG) instead of relying on the model to read the whole uploaded file.
    /// Capped so it can't grow unbounded; stale entries are looked up only by the
    /// current turn's attachment ids, so leftovers are harmless.
    private var pendingDocumentTexts: [String: String] = [:]
    /// Insertion order for `pendingDocumentTexts`, so the cap evicts the OLDEST
    /// entry deterministically (a Dictionary has no order; `.suffix` could drop
    /// the doc just staged for the current turn).
    private var pendingDocumentTextIDs: [String] = []
    private static let maxStagedDocumentChars = 200_000
    private static let maxStagedDocuments = 8
    private var pendingHostedHandoffContinuation: HostedHandoffContinuation?
    private var currentUserMessageMetadata: MessageMetadata?
    private var storageAccountID = "signed-out"
    private var draftPersistenceScopeID = "home"
    private var suppressDraftPersistence = false
    private var loadMessagesTask: Task<Void, Never>?
    private var loadMessagesGeneration = 0
    private var bootstrapInFlightAccountID: String?
    private var lastBootstrappedAccountID: String?
    private var accountBackgroundRefreshTask: Task<Void, Never>?
    private var pendingTextDeltaByMessageID: [String: String] = [:]
    private var pendingTextDeltaFlushTask: Task<Void, Never>?
    private struct PersistedDraftState: Codable {
        var text: String
        var attachments: [ChatAttachment]
        var pendingLargePasteTexts: [String: String]

        var isEmpty: Bool {
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty
        }

        var sanitized: PersistedDraftState {
            let attachmentIDs = Set(attachments.map(\.id))
            let filteredLargePastes = pendingLargePasteTexts.filter { attachmentIDs.contains($0.key) }
            let filteredAttachments = attachments.filter { attachment in
                !attachment.isLocalPendingText || filteredLargePastes[attachment.id] != nil
            }
            return PersistedDraftState(
                text: text,
                attachments: filteredAttachments,
                pendingLargePasteTexts: filteredLargePastes
            )
        }
    }

    static let defaultModelID = "zai-org/GLM-5.1-FP8"
    private static let preferredDefaultModelDefaultsKey = "preferredDefaultModelID"
    private static let selectedModelDefaultsKey = "selectedModel"
    private static let councilModelDefaultsKey = "councilModelIDs"
    private static let pinnedModelDefaultsKey = "pinnedModelIDs"
    private static let maxCouncilModels = 3
    private static let maxConcurrentCouncilStreams = CouncilStreamService.defaultConcurrentStreamLimit
    private static let maxPinnedModels = 12
    private static let selectedProjectDefaultsKey = "selectedProjectID"
    private static let draftDefaultsKeyPrefix = "draftByScope"
    private static let draftStateDefaultsKeyPrefix = "draftStateByScope"
    private static let webSearchDefaultsKey = "webSearchEnabled"
    private static let sourceModeDefaultsKey = "sourceMode"
    private static let researchModeDefaultsKey = "researchModeEnabled"
    private static let systemPromptDefaultsKey = "systemPrompt"
    private static let systemPromptCacheFilename = "system-prompt.txt"
    private static let draftCacheDirectoryName = "drafts"
    private static let draftStateCacheDirectoryName = "draft-state"
    private static let largeTextAsFileDefaultsKey = "largeTextAsFileEnabled"
    private static let advancedModelParamsDefaultsKey = "advancedModelParams"
    private static let conversationsCacheKey = "cachedConversations"
    private static let projectsDefaultsKey = "chatProjects"
    private static let localMessagesDefaultsKey = "localConversationMessages"
    private static let conversationsCacheFilename = "cached-conversations.json"
    private static let projectsCacheFilename = "projects.json"
    private static let localMessagesCacheFilename = "local-conversation-messages.json"
    private static let ironclawThreadIDsCacheFilename = "ironclaw-thread-ids.json"
    private static let maxFileUploadBytes = 10 * 1024 * 1024
    nonisolated private static let maxPDFTextExtractionBytes = 5 * 1024 * 1024
    nonisolated private static let maxPDFExtractedTextBytes = 10 * 1024 * 1024
    nonisolated private static let maxPDFExtractionPages = 40
    nonisolated private static let maxPDFExtractionSeconds: TimeInterval = 5
    private static let maxPromptAttachments = 5
    private static let maxProjectAttachments = 12
    private static let streamDeltaFlushNanoseconds: UInt64 = MessageStreamService.textDeltaFlushNanoseconds
    private static let largePasteThresholdBytes = 8 * 1024
    private static let largePasteThresholdCharacters = 5_000
    private static let staleRunningMessageInterval: TimeInterval = 120
    private static let ironclawSettingsDefaultsKey = "ironclawSettings"
    private static let ironclawThreadIDsDefaultsKey = "ironclawConversationThreadIDs"
    private static let ironclawThreadMappingMigrationKey = "ironclawThreadMappingMigrationV1"
    private static let ironclawTokenKeychainAccount = "ironclaw.authToken"
    private static let nearCloudAPIKeychainAccount = "nearCloud.apiKey"
    private static let frontierModelMigrationKey = "frontierModelMigrationV1"
    private static let frontierModelUpgradeKey = "frontierModelUpgradeV2"
    private static let glmDefaultMigrationKey = "glmDefaultMigrationV1"
    private static let openWeightDefaultMigrationKey = "openWeightDefaultMigrationV1"
    private static let signedOutStorageAccountID = "signed-out"
    private let preferredModelIDs = [
        "zai-org/GLM-5.1-FP8",
        "qwen/qwen3.7-max",
        "anthropic/claude-opus-4-7",
        "openai/gpt-5.5",
        "google/gemini-3.5-flash",
        "Qwen/Qwen3.5-122B-A10B",
        "Qwen/Qwen3.6-35B-A3B-FP8",
        "Qwen/Qwen3-30B-A3B-Instruct-2507",
        "openai/gpt-oss-120b",
        "Qwen/Qwen3-VL-30B-A3B-Instruct",
        "moonshotai/kimi-k2.6",
        "moonshotai/Kimi-K2-Thinking",
        "moonshotai/Kimi-K2-Instruct",
        "MoonshotAI/Kimi-K2-Instruct",
        "deepseek-ai/DeepSeek-V3.2",
        "deepseek-ai/DeepSeek-V3.1",
        "deepseek-ai/DeepSeek-R1",
        "openai/gpt-5.5",
        "anthropic/claude-opus-4-7",
        "anthropic/claude-sonnet-4-6",
        "openai/gpt-5.4",
        "google/gemini-3-pro",
        "openai/gpt-5.2",
        "openai/gpt-5.1",
        "openai/gpt-5",
        "google/gemini-2.5-pro",
        "anthropic/claude-opus-4-6",
        "anthropic/claude-sonnet-4-5",
        "openai/gpt-4.1",
        "openai/o3",
        "openai/o4-mini"
    ]
    private let nearCloudPreferredModelIDs = [
        "anthropic/claude-opus-4-7",
        "openai/gpt-5.5",
        "qwen/qwen3.7-max",
        "moonshotai/kimi-k2.6",
        "google/gemini-3.5-flash",
        "openai/gpt-oss-120b",
        "anthropic/claude-opus-4-6",
        "google/gemini-3-pro",
        "google/gemini-2.5-pro",
        "zai-org/GLM-5.1-FP8",
        "Qwen/Qwen3.5-122B-A10B",
        "Qwen/Qwen3.6-35B-A3B-FP8",
        "Qwen/Qwen3-30B-A3B-Instruct-2507",
        "openai/gpt-5.4",
        "openai/gpt-5.2",
        "openai/gpt-5.1",
        "google/gemini-2.5-flash",
        "google/gemini-3.1-flash-lite"
    ]
    private let defaultCouncilCandidateGroups = [
        [
            "zai-org/GLM-latest",
            "zai-org/GLM-5.1-FP8"
        ],
        [
            "near-cloud/qwen3.7-max",
            "near-cloud/qwen/qwen3.7-max",
            "qwen/qwen3.7-max",
            "Qwen/Qwen3.5-122B-A10B"
        ],
        [
            "near-cloud/anthropic/claude-opus-4-7",
            "anthropic/claude-opus-4-7",
            "anthropic/claude-opus-4-6",
            "anthropic/claude-sonnet-4-6"
        ],
        [
            "near-cloud/openai/gpt-5.5",
            "openai/gpt-5.5",
            "near-cloud/openai/gpt-oss-120b",
            "openai/gpt-oss-120b",
            "openai/gpt-5.4"
        ],
        [
            "near-cloud/moonshotai/kimi-k2.6",
            "moonshotai/kimi-k2.6"
        ],
        [
            "near-cloud/google/gemini-3.5-flash",
            "google/gemini-3-pro",
            "google/gemini-2.5-pro",
            "google/gemini-3.5-flash"
        ]
    ]
    private let ironclawOpenWeightPreferredModelIDs = [
        "zai-org/GLM-5.1-FP8",
        "Qwen/Qwen3.5-122B-A10B",
        "Qwen/Qwen3.6-35B-A3B-FP8",
        "Qwen/Qwen3-30B-A3B-Instruct-2507",
        "openai/gpt-oss-120b",
        "Qwen/Qwen3-VL-30B-A3B-Instruct",
        "moonshotai/kimi-k2.6",
        "moonshotai/Kimi-K2-Thinking",
        "moonshotai/Kimi-K2-Instruct",
        "MoonshotAI/Kimi-K2-Instruct",
        "deepseek-ai/DeepSeek-V3.2",
        "deepseek-ai/DeepSeek-V3.1",
        "deepseek-ai/DeepSeek-R1",
        "DeepSeek/DeepSeek-V3.2",
        "DeepSeek/DeepSeek-V3.1"
    ]
    private var streamTask: Task<Void, Never>?
    private var currentAssistantMessageID: String?
    private var currentCouncilAssistantMessageIDs: [String] = []
    #if DEBUG
    private var didStartLiveCouncilDemo = false
    #endif
    private var councilStopRequestedBatchID: String?
    private var isNormalizingDraft = false
    private var isResettingAccountScopedState = false
    private var approvedHostedHandoffFingerprint: String?

    private enum HostedHandoffContinuation {
        case draft
        case regenerate(ChatMessage)
        case edit(ChatMessage, String)
        case directSend(
            text: String,
            attachments: [ChatAttachment],
            previousResponseIDOverride: String?,
            initiator: String?,
            appendUserMessage: Bool
        )
    }
    private var attachmentUploadNotice: String?
    private var deniedOpenWeightModelIDs = Set<String>()
    private var lastRemoteSettings = RemoteUserSettings(
        notification: nil,
        systemPrompt: nil,
        webSearch: nil,
        appearance: nil
    )

    private struct CouncilStreamResult {
        let modelID: String
        let messageID: String
        let didComplete: Bool
        let failureSummary: String?
        var isStopSignal: Bool = false

        static func stopSignal(batchID: String) -> CouncilStreamResult {
            CouncilStreamResult(
                modelID: batchID,
                messageID: batchID,
                didComplete: false,
                failureSummary: nil,
                isStopSignal: true
            )
        }
    }

    private struct CouncilRunOutcome {
        let results: [CouncilStreamResult]
        let stoppedEarly: Bool
    }

    typealias RouteReadinessIssue = ChatRouteReadinessIssue

    private var projectStore: ProjectStore {
        ProjectStore(
            projects: projects,
            selectedProjectID: selectedProjectID,
            conversations: conversations
        )
    }

    var visibleConversations: [ConversationSummary] {
        projectStore.visibleConversations
    }

    var allVisibleConversations: [ConversationSummary] {
        projectStore.allVisibleConversations
    }

    var archivedConversations: [ConversationSummary] {
        projectStore.archivedConversations
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

    func isMessageSavedToSelectedProject(_ message: ChatMessage) -> Bool {
        guard message.role == .assistant,
              let selectedProjectID,
              let project = projects.first(where: { $0.id == selectedProjectID }) else {
            return false
        }
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let clippedText = Self.clipped(text, maxCharacters: 12_000)
        return project.notes.contains { note in
            note.sourceMessageID == message.id || (!clippedText.isEmpty && note.text == clippedText)
        }
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
        selectedConversation?.title ?? "New chat"
    }

    var selectedModelOption: ModelOption? {
        chatModels.first(where: { $0.id == selectedModel })
    }

    var selectedModelDisplayName: String {
        selectedModelOption?.displayName ?? selectedModel.split(separator: "/").last.map(String.init) ?? selectedModel
    }

    var activeModelDisplayName: String {
        isCouncilModeEnabled ? "LLM Council \(activeCouncilModels.count)" : selectedModelDisplayName
    }

    // MARK: - Preferred default model (user override of shipped default)

    /// The user's chosen default model for new chats. `nil` means use the
    /// shipped fallback (`defaultModelID`). Persisted in account-scoped
    /// UserDefaults so multiple accounts on one device can each pick.
    var preferredDefaultModelID: String? {
        get {
            UserDefaults.standard.string(forKey: scopedDefaultsKey(Self.preferredDefaultModelDefaultsKey))
        }
        set {
            let key = scopedDefaultsKey(Self.preferredDefaultModelDefaultsKey)
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
            objectWillChange.send()
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
        return Self.defaultModelID
    }

    /// Models eligible to be the user's default — the public picker list,
    /// minus IronClaw runtimes (those route to the agent, not chat) and
    /// the synthesis pseudo-model.
    var preferredDefaultModelCandidates: [ModelOption] {
        pickerModels.filter { option in
            !option.isIronclawModel && option.modelID != ModelOption.llmCouncilSynthesisModelID
        }
    }

    /// Sets the user's preferred default model and, if the current chat
    /// is on the shipped default with no messages, switches it over so the
    /// change is felt immediately.
    func setPreferredDefaultModel(_ modelID: String?) {
        preferredDefaultModelID = modelID
        if messages.isEmpty,
           selectedConversation == nil,
           let resolved = modelID,
           pickerModels.contains(where: { $0.id == resolved }) {
            selectedModel = resolved
        }
    }

    var activeCouncilModels: [ModelOption] {
        normalizedCouncilModels(from: councilModelIDs)
    }

    var councilModelNames: [String] {
        activeCouncilModels.map(\.displayName)
    }

    var isCouncilModeEnabled: Bool {
        activeCouncilModels.count > 1 && selectedModelOption?.isIronclawModel != true
    }

    var activeCouncilHasPrivateRoutes: Bool {
        activeCouncilModels.contains { !$0.isExternalModel }
    }

    var activeCouncilHasNearCloudRoutes: Bool {
        activeCouncilModels.contains { $0.isNearCloudModel }
    }

    var activeCouncilHasExternalRoutes: Bool {
        activeCouncilModels.contains { $0.isExternalModel }
    }

    var activeCouncilRouteSummary: String {
        guard isCouncilModeEnabled else {
            return selectedProviderDisplayName
        }
        if activeCouncilHasPrivateRoutes && activeCouncilHasNearCloudRoutes {
            return "Private + Cloud"
        }
        if activeCouncilHasNearCloudRoutes {
            return "NEAR AI Cloud Council"
        }
        return "Private Council"
    }

    var defaultCouncilModels: [ModelOption] {
        normalizedCouncilModels(from: defaultCouncilModelIDs())
    }

    var councilPresets: [CouncilPresetOption] {
        [
            councilPreset(
                id: "balanced",
                title: "Balanced",
                subtitle: "Private proof plus frontier cloud diversity.",
                symbolName: "square.grid.2x2",
                candidateGroups: defaultCouncilCandidateGroups,
                candidateModels: chatModels.filter(isCouncilEligible),
                fallbackModels: chatModels.filter(isCouncilEligible)
            ),
            councilPreset(
                id: "private-proof",
                title: "Private Proof",
                subtitle: "Only NEAR Private or open-weight private routes.",
                symbolName: "checkmark.shield.fill",
                candidateGroups: [
                    ["zai-org/GLM-latest", "zai-org/GLM-5.1-FP8"],
                    ["Qwen/Qwen3.5-122B-A10B", "Qwen/Qwen3.6-35B-A3B-FP8", "Qwen/Qwen3-30B-A3B-Instruct-2507"],
                    ["moonshotai/Kimi-K2-Thinking", "moonshotai/Kimi-K2-Instruct", "moonshotai/kimi-k2.6"],
                    ["deepseek-ai/DeepSeek-V3.2", "deepseek-ai/DeepSeek-V3.1", "deepseek-ai/DeepSeek-R1"],
                    ["openai/gpt-oss-120b"]
                ],
                candidateModels: chatModels.filter { isCouncilEligible($0) && !$0.isExternalModel },
                fallbackModels: chatModels.filter { isCouncilEligible($0) && !$0.isExternalModel }
            ),
            councilPreset(
                id: "cloud-frontier",
                title: "Cloud Frontier",
                subtitle: "Opus, GPT, Qwen, Kimi, and Gemini via NEAR AI Cloud.",
                symbolName: "cloud.fill",
                candidateGroups: [
                    ["near-cloud/anthropic/claude-opus-4-7", "anthropic/claude-opus-4-7"],
                    ["near-cloud/openai/gpt-5.5", "openai/gpt-5.5"],
                    ["near-cloud/qwen/qwen3.7-max", "near-cloud/qwen3.7-max", "qwen/qwen3.7-max"],
                    ["near-cloud/moonshotai/kimi-k2.6", "moonshotai/kimi-k2.6"],
                    ["near-cloud/google/gemini-3.5-flash", "google/gemini-3.5-flash"]
                ],
                candidateModels: cloudRouteModels.filter(isCouncilEligible),
                fallbackModels: cloudRouteModels
            ),
            councilPreset(
                id: "fast-scout",
                title: "Fast Scout",
                subtitle: "Lower-latency scan before deeper synthesis.",
                symbolName: "bolt.fill",
                candidateGroups: [
                    ["zai-org/GLM-5.1-FP8", "zai-org/GLM-latest"],
                    ["near-cloud/google/gemini-3.5-flash", "google/gemini-3.5-flash"],
                    ["near-cloud/qwen/qwen3.7-max", "qwen/qwen3.7-max"],
                    ["near-cloud/openai/gpt-oss-120b", "openai/gpt-oss-120b"]
                ],
                candidateModels: chatModels.filter(isCouncilEligible),
                fallbackModels: chatModels.filter(isCouncilEligible)
            )
        ]
    }

    var featuredPickerModels: [ModelOption] {
        let featuredIDs = [
            Self.defaultModelID,
            "zai-org/GLM-5.1-FP8",
            ModelOption.nearCloudModelID(for: "anthropic/claude-opus-4-7"),
            ModelOption.nearCloudModelID(for: "openai/gpt-5.5"),
            ModelOption.nearCloudModelID(for: "qwen/qwen3.7-max"),
            ModelOption.nearCloudModelID(for: "moonshotai/kimi-k2.6"),
            ModelOption.nearCloudModelID(for: "google/gemini-3.5-flash"),
            ModelOption.ironclawModelID,
            ModelOption.ironclawMobileModelID
        ]
        let available = pickerModels
        var output: [ModelOption] = []

        for featuredID in featuredIDs {
            if let model = available.first(where: { Self.model($0, matchesCandidateID: featuredID) }),
               !output.contains(where: { $0.id == model.id }) {
                output.append(model)
            }
        }

        for model in rankedModels(from: available) where !output.contains(where: { $0.id == model.id }) {
            output.append(model)
            if output.count >= 8 {
                break
            }
        }

        return Array(output.prefix(8))
    }

    var pinnedPickerModels: [ModelOption] {
        modelCatalog.pinnedPickerModels(from: pinnedModelIDs)
    }

    var selectedProviderDisplayName: String {
        if isCouncilModeEnabled {
            return "LLM Council"
        }
        if selectedModelOption?.isIronclawModel == true {
            return "IronClaw"
        }
        if selectedModelOption?.isNearCloudModel == true {
            return "NEAR AI Cloud"
        }
        return "NEAR Private"
    }

    var selectedRouteUsesNearCloud: Bool {
        selectedModelOption?.isNearCloudModel == true
    }

    var signedTranscriptExportContext: SignedTranscriptExportContext {
        let semantics = sourceRoutingSemantics
        let provider = switch selectedProviderDisplayName {
        case "NEAR AI Cloud":
            "near-cloud"
        case "IronClaw":
            selectedModelOption?.isIronclawMobileRuntime == true ? "ironclaw-mobile" : "ironclaw-hosted"
        case "LLM Council":
            "llm-council"
        default:
            "near-private"
        }
        let privacyRoute = if selectedRouteUsesNearCloud {
            "external-cloud"
        } else if selectedProviderDisplayName == "IronClaw" {
            selectedModelOption?.isIronclawMobileRuntime == true ? "phone-agent" : "hosted-agent"
        } else {
            "tee-private"
        }
        return SignedTranscriptExportContext(
            provider: provider,
            privacyRoute: privacyRoute,
            sourceMode: semantics.focus.rawValue,
            webSearchEnabled: semantics.modelNativeWebToolEnabledByDefault || semantics.appWebGroundingPolicy.isEnabledByDefault,
            projectID: selectedProjectID,
            ownerHash: nil,
            attestationSnapshot: attestationSnapshot
        )
    }

    var selectedRouteKind: ChatRouteKind {
        Self.routeKind(forModelID: selectedModel)
    }

    var currentAttestationStatus: AttestationStatus {
        if isCouncilModeEnabled {
            guard !activeCouncilHasExternalRoutes else {
                return .unavailable(reason: .routeNotSupported)
            }
            return privateRouteAttestationStatus
        }
        guard selectedRouteKind == .nearPrivate else {
            return .unavailable(reason: .routeNotSupported)
        }
        return privateRouteAttestationStatus
    }

    var shouldShowSharedAuthorNames: Bool {
        ShareStore.shouldShowSharedAuthorNames(sharedPreview: sharedPreview, shareInfo: shareInfo)
    }

    private var privateRouteAttestationStatus: AttestationStatus {
        if attestationSnapshot == nil, attestationFetchErrorMessage != nil {
            return .unavailable(reason: .serviceUnavailable)
        }
        return AttestationStatus(snapshot: attestationSnapshot, selectedModelID: selectedModel)
    }

    func routingSemantics(for route: ChatRouteKind) -> ChatSourceRoutingSemantics {
        Self.sourceRoutingSemantics(
            sourceMode: sourceMode,
            researchModeEnabled: researchModeEnabled,
            webSearchEnabled: webSearchEnabled,
            route: route
        )
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
                ? "Council includes NEAR AI Cloud models. Cloud legs use privacy proxy routing; all-private Council lineups can fetch verification proof."
                : "Council is using NEAR Private models. Open Verification when you need a signed private-route report."
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
                ? "Use IronClaw Mobile for projects, files, research, and hosted workstation handoff for git, code, shell, and software tasks."
                : "Use IronClaw Mobile for projects, files, research, source links, memory, and NEAR Private inference."
        }
        if selectedModelOption?.isIronclawHostedModel == true {
            return "Run remote git, code, research, and shell-capable IronClaw work through the hosted endpoint."
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
            return effectiveWebSearchEnabled ? "Ask the council with sources" : "Ask the council"
        }
        if researchModeEnabled && !selectedRouteUsesNearCloud {
            return "Ask for a researched answer"
        }
        switch selectedProviderDisplayName {
        case "IronClaw":
            return selectedModelOption?.isIronclawMobileRuntime == true ? "Ask IronClaw Mobile or the workstation" : "Ask the hosted IronClaw workstation"
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

    private var modelCatalog: ModelCatalogStore {
        ModelCatalogStore(
            models: models,
            nearCloudModels: nearCloudModels,
            allowedModelIDs: currentPlanAllowedModelIDs,
            preferredModelIDs: preferredModelIDs,
            nearCloudPreferredModelIDs: nearCloudPreferredModelIDs
        )
    }

    var externalModels: [ModelOption] {
        modelCatalog.externalModels
    }

    var agentModels: [ModelOption] {
        modelCatalog.agentModels
    }

    var cloudModels: [ModelOption] {
        modelCatalog.cloudModels
    }

    private var cloudRouteModels: [ModelOption] {
        modelCatalog.cloudRouteModels
    }

    var chatModels: [ModelOption] {
        modelCatalog.chatModels
    }

    var currentBillingPlanName: String {
        billingSnapshot?.activeSubscription?.plan ?? "free"
    }

    var hiddenPlanLockedModelCount: Int {
        guard currentPlanAllowedModelIDs != nil else { return 0 }
        return models.filter { !$0.isUtilityModel && !isAllowedByCurrentPlan($0) }.count
    }

    var pickerModels: [ModelOption] {
        modelCatalog.pickerModels
    }

    var eliteModels: [ModelOption] {
        modelCatalog.rankedModels(from: pickerModels.filter { !$0.isOpenWeightCandidate && $0.isEliteModel })
    }

    var openWeightModels: [ModelOption] {
        modelCatalog.rankedModels(from: pickerModels.filter { $0.isOpenWeightCandidate })
    }

    var privateModels: [ModelOption] {
        modelCatalog.rankedModels(from: pickerModels.filter { !$0.isOpenWeightCandidate && $0.isPrivateVerifiableChatModel && !$0.isEliteModel })
    }

    var standardModels: [ModelOption] {
        modelCatalog.rankedModels(from: pickerModels.filter { !$0.isExternalModel && !$0.isOpenWeightCandidate && !$0.isEliteModel && !$0.isPrivateVerifiableChatModel && !$0.isLowerPriorityModel })
    }

    var lowerPriorityModels: [ModelOption] {
        modelCatalog.rankedModels(from: pickerModels.filter { !$0.isExternalModel && !$0.isOpenWeightCandidate && $0.isLowerPriorityModel })
    }

    var otherModels: [ModelOption] {
        modelCatalog.rankedModels(from: pickerModels.filter { !$0.isExternalModel && !$0.isEliteModel })
    }

    func canUseInCouncil(_ modelID: String) -> Bool {
        guard let model = chatModels.first(where: { $0.id == modelID }) else {
            return false
        }
        return isCouncilEligible(model)
    }

    func councilIndex(for modelID: String) -> Int? {
        activeCouncilModels.firstIndex(where: { $0.id == modelID }).map { $0 + 1 }
    }

    func isPinnedModel(_ modelID: String) -> Bool {
        pinnedModelIDs.contains(modelID)
    }

    func togglePinnedModel(_ modelID: String) {
        guard let model = pickerModels.first(where: { $0.id == modelID }) else {
            showBanner("That model is not available on this account.")
            return
        }

        var ids = Self.uniqueStrings(pinnedModelIDs)
        if let index = ids.firstIndex(of: modelID) {
            ids.remove(at: index)
            pinnedModelIDs = ids
            showBanner("Removed \(model.displayName) from pinned models.")
            return
        }

        guard ids.count < Self.maxPinnedModels else {
            showBanner("You can pin up to \(Self.maxPinnedModels) models.")
            return
        }
        ids.insert(modelID, at: 0)
        pinnedModelIDs = ids
        showBanner("Pinned \(model.displayName).")
    }

    func toggleCouncilModel(_ modelID: String) {
        guard let model = chatModels.first(where: { $0.id == modelID }), isCouncilEligible(model) else {
            showBanner("Council mode supports available NEAR Private and NEAR AI Cloud chat models.")
            return
        }

        var ids = normalizedCouncilModelIDs(councilModelIDs)
        if let index = ids.firstIndex(of: modelID) {
            ids.remove(at: index)
            if ids.count == 1, selectedModel != ids[0] {
                selectedModel = ids[0]
            }
            councilModelIDs = ids
            routeReadinessIssue = nil
            showBanner(ids.count > 1 ? "Removed \(model.displayName) from the council." : "Council mode off.")
            return
        }

        if ids.isEmpty, canUseInCouncil(selectedModel) {
            ids.append(selectedModel)
        }
        guard ids.count < Self.maxCouncilModels else {
            showBanner("Council mode supports up to \(Self.maxCouncilModels) models at once.")
            return
        }
        ids.append(modelID)
        councilModelIDs = normalizedCouncilModelIDs(ids)
        if selectedModelOption?.isIronclawModel == true {
            selectedModel = councilModelIDs.first ?? modelID
        }
        routeReadinessIssue = nil
        showBanner(councilModelIDs.count > 1 ? "LLM Council enabled with \(councilModelIDs.count) models." : "Added \(model.displayName).")
    }

    func useDefaultCouncilLineup() {
        let ids = defaultCouncilModelIDs()
        guard ids.count > 1 else {
            showBanner("No complete LLM Council lineup is available on this account.")
            return
        }
        councilModelIDs = ids
        selectedModel = ids[0]
        routeReadinessIssue = nil
        clearAttestationState()
        showBanner("LLM Council enabled with \(ids.count) models.")
    }

    func useCouncilPreset(_ presetID: String) {
        guard let preset = councilPresets.first(where: { $0.id == presetID }) else {
            showBanner("That Council lineup is not available.")
            return
        }
        guard preset.isAvailable else {
            showBanner("\(preset.title) needs at least two available models on this account.")
            return
        }
        councilModelIDs = normalizedCouncilModelIDs(preset.modelIDs)
        selectedModel = councilModelIDs.first ?? selectedModel
        routeReadinessIssue = nil
        clearAttestationState()
        showBanner("\(preset.title) Council enabled with \(councilModelIDs.count) models.")
    }

    func clearCouncilMode() {
        councilModelIDs = canUseInCouncil(selectedModel) ? [selectedModel] : []
        routeReadinessIssue = nil
        clearAttestationState()
        showBanner("Council mode off.")
    }

    func switchToPrivateFallbackModel() {
        guard let replacement = preferredAvailableModel() ?? pickerModels.first(where: { !$0.isExternalModel && !$0.isIronclawModel })?.id else {
            showBanner("No NEAR Private chat model is available on this account.")
            return
        }
        selectedModel = replacement
        councilModelIDs = canUseInCouncil(replacement) ? [replacement] : []
        routeReadinessIssue = nil
        clearAttestationState()
        showBanner("Switched to \(modelDisplayName(for: replacement)).")
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
            showBanner("Configure the hosted IronClaw endpoint in Account, then send again.")
        }
    }

    init(api: PrivateChatAPI) {
        self.api = api
        self.ironclawMobileRuntime = IronclawMobileRuntime(api: api)
        if !UserDefaults.standard.bool(forKey: Self.ironclawThreadMappingMigrationKey) {
            UserDefaults.standard.set(true, forKey: Self.ironclawThreadMappingMigrationKey)
        }
        ironclawSettings = .default
        ironclawTokenConfigured = false
        nearCloudKeyConfigured = false
        selectedModel = Self.defaultModelID
        councilModelIDs = [Self.defaultModelID]
        selectedProjectID = nil
        webSearchEnabled = false
        largeTextAsFileEnabled = true
        sourceMode = .auto
        researchModeEnabled = false
        advancedModelParams = .defaults
        systemPrompt = ""
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

    private func scheduleAccountBackgroundRefresh(for accountID: String? = nil) {
        let resolvedAccountID = accountID ?? storageAccountID
        accountBackgroundRefreshTask?.cancel()
        accountBackgroundRefreshTask = Task { @MainActor [weak self] in
            guard let self, self.storageAccountID == resolvedAccountID else { return }
            await self.refreshBilling(showErrors: false)
            guard !Task.isCancelled, self.storageAccountID == resolvedAccountID else { return }
            await self.refreshSharedWithMe(showErrors: false)
            guard !Task.isCancelled, self.storageAccountID == resolvedAccountID else { return }
            if self.ironclawSettings.hasUsableHostedEndpoint {
                await self.refreshIronclawTools()
            }
        }
    }

    private func scheduleConversationListRefresh() {
        Task { @MainActor [weak self] in
            await self?.refreshConversations()
        }
    }

    func prepareForAuthenticatedAccount(_ accountID: String?) {
        let resolvedAccountID = Self.storageScope(for: accountID)
        // Configure memory + activity log up front (even when the account is
        // unchanged) so a fresh signed-out launch still persists them rather
        // than keeping them in RAM until the first account switch.
        memoryStore.configure(accountID: resolvedAccountID)
        activityLog.configure(accountID: resolvedAccountID)
        guard resolvedAccountID != storageAccountID else { return }
        if Self.shouldMigrateStorage(from: storageAccountID, to: resolvedAccountID) {
            Self.migrateAccountScopedStorage(from: storageAccountID, to: resolvedAccountID)
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
        streamTask?.cancel()
        streamTask = nil
        cancelPendingTextDeltaFlushes()
        accountBackgroundRefreshTask?.cancel()
        accountBackgroundRefreshTask = nil
        bootstrapInFlightAccountID = nil
        lastBootstrappedAccountID = nil
        currentCouncilAssistantMessageIDs = []
        conversations = []
        messages = []
        models = []
        nearCloudModels = []
        shareInfo = nil
        clearAttestationState()
        sharedWithMe = []
        sharedPreview = nil
        pendingExternalDeepLink = nil
        pendingHostedHandoffPreflight = nil
        pendingHostedHandoffContinuation = nil
        currentUserMessageMetadata = nil
        approvedHostedHandoffFingerprint = nil
        routeReadinessIssue = nil
        pendingAttachments = []
        pendingLargePasteTexts = [:]
        pendingDocumentTexts = [:]
        pendingDocumentTextIDs = []
        projects = []
        remoteFiles = []
        remoteFilePreview = nil
        shareGroups = []
        billingSnapshot = nil
        diagnosticChecks = []
        pinnedModelIDs = []
        selectedProjectID = nil
        selectedConversation = nil
        draft = ""
        isStreaming = false
        isUploadingAttachment = false
        isLoadingRemoteFilePreview = false
        isLoadingRemoteFiles = false
        isLoadingShareGroups = false
    }

    func resetInteractionDefaults() {
        selectedModel = Self.defaultModelID
        councilModelIDs = [Self.defaultModelID]
        selectedProjectID = nil
        webSearchEnabled = false
        sourceMode = .auto
        researchModeEnabled = false
        advancedModelParams = .defaults
        routeReadinessIssue = nil
        clearAttestationState()
        showBanner("Defaults reset.")
    }

    func refreshConversations(showErrors: Bool = true) async {
        do {
            let fetchedConversations = try await api.fetchConversations()
            if conversations != fetchedConversations {
                conversations = fetchedConversations
            }
            cacheConversations(fetchedConversations)
            ConversationSpotlightIndex.index(fetchedConversations)
            if let selectedConversation,
               let refreshed = fetchedConversations.first(where: { $0.id == selectedConversation.id }),
               self.selectedConversation != refreshed {
                self.selectedConversation = refreshed
            }
        } catch {
            if conversations.isEmpty {
                conversations = loadCachedConversations()
            }
            if showErrors {
                showBanner(conversations.isEmpty ? "Could not refresh chats. Pull to retry." : "Could not refresh chats. Showing cached list.")
            }
        }
    }

    func importChats(from url: URL) async {
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = values.fileSize,
               fileSize > ChatImportLimits.maxImportBytes {
                showBanner("Import JSON must be 8 MB or smaller.")
                return
            }
            let imports = try await Task.detached(priority: .userInitiated, operation: {
                let data = try Data(contentsOf: url)
                return try ChatImportBuilder.conversations(from: data)
            }).value
            guard !imports.isEmpty else {
                showBanner("No importable chats found in that JSON file.")
                return
            }
            guard imports.count <= ChatImportLimits.maxConversationCount,
                  imports.reduce(0, { $0 + $1.items.count }) <= ChatImportLimits.maxTotalItemCount else {
                showBanner("Import is too large to sync safely.")
                return
            }

            isLoading = true
            defer { isLoading = false }

            var importedCount = 0
            var failures: [String] = []
            let importedAt = String(Int(Date().timeIntervalSince1970 * 1000))

            for importedConversation in imports {
                do {
                    let title = Self.clippedTitle(importedConversation.title)
                    let metadata = [
                        "imported_at": importedAt,
                        "initial_created_at": String(Int(importedConversation.timestamp ?? Date().timeIntervalSince1970))
                    ]
                    let conversation = try await api.createConversation(title: title, metadata: metadata)
                    for batch in importedConversation.batchedItems {
                        try await api.addItemsToConversation(conversation.id, items: batch)
                    }
                    importedCount += 1
                } catch {
                    failures.append("\(importedConversation.title): \(Self.displayFailureMessage(error.localizedDescription))")
                }
            }

            await refreshConversations()
            if importedCount > 0 {
                showBanner(failures.isEmpty ? "Imported \(importedCount) chat\(importedCount == 1 ? "" : "s")." : "Imported \(importedCount); \(failures.count) failed.")
            } else {
                showBanner(failures.first ?? "Chat import failed.")
            }
        } catch {
            showBanner(Self.displayFailureMessage(error.localizedDescription))
        }
    }

    func refreshModels(loadCloudCatalog: Bool = false) async {
        do {
            let fetched = try await api.fetchModels()
            let fetchedCloud = loadCloudCatalog
                ? (try? await api.fetchNearCloudModels(apiKey: loadNearCloudAPIKey())) ?? []
                : []
            deniedOpenWeightModelIDs.removeAll()
            if models != fetched {
                models = fetched
            }
            if loadCloudCatalog {
                let routeModels = Self.nearCloudRouteModels(from: fetchedCloud)
                if nearCloudModels != routeModels {
                    nearCloudModels = routeModels
                }
            }
            if nearCloudModels.isEmpty {
                nearCloudModels = Self.fallbackNearCloudModels()
            }
            ensureSelectedModelIsAvailable(shouldShowBanner: false)
            normalizeCouncilSelection()
        } catch {
            if models.isEmpty {
                models = [
                    ModelOption(modelID: Self.defaultModelID, publicModel: true, metadata: nil),
                    ModelOption(modelID: "anthropic/claude-opus-4-7", publicModel: true, metadata: nil),
                    ModelOption(modelID: "google/gemini-3-pro", publicModel: true, metadata: nil),
                    ModelOption(modelID: "openai/gpt-oss-120b", publicModel: true, metadata: nil),
                    ModelOption(modelID: "Qwen/Qwen3-30B-A3B-Instruct-2507", publicModel: true, metadata: nil)
                ]
                normalizeCouncilSelection()
            }
            if nearCloudModels.isEmpty {
                nearCloudModels = Self.fallbackNearCloudModels()
            }
            showBanner(error.localizedDescription)
        }
    }

    func refreshUserSettings(showErrors: Bool = true) async {
        do {
            let response = try await api.fetchUserSettings()
            apply(remoteSettings: response.settings)
        } catch {
            if showErrors {
                showBanner(error.localizedDescription)
            }
        }
    }

    func saveUserSettings(
        systemPrompt: String,
        webSearchEnabled: Bool,
        notificationEnabled: Bool,
        appearancePreference: AppAppearancePreference,
        largeTextAsFileEnabled: Bool,
        advancedParams: AdvancedModelParams
    ) async {
        let sanitizedParams = advancedParams.sanitized
        do {
            let response = try await api.updateUserSettings(
                systemPrompt: systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
                webSearchEnabled: webSearchEnabled,
                notificationEnabled: notificationEnabled,
                appearance: appearancePreference.rawValue,
                largeTextAsFile: largeTextAsFileEnabled,
                advancedParams: sanitizedParams
            )
            apply(remoteSettings: response.settings)
            advancedModelParams = sanitizedParams
            showBanner("Account preferences saved.")
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func refreshBilling(showErrors: Bool = true) async {
        guard !isLoadingBilling else { return }
        isLoadingBilling = true
        defer { isLoadingBilling = false }
        do {
            async let plansLoad = api.fetchSubscriptionPlans()
            async let subscriptionsLoad = api.fetchSubscriptions(includeInactive: false)
            let (plans, subscriptions) = try await (plansLoad, subscriptionsLoad)
            billingSnapshot = BillingSnapshot(plans: plans, subscriptions: subscriptions, fetchedAt: Date())
            ensureSelectedModelIsAvailable(shouldShowBanner: false)
        } catch {
            if showErrors {
                showBanner("Billing unavailable: \(error.localizedDescription)")
            }
        }
    }

    /// Opens a conversation by id (e.g. from a CoreSpotlight result) if it's in
    /// the loaded list. No-op otherwise — the app still foregrounds to home.
    func openConversation(byID id: String) {
        guard let conversation = conversations.first(where: { $0.id == id }) else { return }
        selectConversation(conversation)
    }

    func selectConversation(_ conversation: ConversationSummary) {
        guard !isStreaming else {
            showBanner("Finish or cancel the current response before switching chats.")
            return
        }
        persistCurrentDraftIfNeeded()
        selectedConversation = conversation
        shareInfo = nil
        scheduleMessageLoad(for: conversation)
        transitionDraftScopeToCurrentSelection(loadDraft: true)
    }

    func startNewConversation() {
        guard !isStreaming else {
            showBanner("Finish or cancel the current response before starting a new chat.")
            return
        }
        persistCurrentDraftIfNeeded()
        selectedConversation = nil
        cancelMessageLoad()
        messages = []
        shareInfo = nil
        transitionDraftScopeToCurrentSelection(loadDraft: true)
    }

    /// UserDefaults keys an App Intent (Siri/Shortcuts) writes; the app consumes
    /// them on activation. The intents run in-process (main-target App Intents),
    /// so plain UserDefaults is shared — no App Group needed.
    static let pendingSiriPromptKey = "pendingSiriPrompt"
    static let pendingRunBriefingsKey = "pendingRunBriefings"

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
    ) -> Bool {
        guard let item = PendingShareStore.read(from: fileURL) else { return false }
        guard !isStreaming else {
            // Leave the file in place; the next activation can retry once the
            // current response finishes.
            showBanner("Finish or cancel the current response before starting a new chat.")
            return false
        }
        PendingShareStore.clear(fileURL)
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        startNewConversation()
        draft = String(text.prefix(AppDeepLinkAction.maxDraftCharacters))
        AppHaptics.selection()
        return true
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
            route = "a verified private chat"
        }
        let source = action.sourceMode.map { " Source: \($0.title)." } ?? ""
        let research = action.researchMode ? " Research mode will be enabled." : ""
        let hostedBridge = action.hostedBridgeImport.map { bridge in
            let host = bridge.host ?? "the hosted IronClaw endpoint"
            let token = bridge.authToken == nil ? "" : " Token will be saved."
            let thread = bridge.threadID == nil ? "" : " Thread reuse will be configured."
            let enabled = bridge.isEnabled ? " Hosted bridge for \(host) will be saved and enabled." : " Hosted bridge for \(host) will be saved."
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
                showBanner(action.draft == nil ? "Verified private chat ready." : "Verified prompt ready.")
            }
        }
        openSelectedConversationToken = UUID()
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
        guard let model = chatModels.first(where: { $0.id == modelID }),
              isAllowedByCurrentPlan(model) else {
            showBanner("That model is not available on the \(currentBillingPlanName) plan.")
            return
        }
        selectedModel = modelID
        routeReadinessIssue = nil
        clearAttestationState()
        councilModelIDs = isCouncilEligible(model) ? [modelID] : []
        if model.isNearCloudModel, !nearCloudKeyConfigured {
            showBanner("Using \(model.displayName). Connect NEAR AI Cloud in Account before sending.")
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
        webSearchEnabled.toggle()
        showBanner(webSearchEnabled ? "Web search enabled." : "Web search disabled.")
    }

    func selectSourceMode(_ mode: ChatSourceMode) {
        let wasResearchModeEnabled = researchModeEnabled
        if wasResearchModeEnabled {
            researchModeEnabled = false
        }
        sourceMode = mode
        showBanner(wasResearchModeEnabled ? "Focus: \(mode.title)." : "Focus: \(mode.title).")
    }

    func toggleResearchMode() {
        guard !selectedRouteUsesNearCloud else {
            showBanner("Research focus needs a NEAR Private route or app-side web grounding.")
            return
        }
        researchModeEnabled.toggle()
        showBanner(researchModeEnabled ? "Research focus on." : "Research focus off.")
    }

    func saveIronclawIntegration(
        isEnabled: Bool,
        baseURL: String,
        authToken: String,
        threadID: String
    ) {
        let requestedSettings = IronclawSettings(
            isEnabled: isEnabled,
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            threadID: threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let savedSettings = requestedSettings.standalonePhoneSanitized
        ironclawSettings = savedSettings
        if savedSettings.hasUsableHostedEndpoint {
            routeReadinessIssue = nil
        }

        let trimmedToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToken.isEmpty {
            do {
                try KeychainStore.save(trimmedToken, account: scopedKeychainAccount(Self.ironclawTokenKeychainAccount))
                ironclawTokenConfigured = true
            } catch {
                ironclawStatusText = error.localizedDescription
                showBanner(error.localizedDescription)
                return
            }
        }

        if !savedSettings.isEnabled, selectedModelOption?.isIronclawHostedModel == true {
            selectedModel = Self.defaultModelID
        }

        if isEnabled, let validationMessage = requestedSettings.endpointValidationMessage {
            ironclawStatusText = validationMessage
            ironclawLastVerifiedAt = nil
            showBanner(validationMessage)
            return
        }

        if savedSettings.hasUsableHostedEndpoint {
            ironclawStatusText = ironclawTokenConfigured ? "Hosted endpoint and token saved." : "Hosted endpoint saved."
            showBanner(savedSettings.isEnabled ? "IronClaw hosted endpoint enabled." : "IronClaw endpoint saved.")
        } else {
            ironclawStatusText = ironclawTokenConfigured ? "Endpoint token saved. Add hosted URL." : "Not connected"
            showBanner("IronClaw settings saved.")
        }
    }

    func disconnectIronclaw() {
        KeychainStore.delete(account: scopedKeychainAccount(Self.ironclawTokenKeychainAccount))
        ironclawTokenConfigured = false
        ironclawSettings.isEnabled = false
        ironclawStatusText = "Not connected"
        ironclawLastVerifiedAt = nil
        ironclawToolNames = []
        if selectedModelOption?.isIronclawHostedModel == true {
            selectedModel = Self.defaultModelID
        }
        routeReadinessIssue = nil
        showBanner("IronClaw disconnected.")
    }

    func saveNearCloudAPIKey(_ apiKey: String) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            showBanner("Paste a NEAR AI Cloud key first.")
            return
        }

        do {
            try KeychainStore.save(trimmedKey, account: scopedKeychainAccount(Self.nearCloudAPIKeychainAccount))
            nearCloudKeyConfigured = true
            routeReadinessIssue = nil
            showBanner("NEAR AI Cloud key saved.")
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func connectNearCloudAccount() async -> Bool {
        isConnectingNearCloudAccount = true
        defer { isConnectingNearCloudAccount = false }

        do {
            let response = try await api.connectNearCloudAccount()
            guard let apiKey = response.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
                let message = response.message?.trimmingCharacters(in: .whitespacesAndNewlines)
                showBanner(message?.isEmpty == false ? message! : "Cloud auto-connect is not available yet. Open Cloud, create a key, then paste it here.")
                return false
            }

            let fetchedCloud = response.models.isEmpty
                ? try await api.fetchNearCloudModels(apiKey: apiKey)
                : response.models
            try KeychainStore.save(apiKey, account: scopedKeychainAccount(Self.nearCloudAPIKeychainAccount))
            nearCloudKeyConfigured = true
            routeReadinessIssue = nil
            let routeModels = Self.nearCloudRouteModels(from: fetchedCloud)
            nearCloudModels = routeModels.isEmpty ? Self.fallbackNearCloudModels() : routeModels
            showBanner("NEAR AI Cloud connected. \(nearCloudModels.count) models ready.")
            return true
        } catch APIError.status(let code, _) where code == 404 || code == 405 {
            showBanner("Cloud auto-connect is not available yet. Open Cloud, create a key, then paste it here.")
            return false
        } catch {
            showBanner("Cloud auto-connect failed: \(Self.displayFailureMessage(error.localizedDescription))")
            return false
        }
    }

    func connectNearCloudAPIKey(_ apiKey: String) async -> Bool {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            showBanner("Paste a NEAR AI Cloud key first.")
            return false
        }

        isTestingNearCloudKey = true
        defer { isTestingNearCloudKey = false }

        do {
            let fetchedCloud = try await api.fetchNearCloudModels(apiKey: trimmedKey)
            try KeychainStore.save(trimmedKey, account: scopedKeychainAccount(Self.nearCloudAPIKeychainAccount))
            nearCloudKeyConfigured = true
            routeReadinessIssue = nil
            let routeModels = Self.nearCloudRouteModels(from: fetchedCloud)
            nearCloudModels = routeModels.isEmpty ? Self.fallbackNearCloudModels() : routeModels
            showBanner("NEAR AI Cloud connected. \(nearCloudModels.count) models ready.")
            return true
        } catch {
            showBanner("NEAR AI Cloud key was not saved: \(Self.displayFailureMessage(error.localizedDescription))")
            return false
        }
    }

    func clearNearCloudAPIKey() {
        KeychainStore.delete(account: scopedKeychainAccount(Self.nearCloudAPIKeychainAccount))
        nearCloudKeyConfigured = false
        if selectedModelOption?.isNearCloudModel == true {
            selectedModel = Self.defaultModelID
        }
        routeReadinessIssue = nil
        showBanner("NEAR AI Cloud disconnected.")
    }

    func testIronclawConnection() async {
        guard ironclawSettings.hasUsableHostedEndpoint else {
            let message = ironclawSettings.endpointValidationMessage ?? "Add a hosted HTTPS IronClaw endpoint first."
            ironclawStatusText = message
            showBanner(message)
            return
        }
        isTestingIntegration = true
        defer { isTestingIntegration = false }
        do {
            let message = try await ironclawAPI.testConnection(
                settings: ironclawSettings,
                authToken: loadIronclawAuthToken()
            )
            ironclawStatusText = message
            await refreshIronclawTools()
            showBanner("IronClaw reachable.")
        } catch {
            ironclawStatusText = error.localizedDescription
            showBanner(error.localizedDescription)
        }
    }

    func testIronclawWorkstation() async {
        guard ironclawSettings.hasUsableHostedEndpoint else {
            let message = ironclawSettings.endpointValidationMessage ?? "Add a hosted HTTPS IronClaw endpoint first."
            ironclawStatusText = message
            showBanner(message)
            return
        }
        isTestingIronclawWorkstation = true
        defer { isTestingIronclawWorkstation = false }
        do {
            let message = try await ironclawAPI.testWorkstationCapability(
                settings: ironclawSettings,
                authToken: loadIronclawAuthToken()
            )
            ironclawStatusText = message
            ironclawLastVerifiedAt = Date()
            await refreshIronclawTools()
            showBanner("IronClaw workstation verified.")
        } catch {
            let message = Self.displayFailureMessage(error.localizedDescription)
            ironclawStatusText = message
            showBanner(message)
        }
    }

    func refreshIronclawTools() async {
        guard ironclawSettings.hasUsableHostedEndpoint else {
            ironclawToolNames = []
            return
        }
        do {
            ironclawToolNames = try await ironclawAPI.fetchToolNames(
                settings: ironclawSettings,
                authToken: loadIronclawAuthToken()
            )
        } catch {
            ironclawToolNames = []
        }
    }

    func runDiagnostics() async {
        guard !isRunningDiagnostics else { return }
        isRunningDiagnostics = true
        diagnosticChecks = [
            AppDiagnosticCheck(title: "Model catalog", detail: "Checking NEAR Private API models.", state: .running),
            AppDiagnosticCheck(title: "Web grounding", detail: "Searching a live AI-news query.", state: .running),
            AppDiagnosticCheck(title: "IronClaw bridge", detail: "Checking hosted endpoint and bearer token.", state: .running),
            AppDiagnosticCheck(title: "IronClaw workstation", detail: "Verifying hosted shell/git tools.", state: .running),
            AppDiagnosticCheck(title: "NEAR AI Cloud", detail: nearCloudKeyConfigured ? "Connected." : "Not connected.", state: nearCloudKeyConfigured ? .passed : .warning)
        ]
        defer {
            isRunningDiagnostics = false
            showBanner("Diagnostics complete.")
        }

        do {
            let fetched = try await api.fetchModels()
            deniedOpenWeightModelIDs.removeAll()
            models = fetched
            ensureSelectedModelIsAvailable(shouldShowBanner: false)
            updateDiagnostic(
                title: "Model catalog",
                detail: "\(pickerModels.count) curated chat models available.",
                state: pickerModels.isEmpty ? .warning : .passed
            )
        } catch {
            updateDiagnostic(
                title: "Model catalog",
                detail: "Private API model fetch failed: \(Self.displayFailureMessage(error.localizedDescription))",
                state: .failed
            )
        }

        do {
            let context = try await webGroundingService.search(for: "What is the latest news on AI? Use web search and cite sources.", preferNews: true)
            updateDiagnostic(
                title: "Web grounding",
                detail: "Query: \(context.query). \(context.sources.count) sources returned.",
                state: context.sources.isEmpty ? .warning : .passed
            )
        } catch {
            updateDiagnostic(
                title: "Web grounding",
                detail: "Search failed: \(Self.displayFailureMessage(error.localizedDescription))",
                state: .failed
            )
        }

        guard ironclawSettings.hasUsableHostedEndpoint else {
            updateDiagnostic(
                title: "IronClaw bridge",
                detail: ironclawSettings.endpointValidationMessage ?? "Add a hosted HTTPS IronClaw endpoint.",
                state: .warning
            )
            updateDiagnostic(
                title: "IronClaw workstation",
                detail: "Add a hosted HTTPS IronClaw endpoint before testing tools.",
                state: .warning
            )
            return
        }

        var bridgePassed = false
        do {
            let message = try await ironclawAPI.testConnection(
                settings: ironclawSettings,
                authToken: loadIronclawAuthToken()
            )
            ironclawStatusText = message
            updateDiagnostic(title: "IronClaw bridge", detail: message, state: .passed)
            bridgePassed = true
        } catch {
            let message = Self.displayFailureMessage(error.localizedDescription)
            ironclawStatusText = message
            updateDiagnostic(title: "IronClaw bridge", detail: message, state: .failed)
        }
        guard bridgePassed else {
            updateDiagnostic(
                title: "IronClaw workstation",
                detail: "Bridge check failed before tool preflight.",
                state: .warning
            )
            return
        }

        do {
            let message = try await ironclawAPI.testWorkstationCapability(
                settings: ironclawSettings,
                authToken: loadIronclawAuthToken()
            )
            ironclawStatusText = message
            ironclawLastVerifiedAt = Date()
            updateDiagnostic(title: "IronClaw workstation", detail: message, state: message.contains("verified") ? .passed : .warning)
        } catch {
            let message = Self.displayFailureMessage(error.localizedDescription)
            ironclawStatusText = message
            updateDiagnostic(title: "IronClaw workstation", detail: message, state: .failed)
        }
    }

    func selectAllChats() {
        persistCurrentDraftIfNeeded()
        selectedProjectID = nil
        transitionDraftScopeToCurrentSelection(loadDraft: true)
    }

    func applySetupProfile(_ rawProfile: UserSetupProfile) {
        let profile = rawProfile.normalizedForDefaults
        let readiness = AppSetupReadinessSnapshot(
            modelCatalogLoaded: !models.isEmpty,
            privateModelAvailable: pickerModels.contains { !$0.isExternalModel },
            defaultCouncilModelCount: defaultCouncilModels.count,
            ironclawMobileAvailable: agentModels.contains { $0.id == ModelOption.ironclawMobileModelID },
            hostedIronclawAvailable: ironclawRemoteWorkstationAvailable,
            nearCloudKeyConfigured: nearCloudKeyConfigured
        )
        let plan = AppSetupPlan(profile: profile, readiness: readiness)
        webSearchEnabled = profile.wantsWeb
        sourceMode = plan.focusMode
        researchModeEnabled = profile.useCases.contains(.research) && plan.modelRoute != .ironclaw

        let requestedCouncilModelIDs = plan.modelRoute == .council ? defaultCouncilModelIDs() : []
        switch plan.modelRoute {
        case .ironclaw:
            selectedModel = ModelOption.ironclawMobileModelID
            councilModelIDs = []
        case .council:
            councilModelIDs = requestedCouncilModelIDs
            selectedModel = requestedCouncilModelIDs.first ?? preferredAvailableModel() ?? Self.defaultModelID
        case .privateModel:
            let selectedModelIsUsablePrivateModel =
                pickerModels.contains(where: { $0.id == selectedModel && !$0.isExternalModel }) &&
                Self.routeKind(forModelID: selectedModel) == .nearPrivate
            if !selectedModelIsUsablePrivateModel {
                selectedModel = preferredAvailableModel() ?? Self.defaultModelID
            }
            councilModelIDs = canUseInCouncil(selectedModel) ? [selectedModel] : []
        }

        if let projectName = profile.setupStarterProjectName {
            let project = ensureMobileProject(named: projectName, includeConversationID: nil)
            selectedProjectID = project.id
            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                var didChangeProject = false
                let instructions = profile.setupProjectInstructions
                if projects[index].instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    projects[index].instructions = instructions
                    didChangeProject = true
                }
                didChangeProject = seedSetupProjectMetadata(projectIndex: index, profile: profile) || didChangeProject
                if didChangeProject {
                    saveProjects()
                }
            }
        } else if profile.contextStyle == .simple {
            selectedProjectID = nil
        }

        let shouldSeedStarterDraft = shouldSeedSetupStarterDraft(for: profile)
        if let draft = profile.firstRunDraft, shouldSeedStarterDraft {
            startNewConversation()
            self.draft = draft
            openSelectedConversationToken = UUID()
            showBanner(setupAppliedBanner(for: plan, profile: profile, openedDraft: true))
        } else {
            showBanner(setupAppliedBanner(for: plan, profile: profile, openedDraft: false))
        }
    }

    private func setupAppliedBanner(for plan: AppSetupPlan, profile: UserSetupProfile, openedDraft: Bool) -> String {
        if profile.wantsIronclaw, plan.modelRoute != .ironclaw {
            return openedDraft
                ? "Setup applied. Private prompt ready while agent tools stay unavailable."
                : "Setup applied. Private route is ready while agent tools stay unavailable."
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

    private func seedSetupProjectMetadata(projectIndex index: Int, profile: UserSetupProfile) -> Bool {
        guard projects.indices.contains(index) else { return false }
        var didChange = false
        let style = Self.setupProjectStyle(for: profile)
        if projects[index].iconName == ProjectIcon.folder.symbolName {
            projects[index].iconName = style.iconName
            didChange = true
        }
        if projects[index].paletteName == ProjectPalette.sky.rawValue, style.paletteName != ProjectPalette.sky.rawValue {
            projects[index].paletteName = style.paletteName
            didChange = true
        }
        let setupGuideText = Self.setupGuideNoteText(for: profile)
        if let noteIndex = projects[index].notes.firstIndex(where: { $0.title == Self.setupGuideNoteTitle }) {
            var note = projects[index].notes.remove(at: noteIndex)
            if note.text != setupGuideText {
                note.text = setupGuideText
                didChange = true
            }
            projects[index].notes.insert(note, at: 0)
            if noteIndex != 0 {
                didChange = true
            }
        } else {
            projects[index].notes.insert(
                ProjectNote(title: Self.setupGuideNoteTitle, text: setupGuideText),
                at: 0
            )
            projects[index].notes = Array(projects[index].notes.prefix(20))
            didChange = true
        }
        return didChange
    }

    private static let setupGuideNoteTitle = "Setup guide"

    private static func setupProjectStyle(for profile: UserSetupProfile) -> (iconName: String, paletteName: String) {
        if profile.useCases.contains(.buildAgents) {
            return (ProjectIcon.agent.symbolName, ProjectPalette.violet.rawValue)
        }
        if profile.useCases.contains(.research) {
            return (ProjectIcon.research.symbolName, ProjectPalette.mint.rawValue)
        }
        if profile.useCases.contains(.teamProjects) {
            return (ProjectIcon.memo.symbolName, ProjectPalette.amber.rawValue)
        }
        return (ProjectIcon.folder.symbolName, ProjectPalette.sky.rawValue)
    }

    private static func setupGuideNoteText(for profile: UserSetupProfile) -> String {
        var lines = [
            "This workspace was created from setup so your first chats can reuse the same sources, notes, and instructions.",
            "",
            "Suggested next steps:"
        ]
        if profile.useCases.contains(.research) {
            lines.append("- Add one source link, then ask for a cited research brief.")
        }
        if profile.useCases.contains(.buildAgents) {
            lines.append("- Paste a repo or issue link, then ask IronClaw to plan the first patch and test pass.")
        }
        if profile.useCases.contains(.teamProjects) {
            lines.append("- Save project decisions here so future chats inherit the context.")
        }
        if profile.useCases.contains(.privateChat) {
            lines.append("- Ask privately first; turn on web or files only when the task needs them.")
        }
        let goal = profile.normalizedGoalText
        if !goal.isEmpty {
            lines.append("")
            lines.append("Setup goal: \(goal)")
        }
        return lines.joined(separator: "\n")
    }

    func selectProject(_ project: ChatProject) {
        guard !project.isArchived else {
            showBanner("Unarchive this project before opening it.")
            return
        }
        persistCurrentDraftIfNeeded()
        selectedProjectID = project.id
        let projectConversationIDs = Set(project.conversationIDs)
        if let selectedConversation, projectConversationIDs.contains(selectedConversation.id) {
            transitionDraftScopeToCurrentSelection(loadDraft: true)
            return
        }

        if let latestConversation = conversations
            .filter({ projectConversationIDs.contains($0.id) && !$0.isArchived })
            .sorted(by: { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) })
            .first {
            selectedConversation = latestConversation
            shareInfo = nil
            scheduleMessageLoad(for: latestConversation)
            transitionDraftScopeToCurrentSelection(loadDraft: true)
        } else {
            selectedConversation = nil
            cancelMessageLoad()
            messages = []
            shareInfo = nil
            transitionDraftScopeToCurrentSelection(loadDraft: true)
        }
    }

    func createProject(
        named name: String,
        instructions: String = "",
        iconName: String = ProjectIcon.folder.symbolName,
        paletteName: String = ProjectPalette.sky.rawValue
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showBanner("Name the project first.")
            return
        }
        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = ChatProject(
            id: "project-\(UUID().uuidString)",
            name: trimmed,
            createdAt: Date(),
            conversationIDs: selectedConversation.map { [$0.id] } ?? [],
            instructions: trimmedInstructions,
            iconName: iconName,
            paletteName: paletteName
        )
        projects.insert(project, at: 0)
        selectedProjectID = project.id
        saveProjects()
        showBanner("Project created.")
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
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else {
            showBanner("Project not found.")
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            showBanner("Name the project first.")
            return
        }

        projects[index].name = String(trimmedName.prefix(80))
        projects[index].iconName = iconName
        projects[index].paletteName = paletteName
        if let instructions {
            projects[index].instructions = String(instructions.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4_000))
        }
        saveProjects()
        showBanner("Project updated.")
    }

    func archiveProject(_ project: ChatProject) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else {
            showBanner("Project not found.")
            return
        }
        guard !projects[index].isArchived else {
            showBanner("Project already archived.")
            return
        }
        projects[index].archivedAt = Date()
        if selectedProjectID == project.id {
            selectedProjectID = nil
        }
        saveProjects()
        showBanner("Project archived.")
    }

    func unarchiveProject(_ project: ChatProject) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else {
            showBanner("Project not found.")
            return
        }
        guard projects[index].isArchived else {
            showBanner("Project is already active.")
            return
        }
        projects[index].archivedAt = nil
        saveProjects()
        showBanner("Project restored.")
    }

    func updateSelectedProjectInstructions(_ instructions: String) {
        guard let selectedProjectID,
              let index = projects.firstIndex(where: { $0.id == selectedProjectID }) else {
            showBanner("Select a project first.")
            return
        }
        projects[index].instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        saveProjects()
        showBanner("Project instructions saved.")
    }

    func updateSelectedProjectMemory(_ memory: String) {
        guard let selectedProjectID,
              let index = projects.firstIndex(where: { $0.id == selectedProjectID }) else {
            showBanner("Select a project first.")
            return
        }
        projects[index].memorySummary = memory.trimmingCharacters(in: .whitespacesAndNewlines)
        saveProjects()
        showBanner("Project memory saved.")
    }

    func addSelectedProjectLink(title: String, url rawURL: String) {
        guard let selectedProjectID,
              let index = projects.firstIndex(where: { $0.id == selectedProjectID }) else {
            showBanner("Select a project first.")
            return
        }
        guard projects[index].links.count < 24 else {
            showBanner("This project already has enough links.")
            return
        }
        guard let normalizedURL = Self.normalizedProjectLinkURL(rawURL) else {
            showBanner("Enter a public HTTPS link.")
            return
        }
        if projects[index].links.contains(where: { $0.urlString == normalizedURL.absoluteString }) {
            showBanner("That link is already in this project.")
            return
        }
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = ProjectLink(
            title: resolvedTitle,
            urlString: normalizedURL.absoluteString
        )
        projects[index].links.insert(link, at: 0)
        saveProjects()
        showBanner("Project link added.")
    }

    func deleteProjectLink(_ link: ProjectLink) {
        guard let selectedProjectID,
              let index = projects.firstIndex(where: { $0.id == selectedProjectID }) else {
            return
        }
        projects[index].links.removeAll { $0.id == link.id }
        saveProjects()
        showBanner("Project link removed.")
    }

    func saveMessageAsProjectNote(_ message: ChatMessage) {
        guard message.role == .assistant else { return }
        guard let selectedProjectID,
              let index = projects.firstIndex(where: { $0.id == selectedProjectID }) else {
            showBanner("Select a project before saving notes.")
            return
        }
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            showBanner("No output to save.")
            return
        }
        let title = Self.noteTitle(from: text)
        let clippedText = Self.clipped(text, maxCharacters: 12_000)
        if projects[index].notes.contains(where: { note in
            note.sourceMessageID == message.id || note.text == clippedText
        }) {
            showBanner("Already saved to \(projects[index].name).")
            return
        }
        let note = ProjectNote(
            title: title,
            text: clippedText,
            sourceMessageID: message.id
        )
        projects[index].notes.insert(note, at: 0)
        if projects[index].notes.count > 20 {
            projects[index].notes = Array(projects[index].notes.prefix(20))
        }
        saveProjects()
        showBanner("Saved to \(projects[index].name).")
    }

    func deleteProjectNote(_ note: ProjectNote) {
        guard let selectedProjectID,
              let index = projects.firstIndex(where: { $0.id == selectedProjectID }) else {
            return
        }
        projects[index].notes.removeAll { $0.id == note.id }
        saveProjects()
        showBanner("Project note removed.")
    }

    func assignSelectedConversation(to projectID: String?) {
        guard let selectedConversation else { return }
        assign(conversationID: selectedConversation.id, to: projectID)
    }

    func assign(conversationID: String, to projectID: String?) {
        for index in projects.indices {
            projects[index].conversationIDs.removeAll { $0 == conversationID }
        }
        if let projectID,
           let index = projects.firstIndex(where: { $0.id == projectID }) {
            projects[index].conversationIDs.append(conversationID)
            showBanner("Moved to \(projects[index].name).")
        } else {
            showBanner("Removed from projects.")
        }
        saveProjects()
    }

    func addAttachment(from url: URL) async {
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
            let notice = attachmentUploadNotice
            attachmentUploadNotice = nil
            pendingAttachments.append(attachment)
            registerUploadedAttachment(attachment)
            showBanner(notice ?? "Attached \(attachment.name).")
        }
    }

    func addProjectAttachment(from url: URL) async {
        guard let selectedProjectID,
              let projectIndex = projects.firstIndex(where: { $0.id == selectedProjectID }) else {
            showBanner("Select a project first.")
            return
        }
        switch FileStore.projectAttachmentLimit(
            projectAttachmentCount: projects[projectIndex].attachments.count,
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
            projects[projectIndex].attachments.append(attachment)
            registerUploadedAttachment(attachment)
            saveProjects()
            showBanner(notice ?? "Added \(attachment.name) to \(projects[projectIndex].name).")
        }
    }

    func refreshRemoteFiles(showErrors: Bool = true) async {
        guard !isLoadingRemoteFiles else { return }
        isLoadingRemoteFiles = true
        defer { isLoadingRemoteFiles = false }

        do {
            let response = try await api.fetchFiles()
            remoteFiles = response.data.sorted {
                ($0.createdAt ?? 0) > ($1.createdAt ?? 0)
            }
            if showErrors {
                showBanner("File library refreshed.")
            }
        } catch {
            if showErrors {
                showBanner(error.localizedDescription)
            }
        }
    }

    func previewRemoteFile(_ file: RemoteFileInfo) async {
        guard !isLoadingRemoteFilePreview else { return }
        isLoadingRemoteFilePreview = true
        remoteFilePreview = nil
        defer { isLoadingRemoteFilePreview = false }

        do {
            let metadata = (try? await api.fetchFile(file.id)) ?? file
            let data = try await api.fetchFilePreviewContent(file.id)
            remoteFilePreview = RemoteFilePreview(file: metadata, data: data, maxPreviewBytes: PrivateChatAPI.maxFilePreviewBytes)
        } catch {
            showBanner(error.localizedDescription)
        }
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
        pendingAttachments.append(attachment)
        showBanner("Attached \(attachment.name).")
    }

    func addRemoteFileToSelectedProject(_ file: RemoteFileInfo) {
        guard let selectedProjectID,
              let projectIndex = projects.firstIndex(where: { $0.id == selectedProjectID }) else {
            showBanner("Select a project first.")
            return
        }

        let attachment = file.attachment
        guard !projects[projectIndex].attachments.contains(where: { $0.id == attachment.id }) else {
            showBanner("\(attachment.name) is already in this project.")
            return
        }
        switch FileStore.projectAttachmentLimit(
            projectAttachmentCount: projects[projectIndex].attachments.count,
            maxProjectAttachments: Self.maxProjectAttachments
        ) {
        case .allowed:
            break
        case let .blocked(message):
            showBanner(message)
            return
        }

        projects[projectIndex].attachments.append(attachment)
        saveProjects()
        showBanner("Added \(attachment.name) to \(projects[projectIndex].name).")
    }

    func deleteRemoteFile(_ file: RemoteFileInfo) async {
        do {
            try await api.deleteFile(file.id)
            remoteFiles.removeAll { $0.id == file.id }
            pendingAttachments.removeAll { $0.id == file.id }
            for index in projects.indices {
                projects[index].attachments.removeAll { $0.id == file.id }
            }
            saveProjects()
            if remoteFilePreview?.id == file.id {
                remoteFilePreview = nil
            }
            showBanner("Deleted \(file.name).")
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    private func registerUploadedAttachment(_ attachment: ChatAttachment) {
        guard !remoteFiles.contains(where: { $0.id == attachment.id }) else { return }
        remoteFiles.insert(
            RemoteFileInfo(
                id: attachment.id,
                bytes: attachment.bytes,
                createdAt: Date().timeIntervalSince1970,
                filename: attachment.name,
                purpose: attachment.kind
            ),
            at: 0
        )
    }

    func removeProjectAttachment(_ attachment: ChatAttachment) {
        guard let selectedProjectID,
              let projectIndex = projects.firstIndex(where: { $0.id == selectedProjectID }) else {
            return
        }
        projects[projectIndex].attachments.removeAll { $0.id == attachment.id }
        saveProjects()
        showBanner("Project file removed.")
    }

    private func uploadAttachment(from url: URL) async -> ChatAttachment? {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        if let fileSize, fileSize > Self.maxFileUploadBytes {
            showBanner("Files must be 10 MB or smaller.")
            return nil
        }

        isUploadingAttachment = true
        defer { isUploadingAttachment = false }

        do {
            #if canImport(PDFKit)
            if url.pathExtension.lowercased() == "pdf" {
                if let fileSize, fileSize <= Self.maxPDFTextExtractionBytes,
                   let extraction = await Self.pdfTextExtractionQueue.extract(from: url, fileSize: fileSize) {
                    let cappedText = String(extraction.text.prefix(Self.maxStagedDocumentChars))
                    // Privacy mode: keep the PDF entirely on-device — never upload
                    // it. Only the passages relevant to the question are inlined
                    // at send (a local-only attachment, excluded from the API).
                    if keepDocumentsOnDevice {
                        let localID = "local-doc-\(UUID().uuidString)"
                        stageDocumentText(cappedText, for: localID)
                        attachmentUploadNotice = "Kept \(url.lastPathComponent) on your device — only the passages relevant to your question are sent."
                        return ChatAttachment(id: localID, name: url.lastPathComponent, kind: ChatAttachment.localDocumentKind, bytes: fileSize)
                    }
                    let extractedFilename = Self.extractedPDFFilename(for: url)
                    var attachment = try await api.uploadTextFile(
                        filename: extractedFilename,
                        text: extraction.text
                    )
                    attachment.name = extractedFilename
                    attachment.kind = "pdf_text"
                    // Keep the extracted text on-device too, so a question about
                    // this PDF can inline the most-relevant passages (local RAG).
                    stageDocumentText(cappedText, for: attachment.id)
                    attachmentUploadNotice = extraction.truncated ?
                        "Attached capped readable text from \(url.lastPathComponent)." :
                        "Attached readable text from \(url.lastPathComponent)."
                    return attachment
                } else if let fileSize, fileSize > Self.maxPDFTextExtractionBytes {
                    attachmentUploadNotice = "Attached \(url.lastPathComponent) as a PDF file. Text extraction runs only for PDFs up to 5 MB."
                } else if fileSize == nil {
                    attachmentUploadNotice = "Attached \(url.lastPathComponent) as a PDF file. Text extraction was skipped because the file size could not be verified."
                } else {
                    attachmentUploadNotice = "Attached \(url.lastPathComponent) as a PDF file. Text extraction timed out or found no readable text."
                }
            }
            #endif
            return try await api.uploadFile(from: url)
        } catch {
            showBanner(error.localizedDescription)
            return nil
        }
    }

    private func handleDraftChange(from previous: String, to current: String) {
        guard !isNormalizingDraft, !suppressDraftPersistence else { return }

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
              shouldPromoteLargePaste(previous: previous, current: currentValue) else {
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

    private func shouldPromoteLargePaste(previous: String, current: String) -> Bool {
        guard current.count > previous.count else { return false }
        let insertedCharacters = current.count - previous.count
        let insertedBytes = current.utf8.count - previous.utf8.count
        guard insertedCharacters >= Self.largePasteThresholdCharacters / 2 ||
              insertedBytes >= Self.largePasteThresholdBytes / 2 else {
            return false
        }
        return current.count >= Self.largePasteThresholdCharacters ||
            current.utf8.count >= Self.largePasteThresholdBytes
    }

    private func stageLargePasteForSend(_ text: String) {
        let attachment = ChatAttachment(
            id: "local-paste-\(UUID().uuidString)",
            name: Self.largePasteFilename(),
            kind: ChatAttachment.pendingTextKind,
            bytes: text.utf8.count
        )
        pendingLargePasteTexts[attachment.id] = text
        pendingAttachments.append(attachment)
        showBanner("Large paste staged. It uploads only when you send.")
    }

    private func resolvePromptAttachmentsForSend(_ promptAttachments: [ChatAttachment]) async throws -> [ChatAttachment] {
        var resolved: [ChatAttachment] = []
        var uploadedLocalIDs: [String] = []
        for attachment in promptAttachments {
            guard let text = pendingLargePasteTexts[attachment.id] else {
                resolved.append(attachment)
                continue
            }
            isUploadingAttachment = true
            defer { isUploadingAttachment = false }
            let uploaded = try await api.uploadTextFile(filename: attachment.name, text: text)
            resolved.append(uploaded)
            registerUploadedAttachment(uploaded)
            uploadedLocalIDs.append(attachment.id)
        }
        for id in uploadedLocalIDs {
            pendingLargePasteTexts.removeValue(forKey: id)
        }
        return resolved
    }

    private static func largePasteFilename() -> String {
        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return "large-paste-\(stamp).txt"
    }

    #if canImport(PDFKit)
    private struct PDFTextExtractionResult: Sendable {
        var text: String
        var truncated: Bool
    }

    private actor PDFTextExtractionTimeout {
        private var continuation: CheckedContinuation<PDFTextExtractionResult?, Never>?

        init(continuation: CheckedContinuation<PDFTextExtractionResult?, Never>) {
            self.continuation = continuation
        }

        func resume(_ result: PDFTextExtractionResult?) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(returning: result)
        }
    }

    private actor PDFTextExtractionQueue {
        func extract(from url: URL, fileSize: Int) async -> PDFTextExtractionResult? {
            await ChatStore.extractedPDFTextWithTimeout(from: url, fileSize: fileSize)
        }
    }

    nonisolated private static let pdfTextExtractionQueue = PDFTextExtractionQueue()

    nonisolated private static func extractedPDFTextWithTimeout(from url: URL, fileSize: Int) async -> PDFTextExtractionResult? {
        await withCheckedContinuation { continuation in
            let timeoutState = PDFTextExtractionTimeout(continuation: continuation)
            let extractionTask = Task.detached(priority: .userInitiated) {
                Self.extractedPDFText(from: url, fileSize: fileSize)
            }
            Task.detached {
                let result = await extractionTask.value
                await timeoutState.resume(result)
            }
            Task.detached {
                let nanoseconds = UInt64(maxPDFExtractionSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                extractionTask.cancel()
                await timeoutState.resume(nil)
            }
        }
    }

    nonisolated private static func extractedPDFText(from url: URL, fileSize: Int?) -> PDFTextExtractionResult? {
        if let fileSize, fileSize > maxPDFTextExtractionBytes {
            return nil
        }
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            return nil
        }

        let startedAt = Date()
        let pageLimit = min(document.pageCount, maxPDFExtractionPages)
        var pages: [String] = []
        var accumulatedBytes = 0
        var truncated = document.pageCount > pageLimit

        for pageIndex in 0..<pageLimit {
            if Task.isCancelled || Date().timeIntervalSince(startedAt) > maxPDFExtractionSeconds {
                truncated = true
                break
            }
            let pageText = document.page(at: pageIndex)?.string?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pageText, !pageText.isEmpty else { continue }

            let pageBytes = pageText.utf8.count
            if accumulatedBytes + pageBytes > maxPDFExtractedTextBytes {
                truncated = true
                break
            }
            pages.append(pageText)
            accumulatedBytes += pageBytes + 2
        }

        let text = pages.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : PDFTextExtractionResult(text: text, truncated: truncated)
    }

    nonisolated private static func extractedPDFFilename(for url: URL) -> String {
        let basename = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeBasename = basename.isEmpty ? "attachment" : basename
        return "\(safeBasename)-pdf-text.txt"
    }
    #endif

    func removePendingAttachment(_ attachment: ChatAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
        pendingLargePasteTexts.removeValue(forKey: attachment.id)
        showBanner("Attachment removed.")
    }

    func deleteSelectedConversation() {
        guard let selectedConversation else { return }
        requestDeleteConversation(selectedConversation)
    }

    func requestDeleteConversation(_ conversation: ConversationSummary) {
        pendingDeleteConversation = conversation
    }

    func cancelPendingDelete() {
        pendingDeleteConversation = nil
    }

    func confirmPendingDelete() {
        guard let conversation = pendingDeleteConversation else { return }
        pendingDeleteConversation = nil
        deleteConversation(conversation)
    }

    private func deleteConversation(_ conversation: ConversationSummary) {
        Task {
            do {
                try await api.deleteConversation(conversation.id)
                conversations.removeAll { $0.id == conversation.id }
                removeLocalMessages(for: conversation.id)
                for index in projects.indices {
                    projects[index].conversationIDs.removeAll { $0 == conversation.id }
                }
                saveProjects()
                if selectedConversation?.id == conversation.id {
                    startNewConversation()
                }
                showBanner("Conversation deleted.")
            } catch {
                showBanner(error.localizedDescription)
            }
        }
    }

    func cloneSelectedConversation() {
        guard let selectedConversation else { return }
        cloneConversation(selectedConversation)
    }

    func cloneSharedPreviewToChat() {
        guard let sharedPreview else { return }
        cloneConversation(sharedPreview.conversation)
        self.sharedPreview = nil
    }

    func cloneConversation(_ conversation: ConversationSummary) {
        Task {
            do {
                let cloned = try await api.cloneConversation(conversation.id)
                conversations.removeAll { $0.id == cloned.id }
                conversations.insert(cloned, at: 0)
                if let selectedProjectID {
                    assign(conversationID: cloned.id, to: selectedProjectID)
                }
                selectedConversation = cloned
                shareInfo = nil
                await loadMessages(for: cloned, preferCached: false)
                await refreshConversations()
                showBanner("Conversation copied.")
            } catch {
                showBanner(error.localizedDescription)
            }
        }
    }

    func archiveSelectedConversation() {
        guard let selectedConversation else { return }
        archiveConversation(selectedConversation)
    }

    func archiveConversation(_ conversation: ConversationSummary) {
        Task {
            do {
                try await api.archiveConversation(conversation.id)
                setArchived(true, for: conversation.id)
                await refreshConversations()
                if selectedConversation?.id == conversation.id {
                    startNewConversation()
                }
                showBanner("Conversation archived.")
            } catch {
                showBanner(error.localizedDescription)
            }
        }
    }

    func unarchiveConversation(_ conversation: ConversationSummary) {
        Task {
            do {
                try await api.unarchiveConversation(conversation.id)
                setArchived(false, for: conversation.id)
                await refreshConversations()
                showBanner("Conversation restored.")
            } catch {
                showBanner(error.localizedDescription)
            }
        }
    }

    func unarchiveAllConversations() {
        let archived = archivedConversations
        guard !archived.isEmpty else { return }

        Task {
            do {
                for conversation in archived {
                    try await api.unarchiveConversation(conversation.id)
                    setArchived(false, for: conversation.id)
                }
                await refreshConversations()
                showBanner("Archived conversations restored.")
            } catch {
                showBanner(error.localizedDescription)
            }
        }
    }

    func togglePinSelectedConversation() {
        guard let selectedConversation else { return }
        togglePinConversation(selectedConversation)
    }

    func togglePinConversation(_ conversation: ConversationSummary) {
        let shouldPin = !conversation.isPinned

        Task {
            do {
                if shouldPin {
                    try await api.pinConversation(conversation.id)
                } else {
                    try await api.unpinConversation(conversation.id)
                }
                setPinned(shouldPin, for: conversation.id)
                await refreshConversations()
                showBanner(shouldPin ? "Conversation pinned." : "Conversation unpinned.")
            } catch {
                showBanner(error.localizedDescription)
            }
        }
    }

    func renameSelectedConversation(to title: String) async {
        guard let selectedConversation else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showBanner("Add a title first.")
            return
        }

        do {
            try await api.updateConversationTitle(selectedConversation.id, title: trimmed)
            setTitle(trimmed, for: selectedConversation.id)
            await refreshConversations()
            showBanner("Title updated.")
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func loadShares(for conversation: ConversationSummary? = nil) async {
        guard let conversation = conversation ?? selectedConversation else { return }
        #if DEBUG
        if DemoCapture.isEnabled {
            shareInfo = Self.demoShareInfo(for: conversation)
            return
        }
        #endif
        isLoadingShareInfo = true
        defer { isLoadingShareInfo = false }
        do {
            shareInfo = try await api.fetchConversationShares(conversation.id)
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func refreshSharedWithMe(showErrors: Bool = true) async {
        #if DEBUG
        if DemoCapture.isEnabled {
            sharedWithMe = []
            return
        }
        #endif
        guard !isLoadingSharedWithMe else { return }
        isLoadingSharedWithMe = true
        defer { isLoadingSharedWithMe = false }
        do {
            sharedWithMe = try await api.fetchSharedWithMe()
                .sorted { lhs, rhs in
                    (lhs.createdAt ?? 0) > (rhs.createdAt ?? 0)
                }
        } catch {
            if showErrors {
                showBanner(error.localizedDescription)
            }
        }
    }

    func enablePublicShare(for conversation: ConversationSummary? = nil) async -> URL? {
        guard let conversation = conversation ?? selectedConversation else { return nil }
        do {
            _ = try await api.createPublicShare(conversation.id)
            await loadShares(for: conversation)
            showBanner("Public link enabled.")
            return publicURL(for: conversation)
        } catch {
            showBanner(error.localizedDescription)
            return nil
        }
    }

    func grantDirectShare(
        rawRecipients: String,
        permission: String,
        conversation: ConversationSummary? = nil
    ) async {
        guard let conversation = conversation ?? selectedConversation else { return }
        guard let permission = Self.validSharePermission(permission) else {
            showBanner("Choose read or write access.")
            return
        }
        let recipients = Self.shareInviteRecipients(from: rawRecipients)
        guard !recipients.isEmpty else {
            showBanner("Use valid email addresses or NEAR accounts.")
            return
        }

        do {
            _ = try await api.createDirectShare(
                conversation.id,
                recipients: recipients,
                permission: permission
            )
            await loadShares(for: conversation)
            showBanner(recipients.count == 1 ? "Access granted." : "Access granted to \(recipients.count) people.")
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func grantOrganizationShare(
        emailPattern: String,
        permission: String,
        conversation: ConversationSummary? = nil
    ) async {
        guard let conversation = conversation ?? selectedConversation else { return }
        guard let permission = Self.validSharePermission(permission) else {
            showBanner("Choose read or write access.")
            return
        }
        guard let normalizedPattern = Self.normalizedOrganizationEmailPattern(emailPattern) else {
            showBanner("Use an organization pattern like *@near.org.")
            return
        }

        do {
            _ = try await api.createOrganizationShare(
                conversation.id,
                emailPattern: normalizedPattern,
                permission: permission
            )
            await loadShares(for: conversation)
            showBanner("Organization access granted.")
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func refreshShareGroups(showErrors: Bool = true) async {
        guard !isLoadingShareGroups else { return }
        isLoadingShareGroups = true
        defer { isLoadingShareGroups = false }
        do {
            shareGroups = try await api.fetchShareGroups()
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            if showErrors {
                showBanner(error.localizedDescription)
            }
        }
    }

    func createShareGroup(name: String, rawMembers: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let members = Self.shareInviteRecipients(from: rawMembers)
        guard !trimmedName.isEmpty else {
            showBanner("Name the group first.")
            return
        }
        guard !members.isEmpty else {
            showBanner("Add at least one group member.")
            return
        }

        do {
            let group = try await api.createShareGroup(name: trimmedName, members: members)
            shareGroups.removeAll { $0.id == group.id }
            shareGroups.append(group)
            shareGroups.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            showBanner("Share group created.")
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func updateShareGroup(_ group: ShareGroupInfo, name: String, rawMembers: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let members = Self.shareInviteRecipients(from: rawMembers)
        guard !trimmedName.isEmpty else {
            showBanner("Name the group first.")
            return
        }
        guard !members.isEmpty else {
            showBanner("Add at least one group member.")
            return
        }

        do {
            let updatedGroup = try await api.updateShareGroup(group.id, name: trimmedName, members: members)
            shareGroups.removeAll { $0.id == updatedGroup.id }
            shareGroups.append(updatedGroup)
            shareGroups.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            showBanner("Share group updated.")
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func deleteShareGroup(_ group: ShareGroupInfo) async {
        do {
            try await api.deleteShareGroup(group.id)
            shareGroups.removeAll { $0.id == group.id }
            showBanner("Share group deleted.")
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func grantGroupShare(
        groupID: String,
        permission: String,
        conversation: ConversationSummary? = nil
    ) async {
        guard let conversation = conversation ?? selectedConversation else { return }
        guard let permission = Self.validSharePermission(permission) else {
            showBanner("Choose read or write access.")
            return
        }
        guard !groupID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showBanner("Choose a share group.")
            return
        }

        do {
            _ = try await api.createGroupShare(
                conversation.id,
                groupID: groupID,
                permission: permission
            )
            await loadShares(for: conversation)
            showBanner("Group access granted.")
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func removeConversationShare(
        _ share: ConversationShareInfo,
        conversation: ConversationSummary? = nil
    ) async {
        guard let conversation = conversation ?? selectedConversation else { return }
        do {
            try await api.deleteConversationShare(conversation.id, shareID: share.id)
            await loadShares(for: conversation)
            showBanner("Access removed.")
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func disablePublicShare(for conversation: ConversationSummary? = nil) async {
        guard let conversation = conversation ?? selectedConversation else { return }
        let loadedInfo: ConversationSharesListResponse
        if let shareInfo, shareInfo.publicShare != nil {
            loadedInfo = shareInfo
        } else {
            do {
                loadedInfo = try await api.fetchConversationShares(conversation.id)
            } catch {
                showBanner(error.localizedDescription)
                return
            }
        }

        guard let publicShare = loadedInfo.publicShare else {
            showBanner("Public link is already disabled.")
            return
        }

        do {
            try await api.deleteConversationShare(conversation.id, shareID: publicShare.id)
            await loadShares(for: conversation)
            showBanner("Public link disabled.")
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func publicURL(for conversation: ConversationSummary) -> URL? {
        URL(string: "https://private.near.ai/c/\(conversation.id)")
    }

    private func clearAttestationState() {
        attestationSnapshot = nil
        attestationFetchErrorMessage = nil
    }

    func refreshAttestationReport() async {
        if isCouncilModeEnabled, activeCouncilHasExternalRoutes {
            showBanner("Verification proof is available for all-private Council lineups. Remove NEAR AI Cloud models to fetch proof.")
            return
        }
        guard selectedRouteKind == .nearPrivate else {
            showBanner("Verification proof is available for NEAR Private models.")
            return
        }
        isLoadingAttestation = true
        defer { isLoadingAttestation = false }
        attestationFetchErrorMessage = nil

        do {
            attestationSnapshot = try await api.fetchAttestationReport(
                nonce: Self.makeNonce(),
                model: selectedModel
            )
            attestationFetchErrorMessage = nil
            showBanner("Attestation refreshed.")
        } catch {
            attestationFetchErrorMessage = error.localizedDescription
            showBanner(error.localizedDescription)
        }
    }

    func openSharedConversation(from value: String, knownCanWrite: Bool? = nil, sourceLabel: String? = nil) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let conversationID = Self.conversationID(from: trimmed) else {
            showBanner("Paste a private.near.ai conversation link or conversation ID.")
            return
        }

        isLoadingSharedPreview = true
        defer { isLoadingSharedPreview = false }

        do {
            async let conversation = api.fetchReadableConversation(conversationID)
            async let items = api.fetchReadableConversationItems(conversationID)
            let canWrite: Bool
            if let knownCanWrite {
                canWrite = knownCanWrite
            } else if let access = try? await api.fetchConversationShares(conversationID) {
                canWrite = access.canWrite
            } else {
                canWrite = false
            }
            let snapshot = try await SharedConversationSnapshot(
                conversation: conversation,
                messages: Self.chatMessages(from: items.data),
                source: sourceLabel ?? trimmed,
                canWrite: canWrite,
                loadedAt: Date()
            )
            sharedPreview = snapshot
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func openSharedPreviewForWriting() {
        guard let snapshot = sharedPreview else { return }
        guard snapshot.canWrite else {
            showBanner("This shared conversation is read-only.")
            return
        }
        cancelMessageLoad()
        selectedConversation = snapshot.conversation
        messages = snapshot.messages
        shareInfo = nil
        pendingAttachments = []
        draft = ""
        sharedPreview = nil
        openSelectedConversationToken = UUID()
    }

    func closeSharedPreview() {
        sharedPreview = nil
    }

    func loadMessages(for conversation: ConversationSummary, preferCached: Bool = true) async {
        loadMessagesGeneration += 1
        let generation = loadMessagesGeneration
        loadMessagesTask?.cancel()
        await loadMessages(for: conversation, preferCached: preferCached, generation: generation)
    }

    private func scheduleMessageLoad(for conversation: ConversationSummary, preferCached: Bool = true) {
        loadMessagesGeneration += 1
        let generation = loadMessagesGeneration
        loadMessagesTask?.cancel()
        loadMessagesTask = Task { [weak self] in
            await self?.loadMessages(for: conversation, preferCached: preferCached, generation: generation)
        }
    }

    private func cancelMessageLoad() {
        loadMessagesGeneration += 1
        loadMessagesTask?.cancel()
        loadMessagesTask = nil
    }

    private func loadMessages(for conversation: ConversationSummary, preferCached: Bool, generation: Int) async {
        scheduleSilentShareInfoRefresh(for: conversation, generation: generation)

        let cachedMessages = loadLocalMessages(for: conversation.id)
        if preferCached, let cachedMessages, !cachedMessages.isEmpty {
            let normalizedMessages = Self.normalizedMessages(cachedMessages, assumingStreamLost: true)
            if canApplyMessageLoad(for: conversation.id, generation: generation) {
                if messages != normalizedMessages {
                    messages = normalizedMessages
                }
                restoreSelectedModel(from: normalizedMessages)
                if normalizedMessages != cachedMessages {
                    saveLocalMessages(for: conversation.id)
                }
            }
            if cachedMessages.contains(where: { Self.isExternalModel($0.model ?? "") }) {
                await refreshIronclawLatestResponse(for: conversation.id)
            }
        }

        do {
            let response = try await api.fetchConversationItems(conversation.id)
            guard canApplyMessageLoad(for: conversation.id, generation: generation) else { return }
            let preferredResponseID = selectedResponseVariantByConversationID[conversation.id]
            let remoteMessages = Self.chatMessages(from: response.data, preferredResponseID: preferredResponseID)
            let loadedMessages = Self.mergedMessages(remoteMessages: remoteMessages, localCache: cachedMessages)
            if messages != loadedMessages {
                messages = loadedMessages
            }
            restoreSelectedModel(from: loadedMessages)
            if loadedMessages != cachedMessages {
                saveLocalMessages(for: conversation.id)
            }
        } catch is CancellationError {
            return
        } catch {
            guard canApplyMessageLoad(for: conversation.id, generation: generation) else { return }
            if cachedMessages?.isEmpty == false {
                showBanner("Could not refresh this chat. Showing cached messages.")
            } else {
                showBanner(error.localizedDescription)
            }
        }
    }

    private func scheduleSilentShareInfoRefresh(for conversation: ConversationSummary, generation: Int) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let loadedShareInfo = await self.silentShareInfo(for: conversation)
            guard self.canApplyMessageLoad(for: conversation.id, generation: generation),
                  self.shareInfo != loadedShareInfo else {
                return
            }
            self.shareInfo = loadedShareInfo
        }
    }

    func selectResponseVariant(_ responseID: String) {
        guard !isStreaming else { return }
        guard let conversation = selectedConversation else { return }
        selectedResponseVariantByConversationID[conversation.id] = responseID
        scheduleMessageLoad(for: conversation, preferCached: false)
    }

    private func canApplyMessageLoad(for conversationID: String, generation: Int) -> Bool {
        !Task.isCancelled &&
            loadMessagesGeneration == generation &&
            selectedConversation?.id == conversationID
    }

    private func silentShareInfo(for conversation: ConversationSummary) async -> ConversationSharesListResponse? {
        #if DEBUG
        if DemoCapture.isEnabled {
            return Self.demoShareInfo(for: conversation)
        }
        #endif
        return try? await api.fetchConversationShares(conversation.id)
    }

    nonisolated static func mergedMessages(remoteMessages: [ChatMessage], localCache: [ChatMessage]?) -> [ChatMessage] {
        guard let localCache, !localCache.isEmpty else { return remoteMessages }
        let remoteIDs = Set(remoteMessages.map(\.id))
        let containsExternalLocalTurn = localCache.contains { message in
            isExternalModel(message.model ?? "")
        }
        guard containsExternalLocalTurn else { return remoteMessages }

        let localOnly = localCache.filter { message in
            guard !remoteIDs.contains(message.id) else { return false }
            if isExternalModel(message.model ?? "") { return true }
            if message.status == "failed" || message.status == "approval" { return true }
            return message.role == .user
        }
        guard !localOnly.isEmpty else { return remoteMessages }
        return (remoteMessages + localOnly).sorted { lhs, rhs in
            lhs.createdAt < rhs.createdAt
        }
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
        // A "Track this" follow-up acts immediately (one tap → a tracker); any
        // other follow-up prefills the composer for the user to refine and send.
        switch QuickIntentParser.parse(trimmed) {
        case .createTracker, .trackLast:
            draft = trimmed
            sendDraft()
        default:
            draft = trimmed
            AppHaptics.selection()
        }
    }

    /// Runs a briefing prompt headlessly in a throwaway conversation and returns
    /// the structured widget the model produced (falling back to a generic text
    /// widget). Used by the BriefingStore runner; returns nil on any failure.
    /// The agentic Daily Brief: every active tracker's latest value + a live
    /// market snapshot (auth-free), composed into one digest. Shared by the
    /// on-demand "brief me" intent and the scheduled .dailyBrief tracker.
    private func briefDigestWidget() async -> MessageWidget? {
        let trackers = trackersProvider?() ?? []
        async let ethPrice = LiveDataService.coinUSDPrice(coinID: "ethereum")
        async let btcPrice = LiveDataService.coinUSDPrice(coinID: "bitcoin")
        let (eth, btc) = await (ethPrice, btcPrice)
        var market: [(label: String, value: String)] = []
        if let eth { market.append((label: "ETH", value: LiveDataService.usdPriceString(eth))) }
        if let btc { market.append((label: "BTC", value: LiveDataService.usdPriceString(btc))) }
        return BriefDigest.compose(trackers: trackers, market: market)
    }

    func runBriefing(_ briefing: Briefing) async -> MessageWidget? {
        // Conditional trackers are gated: evaluate the threshold against live
        // data and only deliver (non-nil) on a met run, so the rest of the
        // pipeline (latestResult + notification) fires exactly when it should.
        if let condition = briefing.condition {
            return await runConditionalBriefing(briefing, condition: condition)
        }

        // Live kinds fetch real data from auth-free public APIs (work without the
        // chat backend); custom prompts fall through to the chat model below.
        switch briefing.kind {
        case .ethPrice:
            return await LiveDataService.ethPriceWidget()
        case .cryptoPrice:
            // A cryptoPrice tracker must carry its coin id. Never silently
            // default to ETH — that would surface a wrong coin's price as fact.
            guard let id = briefing.accountID, !id.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return await LiveDataService.cryptoPriceWidget(coinID: id, symbol: LiveDataService.symbol(forCoinID: id))
        case .nearAccount:
            return await LiveDataService.nearAccountWidget(account: briefing.accountID ?? "")
        case .dailyNews:
            return await LiveDataService.newsBriefWidget()
        case .dailyBrief:
            return await briefDigestWidget()
        case .customPrompt:
            break
        }

        // customPrompt briefings run the chat backend (need sign-in). A council
        // briefing runs several models + a synthesis on each scheduled run; a
        // plain one runs a single model. Live kinds above already returned.
        if briefing.council {
            return await runCouncilBriefing(briefing)
        }
        return await runSingleModelBriefing(briefing)
    }

    /// Evaluates a conditional tracker against live price data. Returns the live
    /// price widget only when the threshold is met (so the briefing delivers +
    /// notifies); returns nil otherwise (the briefing stays due and re-checks on
    /// its next cycle). A met run is logged for the activity audit; quiet checks
    /// are intentionally not logged so the log stays meaningful.
    private func runConditionalBriefing(_ briefing: Briefing, condition: BriefingCondition) async -> MessageWidget? {
        guard let price = await LiveDataService.coinUSDPrice(coinID: condition.coinID) else {
            return nil // couldn't fetch — don't fire on missing data
        }
        guard condition.isSatisfied(by: price) else { return nil }
        let priceLabel = LiveDataService.usdPriceString(price)
        activityLog.record("Alert fired — \(condition.summary) (now \(priceLabel))")
        // Surface the live price card; fall back to a plain metric if the chart
        // fetch is unavailable so a met alert always delivers something.
        if let widget = await LiveDataService.cryptoPriceWidget(coinID: condition.coinID, symbol: condition.symbol) {
            return widget
        }
        return MessageWidget(
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
        )
    }

    /// One headless model turn → its full text (nil on failure / empty output).
    private func streamBriefingText(
        model: String,
        prompt: String,
        conversationID: String,
        webSearchEnabled: Bool
    ) async -> String? {
        final class TextSink: @unchecked Sendable { var text = "" }
        let sink = TextSink()
        do {
            try await api.streamResponse(
                model: model,
                text: prompt,
                attachments: [],
                conversationID: conversationID,
                previousResponseID: nil,
                webSearchEnabled: webSearchEnabled,
                systemPrompt: activeSystemPrompt(memoryForModel: model),
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
        } catch {
            return nil
        }
        let trimmed = sink.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    private func runSingleModelBriefing(_ briefing: Briefing) async -> MessageWidget? {
        guard let conversation = try? await api.createConversation(title: briefing.title),
              let text = await streamBriefingText(
                  model: Self.defaultModelID,
                  prompt: briefing.prompt,
                  conversationID: conversation.id,
                  webSearchEnabled: true
              ) else {
            return nil
        }
        return briefingWidget(from: text, title: briefing.title)
    }

    /// Runs a council (several models in the default lineup) on the briefing
    /// prompt, then synthesizes one answer — the scheduled equivalent of the
    /// live Council. Falls back to a single model if fewer than two are usable.
    private func runCouncilBriefing(_ briefing: Briefing) async -> MessageWidget? {
        let modelIDs = defaultCouncilModelIDs()
        guard modelIDs.count > 1 else {
            return await runSingleModelBriefing(briefing)
        }
        guard let conversation = try? await api.createConversation(title: briefing.title) else {
            return nil
        }

        // Best-effort Live Activity for the council run: one step per model plus
        // a final synthesis step. Side-effect only — the returned widget below is
        // identical whether or not the Activity ever appears.
        let totalSteps = modelIDs.count + 1
        agentActivity.start(title: briefing.title, total: totalSteps)

        var responses: [(String, String)] = []
        var stepsDone = 0
        for modelID in modelIDs {
            let displayName = modelDisplayName(for: modelID)
            agentActivity.update(stage: "Asking \(displayName)", completed: stepsDone)
            if let text = await streamBriefingText(
                model: modelID,
                prompt: briefing.prompt,
                conversationID: conversation.id,
                webSearchEnabled: true
            ) {
                responses.append((displayName, text))
            }
            stepsDone += 1
            agentActivity.update(stage: "Asking \(displayName)", completed: stepsDone)
        }
        guard let first = responses.first else {
            agentActivity.end()
            return nil
        }
        guard responses.count > 1 else {
            agentActivity.end()
            return briefingWidget(from: first.1, title: briefing.title)
        }

        agentActivity.update(stage: "Synthesizing", completed: modelIDs.count)
        let synthesisPrompt = Self.councilSynthesisPrompt(
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
        return briefingWidget(from: synthesized ?? first.1, title: briefing.title)
    }

    /// Answers a recognized prompt locally: data questions render a live widget,
    /// "create a tracker…" creates a scheduled briefing. No chat backend needed.
    private func handleQuickIntent(_ intent: QuickIntent, prompt: String) {
        let model = selectedModel
        let userMessage = ChatMessage(
            id: "local-user-\(UUID().uuidString)",
            role: .user, text: prompt, model: model, createdAt: Date(),
            status: "completed", responseID: nil, isStreaming: false
        )
        messages.append(userMessage)

        func appendAssistant(text: String, widget: MessageWidget? = nil, streaming: Bool = false) -> String {
            let id = "local-assistant-\(UUID().uuidString)"
            var message = ChatMessage(
                id: id, role: .assistant, text: text, model: model, createdAt: Date(),
                status: streaming ? "searching" : "completed", responseID: nil, isStreaming: streaming
            )
            message.widget = widget
            messages.append(message)
            return id
        }

        switch intent {
        case let .createTracker(spec):
            let briefing = Briefing(
                title: spec.title,
                prompt: spec.prompt ?? prompt,
                schedule: spec.schedule,
                kind: spec.kind,
                accountID: spec.subject,
                council: spec.council,
                condition: spec.condition
            )
            onCreateTracker?(briefing)
            activityLog.record("Created tracker “\(spec.title)” · \(spec.confirmation)")
            let trackerBody = spec.condition != nil
                ? "Set up an alert — **\(spec.confirmation)**. I’ll check on that cadence and notify you the first time it triggers, then pause it so I don’t repeat. It lives on your Today tab; reopen it any time to re-arm, change, or delete it."
                : "Created a tracker — **\(spec.confirmation)**. It runs on schedule and lands on your Today tab; open it any time to Run now, change it, or delete it."
            _ = appendAssistant(text: trackerBody)
            AppHaptics.selection()
        case let .trackLast(schedule):
            // Track whatever the previous question was about. handleQuickIntent
            // already appended this "track that" turn, so the prior user message
            // (dropLast) is the question to track.
            let priorText = messages.filter { $0.role == .user }.dropLast().last?.text
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let subject = QuickIntentParser.subjectFromQuery(priorText)
            if priorText.count >= 3, subject.count >= 2 {
                let title = QuickIntentParser.prettyTrackerTitle(from: subject)
                let briefing = Briefing(
                    title: title,
                    prompt: "Using web search, find the latest \(subject) and report it concisely — lead with the current number/price (with its currency) and the as-of date. If it's a price or numeric value, present it as a metric or chart widget.",
                    schedule: schedule,
                    kind: .customPrompt
                )
                onCreateTracker?(briefing)
                activityLog.record("Created tracker “\(title)” from “track that”")
                _ = appendAssistant(text: "On it — I’ll track **\(title)** (\(schedule.scheduleLabel)) and surface it on your Today tab. It builds a chart as it runs; reopen it any time to Run now, change, or delete.")
                AppHaptics.selection()
            } else {
                _ = appendAssistant(text: "I’m not sure what to track yet — ask me something first (like “what’s the price of a Rolex GMT Master II”), then say “track that.”")
            }
        case .nearAccount(nil):
            _ = appendAssistant(text: "Sure — what’s your NEAR account? Tell me the id (e.g. **yourname.near**) and I’ll pull its balance and holdings.")
        case let .remember(text):
            if memoryStore.add(text) != nil {
                _ = appendAssistant(text: "Got it — I’ll remember that:\n\n> \(text)\n\nIt stays on your device and I’ll use it when it’s relevant. Ask “what do you remember” any time.")
            } else {
                _ = appendAssistant(text: "I’ve already got that noted.")
            }
            AppHaptics.selection()
        case .recallMemory:
            let memories = memoryStore.items
            if memories.isEmpty {
                _ = appendAssistant(text: "I’m not remembering anything yet. Tell me something like **“remember that I prefer concise answers”** and I’ll keep it on your device.")
            } else {
                let lines = memories.prefix(20).map { item -> String in
                    item.source == .inferred ? "• \(item.text)  _(noted automatically)_" : "• \(item.text)"
                }.joined(separator: "\n")
                let footer = memories.contains { $0.source == .inferred }
                    ? "\n\nItems marked _noted automatically_ were picked up from our chats — say “forget …” to drop any of them."
                    : ""
                _ = appendAssistant(text: "Here’s what I’m keeping on your device:\n\n\(lines)\(footer)")
            }
        case let .forget(text):
            if let text {
                let removed = memoryStore.remove(matching: text)
                _ = appendAssistant(text: removed > 0 ? "Done — I’ve forgotten that." : "I didn’t have anything matching “\(text)” saved.")
            } else {
                memoryStore.clear()
                activityLog.clear()
                _ = appendAssistant(text: "Cleared — I’ve wiped everything stored on this device: all remembered facts and my activity log.")
            }
            AppHaptics.selection()
        case .forgetAutoLearned:
            let removed = memoryStore.removeInferred()
            _ = appendAssistant(text: removed > 0
                ? "Done — dropped \(removed) thing\(removed == 1 ? "" : "s") I’d picked up from our chats. Anything you explicitly asked me to remember is still here."
                : "There was nothing auto-learned to forget. Everything I have, you told me directly.")
            AppHaptics.selection()
        case let .setMemoryCapture(enabled):
            passiveMemoryEnabled = enabled
            _ = appendAssistant(text: enabled
                ? "Passive memory is on — I’ll quietly note durable details you mention (like where you live or what you prefer) so answers stay personal. Say “what do you remember” to review, or “stop learning about me” to turn it off."
                : "Passive memory is off — I’ll stop noting things on my own. I’ll still remember anything you explicitly ask me to. Say “start learning about me” to turn it back on.")
            AppHaptics.selection()
        case let .setDocumentPrivacy(onDevice):
            keepDocumentsOnDevice = onDevice
            _ = appendAssistant(text: onDevice
                ? "Private document mode is on — attach a PDF and it stays on your device. I only send the passages relevant to your question (over the private route); the file itself is never uploaded. Say “upload documents normally” to turn it off."
                : "Private document mode is off — attached PDFs upload as usual so the model can read the whole file. Say “keep documents on device” to turn privacy mode back on.")
            AppHaptics.selection()
        case .activityLog:
            let entries = activityLog.entries
            if entries.isEmpty {
                _ = appendAssistant(text: "Nothing yet — once briefings run or you create a tracker, I’ll log it here (on your device).")
            } else {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                let lines = entries.prefix(20).map { "• \($0.summary) — \(formatter.localizedString(for: $0.date, relativeTo: Date()))" }.joined(separator: "\n")
                _ = appendAssistant(text: "Here’s what I’ve done recently (kept on your device):\n\n\(lines)")
            }
        case .listTrackers:
            _ = appendAssistant(text: TrackerListFormatter.summary(for: trackersProvider?() ?? []))
        case .capabilities:
            _ = appendAssistant(text: QuickIntentParser.capabilitiesText())
        case let .math(expression, result):
            _ = appendAssistant(text: "\(expression) = **\(result)**")
            AppHaptics.selection()
        case let .dateMath(_, answer):
            _ = appendAssistant(text: answer)
            AppHaptics.selection()
        case let .tipSplit(summary):
            _ = appendAssistant(text: summary)
            AppHaptics.selection()
        case let .searchHistory(query):
            let hits = ConversationHistorySearch.search(
                query: query,
                cache: Self.loadLocalMessageCache(),
                conversations: conversations
            )
            if hits.isEmpty {
                _ = appendAssistant(text: "I couldn’t find anything about “\(query)” in your saved chats. I only search conversations cached on this device, so a chat that hasn’t synced here won’t show up.")
            } else {
                let relative = RelativeDateTimeFormatter()
                relative.unitsStyle = .abbreviated
                let lines = hits.map { hit -> String in
                    let who = hit.isUser ? "You" : "Assistant"
                    let when = hit.date.map { " · \(relative.localizedString(for: $0, relativeTo: Date()))" } ?? ""
                    return "• **\(hit.conversationTitle)** — \(who): \(hit.snippet)\(when)"
                }.joined(separator: "\n")
                _ = appendAssistant(text: "Found \(hits.count) match\(hits.count == 1 ? "" : "es") for “\(query)” in your chats:\n\n\(lines)")
            }
        case let .createReminder(reminder):
            BriefingStore.schedulePersonalReminder(title: reminder.title, date: reminder.date)
            activityLog.record("Set reminder: \(reminder.title)")
            let relative = RelativeDateTimeFormatter()
            relative.unitsStyle = .full
            _ = appendAssistant(text: "Reminder set — I’ll nudge you to **\(reminder.title)** \(relative.localizedString(for: reminder.date, relativeTo: Date())). You’ll get a notification even if the app is closed.")
            AppHaptics.selection()
        default:
            let id = appendAssistant(text: "", streaming: true)
            currentAssistantMessageID = id
            isStreaming = true
            // Track the fetch in streamTask so cancelStream() can stop it, and
            // bail after the await if cancelled so we don't overwrite the turn
            // cancelStream() already finalized.
            streamTask = Task { [weak self] in
                let widget = await self?.fetchQuickIntentWidget(intent)
                guard let self, !Task.isCancelled else { return }
                self.updateMessage(id) { message in
                    message.isStreaming = false
                    message.status = "completed"
                    if let widget {
                        message.widget = widget
                    } else {
                        message.text = "I couldn’t fetch that just now — try again in a moment."
                    }
                }
                self.currentAssistantMessageID = nil
                self.isStreaming = false
                self.streamTask = nil
            }
        }
    }

    /// Runs a compound prompt ("eth price and tokyo weather"): one user turn,
    /// then a live widget per chained data lookup, fetched in order.
    private func handleCompoundIntent(_ intents: [QuickIntent], prompt: String) {
        let model = selectedModel
        messages.append(ChatMessage(
            id: "local-user-\(UUID().uuidString)",
            role: .user, text: prompt, model: model, createdAt: Date(),
            status: "completed", responseID: nil, isStreaming: false
        ))
        let pendingID = "local-assistant-\(UUID().uuidString)"
        var pending = ChatMessage(
            id: pendingID, role: .assistant, text: "Working on \(intents.count) lookups…",
            model: model, createdAt: Date(), status: "searching", responseID: nil, isStreaming: true
        )
        messages.append(pending)
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
                let widget = await self.fetchQuickIntentWidget(intent)
                guard !Task.isCancelled else { break }
                completed += 1
                self.agentActivity.update(stage: "Lookup \(completed) of \(intents.count)", completed: completed)
                guard let widget else { continue }
                produced = true
                var message = ChatMessage(
                    id: "local-assistant-\(UUID().uuidString)", role: .assistant, text: "",
                    model: model, createdAt: Date(), status: "completed", responseID: nil, isStreaming: false
                )
                message.widget = widget
                self.messages.append(message)
            }
            guard !Task.isCancelled else {
                self.agentActivity.end()
                return
            }
            self.updateMessage(pendingID) { message in
                message.isStreaming = false
                message.status = "completed"
                message.text = produced ? "" : "I couldn’t fetch those just now — try again in a moment."
            }
            if produced { self.messages.removeAll { $0.id == pendingID } }
            self.currentAssistantMessageID = nil
            self.isStreaming = false
            self.streamTask = nil
            self.agentActivity.end()
        }
    }

    private func fetchQuickIntentWidget(_ intent: QuickIntent) async -> MessageWidget? {
        switch intent {
        case let .price(coinID, symbol):
            return await LiveDataService.cryptoPriceWidget(coinID: coinID, symbol: symbol)
        case .trendingCrypto:
            return await LiveDataService.trendingCryptoWidget()
        case .cryptoMarket:
            return await LiveDataService.cryptoMarketWidget()
        case .briefMe:
            return await briefDigestWidget()
        case let .nearAccount(account):
            return await LiveDataService.nearAccountWidget(account: account ?? "")
        case .news:
            return await LiveDataService.newsBriefWidget()
        case let .weather(query):
            return await LiveDataService.weatherWidget(query: query)
        case let .worldTime(query):
            return await LiveDataService.worldTimeWidget(query: query)
        case let .fx(amount, from, to):
            return await LiveDataService.fxWidget(amount: amount, from: from, to: to)
        case let .unitConvert(value, from, to):
            return await LiveDataService.unitConvertWidget(value: value, from: from, to: to)
        case let .define(word):
            return await LiveDataService.defineWidget(word: word)
        case .math, .dateMath, .tipSplit, .remember, .recallMemory, .forget, .forgetAutoLearned, .setMemoryCapture, .setDocumentPrivacy, .activityLog, .listTrackers, .capabilities, .searchHistory, .createReminder, .createTracker, .trackLast:
            // Handled synchronously in handleQuickIntent — never fetched here.
            return nil
        }
    }

    /// Passively records durable self-facts the user disclosed in an ordinary
    /// turn — no "remember" keyword needed. Silent by design (it never injects a
    /// chat reply) but logged to the activity log so the user can audit what was
    /// auto-learned, and stored as `.inferred` so recall labels it. Only genuinely
    /// new facts are logged; re-stating a known fact is a no-op.
    private func captureInferredMemory(from text: String) {
        guard passiveMemoryEnabled else { return }
        let learned = QuickIntentParser.inferredFacts(from: text)
        guard !learned.isEmpty else { return }
        var stored: [String] = []
        for fact in learned {
            let isNew = !memoryStore.items.contains { $0.text.caseInsensitiveCompare(fact) == .orderedSame }
            if memoryStore.add(fact, source: .inferred) != nil, isNew {
                stored.append(fact)
            }
        }
        guard !stored.isEmpty else { return }
        activityLog.record("Noted from chat: \(stored.joined(separator: "; "))")
    }

    func sendDraft() {
        let text = Self.normalizedDraftInput(draft).trimmingCharacters(in: .whitespacesAndNewlines)
        let promptAttachments = pendingAttachments
        let pendingLargePasteTextsSnapshot = pendingLargePasteTexts
        let attachments = activeAttachments(promptAttachments: promptAttachments)
        guard (!text.isEmpty || !attachments.isEmpty), !isStreaming else { return }

        // Prompt-driven live answers: recognized data questions ("eth price",
        // "how is my near account") and "create a tracker…" commands are handled
        // locally with real public-API data — generative chat without sign-in.
        if attachments.isEmpty, let intents = QuickIntentParser.parseCompound(text) {
            removePersistedDraft(for: draftPersistenceScopeID)
            draft = ""
            routeReadinessIssue = nil
            handleCompoundIntent(intents, prompt: text)
            return
        }
        if attachments.isEmpty, let intent = QuickIntentParser.parse(text) {
            removePersistedDraft(for: draftPersistenceScopeID)
            draft = ""
            // The local answer needs no sign-in/model route, so clear any stale
            // route-readiness banner left over from a prior blocked send.
            routeReadinessIssue = nil
            handleQuickIntent(intent, prompt: text)
            return
        }

        if let preflight = hostedHandoffPreflightIfNeeded(text: text, promptAttachments: promptAttachments),
           approvedHostedHandoffFingerprint != preflight.fingerprint {
            pendingHostedHandoffContinuation = .draft
            pendingHostedHandoffPreflight = preflight
            return
        }
        if let issue = currentRouteReadinessIssue(for: text) {
            blockSendForRouteReadiness(issue)
            return
        }
        routeReadinessIssue = nil
        // Passively learn durable self-facts from this turn (committed-to-send
        // path only, so a blocked/rephrased message doesn't store anything).
        if attachments.isEmpty { captureInferredMemory(from: text) }
        removePersistedDraft(for: draftPersistenceScopeID)
        draft = ""
        pendingAttachments = []
        streamTask = Task { [weak self] in
            await self?.sendResolvedDraft(
                text: text,
                promptAttachments: promptAttachments,
                pendingLargePasteTextsSnapshot: pendingLargePasteTextsSnapshot
            )
        }
    }

    func confirmHostedHandoff(_ preflight: HostedIronclawHandoffPreflight) {
        let continuation = pendingHostedHandoffContinuation
        approvedHostedHandoffFingerprint = preflight.fingerprint
        pendingHostedHandoffContinuation = nil
        pendingHostedHandoffPreflight = nil
        switch continuation {
        case .draft, .none:
            sendDraft()
        case let .regenerate(message):
            regenerateResponse(for: message)
        case let .edit(message, replacementText):
            editAndResend(message, replacementText: replacementText)
        case let .directSend(text, attachments, previousResponseIDOverride, initiator, appendUserMessage):
            streamTask = Task { [weak self] in
                await self?.send(
                    text,
                    attachments: attachments,
                    previousResponseIDOverride: previousResponseIDOverride,
                    initiator: initiator,
                    appendUserMessage: appendUserMessage
                )
            }
        }
    }

    func cancelHostedHandoff() {
        pendingHostedHandoffPreflight = nil
        pendingHostedHandoffContinuation = nil
        approvedHostedHandoffFingerprint = nil
        showBanner("Hosted IronClaw handoff cancelled.")
    }

    private func hostedHandoffPreflightIfNeeded(
        text: String,
        promptAttachments: [ChatAttachment]
    ) -> HostedIronclawHandoffPreflight? {
        guard ironclawRemoteWorkstationAvailable else { return nil }
        let willUseHosted =
            selectedModel == ModelOption.ironclawModelID ||
            (selectedModel == ModelOption.ironclawMobileModelID && Self.promptNeedsRemoteWorkstation(text))
        guard willUseHosted else { return nil }

        var disclosedItems = ["Prompt text: \(text.utf8.count) bytes"]
        if !promptAttachments.isEmpty {
            disclosedItems.append("Prompt files: \(promptAttachments.map(\.name).joined(separator: ", "))")
        }
        if let selectedProject {
            disclosedItems.append("Project: \(selectedProject.name)")
            if !selectedProject.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                disclosedItems.append("Project instructions")
            }
            if !selectedProject.memorySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                disclosedItems.append("Project memory")
            }
            if !selectedProject.notes.isEmpty {
                disclosedItems.append("Saved notes: \(min(selectedProject.notes.count, 6))")
            }
            let publicLinks = selectedProject.links.filter { link in
                URL(string: link.urlString).map(URLSecurity.isPublicHTTPSURL) == true
            }
            if !publicLinks.isEmpty {
                disclosedItems.append("Source links: \(min(publicLinks.count, 12))")
            }
            if !selectedProject.attachments.isEmpty {
                disclosedItems.append("Project file names: \(selectedProject.attachments.map(\.name).joined(separator: ", "))")
            }
        }

        let attachmentFingerprint = promptAttachments.map(\.id).joined(separator: "|")
        let projectFingerprint = selectedProject.map { project in
            [
                project.id,
                project.instructions,
                project.memorySummary,
                project.notes.map(\.id).joined(separator: "|"),
                project.links.map(\.urlString).joined(separator: "|"),
                project.attachments.map(\.id).joined(separator: "|")
            ].joined(separator: "|")
        } ?? ""
        let rawFingerprint = [
            selectedModel,
            ironclawSettings.normalizedBaseURL,
            text,
            attachmentFingerprint,
            projectFingerprint
        ].joined(separator: "|~|")
        let host = URL(string: ironclawSettings.normalizedBaseURL)?.host ?? "hosted IronClaw"
        return HostedIronclawHandoffPreflight(
            fingerprint: String(rawFingerprint.hashValue),
            destinationHost: host,
            promptPreview: Self.clipped(text, maxCharacters: 500),
            disclosedItems: disclosedItems
        )
    }

    private func currentRouteReadinessIssue(
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
            return "Turn on Hosted Agent in Account before sending."
        }
        return ironclawSettings.endpointValidationMessage
    }

    private func blockSendForRouteReadiness(_ issue: RouteReadinessIssue) {
        routeReadinessIssue = issue
        showBanner(issue.title)
    }

    private func sendResolvedDraft(
        text: String,
        promptAttachments: [ChatAttachment],
        pendingLargePasteTextsSnapshot: [String: String]
    ) async {
        do {
            let resolvedPromptAttachments = try await resolvePromptAttachmentsForSend(promptAttachments)
            let attachments = activeAttachments(promptAttachments: resolvedPromptAttachments)
            let didStartSend = await send(text, attachments: attachments)
            if !didStartSend {
                draft = text
                pendingAttachments = promptAttachments
                pendingLargePasteTexts = pendingLargePasteTextsSnapshot
            }
        } catch is CancellationError {
            draft = text
            pendingAttachments = promptAttachments
            pendingLargePasteTexts = pendingLargePasteTextsSnapshot
        } catch {
            draft = text
            pendingAttachments = promptAttachments
            pendingLargePasteTexts = pendingLargePasteTextsSnapshot
            showBanner(Self.displayFailureMessage(error.localizedDescription))
        }
    }

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        if let currentAssistantMessageID,
           let index = messages.firstIndex(where: { $0.id == currentAssistantMessageID }) {
            flushPendingTextDelta(for: currentAssistantMessageID)
            messages[index].isStreaming = false
            messages[index].status = "cancelled"
        }
        for messageID in currentCouncilAssistantMessageIDs {
            flushPendingTextDelta(for: messageID)
            if let index = messages.firstIndex(where: { $0.id == messageID }) {
                messages[index].isStreaming = false
                messages[index].status = "cancelled"
            }
        }
        currentCouncilAssistantMessageIDs = []
        councilStopRequestedBatchID = nil
        if let selectedConversation, messages.contains(where: { Self.isExternalModel($0.model ?? "") }) {
            saveLocalMessages(for: selectedConversation.id)
        }
    }

    func stopWaitingForCouncil(batchID: String?) {
        guard let batchID,
              isStreaming,
              currentCouncilAssistantMessageIDs.contains(where: { messageID in
                  messages.first(where: { $0.id == messageID })?.councilBatchID == batchID
              }) else {
            cancelStream()
            return
        }
        councilStopRequestedBatchID = batchID
        showBanner("Stopping slow Council legs. Completed answers will be synthesized.")
    }

    func copyCurrentTranscript() {
        guard !messages.isEmpty else {
            showBanner("No transcript to copy.")
            return
        }

        let transcript = ConversationExportBuilder.transcriptText(
            conversation: selectedConversation,
            messages: messages
        )
        Clipboard.copy(transcript)
        showBanner("Transcript copied.")
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
            showBanner("Signed answer copied. Device key ID may link repeated exports.")
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
        guard !isStreaming else { return }
        guard message.role == .assistant,
              let assistantIndex = messages.firstIndex(where: { $0.id == message.id }),
              let userMessage = messages[..<assistantIndex].last(where: { $0.role == .user }) else {
            showBanner("No prompt found to regenerate.")
            return
        }
        let promptAttachments = promptOnlyAttachments(from: userMessage.attachments)
        let attachments = activeAttachments(promptAttachments: promptAttachments)
        let parentResponseID = message.previousResponseID ??
            messages[..<assistantIndex].last(where: { $0.role == .assistant })?.responseID
        if let preflight = hostedHandoffPreflightIfNeeded(text: userMessage.text, promptAttachments: promptAttachments),
           approvedHostedHandoffFingerprint != preflight.fingerprint {
            pendingHostedHandoffContinuation = .regenerate(message)
            pendingHostedHandoffPreflight = preflight
            return
        }
        if let issue = currentRouteReadinessIssue(for: userMessage.text, appendUserMessage: false) {
            blockSendForRouteReadiness(issue)
            return
        }
        if let conversationID = selectedConversation?.id {
            selectedResponseVariantByConversationID.removeValue(forKey: conversationID)
        }
        messages.removeSubrange(assistantIndex..<messages.endIndex)
        showBanner("Regenerating response.")
        streamTask = Task { [weak self] in
            await self?.send(
                userMessage.text,
                attachments: attachments,
                previousResponseIDOverride: parentResponseID,
                initiator: "regenerate",
                appendUserMessage: false
            )
        }
    }

    func editAndResend(_ message: ChatMessage, replacementText: String) {
        guard !isStreaming else { return }
        let text = Self.normalizedDraftInput(replacementText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.role == .user,
              let userIndex = messages.firstIndex(where: { $0.id == message.id }),
              (!text.isEmpty || !message.attachments.isEmpty) else {
            showBanner("No prompt found to edit.")
            return
        }

        let promptAttachments = promptOnlyAttachments(from: message.attachments)
        let attachments = activeAttachments(promptAttachments: promptAttachments)
        let parentResponseID = message.previousResponseID
        if let preflight = hostedHandoffPreflightIfNeeded(text: text, promptAttachments: promptAttachments),
           approvedHostedHandoffFingerprint != preflight.fingerprint {
            pendingHostedHandoffContinuation = .edit(message, replacementText)
            pendingHostedHandoffPreflight = preflight
            return
        }
        if let issue = currentRouteReadinessIssue(for: text) {
            blockSendForRouteReadiness(issue)
            return
        }
        if let conversationID = selectedConversation?.id {
            selectedResponseVariantByConversationID.removeValue(forKey: conversationID)
        }
        messages.removeSubrange(userIndex..<messages.endIndex)
        showBanner("Branching from edited prompt.")
        streamTask = Task { [weak self] in
            await self?.send(
                text,
                attachments: attachments,
                previousResponseIDOverride: parentResponseID,
                initiator: "edit_message",
                appendUserMessage: true
            )
        }
    }

    @discardableResult
    /// Prepends a "relevant excerpts" block from any attached PDF whose text we
    /// staged on-device, ranked against the user's question. No-op when there's
    /// no staged doc, no question, or nothing relevant — so it never disturbs a
    /// plain turn.
    /// Stashes a document's extracted text on-device (capped, insertion-ordered
    /// eviction) so a question about it can inline the relevant passages.
    private func stageDocumentText(_ text: String, for id: String) {
        pendingDocumentTexts[id] = text
        pendingDocumentTextIDs.removeAll { $0 == id }
        pendingDocumentTextIDs.append(id)
        while pendingDocumentTextIDs.count > Self.maxStagedDocuments {
            let evicted = pendingDocumentTextIDs.removeFirst()
            pendingDocumentTexts.removeValue(forKey: evicted)
        }
    }

    private func documentAugmentedPrompt(_ prompt: String, question: String, attachments: [ChatAttachment]) -> String {
        let documents = attachments.compactMap { pendingDocumentTexts[$0.id] }
        guard !documents.isEmpty,
              !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let context = DocumentChunker.contextBlock(for: question, in: documents, topK: 4) else {
            return prompt
        }
        return "\(context)\n\nUsing those excerpts (and the attached file) where relevant:\n\(prompt)"
    }

    /// Whether on-device document excerpts (privacy-mode docs) may be inlined
    /// into this turn's prompt. They may ONLY go to the private near.ai route —
    /// never a cloud model, a cloud council leg, or the hosted/mission route —
    /// so on-device passages never leave the device for a third party. Mirrors
    /// the personal-memory gate in `activeSystemPrompt`. Pure + static so the
    /// privacy guarantee is unit-testable without the network.
    nonisolated static func localDocsAllowedForRoute(councilModelIDs: [String], singleModelID: String) -> Bool {
        if councilModelIDs.count > 1 {
            return councilModelIDs.allSatisfy { RoutePlanner.routeKind(forModelID: $0) == .nearPrivate }
        }
        return RoutePlanner.routeKind(forModelID: singleModelID) == .nearPrivate
    }

    private func send(
        _ text: String,
        attachments: [ChatAttachment],
        previousResponseIDOverride: String? = nil,
        initiator: String? = nil,
        appendUserMessage: Bool = true
    ) async -> Bool {
        let promptAttachments = promptOnlyAttachments(from: attachments)
        if let preflight = hostedHandoffPreflightIfNeeded(text: text, promptAttachments: promptAttachments),
           approvedHostedHandoffFingerprint != preflight.fingerprint {
            pendingHostedHandoffContinuation = .directSend(
                text: text,
                attachments: attachments,
                previousResponseIDOverride: previousResponseIDOverride,
                initiator: initiator,
                appendUserMessage: appendUserMessage
            )
            pendingHostedHandoffPreflight = preflight
            return false
        }

        isStreaming = true
        let approvedHandoffForTurn = approvedHostedHandoffFingerprint
        defer {
            isStreaming = false
            currentAssistantMessageID = nil
            currentCouncilAssistantMessageIDs = []
            councilStopRequestedBatchID = nil
            if approvedHostedHandoffFingerprint == approvedHandoffForTurn {
                approvedHostedHandoffFingerprint = nil
            }
            streamTask = nil
        }

        do {
            if models.isEmpty {
                await refreshModels()
            }
            if billingSnapshot == nil {
                scheduleAccountBackgroundRefresh()
            }
            ensureSelectedModelIsAvailable(shouldShowBanner: true)
            routeCurrentPromptIfNeeded(text, attachments: attachments)
            if let issue = currentRouteReadinessIssue(for: text, appendUserMessage: appendUserMessage) {
                blockSendForRouteReadiness(issue)
                return false
            }
            routeReadinessIssue = nil
            // Inline the most-relevant excerpts of any attached PDF (local RAG)
            // so the model focuses on the right section; the uploaded file is
            // still attached, so this only adds context and never removes any.
            // routedText stays clean (it also feeds the council legs, the repo-URL
            // scan, and council synthesis) — excerpts are inlined only on the
            // single-model, non-mission send below.
            let mission = phoneAgentMissionPromptIfNeeded(for: text)
            var routedText = mission ?? text
            let existingConversation = selectedConversation
            let requestedModel = selectedModel
            let requestModel = requestedModel
            let previousAssistantMessage = messages.last(where: { $0.role == .assistant })
            let previousResponseID = previousResponseIDOverride ??
                previousAssistantMessage.flatMap { Self.isExternalModel($0.model ?? "") ? nil : $0.responseID }
            let requestInitiator = initiator ?? (existingConversation == nil ? "new_chat" : "new_message")
            let councilModelIDs = appendUserMessage ? requestCouncilModelIDs(for: requestModel) : []
            // Privacy mode: on-device docs are never uploaded — exclude them from
            // the API attachments and inline their relevant passages into the
            // prompt. CRITICAL privacy gate: inline ONLY when every destination is
            // the private near.ai route (never a cloud model, a cloud council
            // leg, or the hosted/mission route), so on-device passages never
            // leave the device for a third party. Mirrors the memory gate in
            // `activeSystemPrompt`.
            let apiAttachments = attachments.filter { !$0.isLocalOnly }
            let localDocs = attachments.filter { $0.isLocalOnly }.compactMap { pendingDocumentTexts[$0.id] }
            if !localDocs.isEmpty {
                if Self.localDocsAllowedForRoute(councilModelIDs: councilModelIDs, singleModelID: requestModel) {
                    if let context = DocumentChunker.contextBlock(for: text, in: localDocs, topK: 4) {
                        routedText = "\(context)\n\nUsing those excerpts (my attached on-device document) where relevant:\n\(routedText)"
                    }
                } else {
                    showBanner("Your on-device document stays private — its text isn’t sent to cloud or hosted models. Switch to the private model to use it here.")
                }
            }
            if councilModelIDs.count > 1 {
                let conversation = try await ensureConversation(for: text, attachments: apiAttachments)
                selectedConversation = conversation
                transitionDraftScopeToCurrentSelection(loadDraft: false)
                organizePhoneAgentConversationIfNeeded(
                    conversation: conversation,
                    originalText: text,
                    routedText: mission ?? text
                )
                try await sendCouncilTurn(
                    text: text,
                    routedText: routedText,
                    attachments: apiAttachments,
                    conversation: conversation,
                    modelIDs: councilModelIDs,
                    previousResponseID: previousResponseID,
                    initiator: requestInitiator
                )
                return true
            }

            let userMessage = ChatMessage(
                id: "local-user-\(UUID().uuidString)",
                role: .user,
                text: text,
                model: requestModel,
                createdAt: Date(),
                status: "completed",
                responseID: nil,
                previousResponseID: previousResponseID,
                isStreaming: false,
                attachments: attachments,
                metadata: currentUserMessageMetadata
            )
            let assistantMessage = ChatMessage(
                id: "local-assistant-\(UUID().uuidString)",
                role: .assistant,
                text: "",
                model: requestModel,
                createdAt: Date(),
                status: "streaming",
                responseID: nil,
                previousResponseID: previousResponseID,
                isStreaming: true
            )
            currentAssistantMessageID = assistantMessage.id
            if appendUserMessage {
                messages.append(userMessage)
            }
            messages.append(assistantMessage)

            let conversation = try await ensureConversation(for: text, attachments: apiAttachments)
            selectedConversation = conversation
            transitionDraftScopeToCurrentSelection(loadDraft: false)
            organizePhoneAgentConversationIfNeeded(
                conversation: conversation,
                originalText: text,
                routedText: mission ?? text
            )

            // Uploaded-doc focus injection uses apiAttachments (non-local); any
            // local-only doc is already inlined into routedText above.
            let singleModelText = mission == nil
                ? documentAugmentedPrompt(routedText, question: text, attachments: apiAttachments)
                : routedText
            let finalModel = try await streamResponseWithFallback(
                initialModel: requestModel,
                text: singleModelText,
                attachments: apiAttachments,
                conversationID: conversation.id,
                previousResponseID: previousResponseID,
                initiator: requestInitiator
            )

            if let currentAssistantMessageID,
               let index = messages.firstIndex(where: { $0.id == currentAssistantMessageID }) {
                messages[index].isStreaming = false
                if messages[index].status != "failed", messages[index].status != "approval" {
                    messages[index].status = "completed"
                }
            }

            if Self.isExternalModel(finalModel) {
                saveLocalMessages(for: conversation.id)
            } else {
                saveLocalMessages(for: conversation.id)
                scheduleMessageLoad(for: conversation, preferCached: false)
            }
            scheduleConversationListRefresh()
            return true
        } catch is CancellationError {
            cancelStream()
            return true
        } catch {
            let displayError = Self.displayFailureMessage(error.localizedDescription)
            if let currentAssistantMessageID,
               let index = messages.firstIndex(where: { $0.id == currentAssistantMessageID }) {
                messages[index].isStreaming = false
                messages[index].status = "failed"
                if let localFailure = Self.localFailureMessage(from: messages[index].text) {
                    messages[index].text = localFailure
                } else if messages[index].text.isEmpty {
                    messages[index].text = displayError
                }
            }
            if let selectedConversation, messages.contains(where: { Self.isExternalModel($0.model ?? "") }) {
                saveLocalMessages(for: selectedConversation.id)
            }
            showBanner(displayError)
            return true
        }
    }

    private func sendCouncilTurn(
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
            ChatMessage(
                id: "local-council-\(offset)-\(UUID().uuidString)",
                role: .assistant,
                text: "",
                model: modelID,
                createdAt: Date().addingTimeInterval(Double(offset) * 0.01),
                status: "streaming",
                responseID: nil,
                previousResponseID: previousResponseID,
                councilBatchID: batchID,
                isStreaming: true
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
                            failureSummary: "The app released the request before it completed."
                        )
                    }

                    do {
                        try Task.checkCancellation()
                        try await self.streamResponse(
                            model: modelID,
                            text: routedText,
                            attachments: attachments,
                            conversationID: conversation.id,
                            previousResponseID: previousResponseID,
                            initiator: initiator,
                            assistantMessageID: assistantID
                        )
                        self.finishAssistantMessage(assistantID)
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
                            failureSummary: summary
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
        scheduleConversationListRefresh()
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

        let synthesisID = "local-council-synthesis-\(UUID().uuidString)"
        let synthesisMessage = ChatMessage(
            id: synthesisID,
            role: .assistant,
            text: "",
            model: ModelOption.llmCouncilSynthesisModelID,
            createdAt: Date().addingTimeInterval(0.2),
            status: "streaming",
            responseID: nil,
            previousResponseID: previousResponseID,
            isStreaming: true,
            searchQuery: prompt,
            sources: councilSources
        )
        currentCouncilAssistantMessageIDs.append(synthesisID)
        messages.append(synthesisMessage)

        let synthesisModelID = successfulResults.first?.modelID ?? selectedModel
        do {
            try await streamResponse(
                model: synthesisModelID,
                text: Self.councilSynthesisPrompt(
                    originalPrompt: prompt,
                    routedPrompt: routedPrompt,
                    responses: responses
                ),
                attachments: [],
                conversationID: conversationID,
                previousResponseID: previousResponseID,
                initiator: "llm_council_synthesis",
                assistantMessageID: synthesisID
            )
            finishAssistantMessage(synthesisID)
        } catch {
            await apply(
                streamEvent: .failed("Council synthesis failed: \(Self.modelFailureSummary(error))"),
                conversationID: conversationID,
                assistantMessageID: synthesisID
            )
        }
    }

    private static func councilSynthesisPrompt(
        originalPrompt: String,
        routedPrompt: String,
        responses: [(String, String)]
    ) -> String {
        let councilResponses = responses.map { modelName, text in
            """
            ## \(modelName)
            \(clipped(text, maxCharacters: 5_000))
            """
        }.joined(separator: "\n\n")
        let routeNote = originalPrompt == routedPrompt ? "" : "\n\nRouted prompt actually sent:\n\(clipped(routedPrompt, maxCharacters: 2_000))"
        return """
        You are synthesizing an LLM Council run. Compare the model answers, choose the strongest claims, and call out meaningful disagreements. Do not average weak claims; prefer correctness, recency, and evidence.

        If the user asked for exact wording, a one-word answer, code-only output, JSON-only output, or any other constrained format, obey that requested output shape exactly. Do not add sections, commentary, or meta-analysis in those cases.

        Do not ask the user a follow-up question. If there is no useful next step, write "None." for the next step.

        User prompt:
        \(clipped(originalPrompt, maxCharacters: 2_000))\(routeNote)

        Council responses:
        \(councilResponses)

        Return a polished final answer using Markdown headings exactly like this:
        ## Direct answer
        ## What the council agrees on
        ## Disagreements or uncertainty
        ## Recommended next step

        Preserve source citations where they are useful. If the model answers cite sources with bracket markers like [1], keep those markers in the synthesized answer.

        Do not include a "Why synthesis is better" section.
        """
    }

    private func streamResponseWithFallback(
        initialModel: String,
        text: String,
        attachments: [ChatAttachment],
        conversationID: String,
        previousResponseID: String?,
        initiator: String
    ) async throws -> String {
        var currentModel = initialModel
        var unavailableModels = Set<String>()

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
                return currentModel
            } catch {
                unavailableModels.insert(currentModel)
                guard !Self.isExternalModel(currentModel),
                      Self.isRecoverableModelError(error),
                      let fallbackModel = preferredAvailableModel(excluding: unavailableModels),
                      fallbackModel != currentModel else {
                    throw error
                }

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
                    ? "Turn on Hosted Agent in Account before sending."
                    : settings.endpointValidationMessage ?? "Add a hosted HTTPS IronClaw endpoint first."
                throw APIError.status(0, message)
            }
            let webContext = try await appWebGroundingContextIfNeeded(
                model: model,
                text: text,
                conversationID: conversationID,
                assistantMessageID: assistantMessageID
            )
            try await ironclawAPI.streamPrompt(
                prompt: ironclawPrompt(for: text, attachments: attachments, webContext: webContext),
                attachments: attachments,
                settings: settings,
                authToken: loadIronclawAuthToken(),
                onResolvedThreadID: { [weak self] threadID in
                    self?.rememberIronclawThreadID(threadID, for: conversationID)
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
        let response = try await api.fetchNearCloudChatCompletion(
            apiKey: apiKey,
            model: cloudModelID,
            prompt: nearCloudPrompt(for: text, attachments: attachments, webContext: webContext),
            systemPrompt: nearCloudSystemPrompt(modelDisplayName: modelDisplayName(for: modelID), hasWebContext: webContext != nil),
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
                streamEvent: .textDelta(Self.ironclawToolResultMarkdown(toolResults)),
                conversationID: conversationID,
                assistantMessageID: assistantMessageID
            )
        }

        if Self.promptNeedsRemoteWorkstation(text), ironclawRemoteWorkstationAvailable {
            updateCurrentExchange(to: ModelOption.ironclawModelID, shouldClearText: false)
            selectedModel = ModelOption.ironclawModelID
            let handoffMessage = """
            **IronClaw workstation handoff**
            This needs hosted git/code/shell/research tools, so I am running it on the IronClaw workstation. Local iOS project actions above stay attached to this run.

            """
            await apply(streamEvent: .textDelta(handoffMessage), conversationID: conversationID, assistantMessageID: assistantMessageID)
            showBanner("IronClaw Mobile handed this to the hosted workstation.")
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
        var unavailableModels = Set<String>()
        var modelFailures: [String: String] = [:]

        while let baseModel = preferredIronclawBaseModel(excluding: unavailableModels) {
            do {
                try await ironclawMobileRuntime.streamTurn(
                    prompt: Self.normalizedIronclawPrompt(text),
                    attachments: attachments,
                    context: mobileProjectContext(promptAttachments: attachments),
                    baseModel: baseModel,
                    conversationID: conversationID,
                    previousResponseID: previousResponseID,
                    webSearchEnabled: webContext == nil && shouldEnableModelNativeWebTool(model: ModelOption.ironclawMobileModelID, prompt: text),
                    systemPrompt: activeSystemPrompt(),
                    toolResults: toolResults,
                    webContext: webContext
                ) { [weak self] event in
                    await self?.apply(streamEvent: event, conversationID: conversationID, assistantMessageID: assistantMessageID)
                }
                return
            } catch {
                unavailableModels.insert(baseModel)
                modelFailures[baseModel] = Self.modelFailureSummary(error)
                if Self.isModelPlanError(error) {
                    deniedOpenWeightModelIDs.insert(baseModel)
                }
                guard Self.isRecoverableModelError(error) else {
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

                resetCurrentAssistantForRetry(preserving: Self.ironclawToolResultMarkdown(toolResults))
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
        let groundingPrompt = Self.webGroundingPrompt(from: text)
        guard shouldUseAppWebGrounding(model: model, prompt: groundingPrompt) else {
            return nil
        }

        let query = WebGroundingService.query(from: groundingPrompt)
        await apply(streamEvent: .webSearchStarted(query: query), conversationID: conversationID, assistantMessageID: assistantMessageID)
        do {
            let context = try await webGroundingService.search(
                for: groundingPrompt,
                preferNews: researchModeEnabled || Self.promptNeedsLiveWeb(groundingPrompt)
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

    private static func webGroundingPrompt(from text: String) -> String {
        if let brief = agentMissionBrief(from: text) {
            return brief
        }
        return strippedAgentLaunchPrefix(from: text)
    }

    private func shouldEnableModelNativeWebTool(model: String, prompt: String) -> Bool {
        let semantics = routingSemantics(for: Self.routeKind(forModelID: model))
        return semantics.modelNativeWebToolPolicy.resolves(
            benefitsFromSearch: Self.promptBenefitsFromAppSearch(prompt),
            needsFreshFacts: Self.promptNeedsLiveWeb(prompt)
        )
    }

    private func shouldUseAppWebGrounding(model: String, prompt: String) -> Bool {
        let route = Self.routeKind(forModelID: model)
        let semantics = routingSemantics(for: route)
        guard semantics.appWebGroundingPolicy != .never else { return false }
        if model == ModelOption.ironclawModelID,
           Self.promptNeedsRemoteWorkstation(prompt),
           !Self.promptNeedsLiveWeb(prompt) {
            return false
        }
        return semantics.appWebGroundingPolicy.resolves(
            benefitsFromSearch: Self.promptBenefitsFromAppSearch(prompt),
            needsFreshFacts: Self.promptNeedsLiveWeb(prompt)
        )
    }

    private func ironclawPrompt(
        for text: String,
        attachments: [ChatAttachment],
        webContext: WebGroundingContext?
    ) -> String {
        let prompt = Self.normalizedIronclawPrompt(text)
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
        var lines: [String] = []
        if let selectedProject {
            lines.append("iOS project context:")
            lines.append("- Project: \(selectedProject.name)")
            let instructions = selectedProject.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            if !instructions.isEmpty {
                lines.append("- Project instructions: \(Self.clipped(instructions, maxCharacters: 1_500))")
            }
            let memory = selectedProject.memorySummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !memory.isEmpty {
                lines.append("- Project memory: \(Self.clipped(memory, maxCharacters: 1_500))")
            }
            if !selectedProject.notes.isEmpty {
                let notes = selectedProject.notes.prefix(6).map { "\($0.title): \(Self.clipped($0.text, maxCharacters: 300))" }
                lines.append("- Project notes: \(notes.joined(separator: " | "))")
            }
            let publicLinks = selectedProject.links.filter { link in
                URL(string: link.urlString).map(URLSecurity.isPublicHTTPSURL) == true
            }
            if !publicLinks.isEmpty {
                let links = publicLinks.prefix(12).map { "\($0.displayTitle): \($0.urlString)" }
                lines.append("- Source links: \(links.joined(separator: " | "))")
            }
            if !selectedProject.attachments.isEmpty {
                lines.append("- Project files available by name in the app context: \(selectedProject.attachments.map(\.name).joined(separator: ", "))")
            }
        }
        if !promptAttachments.isEmpty {
            if lines.isEmpty {
                lines.append("iOS prompt context:")
            }
            lines.append("- Prompt files attached by name: \(promptAttachments.map(\.name).joined(separator: ", "))")
        }
        if lines.isEmpty { return "" }
        lines.append("- Focus: \(sourceModeDetail)")
        return lines.joined(separator: "\n")
    }

    private static func ironclawWorkstationInstructions(for prompt: String) -> String {
        guard promptNeedsRemoteWorkstation(prompt) else {
            return ""
        }
        return """
        IronClaw iOS coding-agent task.
        Please run the requested local workstation task now.
        You MUST use local workstation tools before answering. For git, code, shell, tests, files, repo setup, or filesystem requests, call shell, file, grep, or apply_patch first.
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

    

    private func ensureConversation(for firstMessage: String, attachments: [ChatAttachment]) async throws -> ConversationSummary {
        if let selectedConversation {
            return selectedConversation
        }

        let title = Self.initialConversationTitle(from: firstMessage, attachments: attachments)
        var created = try await api.createConversation(title: title)
        if created.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            created.metadata = ConversationMetadata(title: title)
        }
        conversations.insert(created, at: 0)
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
        let missionMarkers = ["Hosted IronClaw Mission:", "IronClaw Agent Mission:"]
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

        let brief = agentMissionBrief(from: text)
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

    private static func agentMissionBrief(from text: String) -> String? {
        guard let briefRange = text.range(of: "Mission brief from phone:", options: [.caseInsensitive]) else {
            return nil
        }
        let afterBrief = text[briefRange.upperBound...]
        let endRange = afterBrief.range(of: "Execution contract:", options: [.caseInsensitive])
        let rawBrief = endRange.map { String(afterBrief[..<$0.lowerBound]) } ?? String(afterBrief)
        let normalizedBrief = rawBrief
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#*` -").union(.whitespacesAndNewlines))
        guard !normalizedBrief.isEmpty else {
            return nil
        }
        return normalizedBrief
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
        guard let assistantMessageID else {
            return
        }

        switch event {
        case let .created(responseID):
            flushPendingTextDelta(for: assistantMessageID)
            updateMessage(assistantMessageID) { message in
                message.responseID = responseID
            }
        case .reasoningStarted:
            updateMessage(assistantMessageID) { message in
                if message.text.isEmpty {
                    message.status = "reasoning"
                }
            }
        case let .approvalNeeded(approval):
            flushPendingTextDelta(for: assistantMessageID)
            updateMessage(assistantMessageID) { message in
                message.pendingApproval = approval
                message.status = "approval"
                message.isStreaming = false
            }
        case let .webSearchStarted(query):
            updateMessage(assistantMessageID) { message in
                message.status = "searching"
                message.searchQuery = query
            }
        case let .webSearchCompleted(query, sources):
            updateMessage(assistantMessageID) { message in
                message.status = message.text.isEmpty ? "thinking" : message.status
                message.searchQuery = query ?? message.searchQuery
                message.sources = Self.uniqueSources(message.sources + sources)
            }
        case let .textDelta(delta):
            if !delta.isEmpty {
                let messageNeedsFirstTokenUpdate = messages.first(where: { $0.id == assistantMessageID }).map { message in
                    message.firstTokenAt == nil || (message.text.isEmpty && message.status == "searching")
                } ?? false
                if messageNeedsFirstTokenUpdate {
                    updateMessage(assistantMessageID) { message in
                        if message.text.isEmpty && message.status == "searching" {
                            message.status = "streaming"
                        }
                        if message.firstTokenAt == nil {
                            message.firstTokenAt = Date()
                        }
                    }
                }
            }
            appendBufferedTextDelta(delta, to: assistantMessageID)
        case let .itemDone(text):
            flushPendingTextDelta(for: assistantMessageID)
            if let text, !text.isEmpty {
                updateMessage(assistantMessageID) { message in
                    let existingText = message.text
                    if message.firstTokenAt == nil {
                        message.firstTokenAt = Date()
                    }
                    let shouldReplaceFailure = message.status == "failed" || Self.localFailureMessage(from: existingText) != nil
                    if existingText.isEmpty || shouldReplaceFailure || text.contains(existingText) {
                        message.text = text
                    } else if !existingText.contains(text) {
                        message.text += "\n\n\(text)"
                    }
                    if message.status != "approval" {
                        message.status = "streaming"
                        message.isStreaming = true
                    }
                }
            }
        case let .titleUpdated(title):
            guard !title.isEmpty else { return }
            if let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }) {
                conversations[conversationIndex].metadata = ConversationMetadata(title: title)
                selectedConversation = conversations[conversationIndex]
            }
        case let .completed(responseID):
            flushPendingTextDelta(for: assistantMessageID)
            updateMessage(assistantMessageID) { message in
                guard message.status != "failed", message.status != "approval" else {
                    message.responseID = responseID ?? message.responseID
                    message.isStreaming = false
                    return
                }
                message.responseID = responseID ?? message.responseID
                if message.sources.isEmpty {
                    message.sources = Self.inferredSources(from: message.text)
                }
                message.status = "completed"
                message.isStreaming = false
                if let localFailure = Self.localFailureMessage(from: message.text) {
                    message.status = "failed"
                    message.text = localFailure
                }
            }
        case let .failed(message):
            flushPendingTextDelta(for: assistantMessageID)
            let displayMessage = Self.displayFailureMessage(message)
            updateMessage(assistantMessageID) { message in
                message.status = "failed"
                message.isStreaming = false
                if message.text.isEmpty || Self.localFailureMessage(from: message.text) != nil {
                    message.text = displayMessage
                } else if !message.text.localizedCaseInsensitiveContains(displayMessage) {
                    message.text += "\n\nResponse failed: \(displayMessage)"
                }
            }
        }
    }

    @discardableResult
    private func updateMessage(_ messageID: String, mutate: (inout ChatMessage) -> Void) -> Bool {
        var updatedMessages = messages
        guard let index = updatedMessages.firstIndex(where: { $0.id == messageID }) else {
            return false
        }
        let originalMessage = updatedMessages[index]
        mutate(&updatedMessages[index])
        guard updatedMessages[index] != originalMessage else {
            return false
        }
        messages = updatedMessages
        return true
    }

    private func finishAssistantMessage(_ messageID: String) {
        flushPendingTextDelta(for: messageID)
        updateMessage(messageID) { message in
            message.isStreaming = false
            if message.status != "failed", message.status != "approval" {
                message.status = "completed"
            }
            if message.firstTokenAt == nil,
               !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                message.firstTokenAt = Date()
            }
            if message.widget == nil {
                let extraction = MessageWidget.extract(from: message.text)
                if let widget = extraction.widget {
                    message.widget = widget
                    message.text = extraction.cleanedText
                }
            }
            if message.sources.isEmpty {
                message.sources = Self.inferredSources(from: message.text)
            }
        }
    }

    private func appendBufferedTextDelta(_ delta: String, to messageID: String) {
        guard !delta.isEmpty else { return }
        pendingTextDeltaByMessageID[messageID, default: ""] += delta
        guard pendingTextDeltaFlushTask == nil else { return }
        let flushDelay = pendingTextDeltaFlushNanoseconds()
        pendingTextDeltaFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: flushDelay)
            guard !Task.isCancelled else { return }
            self?.flushPendingTextDeltas()
        }
    }

    private func pendingTextDeltaFlushNanoseconds() -> UInt64 {
        let pendingIDs = Set(pendingTextDeltaByMessageID.keys)
        guard !pendingIDs.isEmpty,
              pendingIDs.allSatisfy({ messageID in
                  messages.first(where: { $0.id == messageID })?.councilBatchID != nil
              }) else {
            return Self.streamDeltaFlushNanoseconds
        }
        return MessageStreamService.councilTextDeltaFlushNanoseconds
    }

    private func flushPendingTextDelta(for messageID: String) {
        guard let delta = pendingTextDeltaByMessageID.removeValue(forKey: messageID),
              !delta.isEmpty,
              let index = messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }
        var updatedMessages = messages
        updatedMessages[index].text += delta
        messages = updatedMessages
        if pendingTextDeltaByMessageID.isEmpty {
            pendingTextDeltaFlushTask?.cancel()
            pendingTextDeltaFlushTask = nil
        }
    }

    private func flushPendingTextDeltas() {
        pendingTextDeltaFlushTask = nil
        let pendingDeltas = pendingTextDeltaByMessageID
        pendingTextDeltaByMessageID.removeAll()
        guard !pendingDeltas.isEmpty else { return }

        var updatedMessages = messages
        var didApplyDelta = false
        for (messageID, delta) in pendingDeltas where !delta.isEmpty {
            guard let index = updatedMessages.firstIndex(where: { $0.id == messageID }) else {
                continue
            }
            updatedMessages[index].text += delta
            didApplyDelta = true
        }
        if didApplyDelta {
            messages = updatedMessages
        }
    }

    private func cancelPendingTextDeltaFlushes() {
        pendingTextDeltaFlushTask?.cancel()
        pendingTextDeltaFlushTask = nil
        pendingTextDeltaByMessageID.removeAll()
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
                threadID: approval.threadID
            ) { [weak self] event in
                await self?.apply(streamEvent: event, conversationID: conversationID)
            }

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
                threadID: approval.threadID
            ) { [weak self] event in
                await self?.apply(streamEvent: event, conversationID: conversationID)
            }

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
        var settings = ironclawSettings
        let configuredThreadID = settings.threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        if configuredThreadID.isEmpty, let mappedThreadID = loadIronclawThreadID(for: conversationID) {
            settings.threadID = mappedThreadID
        }
        return settings
    }

    private func rememberIronclawThreadID(_ threadID: String, for conversationID: String) {
        let trimmed = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var cache = loadIronclawThreadIDCache()
        guard cache[conversationID] != trimmed else {
            ironclawStatusText = "Using thread \(String(trimmed.prefix(8)))."
            return
        }
        cache[conversationID] = trimmed
        saveIronclawThreadIDCache(cache)
        ironclawStatusText = "Using thread \(String(trimmed.prefix(8)))."
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

    private func showBanner(_ message: String) {
        bannerMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if bannerMessage == message {
                bannerMessage = nil
            }
        }
    }

    private func apply(remoteSettings: RemoteUserSettings) {
        lastRemoteSettings = remoteSettings
        notificationPreferenceEnabled = remoteSettings.notification ?? false
        appearancePreference = AppAppearancePreference(remoteValue: remoteSettings.appearance)
        if let remoteWebSearch = remoteSettings.webSearch {
            webSearchEnabled = remoteWebSearch
        }
        if let remoteLargeTextAsFile = remoteSettings.largeTextAsFile {
            largeTextAsFileEnabled = remoteLargeTextAsFile
        }
        if remoteSettings.temperature != nil || remoteSettings.topP != nil || remoteSettings.maxTokens != nil {
            advancedModelParams = AdvancedModelParams(
                temperature: remoteSettings.temperature,
                topP: remoteSettings.topP,
                maxTokens: remoteSettings.maxTokens,
                reasoningEffort: advancedModelParams.reasoningEffort
            ).sanitized
        }
        systemPrompt = remoteSettings.systemPrompt ?? ""
    }

    private func loadAccountScopedState() {
        let loadedIronclawSettings = loadIronclawSettings()
        ironclawSettings = loadedIronclawSettings
        ironclawTokenConfigured = loadIronclawAuthToken()?.isEmpty == false
        nearCloudKeyConfigured = loadNearCloudAPIKey()?.isEmpty == false

        let storedModel = UserDefaults.standard.string(forKey: scopedDefaultsKey(Self.selectedModelDefaultsKey))
        let initialModel = storedModel ?? effectiveDefaultModelID
        selectedModel = Self.routeKind(forModelID: initialModel).isIronclawRoute ? effectiveDefaultModelID : initialModel
        let storedCouncilModelIDs = loadStoredCouncilModelIDs()
        councilModelIDs = storedCouncilModelIDs.isEmpty ? [selectedModel] : storedCouncilModelIDs
        pinnedModelIDs = loadPinnedModelIDs()
        selectedProjectID = UserDefaults.standard.string(forKey: scopedDefaultsKey(Self.selectedProjectDefaultsKey))

        if UserDefaults.standard.object(forKey: scopedDefaultsKey(Self.webSearchDefaultsKey)) == nil {
            webSearchEnabled = false
        } else {
            webSearchEnabled = UserDefaults.standard.bool(forKey: scopedDefaultsKey(Self.webSearchDefaultsKey))
        }
        if UserDefaults.standard.object(forKey: scopedDefaultsKey(Self.largeTextAsFileDefaultsKey)) == nil {
            largeTextAsFileEnabled = true
        } else {
            largeTextAsFileEnabled = UserDefaults.standard.bool(forKey: scopedDefaultsKey(Self.largeTextAsFileDefaultsKey))
        }
        if let rawSourceMode = UserDefaults.standard.string(forKey: scopedDefaultsKey(Self.sourceModeDefaultsKey)),
           let loadedSourceMode = ChatSourceMode(rawValue: rawSourceMode) {
            sourceMode = loadedSourceMode
        } else {
            sourceMode = .auto
        }
        researchModeEnabled = UserDefaults.standard.bool(forKey: scopedDefaultsKey(Self.researchModeDefaultsKey))
        advancedModelParams = loadAdvancedModelParams()
        systemPrompt = loadProtectedText(filename: Self.systemPromptCacheFilename, legacyDefaultsKey: scopedDefaultsKey(Self.systemPromptDefaultsKey))
        conversations = loadCachedConversations()
        projects = loadProjects()
        selectedResponseVariantByConversationID = [:]
        transitionDraftScopeToCurrentSelection(loadDraft: true)

        if loadedIronclawSettings.hasUsableHostedEndpoint {
            ironclawStatusText = ironclawTokenConfigured ? "Hosted endpoint and token saved." : "Hosted endpoint saved."
        } else if loadedIronclawSettings.hasEndpoint {
            ironclawStatusText = loadedIronclawSettings.endpointValidationMessage ?? "Endpoint needs attention."
        } else if ironclawTokenConfigured {
            ironclawStatusText = "Endpoint token saved. Add hosted URL."
        } else {
            ironclawStatusText = "Not connected"
        }
    }

    private func scopedDefaultsKey(_ key: String) -> String {
        Self.scopedDefaultsKey(key, accountID: storageAccountID)
    }

    private var currentDraftScopeID: String {
        if let conversationID = selectedConversation?.id.trimmingCharacters(in: .whitespacesAndNewlines),
           !conversationID.isEmpty {
            return "conversation:\(conversationID)"
        }
        if let projectID = selectedProjectID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !projectID.isEmpty {
            return "project:\(projectID)"
        }
        return "home"
    }

    private func transitionDraftScopeToCurrentSelection(loadDraft: Bool) {
        draftPersistenceScopeID = currentDraftScopeID
        guard loadDraft else { return }
        let persistedState = loadPersistedDraftState(for: draftPersistenceScopeID)
        suppressDraftPersistence = true
        draft = persistedState.text
        pendingAttachments = persistedState.attachments
        pendingLargePasteTexts = persistedState.pendingLargePasteTexts
        suppressDraftPersistence = false
    }

    private func persistCurrentDraftIfNeeded() {
        guard !suppressDraftPersistence, !isResettingAccountScopedState else { return }
        let state = PersistedDraftState(
            text: draft,
            attachments: pendingAttachments,
            pendingLargePasteTexts: pendingLargePasteTexts
        ).sanitized
        if state.isEmpty {
            removePersistedDraft(for: draftPersistenceScopeID)
            return
        }
        guard let data = try? JSONEncoder().encode(state),
              writeFileBackedData(
                  data,
                  filename: draftStateCacheFilename(for: draftPersistenceScopeID),
                  legacyDefaultsKey: draftStateDefaultsKey(for: draftPersistenceScopeID)
              ) else {
            showBanner("Draft state could not be saved securely.")
            return
        }
        removeProtectedText(
            filename: draftCacheFilename(for: draftPersistenceScopeID),
            legacyDefaultsKey: draftDefaultsKey(for: draftPersistenceScopeID)
        )
        UserDefaults.standard.removeObject(forKey: draftStateDefaultsKey(for: draftPersistenceScopeID))
    }

    private func removePersistedDraft(for scopeID: String) {
        removeProtectedText(filename: draftCacheFilename(for: scopeID), legacyDefaultsKey: draftDefaultsKey(for: scopeID))
        try? FileManager.default.removeItem(at: Self.fileBackedStoreURL(
            filename: draftStateCacheFilename(for: scopeID),
            accountID: storageAccountID
        ))
        UserDefaults.standard.removeObject(forKey: draftStateDefaultsKey(for: scopeID))
    }

    private func draftDefaultsKey(for scopeID: String) -> String {
        scopedDefaultsKey("\(Self.draftDefaultsKeyPrefix).\(scopeID)")
    }

    private func draftStateDefaultsKey(for scopeID: String) -> String {
        scopedDefaultsKey("\(Self.draftStateDefaultsKeyPrefix).\(scopeID)")
    }

    private func draftCacheFilename(for scopeID: String) -> String {
        "\(Self.draftCacheDirectoryName)/\(Self.safeCacheFilenameComponent(scopeID)).txt"
    }

    private func draftStateCacheFilename(for scopeID: String) -> String {
        "\(Self.draftStateCacheDirectoryName)/\(Self.safeCacheFilenameComponent(scopeID)).json"
    }

    private func loadPersistedDraftState(for scopeID: String) -> PersistedDraftState {
        if let data = fileBackedData(
            filename: draftStateCacheFilename(for: scopeID),
            legacyDefaultsKey: draftStateDefaultsKey(for: scopeID)
        ),
           let state = try? JSONDecoder().decode(PersistedDraftState.self, from: data) {
            return state.sanitized
        }

        return PersistedDraftState(
            text: loadProtectedText(
                filename: draftCacheFilename(for: scopeID),
                legacyDefaultsKey: draftDefaultsKey(for: scopeID)
            ),
            attachments: [],
            pendingLargePasteTexts: [:]
        )
    }

    private func scopedKeychainAccount(_ account: String) -> String {
        Self.scopedDefaultsKey(account, accountID: storageAccountID)
    }

    private static func scopedDefaultsKey(_ key: String, accountID: String) -> String {
        "\(key).account.\(normalizedStorageScope(accountID))"
    }

    private static func storageScope(for accountID: String?) -> String {
        let trimmed = accountID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? signedOutStorageAccountID : trimmed
    }

    private static func shouldMigrateStorage(from oldAccountID: String, to newAccountID: String) -> Bool {
        oldAccountID != newAccountID &&
            UserSetupStorage.isFallbackAccountID(oldAccountID) &&
            !UserSetupStorage.isFallbackAccountID(newAccountID) &&
            newAccountID != signedOutStorageAccountID
    }

    private static func migrateAccountScopedStorage(from oldAccountID: String, to newAccountID: String) {
        let defaultsKeys = [
            selectedModelDefaultsKey,
            councilModelDefaultsKey,
            pinnedModelDefaultsKey,
            selectedProjectDefaultsKey,
            webSearchDefaultsKey,
            sourceModeDefaultsKey,
            researchModeDefaultsKey,
            systemPromptDefaultsKey,
            largeTextAsFileDefaultsKey,
            advancedModelParamsDefaultsKey,
            ironclawSettingsDefaultsKey
        ]
        for key in defaultsKeys {
            let oldKey = scopedDefaultsKey(key, accountID: oldAccountID)
            let newKey = scopedDefaultsKey(key, accountID: newAccountID)
            if UserDefaults.standard.object(forKey: newKey) == nil,
               let object = UserDefaults.standard.object(forKey: oldKey) {
                UserDefaults.standard.set(object, forKey: newKey)
            }
            UserDefaults.standard.removeObject(forKey: oldKey)
        }

        let fileCaches: [(filename: String, legacyKey: String)] = [
            (conversationsCacheFilename, conversationsCacheKey),
            (projectsCacheFilename, projectsDefaultsKey),
            (localMessagesCacheFilename, localMessagesDefaultsKey),
            (ironclawThreadIDsCacheFilename, ironclawThreadIDsDefaultsKey)
        ]
        for cache in fileCaches {
            if fileBackedData(filename: cache.filename, legacyDefaultsKey: cache.legacyKey, accountID: newAccountID) == nil,
               let oldData = fileBackedData(filename: cache.filename, legacyDefaultsKey: cache.legacyKey, accountID: oldAccountID) {
                _ = writeFileBackedData(
                    oldData,
                    filename: cache.filename,
                    legacyDefaultsKey: cache.legacyKey,
                    accountID: newAccountID
                )
            }
            try? FileManager.default.removeItem(at: fileBackedStoreURL(filename: cache.filename, accountID: oldAccountID))
        }

        let keychainAccounts = [
            ironclawTokenKeychainAccount,
            nearCloudAPIKeychainAccount
        ]
        for account in keychainAccounts {
            let oldAccount = scopedDefaultsKey(account, accountID: oldAccountID)
            let newAccount = scopedDefaultsKey(account, accountID: newAccountID)
            if (try? KeychainStore.readString(account: newAccount)) == nil,
               let value = try? KeychainStore.readString(account: oldAccount) {
                try? KeychainStore.save(value, account: newAccount)
            }
            KeychainStore.delete(account: oldAccount)
        }
    }

    private static func normalizedStorageScope(_ accountID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = accountID.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let normalized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return normalized.isEmpty ? signedOutStorageAccountID : normalized
    }

    private static func safeCacheFilenameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        var normalized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        if normalized.count > 96 {
            normalized = "\(normalized.prefix(72))-\(stableShortDigest(value))"
        }
        return normalized.isEmpty ? "home" : normalized
    }

    private static func stableShortDigest(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    private func saveIronclawSettings(_ settings: IronclawSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: scopedDefaultsKey(Self.ironclawSettingsDefaultsKey))
    }

    private func saveAdvancedModelParams(_ params: AdvancedModelParams) {
        guard let data = try? JSONEncoder().encode(params.sanitized) else { return }
        UserDefaults.standard.set(data, forKey: scopedDefaultsKey(Self.advancedModelParamsDefaultsKey))
    }

    private func loadAdvancedModelParams() -> AdvancedModelParams {
        guard let data = UserDefaults.standard.data(forKey: scopedDefaultsKey(Self.advancedModelParamsDefaultsKey)),
              let params = try? JSONDecoder().decode(AdvancedModelParams.self, from: data) else {
            return .defaults
        }
        return params.sanitized
    }

    private func loadStoredCouncilModelIDs() -> [String] {
        normalizedCouncilModelIDs(UserDefaults.standard.stringArray(forKey: scopedDefaultsKey(Self.councilModelDefaultsKey)) ?? [])
    }

    private func loadPinnedModelIDs() -> [String] {
        Array(Self.uniqueStrings(UserDefaults.standard.stringArray(forKey: scopedDefaultsKey(Self.pinnedModelDefaultsKey)) ?? []).prefix(Self.maxPinnedModels))
    }

    private func loadIronclawSettings() -> IronclawSettings {
        guard let data = UserDefaults.standard.data(forKey: scopedDefaultsKey(Self.ironclawSettingsDefaultsKey)),
              let settings = try? JSONDecoder().decode(IronclawSettings.self, from: data) else {
            return .default
        }
        let sanitized = settings.standalonePhoneSanitized
        if sanitized != settings {
            saveIronclawSettings(sanitized)
        }
        return sanitized
    }

    private func loadIronclawAuthToken() -> String? {
        (try? KeychainStore.readString(account: scopedKeychainAccount(Self.ironclawTokenKeychainAccount))) ?? nil
    }

    private func loadNearCloudAPIKey() -> String? {
        (try? KeychainStore.readString(account: scopedKeychainAccount(Self.nearCloudAPIKeychainAccount))) ?? nil
    }

    private func fileBackedData(filename: String, legacyDefaultsKey: String) -> Data? {
        Self.fileBackedData(filename: filename, legacyDefaultsKey: legacyDefaultsKey, accountID: storageAccountID)
    }

    @discardableResult
    private func writeFileBackedData(_ data: Data, filename: String, legacyDefaultsKey: String) -> Bool {
        Self.writeFileBackedData(data, filename: filename, legacyDefaultsKey: legacyDefaultsKey, accountID: storageAccountID)
    }

    private func loadProtectedText(filename: String, legacyDefaultsKey: String) -> String {
        if let data = fileBackedData(filename: filename, legacyDefaultsKey: legacyDefaultsKey),
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        guard let legacyValue = UserDefaults.standard.string(forKey: legacyDefaultsKey) else {
            return ""
        }
        saveProtectedText(legacyValue, filename: filename, legacyDefaultsKey: legacyDefaultsKey)
        return legacyValue
    }

    private func saveProtectedText(_ value: String, filename: String, legacyDefaultsKey: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            removeProtectedText(filename: filename, legacyDefaultsKey: legacyDefaultsKey)
            return
        }
        guard let data = value.data(using: .utf8),
              writeFileBackedData(data, filename: filename, legacyDefaultsKey: legacyDefaultsKey) else {
            showBanner("Private text could not be saved securely.")
            return
        }
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }

    private func removeProtectedText(filename: String, legacyDefaultsKey: String) {
        try? FileManager.default.removeItem(at: Self.fileBackedStoreURL(filename: filename, accountID: storageAccountID))
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }

    private func cacheConversations(_ conversations: [ConversationSummary]) {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        if !writeFileBackedData(data, filename: Self.conversationsCacheFilename, legacyDefaultsKey: Self.conversationsCacheKey) {
            showBanner("Chat list cache could not be saved securely.")
        }
    }

    private func loadCachedConversations() -> [ConversationSummary] {
        guard let data = fileBackedData(filename: Self.conversationsCacheFilename, legacyDefaultsKey: Self.conversationsCacheKey),
              let conversations = try? JSONDecoder().decode([ConversationSummary].self, from: data) else {
            return []
        }
        return conversations
    }

    private func loadProjects() -> [ChatProject] {
        guard let data = fileBackedData(filename: Self.projectsCacheFilename, legacyDefaultsKey: Self.projectsDefaultsKey),
              let projects = try? JSONDecoder().decode([ChatProject].self, from: data) else {
            return []
        }
        return projects.sorted { $0.createdAt > $1.createdAt }
    }

    private func loadLocalMessages(for conversationID: String) -> [ChatMessage]? {
        loadLocalMessageCache()[conversationID]
    }

    func cachedConversationPreview(for conversationID: String) -> String? {
        let sourceMessages: [ChatMessage]
        if selectedConversation?.id == conversationID, !messages.isEmpty {
            sourceMessages = messages
        } else {
            sourceMessages = loadLocalMessages(for: conversationID) ?? []
        }
        return sourceMessages
            .reversed()
            .first { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { Self.compactPreviewText($0.text) }
    }

    private static func compactPreviewText(_ text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > 140 else { return collapsed }
        return "\(collapsed.prefix(137))..."
    }

    private func loadLocalMessageCache() -> [String: [ChatMessage]] {
        guard let data = fileBackedData(filename: Self.localMessagesCacheFilename, legacyDefaultsKey: Self.localMessagesDefaultsKey),
              let cache = try? JSONDecoder().decode([String: [ChatMessage]].self, from: data) else {
            return [:]
        }
        return cache
    }

    private func loadIronclawThreadID(for conversationID: String) -> String? {
        let trimmed = loadIronclawThreadIDCache()[conversationID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func loadIronclawThreadIDCache() -> [String: String] {
        guard let data = fileBackedData(filename: Self.ironclawThreadIDsCacheFilename, legacyDefaultsKey: Self.ironclawThreadIDsDefaultsKey),
              let cache = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return cache
    }

    private func saveIronclawThreadIDCache(_ cache: [String: String]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        if !writeFileBackedData(data, filename: Self.ironclawThreadIDsCacheFilename, legacyDefaultsKey: Self.ironclawThreadIDsDefaultsKey) {
            showBanner("IronClaw thread cache could not be saved securely.")
        }
    }

    private func removeIronclawThreadID(for conversationID: String) {
        var cache = loadIronclawThreadIDCache()
        cache.removeValue(forKey: conversationID)
        saveIronclawThreadIDCache(cache)
    }

    private func saveProjects() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        if !writeFileBackedData(data, filename: Self.projectsCacheFilename, legacyDefaultsKey: Self.projectsDefaultsKey) {
            showBanner("Project cache could not be saved securely.")
        }
    }

    private func saveLocalMessages(for conversationID: String) {
        var cache = loadLocalMessageCache()
        cache[conversationID] = messages
        guard let data = try? JSONEncoder().encode(cache) else { return }
        if !writeFileBackedData(data, filename: Self.localMessagesCacheFilename, legacyDefaultsKey: Self.localMessagesDefaultsKey) {
            showBanner("Local message cache could not be saved securely.")
        }
    }

    private func removeLocalMessages(for conversationID: String) {
        var cache = loadLocalMessageCache()
        cache.removeValue(forKey: conversationID)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        if !writeFileBackedData(data, filename: Self.localMessagesCacheFilename, legacyDefaultsKey: Self.localMessagesDefaultsKey) {
            showBanner("Local message cache could not be updated securely.")
        }
        removeIronclawThreadID(for: conversationID)
    }

    nonisolated private static func isExternalModel(_ modelID: String) -> Bool {
        modelID == ModelOption.ironclawModelID ||
            modelID == ModelOption.ironclawMobileModelID ||
            modelID == ModelOption.nearCloudQwenMaxModelID ||
            modelID.hasPrefix(ModelOption.nearCloudModelPrefix)
    }

    private static func ironclawMobileModel() -> ModelOption {
        ModelCatalogStore.ironclawMobileModel()
    }

    private static func ironclawModel() -> ModelOption {
        ModelCatalogStore.ironclawModel()
    }

    private static func fallbackNearCloudModels() -> [ModelOption] {
        ModelCatalogStore.fallbackNearCloudModels()
    }

    private static func nearCloudRouteModels(from cloudModels: [ModelOption]) -> [ModelOption] {
        ModelCatalogStore.nearCloudRouteModels(from: cloudModels)
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

    private static func saveIronclawSettings(_ settings: IronclawSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: ironclawSettingsDefaultsKey)
    }

    private static func saveAdvancedModelParams(_ params: AdvancedModelParams) {
        guard let data = try? JSONEncoder().encode(params.sanitized) else { return }
        UserDefaults.standard.set(data, forKey: advancedModelParamsDefaultsKey)
    }

    private static func loadAdvancedModelParams() -> AdvancedModelParams {
        guard let data = UserDefaults.standard.data(forKey: advancedModelParamsDefaultsKey),
              let params = try? JSONDecoder().decode(AdvancedModelParams.self, from: data) else {
            return .defaults
        }
        return params.sanitized
    }

    private static func loadStoredCouncilModelIDs() -> [String] {
        let ids = (UserDefaults.standard.stringArray(forKey: councilModelDefaultsKey) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var seen = Set<String>()
        var normalized: [String] = []
        for modelID in ids {
            guard !modelID.isEmpty, !seen.contains(modelID) else {
                continue
            }
            normalized.append(modelID)
            seen.insert(modelID)
            if normalized.count == maxCouncilModels {
                break
            }
        }
        return normalized
    }

    private static func loadIronclawSettings() -> IronclawSettings {
        guard let data = UserDefaults.standard.data(forKey: ironclawSettingsDefaultsKey),
              let settings = try? JSONDecoder().decode(IronclawSettings.self, from: data) else {
            return .default
        }
        let sanitized = settings.standalonePhoneSanitized
        if sanitized != settings {
            saveIronclawSettings(sanitized)
        }
        return sanitized
    }

    private static func loadIronclawAuthToken() -> String? {
        (try? KeychainStore.readString(account: ironclawTokenKeychainAccount)) ?? nil
    }

    private static func loadNearCloudAPIKey() -> String? {
        (try? KeychainStore.readString(account: nearCloudAPIKeychainAccount)) ?? nil
    }

    private static func loadLocalMessages(for conversationID: String) -> [ChatMessage]? {
        loadLocalMessageCache()[conversationID]
    }

    private static func loadLocalMessageCache() -> [String: [ChatMessage]] {
        guard let data = fileBackedData(filename: localMessagesCacheFilename, legacyDefaultsKey: localMessagesDefaultsKey),
              let cache = try? JSONDecoder().decode([String: [ChatMessage]].self, from: data) else {
            return [:]
        }
        return cache
    }

    private static func loadIronclawThreadID(for conversationID: String) -> String? {
        let trimmed = loadIronclawThreadIDCache()[conversationID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func loadIronclawThreadIDCache() -> [String: String] {
        guard let data = fileBackedData(filename: ironclawThreadIDsCacheFilename, legacyDefaultsKey: ironclawThreadIDsDefaultsKey),
              let cache = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return cache
    }

    private static func saveIronclawThreadIDCache(_ cache: [String: String]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        writeFileBackedData(data, filename: ironclawThreadIDsCacheFilename, legacyDefaultsKey: ironclawThreadIDsDefaultsKey)
    }

    private static func removeIronclawThreadID(for conversationID: String) {
        var cache = loadIronclawThreadIDCache()
        cache.removeValue(forKey: conversationID)
        saveIronclawThreadIDCache(cache)
    }

    private static func promptNeedsLiveWeb(_ prompt: String) -> Bool {
        let lowercased = prompt.lowercased()
        let triggers = [
            "latest",
            "current",
            "today",
            "right now",
            "this week",
            "recent",
            "news",
            "web search",
            "search the web",
            "browse",
            "cite",
            "citation",
            "sources",
            "source links"
        ]
        return triggers.contains { lowercased.contains($0) }
    }

    private static func promptRequestsCouncil(_ prompt: String) -> Bool {
        let lowercased = prompt
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowercased.isEmpty else { return false }

        let directPhrases = [
            "llm council",
            "model council",
            "multi-model",
            "multi model",
            "multiple models",
            "several models",
            "ask different models",
            "ask multiple models",
            "run different models",
            "run multiple models",
            "all the models",
            "second opinion",
            "second opinions",
            "compare model answers",
            "compare answers from models",
            "consensus answer",
            "model consensus"
        ]
        if directPhrases.contains(where: { lowercased.contains($0) }) {
            return true
        }

        let comparisonWords = [
            "compare",
            "contrast",
            "debate",
            "cross-check",
            "cross check",
            "sanity check",
            "red team"
        ]
        let modelWords = [
            "model",
            "models",
            "answers",
            "responses",
            "opinions",
            "takes"
        ]
        return comparisonWords.contains { lowercased.contains($0) } &&
            modelWords.contains { lowercased.contains($0) }
    }

    private static func promptNeedsRemoteWorkstation(_ prompt: String) -> Bool {
        let lowercased = prompt
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowercased.isEmpty else { return false }

        let explicitAgentPhrases = [
            "use ironclaw",
            "ask ironclaw",
            "hosted ironclaw",
            "ironclaw agent",
            "coding agent",
            "software agent",
            "remote workstation",
            "hosted workstation",
            "agent mission:",
            "phone agent:",
            "run tests",
            "run the tests",
            "git status",
            "make changes",
            "fix the repo",
            "review the repo",
            "audit the repo",
            "clone and",
            "research to code",
            "research-to-code",
            "write software",
            "build software"
        ]
        if explicitAgentPhrases.contains(where: { lowercased.contains($0) }) {
            return true
        }

        let remoteActions = [
            "agent",
            "agentic",
            "audit",
            "analyze",
            "review",
            "debug",
            "diagnose",
            "triage",
            "implement",
            "scaffold",
            "refactor",
            "run",
            "execute",
            "inspect",
            "clone",
            "checkout",
            "branch",
            "commit",
            "push",
            "pull",
            "open a pr",
            "create a pr",
            "make a pr",
            "pull request",
            "edit",
            "modify",
            "patch",
            "fix",
            "write",
            "build",
            "test",
            "ship",
            "install",
            "deploy",
            "ssh",
            "use git",
            "can you use",
            "from my phone"
        ]
        let remoteTargets = [
            "git ",
            " git",
            "git?",
            "git.",
            "github",
            "repo",
            "repository",
            " code ",
            "code?",
            "code.",
            "codebase",
            "source code",
            "source file",
            "pull request",
            "package.json",
            "requirements.txt",
            "unit test",
            "tests",
            "xcode",
            "swiftui",
            "write software",
            "build software",
            "software",
            "xcodebuild",
            "swift",
            "npm",
            "node ",
            "javascript",
            "typescript",
            "python",
            "pytest",
            "rust",
            "cargo",
            "terminal",
            "shell",
            "filesystem",
            "file system",
            "docker",
            "mcp",
            "workstation",
            "ironclaw hosted"
        ]
        let hasAction = remoteActions.contains { lowercased.contains($0) }
        let hasTarget = remoteTargets.contains { lowercased.contains($0) }
        return hasAction && hasTarget
    }

    private func phoneAgentMissionPromptIfNeeded(for text: String) -> String? {
        guard selectedModel == ModelOption.ironclawModelID || selectedModel == ModelOption.ironclawMobileModelID else {
            return nil
        }
        guard Self.promptNeedsRemoteWorkstation(text) else {
            return nil
        }
        return Self.phoneAgentMissionPrompt(for: text)
    }

    private static func phoneAgentMissionPrompt(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if trimmed.localizedCaseInsensitiveContains("IronClaw Agent Mission:") ||
            trimmed.localizedCaseInsensitiveContains("Hosted IronClaw Mission:") {
            return nil
        }

        let brief = strippedAgentLaunchPrefix(from: trimmed)
        let mission = phoneAgentMissionKind(for: brief)
        let skillPrompt = IronclawSkillCatalog.promptSection(for: brief)
        return """
        Hosted IronClaw Mission: \(mission.title)

        Mission brief from phone:
        \(brief)

        Execution contract:
        \(mission.executionContract)

        IronClaw skill routing:
        \(mission.skillRoutingHint)
        \(skillPrompt)

        Phone run contract:
        - Result first; do not echo this contract back to the user.
        - Keep commands bounded with timeouts and explain any skipped step.
        - Do not commit, push, or open a PR unless I explicitly ask.
        - Return Commands, Changed Files, Tests, Risk, and Next Actions.
        """
    }

    private static func strippedAgentLaunchPrefix(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "Hosted IronClaw:",
            "Hosted IronClaw agent:",
            "IronClaw agent:",
            "Agent mission:",
            "Phone agent:",
            "Agent:"
        ]
        for prefix in prefixes where trimmed.lowercased().hasPrefix(prefix.lowercased()) {
            let start = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
            let stripped = trimmed[start...].trimmingCharacters(in: .whitespacesAndNewlines)
            return stripped.isEmpty ? trimmed : stripped
        }
        return trimmed
    }

    private func organizePhoneAgentConversationIfNeeded(
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
        guard let detectedRepoURL = Self.firstRepoURL(in: "\(originalText)\n\(routedText)"),
              let projectName = Self.repoProjectName(from: detectedRepoURL) else {
            return
        }
        let repoRootURL = Self.repoRootURL(from: detectedRepoURL) ?? detectedRepoURL

        let projectIndex: Int
        if let selectedProjectID,
           let currentProjectIndex = projects.firstIndex(where: { $0.id == selectedProjectID }) {
            projectIndex = currentProjectIndex
            if !projects[projectIndex].conversationIDs.contains(conversation.id) {
                projects[projectIndex].conversationIDs.append(conversation.id)
            }
        } else {
            let project = ensureMobileProject(named: projectName, includeConversationID: conversation.id)
            guard let createdIndex = projects.firstIndex(where: { $0.id == project.id }) else {
                return
            }
            projectIndex = createdIndex
        }

        addProjectLinkIfNeeded(
            projectIndex: projectIndex,
            title: projectName,
            urlString: repoRootURL.absoluteString
        )
        if detectedRepoURL.absoluteString != repoRootURL.absoluteString {
            addProjectLinkIfNeeded(
                projectIndex: projectIndex,
                title: Self.repoTaskLinkTitle(from: detectedRepoURL, projectName: projectName),
                urlString: detectedRepoURL.absoluteString
            )
        }

        if projects[projectIndex].instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            projects[projectIndex].instructions = "Repo-backed IronClaw agent workspace. Use saved repo, issue, PR, and source links for follow-up research, code edits, tests, and triage for \(projectName)."
        }

        saveProjects()
    }

    private func addProjectLinkIfNeeded(projectIndex: Int, title: String, urlString: String) {
        guard projects.indices.contains(projectIndex) else {
            return
        }
        guard let normalizedURL = Self.normalizedProjectLinkURL(urlString) else {
            return
        }
        guard !projects[projectIndex].links.contains(where: { $0.urlString == normalizedURL.absoluteString }) else {
            return
        }
        projects[projectIndex].links.insert(
            ProjectLink(title: title, urlString: normalizedURL.absoluteString),
            at: 0
        )
    }

    private static func firstRepoURL(in text: String) -> URL? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?:(?:https?://)?(?:www\.)?)?(?:github\.com|gitlab\.com|bitbucket\.org)/[^\s,;)"']+"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }
        let rawURL = String(text[matchRange])
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}"))
        return normalizedProjectLinkURL(rawURL)
    }

    private static func repoProjectName(from url: URL) -> String? {
        guard let host = url.host()?.lowercased(), !host.isEmpty else {
            return nil
        }
        let pathParts = url.path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard pathParts.count >= 2 else {
            return nil
        }

        let owner = cleanProjectName(pathParts[0])
        let repo = cleanProjectName(strippedGitSuffix(pathParts[1]))
        guard let owner, let repo else {
            return nil
        }
        return "\(owner)/\(repo)"
    }

    private static func repoRootURL(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let pathParts = components.path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard pathParts.count >= 2 else {
            return nil
        }
        components.path = "/\(pathParts[0])/\(strippedGitSuffix(pathParts[1]))"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func repoTaskLinkTitle(from url: URL, projectName: String) -> String {
        let pathParts = url.path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard pathParts.count >= 4 else {
            return "Task link"
        }

        let kind = pathParts[2].lowercased()
        let identifier = pathParts[3]
        switch kind {
        case "issues":
            return "Issue #\(identifier)"
        case "pull", "pulls":
            return "PR #\(identifier)"
        case "merge_requests":
            return "MR #\(identifier)"
        case "commit", "commits":
            return "Commit \(String(identifier.prefix(8)))"
        case "tree":
            return "Branch \(identifier)"
        case "blob":
            return "File in \(projectName)"
        default:
            return "Task link"
        }
    }

    private static func cleanProjectName(_ rawName: String) -> String? {
        let trimmed = rawName
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'` "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(80))
    }

    private static func strippedGitSuffix(_ value: String) -> String {
        value.replacingOccurrences(of: #"\.git$"#, with: "", options: .regularExpression)
    }

    private static func phoneAgentMissionKind(for text: String) -> PhoneAgentMissionKind {
        let lowercased = text.lowercased()
        let hasSecurityIntent = [
            "security review",
            "security audit",
            "vulnerability",
            "vulnerabilities",
            "threat model",
            "secrets",
            "secret leak",
            "auth bug",
            "permission bug",
            "ssrf",
            "xss",
            "injection"
        ].contains { lowercased.contains($0) }
        let hasQAIntent = [
            "qa review",
            "qa pass",
            "quality assurance",
            "test plan",
            "manual qa",
            "smoke test",
            "web ui test",
            "browser test",
            "repro steps"
        ].contains { lowercased.contains($0) }
        let hasPlanningIntent = [
            "plan",
            "break down",
            "architecture",
            "technical design",
            "design doc",
            "scope this",
            "implementation plan"
        ].contains { lowercased.contains($0) }
        let hasProductPrioritizationIntent = [
            "prioritize",
            "prioritization",
            "roadmap",
            "what should we build",
            "product strategy",
            "rank these",
            "feature priority"
        ].contains { lowercased.contains($0) }
        let hasDecisionCaptureIntent = [
            "decision",
            "decisions",
            "decision log",
            "capture this",
            "adr",
            "record the decision"
        ].contains { lowercased.contains($0) }
        let hasResearchIntent = [
            "research",
            "latest",
            "current",
            "news",
            "web search",
            "search the web",
            "sources",
            "cite"
        ].contains { lowercased.contains($0) }
        let hasGithubTriageIntent = [
            "issue",
            "issues",
            "/issues/",
            "/pull/",
            "/pulls/",
            "/merge_requests/",
            "pull request",
            "pr ",
            "review",
            "audit",
            "triage"
        ].contains { lowercased.contains($0) }
        let hasCodeReviewIntent = hasGithubTriageIntent && [
            "code review",
            "review this pr",
            "review this pull",
            "review the diff",
            "review the repo",
            "review this repo",
            "audit the repo"
        ].contains { lowercased.contains($0) }
        let hasSetupIntent = [
            "clone",
            "set up",
            "setup",
            "install",
            "bootstrap",
            "get this running"
        ].contains { lowercased.contains($0) }
        let hasPatchIntent = [
            "fix",
            "implement",
            "edit",
            "modify",
            "patch",
            "refactor",
            "write",
            "build",
            "test"
        ].contains { lowercased.contains($0) }

        if hasSecurityIntent {
            return .securityReview
        }
        if hasQAIntent {
            return .qaReview
        }
        if hasProductPrioritizationIntent {
            return .productPrioritization
        }
        if hasDecisionCaptureIntent {
            return .decisionCapture
        }
        if hasPlanningIntent && !hasPatchIntent {
            return .planMode
        }
        if hasResearchIntent {
            return .researchToCode
        }
        if hasCodeReviewIntent {
            return .codeReview
        }
        if hasGithubTriageIntent {
            return .githubTriage
        }
        if hasSetupIntent && !hasPatchIntent {
            return .repoSetup
        }
        return .patchAndTest
    }

    private enum PhoneAgentMissionKind {
        case repoSetup
        case patchAndTest
        case researchToCode
        case githubTriage
        case codeReview
        case securityReview
        case qaReview
        case planMode
        case productPrioritization
        case decisionCapture

        var title: String {
            switch self {
            case .repoSetup:
                return "Repo Setup"
            case .patchAndTest:
                return "Patch + Test"
            case .researchToCode:
                return "Research To Code"
            case .githubTriage:
                return "GitHub Triage"
            case .codeReview:
                return "Code Review"
            case .securityReview:
                return "Security Review"
            case .qaReview:
                return "QA Review"
            case .planMode:
                return "Plan Mode"
            case .productPrioritization:
                return "Product Prioritization"
            case .decisionCapture:
                return "Decision Capture"
            }
        }

        var executionContract: String {
            switch self {
            case .repoSetup:
                return "Clone or inspect the repo, identify the stack, install only required dependencies, and report the exact run/test command path."
            case .patchAndTest:
                return "Inspect the relevant files, make the smallest useful patch, run focused tests or static checks with timeouts, and explain any remaining gap."
            case .researchToCode:
                return "Call nearai_web_search first when fresh sources are needed, convert findings into a concrete repo plan, then patch and test only when the repo context is available."
            case .githubTriage:
                return "Use IronClaw's GitHub and software-agent tools to inspect linked issues, PRs, or repo context, then produce a prioritized action plan with any safe patch or test result."
            case .codeReview:
                return "Review the linked repo, PR, diff, or files for correctness bugs, regressions, missing tests, and maintainability risks. Lead with findings by severity and include file/line references when available."
            case .securityReview:
                return "Perform a security-focused review for auth, secrets, injection, SSRF, permission boundaries, dependency risk, and unsafe network/file access. Separate confirmed issues from hypotheses and include concrete mitigations."
            case .qaReview:
                return "Design and run the smallest meaningful QA pass: identify critical flows, execute available tests or browser checks, capture repro steps for failures, and report pass/fail evidence."
            case .planMode:
                return "Clarify the goal from existing context, split the work into small verifiable steps, call out risks and dependencies, then recommend the next implementation step without overbuilding."
            case .productPrioritization:
                return "Rank candidate product work by user impact, confidence, effort, and dependency risk. Prefer concrete next shippable increments over broad feature catalogs."
            case .decisionCapture:
                return "Extract durable decisions, assumptions, owners, open questions, and follow-ups from the brief or repo context. Keep it terse enough to paste into a project note."
            }
        }

        var skillRoutingHint: String {
            switch self {
            case .repoSetup:
                return "Use the IronClaw project-setup, developer-setup, or new-project skill behavior when available."
            case .patchAndTest:
                return "Use the IronClaw coding and local-test skill behavior when available."
            case .researchToCode:
                return "Use the IronClaw coding, github-workflow, and web research behavior when available."
            case .githubTriage:
                return "Use the IronClaw github, github-workflow, delegation, and review skill behavior when available."
            case .codeReview:
                return "Use the IronClaw code-review and review-readiness skill behavior when available."
            case .securityReview:
                return "Use the IronClaw security-review skill behavior when available."
            case .qaReview:
                return "Use the IronClaw qa-review, web-ui-test, and local-test skill behavior when available."
            case .planMode:
                return "Use the IronClaw plan-mode skill behavior when available."
            case .productPrioritization:
                return "Use the IronClaw product-prioritization skill behavior when available."
            case .decisionCapture:
                return "Use the IronClaw decision-capture, commitment, idea-parking, and tech-debt-tracker skill behavior when available."
            }
        }
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

    private var currentPlanAllowedModelIDs: Set<String>? {
        guard let billingSnapshot else { return nil }
        let planName = currentBillingPlanName.lowercased()
        let plan = billingSnapshot.plans.first { $0.name.lowercased() == planName } ??
            billingSnapshot.plans.first { $0.name.lowercased() == "free" }
        guard let allowedModels = plan?.allowedModels, !allowedModels.isEmpty else {
            return nil
        }
        return Set(allowedModels.map { $0.lowercased() })
    }

    private func isAllowedByCurrentPlan(_ model: ModelOption) -> Bool {
        if model.isExternalModel {
            return true
        }
        guard let allowedIDs = currentPlanAllowedModelIDs else {
            return true
        }
        return allowedIDs.contains(model.id.lowercased())
    }

    private func routeCurrentPromptIfNeeded(_ text: String, attachments: [ChatAttachment]) {
        if selectedModel != ModelOption.ironclawModelID,
           selectedModel != ModelOption.ironclawMobileModelID,
           Self.promptNeedsRemoteWorkstation(text),
           ironclawRemoteWorkstationAvailable {
            selectedModel = ModelOption.ironclawModelID
            clearAttestationState()
            showBanner("Switched to IronClaw because this prompt needs hosted agent tools.")
            return
        }

        if routeCouncilIfNeeded(text) {
            return
        }

        guard selectedModelOption?.isNearCloudModel == true,
              Self.promptNeedsLiveWeb(text),
              !shouldUseAppWebGrounding(model: selectedModel, prompt: text),
              let privateModel = preferredAvailableModel() else {
            return
        }
        selectedModel = privateModel
        clearAttestationState()
        showBanner("Switched to \(modelDisplayName(for: privateModel)) because this prompt needs NEAR Private web search.")
    }

    private func routeCouncilIfNeeded(_ text: String) -> Bool {
        guard Self.promptRequestsCouncil(text),
              selectedModel != ModelOption.ironclawModelID,
              selectedModel != ModelOption.ironclawMobileModelID else {
            return false
        }
        if isCouncilModeEnabled {
            return true
        }
        let ids = defaultCouncilModelIDs()
        guard ids.count > 1 else {
            return false
        }
        selectedModel = ids[0]
        councilModelIDs = ids
        clearAttestationState()
        showBanner("LLM Council selected for a multi-model answer.")
        return true
    }

    private func ensureSelectedModelIsAvailable(shouldShowBanner: Bool) {
        guard !models.isEmpty else {
            return
        }
        guard !pickerModels.contains(where: { $0.id == selectedModel }) else {
            normalizeCouncilSelection()
            return
        }
        guard let replacement = preferredAvailableModel() ?? pickerModels.first?.id else {
            return
        }
        let previousModel = selectedModel
        selectedModel = replacement
        routeReadinessIssue = nil
        clearAttestationState()
        normalizeCouncilSelection()
        if shouldShowBanner {
            showBanner("\(modelDisplayName(for: previousModel)) is not available on the \(currentBillingPlanName) plan. Switched to \(modelDisplayName(for: replacement)).")
        }
    }

    private func isCouncilEligible(_ model: ModelOption) -> Bool {
        !model.isIronclawModel &&
            !model.isUtilityModel &&
            !model.isDeprecatedPickerModel &&
            isAllowedByCurrentPlan(model)
    }

    private func normalizedCouncilModels(from ids: [String]) -> [ModelOption] {
        let normalizedIDs = normalizedCouncilModelIDs(ids)
        return normalizedIDs.compactMap { modelID in
            chatModels.first(where: { $0.id == modelID && isCouncilEligible($0) })
        }
    }

    private func normalizedCouncilModelIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        let eligibleIDs = Set(chatModels.filter(isCouncilEligible).map(\.id))
        for modelID in ids where !seen.contains(modelID) {
            if eligibleIDs.isEmpty || eligibleIDs.contains(modelID) {
                normalized.append(modelID)
                seen.insert(modelID)
            }
            if normalized.count == Self.maxCouncilModels {
                break
            }
        }
        return normalized
    }

    private func normalizeCouncilSelection() {
        let normalized = normalizedCouncilModelIDs(councilModelIDs)
        if normalized.isEmpty, canUseInCouncil(selectedModel) {
            councilModelIDs = [selectedModel]
        } else if normalized != councilModelIDs {
            councilModelIDs = normalized
        }
    }

    private func defaultCouncilModelIDs() -> [String] {
        let eligibleIDs = Set(chatModels.filter(isCouncilEligible).map(\.id))
        guard !eligibleIDs.isEmpty else {
            return []
        }
        var ids: [String] = []
        for group in defaultCouncilCandidateGroups {
            if let modelID = group.first(where: { eligibleIDs.contains($0) }),
               !ids.contains(modelID) {
                ids.append(modelID)
            }
        }
        if ids.count < 2 {
            let ranked = rankedModels(from: chatModels.filter(isCouncilEligible)).map(\.id)
            for modelID in ranked where !ids.contains(modelID) {
                ids.append(modelID)
                if ids.count == Self.maxCouncilModels {
                    break
                }
            }
        }
        return Array(ids.prefix(Self.maxCouncilModels))
    }

    private func councilPreset(
        id: String,
        title: String,
        subtitle: String,
        symbolName: String,
        candidateGroups: [[String]],
        candidateModels: [ModelOption],
        fallbackModels: [ModelOption]
    ) -> CouncilPresetOption {
        var ids: [String] = []
        let eligibleModels = candidateModels.filter(isCouncilEligible)

        for group in candidateGroups {
            if let model = eligibleModels.first(where: { model in
                group.contains { Self.model(model, matchesCandidateID: $0) }
            }),
               !ids.contains(model.id) {
                ids.append(model.id)
            }
            if ids.count == Self.maxCouncilModels {
                break
            }
        }

        if ids.count < 2 {
            for model in rankedModels(from: fallbackModels.filter(isCouncilEligible)) where !ids.contains(model.id) {
                ids.append(model.id)
                if ids.count == Self.maxCouncilModels {
                    break
                }
            }
        }

        return CouncilPresetOption(
            id: id,
            title: title,
            subtitle: subtitle,
            symbolName: symbolName,
            models: normalizedCouncilModels(from: ids)
        )
    }

    private static func model(_ model: ModelOption, matchesCandidateID candidateID: String) -> Bool {
        ModelCatalogStore.model(model, matchesCandidateID: candidateID)
    }

    private func requestCouncilModelIDs(for requestModel: String) -> [String] {
        guard requestModel == selectedModel, selectedModelOption?.isIronclawModel != true else {
            return []
        }
        var ids = normalizedCouncilModelIDs(councilModelIDs)
        if ids.isEmpty, canUseInCouncil(requestModel) {
            ids = [requestModel]
        }
        if ids.count > 1, !ids.contains(requestModel), canUseInCouncil(requestModel) {
            ids.insert(requestModel, at: 0)
        }
        return Array(ids.prefix(Self.maxCouncilModels))
    }

    private func preferredAvailableModel(excluding unavailableModels: Set<String>) -> String? {
        let availableModels = pickerModels.filter { !$0.isExternalModel }
        let availableIDs = Set(availableModels.map(\.id))
        let prioritizedIDs = preferredModelIDs + rankedModels(from: availableModels).map(\.id)

        return prioritizedIDs.first { modelID in
            availableIDs.contains(modelID) &&
                !unavailableModels.contains(modelID)
        } ?? rankedModels(from: availableModels).first(where: { !unavailableModels.contains($0.id) })?.id
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
        if modelID == ModelOption.nearCloudQwenMaxModelID {
            return "qwen/qwen3.7-max"
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
        modelCatalog.rankedModels(from: source)
    }

    private func updateCurrentExchange(to model: String, shouldClearText: Bool = true) {
        guard let currentAssistantMessageID,
              let assistantIndex = messages.firstIndex(where: { $0.id == currentAssistantMessageID }) else {
            return
        }

        messages[assistantIndex].model = model
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
                    summary: "Read the current iPhone workspace state.",
                    detail: snapshot.summary
                ))

            case IronclawMobileToolNames.runtimeCapabilities:
                results.append(IronclawMobileToolResult(
                    callName: call.name,
                    status: .completed,
                    summary: "Loaded the IronClaw Mobile capability manifest.",
                    detail: Self.ironclawMobileCapabilityDetail
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
                selectedProjectID = projects[index].id
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
                selectedProjectID = project.id
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
                    try await api.updateConversationTitle(conversationID, title: title)
                    setTitle(title, for: conversationID)
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
                    if pinned {
                        try await api.pinConversation(conversationID)
                    } else {
                        try await api.unpinConversation(conversationID)
                    }
                    setPinned(pinned, for: conversationID)
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
                    if archived {
                        try await api.archiveConversation(conversationID)
                    } else {
                        try await api.unarchiveConversation(conversationID)
                    }
                    setArchived(archived, for: conversationID)
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
        let projectAttachmentIDs = Set(selectedProjectAttachments.map(\.id))
        let promptOnlyFiles = promptAttachments
            .filter { !projectAttachmentIDs.contains($0.id) }
            .map(\.name)

        return IronclawMobileProjectContext(
            projectName: selectedProject?.name,
            projectInstructions: selectedProject?.instructions,
            projectMemory: selectedProject?.memorySummary,
            projectNotes: selectedProject?.notes.prefix(6).map { "\($0.title): \(Self.clipped($0.text, maxCharacters: 500))" } ?? [],
            projectLinks: selectedProject?.links
                .filter { URL(string: $0.urlString).map(URLSecurity.isPublicHTTPSURL) == true }
                .prefix(12)
                .map { "\($0.displayTitle): \($0.urlString)" } ?? [],
            projectFiles: selectedProjectAttachments.map(\.name),
            promptFiles: promptOnlyFiles
        )
    }

    private func promptOnlyAttachments(from attachments: [ChatAttachment]) -> [ChatAttachment] {
        let projectAttachmentIDs = Set(selectedProjectAttachments.map(\.id))
        return attachments.filter { !projectAttachmentIDs.contains($0.id) }
    }

    private func ensureMobileProject(named rawName: String, includeConversationID conversationID: String?) -> ChatProject {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = projectIndex(matching: name) {
            var didChange = false
            if projects[index].isArchived {
                projects[index].archivedAt = nil
                didChange = true
            }
            selectedProjectID = projects[index].id
            if let conversationID, !projects[index].conversationIDs.contains(conversationID) {
                projects[index].conversationIDs.append(conversationID)
                didChange = true
            }
            if didChange {
                saveProjects()
            }
            return projects[index]
        }

        let project = ChatProject(
            id: "project-\(UUID().uuidString)",
            name: name.isEmpty ? "Untitled Project" : name,
            createdAt: Date(),
            conversationIDs: conversationID.map { [$0] } ?? []
        )
        projects.insert(project, at: 0)
        selectedProjectID = project.id
        saveProjects()
        return project
    }

    private func projectIndex(matching rawName: String) -> Int? {
        let normalizedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedName.isEmpty else { return nil }
        if let exactIndex = projects.firstIndex(where: { $0.name.lowercased() == normalizedName }) {
            return exactIndex
        }
        return projects.firstIndex {
            let candidate = $0.name.lowercased()
            return candidate.contains(normalizedName) || normalizedName.contains(candidate)
        }
    }

    private func selectedProjectIndexForIronclaw(callName: String) -> (index: Int?, failure: IronclawMobileToolResult?) {
        guard let selectedProjectID,
              let index = projects.firstIndex(where: { $0.id == selectedProjectID }) else {
            return (nil, .init(
                callName: callName,
                status: .failed,
                summary: "Create or select a project first.",
                detail: nil
            ))
        }
        return (index, nil)
    }

    private func addProjectLinkFromIronclaw(_ call: IronclawMobileToolCall) -> IronclawMobileToolResult {
        let selection = selectedProjectIndexForIronclaw(callName: call.name)
        if let result = selection.failure {
            return result
        }
        guard let projectIndex = selection.index else {
            return .init(callName: call.name, status: .failed, summary: "Create or select a project first.", detail: nil)
        }
        guard projects[projectIndex].links.count < 24 else {
            return .init(
                callName: call.name,
                status: .failed,
                summary: "Project \"\(projects[projectIndex].name)\" already has the maximum source links.",
                detail: nil
            )
        }
        guard let rawURL = call.arguments["url"],
              let normalizedURL = Self.normalizedProjectLinkURL(rawURL) else {
            return .init(callName: call.name, status: .failed, summary: "Missing or non-public HTTPS link URL.", detail: nil)
        }
        if projects[projectIndex].links.contains(where: { $0.urlString == normalizedURL.absoluteString }) {
            return .init(
                callName: call.name,
                status: .skipped,
                summary: "That source link is already saved in \"\(projects[projectIndex].name)\".",
                detail: normalizedURL.absoluteString
            )
        }

        let title = call.arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let link = ProjectLink(title: title, urlString: normalizedURL.absoluteString)
        projects[projectIndex].links.insert(link, at: 0)
        saveProjects()
        return .init(
            callName: call.name,
            status: .completed,
            summary: "Added source link to project \"\(projects[projectIndex].name)\".",
            detail: "\(link.displayTitle): \(link.urlString)"
        )
    }

    private func setProjectInstructionsFromIronclaw(_ call: IronclawMobileToolCall) -> IronclawMobileToolResult {
        let selection = selectedProjectIndexForIronclaw(callName: call.name)
        if let result = selection.failure {
            return result
        }
        guard let projectIndex = selection.index else {
            return .init(callName: call.name, status: .failed, summary: "Create or select a project first.", detail: nil)
        }
        let instructions = call.arguments["instructions"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !instructions.isEmpty else {
            return .init(callName: call.name, status: .failed, summary: "Missing project instructions.", detail: nil)
        }
        projects[projectIndex].instructions = String(instructions.prefix(4_000))
        saveProjects()
        return .init(
            callName: call.name,
            status: .completed,
            summary: "Updated instructions for project \"\(projects[projectIndex].name)\".",
            detail: projects[projectIndex].instructions
        )
    }

    private func updateProjectMemoryFromIronclaw(_ call: IronclawMobileToolCall) -> IronclawMobileToolResult {
        let selection = selectedProjectIndexForIronclaw(callName: call.name)
        if let result = selection.failure {
            return result
        }
        guard let projectIndex = selection.index else {
            return .init(callName: call.name, status: .failed, summary: "Create or select a project first.", detail: nil)
        }
        let memory = call.arguments["memory"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !memory.isEmpty else {
            return .init(callName: call.name, status: .failed, summary: "Missing project memory.", detail: nil)
        }
        let shouldAppend = call.arguments["append"] != "false"
        let existing = projects[projectIndex].memorySummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedMemory: String
        if shouldAppend, !existing.isEmpty, !existing.localizedCaseInsensitiveContains(memory) {
            updatedMemory = "\(existing)\n- \(memory)"
        } else {
            updatedMemory = memory
        }
        projects[projectIndex].memorySummary = String(updatedMemory.prefix(4_000))
        saveProjects()
        return .init(
            callName: call.name,
            status: .completed,
            summary: "Updated memory for project \"\(projects[projectIndex].name)\".",
            detail: projects[projectIndex].memorySummary
        )
    }

    private func saveProjectNoteFromIronclaw(_ call: IronclawMobileToolCall) -> IronclawMobileToolResult {
        let selection = selectedProjectIndexForIronclaw(callName: call.name)
        if let result = selection.failure {
            return result
        }
        guard let projectIndex = selection.index else {
            return .init(callName: call.name, status: .failed, summary: "Create or select a project first.", detail: nil)
        }
        let text = call.arguments["text"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            return .init(callName: call.name, status: .failed, summary: "Missing note text.", detail: nil)
        }
        let title = call.arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = ProjectNote(
            title: title?.isEmpty == false ? title! : Self.noteTitle(from: text),
            text: Self.clipped(text, maxCharacters: 12_000),
            sourceMessageID: nil
        )
        projects[projectIndex].notes.insert(note, at: 0)
        if projects[projectIndex].notes.count > 20 {
            projects[projectIndex].notes = Array(projects[projectIndex].notes.prefix(20))
        }
        saveProjects()
        return .init(
            callName: call.name,
            status: .completed,
            summary: "Saved a note to project \"\(projects[projectIndex].name)\".",
            detail: note.title
        )
    }

    private func addPromptFilesToSelectedProject(_ promptAttachments: [ChatAttachment]) -> IronclawMobileToolResult {
        guard let selectedProjectID,
              let projectIndex = projects.firstIndex(where: { $0.id == selectedProjectID }) else {
            return .init(
                callName: IronclawMobileToolNames.projectAddPromptFiles,
                status: .failed,
                summary: "Select or create a project before adding prompt files.",
                detail: nil
            )
        }

        guard !promptAttachments.isEmpty else {
            return .init(
                callName: IronclawMobileToolNames.projectAddPromptFiles,
                status: .skipped,
                summary: "No prompt-only files were attached.",
                detail: nil
            )
        }

        var existingIDs = Set(projects[projectIndex].attachments.map(\.id))
        let filesToAdd = promptAttachments.filter { existingIDs.insert($0.id).inserted }
        guard !filesToAdd.isEmpty else {
            return .init(
                callName: IronclawMobileToolNames.projectAddPromptFiles,
                status: .skipped,
                summary: "Those files are already in the project.",
                detail: nil
            )
        }

        let remainingSlots = max(0, 12 - projects[projectIndex].attachments.count)
        let acceptedFiles = Array(filesToAdd.prefix(remainingSlots))
        guard !acceptedFiles.isEmpty else {
            return .init(
                callName: IronclawMobileToolNames.projectAddPromptFiles,
                status: .failed,
                summary: "Project context already has the maximum twelve files.",
                detail: nil
            )
        }

        projects[projectIndex].attachments.append(contentsOf: acceptedFiles)
        saveProjects()
        return .init(
            callName: IronclawMobileToolNames.projectAddPromptFiles,
            status: .completed,
            summary: "Added \(acceptedFiles.count) attached file\(acceptedFiles.count == 1 ? "" : "s") to project \"\(projects[projectIndex].name)\".",
            detail: acceptedFiles.map(\.name).joined(separator: ", ")
        )
    }

    private func activeAttachments(promptAttachments: [ChatAttachment]) -> [ChatAttachment] {
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

    private func setPinned(_ pinned: Bool, for conversationID: String) {
        let timestamp = pinned ? ISO8601DateFormatter().string(from: Date()) : nil
        if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            if conversations[index].metadata == nil {
                conversations[index].metadata = ConversationMetadata()
            }
            conversations[index].metadata?.pinnedAt = timestamp
            if selectedConversation?.id == conversationID {
                selectedConversation = conversations[index]
            }
        } else if selectedConversation?.id == conversationID {
            if selectedConversation?.metadata == nil {
                selectedConversation?.metadata = ConversationMetadata()
            }
            selectedConversation?.metadata?.pinnedAt = timestamp
        }
    }

    private func setArchived(_ archived: Bool, for conversationID: String) {
        let timestamp = archived ? ISO8601DateFormatter().string(from: Date()) : nil
        if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            if conversations[index].metadata == nil {
                conversations[index].metadata = ConversationMetadata()
            }
            conversations[index].metadata?.archivedAt = timestamp
            if selectedConversation?.id == conversationID {
                selectedConversation = conversations[index]
            }
        } else if selectedConversation?.id == conversationID {
            if selectedConversation?.metadata == nil {
                selectedConversation?.metadata = ConversationMetadata()
            }
            selectedConversation?.metadata?.archivedAt = timestamp
        }
    }

    private func setTitle(_ title: String, for conversationID: String) {
        if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            if conversations[index].metadata == nil {
                conversations[index].metadata = ConversationMetadata()
            }
            conversations[index].metadata?.title = title
            if selectedConversation?.id == conversationID {
                selectedConversation = conversations[index]
            }
        } else if selectedConversation?.id == conversationID {
            if selectedConversation?.metadata == nil {
                selectedConversation?.metadata = ConversationMetadata()
            }
            selectedConversation?.metadata?.title = title
        }
    }

    private static func makeNonce() -> String {
        (0..<32)
            .map { _ in String(format: "%02x", UInt8.random(in: UInt8.min ... UInt8.max)) }
            .joined()
    }

    nonisolated static func conversationID(from value: String) -> String? {
        guard !value.isEmpty else { return nil }
        if isSafeRawConversationID(value) {
            return value
        }

        let normalized = value.hasPrefix("http") ? value : "https://\(value)"
        guard let url = URL(string: normalized),
              isAllowedSharedConversationURL(url) else { return nil }
        let pathParts = url.pathComponents.filter { $0 != "/" }
        guard pathParts.allSatisfy({ $0 == "c" || isSafeRawConversationID($0) }) else {
            return nil
        }

        if let index = pathParts.firstIndex(of: "c"),
           pathParts.count == index + 2,
           isSafeRawConversationID(pathParts[index + 1]) {
            return pathParts[index + 1]
        }

        if let last = pathParts.last, isSafeRawConversationID(last) {
            return last
        }

        return nil
    }

    nonisolated private static func isAllowedSharedConversationURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host()?.lowercased() else {
            return false
        }
        return ["private.near.ai"].contains(host)
    }

    nonisolated private static func isSafeRawConversationID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == value,
              trimmed.count >= 6,
              !trimmed.contains("/"),
              !trimmed.contains(":"),
              !trimmed.contains(".") else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func shareInviteRecipients(from value: String) -> [ShareInviteRecipient] {
        var seen = Set<String>()
        return value
            .split { character in
                character == "," || character == ";" || character == "\n" || character == "\t"
            }
            .compactMap { rawValue -> ShareInviteRecipient? in
                let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let normalized = trimmed.lowercased()
                guard seen.insert(normalized).inserted else { return nil }
                if isValidEmailAddress(trimmed) {
                    return ShareInviteRecipient(kind: "email", value: normalized)
                }
                if isValidNEARAccountID(trimmed) {
                    return ShareInviteRecipient(kind: "near_account", value: normalized)
                }
                return nil
            }
    }

    private static func validSharePermission(_ permission: String) -> String? {
        let normalized = permission.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["read", "write"].contains(normalized) ? normalized : nil
    }

    private static func normalizedOrganizationEmailPattern(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let domain = trimmed.hasPrefix("*@") ? String(trimmed.dropFirst(2)) : trimmed
        guard isValidEmailDomain(domain) else { return nil }
        return "*@\(domain)"
    }

    private static func isValidEmailAddress(_ value: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,63}$"#
        return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isValidEmailDomain(_ value: String) -> Bool {
        guard value.count <= 253, value.contains(".") else { return false }
        let pattern = #"^[A-Z0-9](?:[A-Z0-9\-]{0,61}[A-Z0-9])?(?:\.[A-Z0-9](?:[A-Z0-9\-]{0,61}[A-Z0-9])?)+$"#
        return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isValidNEARAccountID(_ value: String) -> Bool {
        let normalized = value.lowercased()
        guard normalized == value.lowercased(),
              normalized.count >= 2,
              normalized.count <= 64,
              !normalized.contains("@"),
              !normalized.hasPrefix("."),
              !normalized.hasSuffix(".") else {
            return false
        }
        let pattern = #"^[a-z0-9]+(?:[._\-][a-z0-9]+)*$"#
        return normalized.range(of: pattern, options: .regularExpression) != nil
    }

    private static func localFailureMessage(from text: String) -> String? {
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
        let now = Date()
        return messages.map { message in
            guard message.role == .assistant else { return message }
            var copy = message
            if copy.model == ModelOption.ironclawModelID, isTransportOnlyGatewayText(copy.text) {
                copy.text = gatewayStatusFailureMessage
                copy.status = "failed"
                copy.isStreaming = false
                return copy
            }
            if copy.model == ModelOption.ironclawModelID, let failureMessage = localFailureMessage(from: copy.text) {
                copy.text = failureMessage
                copy.status = "failed"
                copy.isStreaming = false
                return copy
            }

            let status = copy.status.lowercased()
            let isActiveStatus = ["streaming", "reasoning", "searching", "thinking", "running", "queued", "in_progress"].contains(status)
            let isOld = now.timeIntervalSince(copy.createdAt) > staleRunningMessageInterval
            if copy.isStreaming || (isActiveStatus && (assumingStreamLost || isOld)) {
                copy.text = copy.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? staleRunFailureMessage
                    : copy.text
                copy.status = "failed"
                copy.isStreaming = false
            }
            return copy
        }
    }

    private static var gatewayStatusFailureMessage: String {
        "IronClaw accepted the request, but the bridge only returned gateway status instead of a final answer. Start or repair the IronClaw bridge, then retry."
    }

    private static var staleRunFailureMessage: String {
        "This run was interrupted or timed out before visible output arrived. Retry the message with a reachable model or IronClaw bridge."
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

    private static func displayFailureMessage(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        if lowercased == "access denied" || lowercased.contains("\"access denied\"") {
            return "Access denied by the NEAR Private API. Sign in again or choose another available model."
        }

        if lowercased.contains("402") ||
            lowercased.contains("payment required") ||
            (lowercased.contains("billing") && lowercased.contains("required")) ||
            lowercased.contains("insufficient credits") ||
            lowercased.contains("budget exceeded") {
            return "Payment or credits required. Open Account, refresh Billing, then retry with an active plan or budget."
        }

        if lowercased.contains("chat route needs a valid ironclaw token") {
            return "IronClaw is reachable, but the endpoint token is missing or invalid. Open Account and test the IronClaw integration."
        }

        if lowercased.contains("tool 'http' failed") &&
            lowercased.contains("request returned redirect") &&
            lowercased.contains("blocked to prevent ssrf") {
            return "IronClaw's web fetch tool hit a redirect and blocked it as an SSRF precaution. Upgrade or restart the hosted bridge on IronClaw 0.28.2 or newer, then retry."
        }

        if lowercased.contains("tool error") || lowercased.contains("tool '") || lowercased.contains("tool \"") {
            return "IronClaw tool failed before producing an answer: \(trimmed)"
        }

        if lowercased.contains("not available in your plan") {
            return "\(trimmed) Choose an allowed plan model from the picker or refresh Billing in Account."
        }

        if lowercased.contains("not authenticated") || lowercased.contains("unauthorized") {
            return "Authentication failed. Sign in again, then retry the request."
        }

        return trimmed.isEmpty ? "The request failed." : trimmed
    }

    private static func isRawToolFailureText(_ text: String) -> Bool {
        let lowercased = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowercased.isEmpty else { return false }
        return lowercased.contains("tool error") ||
            lowercased.contains("tool '") ||
            lowercased.contains("tool \"")
    }

    private static func normalizedIronclawPrompt(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        let prefixes = [
            "use ironclaw to ",
            "ask ironclaw to ",
            "have ironclaw ",
            "run ironclaw to "
        ]

        for prefix in prefixes where lowercased.hasPrefix(prefix) {
            let start = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
            let normalized = trimmed[start...].trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? text : normalized
        }

        return text
    }

    private static func normalizedDraftInput(_ text: String) -> String {
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

    private func activeSystemPrompt(memoryForModel model: String? = nil) -> String {
        let userPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let modePrompt = sourceModeInstructions().trimmingCharacters(in: .whitespacesAndNewlines)
        // Personal memory is injected ONLY for the private near.ai route — never
        // cloud, council cloud legs, or hosted/IronClaw routes — so on-device
        // facts never leave for a third-party cloud.
        let memoryAllowed = model.map { RoutePlanner.routeKind(forModelID: $0) == .nearPrivate } ?? false
        let memoryPrompt = memoryAllowed
            ? (memoryStore.contextBlock()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            : ""
        let requestedPrompt = researchModeEnabled ? Self.researchModeInstructions(appendingTo: userPrompt) : userPrompt
        let basePrompt = [memoryPrompt, requestedPrompt, modePrompt]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard let project = selectedProject else {
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
        let projectNotes = project.notes
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

    private func sourceModeInstructions() -> String {
        let semantics = sourceRoutingSemantics
        if semantics.isResearch {
            return """
            Focus: Research.
            - Use web search for current information and combine it with active project files, saved links, and prompt attachments.
            - Prefer primary sources and include dates when recency matters.
            """
        }

        switch semantics.focus {
        case .auto:
            return webSearchEnabled
                ? """
                Focus: Auto.
                - Use web search when the user asks for current information.
                - Use project files, saved links, and prompt attachments when they are relevant.
                """
                : """
                Focus: Auto.
                - Prefer project files, saved links, and prompt attachments.
                - Avoid web search unless the user explicitly asks for current information.
                """
        case .web:
            return """
            Focus: Web.
            - Use web search for current or source-backed answers.
            - Include active project files, saved links, notes, and prompt attachments when they are relevant to the question.
            """
        case .links:
            return """
            Focus: Links.
            - Treat the project Source links as the primary retrieval targets.
            - Avoid broad web search unless the user explicitly asks, or a saved link needs resolution.
            - If only link titles or URLs are available, say that before inferring.
            """
        case .files:
            return """
            Focus: Files.
            - Answer from project files and prompt attachments.
            - Do not use web search unless the user explicitly asks for current information.
            """
        case .project:
            return """
            Focus: Project.
            - Combine web search, saved project links, project files, and prompt attachments.
            - Call out conflicts between sources instead of smoothing them over.
            """
        case .research:
            return ""
        }
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
        guard text.count > maxCharacters else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: maxCharacters)
        return "\(text[..<endIndex])..."
    }

    private static func normalizedProjectLinkURL(_ rawURL: String) -> URL? {
        URLSecurity.normalizedPublicHTTPSURL(from: rawURL)
    }

    private func nearCloudPrompt(
        for text: String,
        attachments: [ChatAttachment],
        webContext: WebGroundingContext?
    ) -> String {
        let currentPrompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let recentTranscript = messages
            .dropLast()
            .suffix(8)
            .map { message in
                let speaker = message.role == .user ? "User" : "Assistant"
                return "\(speaker): \(message.text.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        let attachmentNote: String
        if attachments.isEmpty {
            attachmentNote = ""
        } else {
            let names = attachments.map(\.name).joined(separator: ", ")
            attachmentNote = "\n\nAttachment context: The user attached \(names). Use any extracted text or project context supplied by the app; if only filenames are present, say that clearly before making file-specific claims."
        }
        let webNote: String
        if let webContext {
            webNote = """

            Live web context supplied by the iOS app:
            \(webContext.promptSection)

            Use this search context for current facts. Do not say you cannot browse; the app has already fetched the web context.
            """
        } else {
            webNote = ""
        }

        if recentTranscript.isEmpty {
            return "\(currentPrompt)\(attachmentNote)\(webNote)"
        }

        return """
        Recent conversation:
        \(recentTranscript)

        Current request:
        \(currentPrompt)
        \(attachmentNote)\(webNote)
        """
    }

    private func nearCloudSystemPrompt(modelDisplayName: String, hasWebContext: Bool) -> String {
        let userPrompt = activeSystemPrompt()
        let base: String
        if hasWebContext {
            base = """
            You are \(modelDisplayName) running through NEAR AI Cloud inside an iOS chat app.
            Do not emit tool-call markup, XML tool tags, JSON tool calls, or fake function calls.
            The iOS app has already performed web search and included live web context in the user message. Use that context directly, cite source titles or domains, and never claim that you cannot browse.
            Use any project instructions, saved links, notes, attachment summaries, or extracted text included by the app.
            Format answers cleanly with concise headings and bullets when useful.
            """
        } else {
            base = """
            You are \(modelDisplayName) running through NEAR AI Cloud inside an iOS chat app.
            Do not emit tool-call markup, XML tool tags, JSON tool calls, or fake function calls.
            Use any project instructions, saved links, notes, attachment summaries, or extracted text included by the app. If no live web context was supplied and current facts are essential, say what context is missing and answer from what is available.
            Format answers cleanly with concise headings and bullets when useful.
            """
        }
        guard !userPrompt.isEmpty else { return base }
        return """
        \(base)

        User system preferences:
        \(userPrompt)
        """
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

    private static func ironclawToolResultMarkdown(_ results: [IronclawMobileToolResult]) -> String {
        guard !results.isEmpty else { return "" }
        let blocks = results.map { result in
            var lines = [result.markdownLine]
            if let detail = result.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
               !detail.isEmpty {
                let maxCharacters = result.callName == IronclawMobileToolNames.runtimeCapabilities ? 1_200 : 900
                let clippedDetail = Self.clipped(detail, maxCharacters: maxCharacters)
                let visibleLines = clippedDetail
                    .split(whereSeparator: \.isNewline)
                    .prefix(12)
                    .map { "  \($0)" }
                    .joined(separator: "\n")
                if !visibleLines.isEmpty {
                    lines.append(visibleLines)
                }
            }
            return lines.joined(separator: "\n")
        }
        return "**IronClaw Mobile actions**\n\(blocks.joined(separator: "\n"))\n\n"
    }

    private static var ironclawMobileCapabilityDetail: String {
        """
        Available on iPhone:
        - NEAR Private inference with model fallback.
        - NEAR Private web search when enabled.
        - Prompt files and reusable project file context.
        - Local project creation and selection.
        - Source link capture, project instructions, project memory, and project notes.
        - File promotion into reusable project context.
        - Chat move, rename, pin, and archive actions.
        - Web-search, source-mode, and research-mode switching.

        Hosted workstation handoff:
        - When the hosted IronClaw endpoint is connected, Mobile can hand off git, code editing, tests, shell, package installation, and repo work to that remote workstation and keep the answer in this chat.
        - The hosted workstation is expected to provide sandboxed shell, git, file read/write, grep, and patch tools; Account diagnostics can verify those tools before a serious run.

        Not available locally inside the iOS sandbox:
        - Shell commands, Docker, Postgres, arbitrary host filesystem access, local LAN gateways, desktop daemons, and unsandboxed MCP/WASM tool execution.
        """
    }

    private static func fileBackedData(
        filename: String,
        legacyDefaultsKey: String,
        accountID: String = "signed-out"
    ) -> Data? {
        let url = fileBackedStoreURL(filename: filename, accountID: accountID)
        if let data = try? Data(contentsOf: url) {
            return data
        }
        guard accountID == signedOutStorageAccountID else {
            return nil
        }
        guard let legacyData = UserDefaults.standard.data(forKey: legacyDefaultsKey) else {
            return nil
        }
        return writeFileBackedData(legacyData, filename: filename, legacyDefaultsKey: legacyDefaultsKey, accountID: accountID) ? legacyData : nil
    }

    @discardableResult
    private static func writeFileBackedData(
        _ data: Data,
        filename: String,
        legacyDefaultsKey: String,
        accountID: String = "signed-out"
    ) -> Bool {
        var url = fileBackedStoreURL(filename: filename, accountID: accountID)
        var directoryURL = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            var directoryValues = URLResourceValues()
            directoryValues.isExcludedFromBackup = true
            try? directoryURL.setResourceValues(directoryValues)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            var fileValues = URLResourceValues()
            fileValues.isExcludedFromBackup = true
            try? url.setResourceValues(fileValues)
            #if os(iOS)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
            #endif
            if accountID == signedOutStorageAccountID {
                UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
            }
            return true
        } catch {
            #if DEBUG
            assertionFailure("Secure file-backed cache write failed for \(filename): \(error.localizedDescription)")
            #endif
            return false
        }
    }

    private static func fileBackedStoreURL(filename: String, accountID: String = "signed-out") -> URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            FileManager.default.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("NEARPrivateChat", isDirectory: true)
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent(normalizedStorageScope(accountID), isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }

    private static func cacheConversations(_ conversations: [ConversationSummary]) {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        writeFileBackedData(data, filename: conversationsCacheFilename, legacyDefaultsKey: conversationsCacheKey)
    }

    private static func loadCachedConversations() -> [ConversationSummary] {
        guard let data = fileBackedData(filename: conversationsCacheFilename, legacyDefaultsKey: conversationsCacheKey),
              let conversations = try? JSONDecoder().decode([ConversationSummary].self, from: data) else {
            return []
        }
        return conversations
    }

    private static func loadProjects() -> [ChatProject] {
        guard let data = fileBackedData(filename: projectsCacheFilename, legacyDefaultsKey: projectsDefaultsKey),
              let projects = try? JSONDecoder().decode([ChatProject].self, from: data) else {
            return []
        }
        return projects.sorted { $0.createdAt > $1.createdAt }
    }

    private static func chatMessages(from items: [ConversationItem], preferredResponseID: String? = nil) -> [ChatMessage] {
        let sourcesByResponseID = Dictionary(
            grouping: items.filter { $0.type == "web_search_call" },
            by: \.responseID
        ).mapValues { searchItems in
            uniqueSources(searchItems.flatMap { $0.action?.sources ?? [] })
        }
        let queryByResponseID = Dictionary(
            grouping: items.filter { $0.type == "web_search_call" },
            by: \.responseID
        ).mapValues { searchItems in
            searchItems.compactMap { $0.action?.query }.first
        }

        let messageItems = items
            .filter { $0.type == "message" && ($0.role == .user || $0.role == .assistant) }
            .sorted { ($0.createdAt ?? 0) < ($1.createdAt ?? 0) }

        let branchVariants = branchVariantMetadata(from: messageItems)
        let visibleItems = activeConversationPathItems(from: messageItems, preferredResponseID: preferredResponseID)
        let messages = visibleItems
            .map { item in
                ChatMessage(
                    id: item.id,
                    role: item.role ?? .assistant,
                    text: item.displayText,
                    model: item.model,
                    createdAt: Date(timeIntervalSince1970: item.createdAt ?? Date().timeIntervalSince1970),
                    status: item.status ?? "completed",
                    responseID: item.responseID,
                    previousResponseID: item.previousResponseID,
                    isStreaming: false,
                    searchQuery: item.role == .assistant ? queryByResponseID[item.responseID] ?? nil : nil,
                    sources: item.role == .assistant ? sourcesByResponseID[item.responseID] ?? [] : [],
                    attachments: item.role == .user ? attachments(from: item.content ?? []) : [],
                    branchVariant: item.role == .assistant ? branchVariants[item.responseID] : nil,
                    metadata: item.metadata
                )
            }
        return normalizedMessages(messages, assumingStreamLost: false)
    }

    private static func activeConversationPathItems(from items: [ConversationItem], preferredResponseID: String? = nil) -> [ConversationItem] {
        guard items.contains(where: { $0.previousResponseID?.isEmpty == false }) else {
            return items
        }

        let responseIDs = Set(items.map(\.responseID))
        let groupedByResponseID = Dictionary(grouping: items, by: \.responseID)
        let responseCreatedAt = groupedByResponseID.mapValues { groupedItems in
            groupedItems.compactMap(\.createdAt).min() ?? 0
        }
        let parentByResponseID = groupedByResponseID.mapValues { groupedItems in
            groupedItems.compactMap(\.previousResponseID).first
        }

        let rootIDs = responseIDs.filter { responseID in
            guard let parent = parentByResponseID[responseID] ?? nil,
                  !parent.isEmpty else {
                return true
            }
            return !responseIDs.contains(parent)
        }

        var childrenByParent: [String: [String]] = [:]
        for responseID in responseIDs {
            guard let parent = parentByResponseID[responseID] ?? nil,
                  !parent.isEmpty else {
                continue
            }
            childrenByParent[parent, default: []].append(responseID)
        }

        let currentID: String
        var activeIDs: [String]
        if let preferredResponseID, responseIDs.contains(preferredResponseID) {
            var ancestry: [String] = [preferredResponseID]
            var cursor = preferredResponseID
            var seen = Set([preferredResponseID])
            while let parent = parentByResponseID[cursor] ?? nil,
                  !parent.isEmpty,
                  responseIDs.contains(parent),
                  !seen.contains(parent) {
                ancestry.append(parent)
                seen.insert(parent)
                cursor = parent
            }
            currentID = preferredResponseID
            activeIDs = Array(ancestry.reversed().dropLast())
        } else {
            guard let rootID = sortedResponseIDs(rootIDs, createdAt: responseCreatedAt).last else {
                return items
            }
            currentID = rootID
            activeIDs = []
        }

        var cursorID = currentID
        var seen = Set<String>()
        while !seen.contains(cursorID) {
            seen.insert(cursorID)
            activeIDs.append(cursorID)
            guard let children = childrenByParent[cursorID], !children.isEmpty else {
                break
            }
            cursorID = sortedResponseIDs(children, createdAt: responseCreatedAt).last ?? children[0]
        }

        let activeIDSet = Set(activeIDs)
        let activeItems = items.filter { activeIDSet.contains($0.responseID) }
        return activeItems.isEmpty ? items : activeItems
    }

    private static func branchVariantMetadata(from items: [ConversationItem]) -> [String: MessageBranchVariant] {
        let responseIDs = Set(items.map(\.responseID).filter { !$0.isEmpty })
        guard responseIDs.count > 1 else { return [:] }

        let groupedByResponseID = Dictionary(grouping: items, by: \.responseID)
        let responseCreatedAt = groupedByResponseID.mapValues { groupedItems in
            groupedItems.compactMap(\.createdAt).min() ?? 0
        }
        let parentByResponseID = groupedByResponseID.mapValues { groupedItems in
            groupedItems.compactMap(\.previousResponseID).first
        }
        let rootParentKey = "__near_private_chat_root__"
        var childrenByParent: [String: [String]] = [:]

        for responseID in responseIDs {
            let parent = parentByResponseID[responseID] ?? nil
            let parentKey = parent?.isEmpty == false ? parent! : rootParentKey
            childrenByParent[parentKey, default: []].append(responseID)
        }

        var variants: [String: MessageBranchVariant] = [:]
        for (parentKey, siblings) in childrenByParent where siblings.count > 1 {
            let sortedSiblings = sortedResponseIDs(siblings, createdAt: responseCreatedAt)
            for responseID in sortedSiblings {
                variants[responseID] = MessageBranchVariant(
                    responseIDs: sortedSiblings,
                    currentResponseID: responseID,
                    parentResponseID: parentKey == rootParentKey ? nil : parentKey
                )
            }
        }
        return variants
    }

    private static func sortedResponseIDs(_ responseIDs: some Collection<String>, createdAt: [String: TimeInterval]) -> [String] {
        responseIDs.sorted { lhs, rhs in
            let lhsDate = createdAt[lhs] ?? 0
            let rhsDate = createdAt[rhs] ?? 0
            if lhsDate == rhsDate {
                return lhs < rhs
            }
            return lhsDate < rhsDate
        }
    }

    private static func uniqueSources(_ sources: [WebSearchSource]) -> [WebSearchSource] {
        var seen = Set<String>()
        return sources.filter { source in
            if seen.contains(source.url) {
                return false
            }
            seen.insert(source.url)
            return true
        }
    }

    private static func inferredSources(from text: String) -> [WebSearchSource] {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s\)\]\}<>"]+"#) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange)
        let sources = matches.compactMap { match -> WebSearchSource? in
            guard let range = Range(match.range, in: text) else { return nil }
            let rawURL = String(text[range])
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
            guard let url = WebSearchSource.sanitizedURLString(rawURL) else { return nil }
            return WebSearchSource(type: "inferred", url: url)
        }
        return Array(uniqueSources(sources).prefix(8))
    }

    private static func attachments(from content: [ContentPart]) -> [ChatAttachment] {
        content.compactMap { part in
            guard part.type == "input_file" || part.type == "input_audio" || part.type == "input_image" else {
                return nil
            }
            let id = part.fileID ?? part.audioFileID ?? part.imageURL ?? UUID().uuidString
            let suffix = id.suffix(8)
            return ChatAttachment(id: id, name: "file-\(suffix)", kind: part.type, bytes: nil)
        }
    }

    #if DEBUG
    func prepareDemoCapture(screen: DemoCaptureScreen = .home) {
        streamTask?.cancel()
        streamTask = nil
        loadMessagesTask?.cancel()
        loadMessagesTask = nil
        isLoading = false
        isStreaming = false
        isUploadingAttachment = false
        isLoadingAttestation = false
        isLoadingShareInfo = false
        isLoadingRemoteFiles = false
        isLoadingShareGroups = false
        bannerMessage = nil

        let data = Self.demoCaptureData(now: Date())
        models = data.models
        nearCloudModels = data.nearCloudModels
        projects = [data.project]
        conversations = data.conversations
        sharedWithMe = []
        remoteFiles = []
        shareGroups = data.shareGroups
        shareInfo = data.shareInfo
        attestationSnapshot = data.attestation
        attestationFetchErrorMessage = nil
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
        pendingAttachments = []
        pendingLargePasteTexts = [:]
        pendingDocumentTexts = [:]
        pendingDocumentTextIDs = []
        selectedProjectID = data.project.id
        selectedModel = Self.defaultModelID
        councilModelIDs = [Self.defaultModelID, ModelOption.nearCloudQwenMaxModelID, "near-cloud/anthropic/claude-opus-4-7"]
        webSearchEnabled = false
        sourceMode = .auto
        researchModeEnabled = false
        advancedModelParams = .defaults
        systemPrompt = ""

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
            selectedProjectID = nil
            pendingAttachments = []
            sourceMode = .web
            webSearchEnabled = true
            draft = "Is the war in Iran ending as of today?"
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
            selectedProjectID = nil
            sourceMode = .web
            webSearchEnabled = true
            draft = ""
        case .verification:
            selectedConversation = data.glmConversation
            messages = data.glmMessages
            selectedModel = Self.defaultModelID
            councilModelIDs = []
            selectedProjectID = nil
            draft = ""
        case .models:
            selectedConversation = data.glmConversation
            messages = data.glmMessages
            selectedModel = Self.defaultModelID
            councilModelIDs = []
            selectedProjectID = nil
            draft = ""
        case .widgets:
            selectedConversation = data.glmConversation
            messages = Self.demoWidgetMessages(now: Date())
            selectedModel = Self.defaultModelID
            councilModelIDs = []
            selectedProjectID = nil
            sourceMode = .web
            webSearchEnabled = true
            draft = ""
        case .generativeChat:
            // Drives the REAL prompt → QuickIntent → live-widget path: types a
            // prompt and sends it, so the chat answers with real public-API data
            // (no sign-in). Override the prompt with NEAR_DEMO_PROMPT to capture
            // eth/near/news/tracker flows from one screen.
            selectedConversation = data.primaryConversation
            selectedProjectID = nil
            messages = []
            draft = DemoCapture.demoPrompt ?? "what is the eth price"
            sendDraft()
        case .chatStarters:
            // Empty new chat with council off so the default live-data starter
            // chips show (ETH price / My NEAR / Today's news / Daily tracker).
            selectedConversation = nil
            selectedProjectID = nil
            messages = []
            councilModelIDs = [Self.defaultModelID]
            selectedModel = Self.defaultModelID
            draft = ""
        case .councilBriefingLive:
            // Runs a REAL scheduled council briefing against the backend using an
            // env-injected session token (DebugBackend). Verifies end-to-end that
            // "using council" trackers do real multi-model work on a schedule.
            selectedConversation = nil
            selectedProjectID = nil
            messages = []
            draft = ""
            if !didStartLiveCouncilDemo {
                didStartLiveCouncilDemo = true
                Task { @MainActor [weak self] in
                    await self?.runLiveCouncilBriefingDemo()
                }
            }
        case .chat, .councilOutput, .cloudModels, .council, .councilRoom, .threaded, .liveData, .project, .share:
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
        let widget = await runBriefing(briefing)
        updateMessage("live-council-pending") { message in
            message.isStreaming = false
            message.status = "completed"
            if let widget {
                message.widget = widget
                message.text = ""
            } else {
                message.text = "Council produced no result — check sign-in, models, or network."
            }
        }
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

    private static func demoShareInfo(for conversation: ConversationSummary) -> ConversationSharesListResponse {
        ConversationSharesListResponse(
            isOwner: true,
            canShare: true,
            canWrite: true,
            shares: [
                ConversationShareInfo(
                    id: "demo-public-share",
                    conversationID: conversation.id,
                    permission: "read",
                    shareType: "public",
                    recipient: nil,
                    groupID: nil,
                    orgEmailPattern: nil,
                    publicToken: "demo-iran-status",
                    createdAt: "2026-05-25T13:39:00Z",
                    updatedAt: "2026-05-25T13:40:00Z"
                )
            ],
            owner: ShareOwner(userID: "demo.capture.near", name: "Demo Account")
        )
    }

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
        let shareGroups: [ShareGroupInfo]
        let shareInfo: ConversationSharesListResponse
        let attestation: AttestationSnapshot
    }

    private static func demoCaptureData(now: Date) -> DemoCaptureData {
        let projectID = "demo-project-ironclaw-pr-plan"
        let conversationID = "demo-conversation-iran-council"
        let glmConversationID = "demo-conversation-glm-private"
        let councilBatchID = "demo-council-iran-status"
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
            The best answer is: not over, but closer to an off-ramp. GLM reads the AP/PBS overview as evidence that a deal is emerging [1][2]. Qwen Max focuses on whether the reported framework and Strait of Hormuz terms actually get implemented [3][4]. Opus keeps the caution high because fresh military activity and the Israel-Hezbollah front can still break the diplomatic track [5][6].

            ## What the council agrees on
            Nobody should say the war is already over. The supported statement is narrower: talks appear close to an agreement, but the outcome still depends on a signed/finalized deal, implementation of the Hormuz reopening, and containment of related military fronts [1][3][5][6].

            ## How the models vary
            - GLM 5.1: weighs the broad AP/PBS explainer coverage and calls this a possible endgame, not a settled peace [1][2].
            - Qwen Max: reads the deal-specific reporting as an implementation checklist: final text, Hormuz reopening, and follow-on negotiations [3][4].
            - Claude Opus: reads the security reporting as a warning that diplomacy is still exposed to military and regional shocks [5][6].

            ## Disagreements or uncertainty
            The disagreement is about confidence. GLM is the most optimistic because the overview reporting points to a possible deal. Qwen Max is conditional because a framework is not the same as implementation. Opus is the least willing to call it ending while strike reports and spillover risks remain live.
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
            ## Qwen Max
            The deal-specific reporting makes this an implementation question [1][2]. If the framework is finalized and the Strait of Hormuz reopening actually starts, then "ending" becomes plausible. If those milestones slip, the headline is only diplomatic momentum.
            """,
            model: ModelOption.nearCloudQwenMaxModelID,
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
            ## Claude Opus 4.7
            I would be careful with the word "ending." Diplomatic signals can coexist with active coercion. Fresh strike reporting and the Israel-Hezbollah front mean the safer answer is: negotiations may be near an off-ramp, but the conflict is not reliably settled yet [1][2].
            """,
            model: "near-cloud/anthropic/claude-opus-4-7",
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
            demoModel(Self.defaultModelID, displayName: "GLM 5.1", description: "Default private route with verification.", verifiable: true),
            demoModel(ModelOption.nearCloudQwenMaxModelID, displayName: "Qwen Max", description: "Frontier model through NEAR Cloud privacy proxy.", verifiable: false),
            demoModel("near-cloud/anthropic/claude-opus-4-7", displayName: "Claude Opus 4.7", description: "Claude Opus through NEAR Cloud privacy proxy.", verifiable: false),
            demoModel(ModelOption.ironclawMobileModelID, displayName: "IronClaw Mobile", description: "Phone-safe agent runtime.", verifiable: false),
            demoModel(ModelOption.ironclawModelID, displayName: "Hosted IronClaw", description: "Connected workstation agent.", verifiable: false)
        ]
        let nearCloudModels = Self.fallbackNearCloudModels()
        let attestation = AttestationSnapshot(
            nonce: "demo-\(Int(now.timeIntervalSince1970))",
            signingAlgorithm: "ed25519 + Intel TDX quote",
            model: "GLM-5.1-FP8",
            coveredModelIDs: [Self.defaultModelID],
            fetchedAt: now.addingTimeInterval(-45),
            chatGatewayAddress: "tee-gateway.near.ai",
            cloudGatewayAddress: nil,
            modelAttestationCount: 1,
            prettyJSON: """
            {
              "nonce": "demo-\(Int(now.timeIntervalSince1970))",
              "gateway": "tee-gateway.near.ai",
              "model": "GLM-5.1-FP8",
              "covered_models": [
                "zai-org/GLM-5.1-FP8"
              ],
              "quote": "demo-intel-tdx-quote",
              "signature": "demo-ed25519-signature"
            }
            """
        )
        let shareInfo = demoShareInfo(for: primaryConversation)
        let shareGroups = [
            ShareGroupInfo(
                id: "demo-share-group-launch",
                name: "Research Review",
                members: [
                    ShareInviteRecipient(kind: "email", value: "reviewer@example.com")
                ],
                createdAt: "2026-05-25T13:38:00Z",
                updatedAt: "2026-05-25T13:38:00Z"
            )
        ]

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
            shareGroups: shareGroups,
            shareInfo: shareInfo,
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
