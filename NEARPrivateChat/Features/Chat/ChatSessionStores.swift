import Foundation
import Combine

@MainActor
final class ChatTranscriptStore: ObservableObject {
    let timelineStore: MessageTimelineStore
    private var cancellables: Set<AnyCancellable> = []

    init() {
        self.timelineStore = MessageTimelineStore()
        bindTimelineStore()
    }

    init(timelineStore: MessageTimelineStore) {
        self.timelineStore = timelineStore
        bindTimelineStore()
    }

    private func bindTimelineStore() {
        timelineStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var state: ChatTranscriptState {
        timelineStore.state
    }

    var messages: [ChatMessage] {
        get { timelineStore.messages }
        set { timelineStore.messages = newValue }
    }

    var isStreaming: Bool {
        get { timelineStore.isStreaming }
        set { timelineStore.isStreaming = newValue }
    }

    func replaceMessages(_ messages: [ChatMessage]) {
        timelineStore.messages = messages
    }
}

struct ChatTranscriptState {
    let messages: [ChatMessage]
    let displayItems: [ChatDisplayItem]
    let isStreaming: Bool

    init(messages: [ChatMessage] = [], isStreaming: Bool = false) {
        self.messages = messages
        self.displayItems = MessageTimelineStore.displayItems(from: messages)
        self.isStreaming = isStreaming
    }

    private init(messages: [ChatMessage], displayItems: [ChatDisplayItem], isStreaming: Bool) {
        self.messages = messages
        self.displayItems = displayItems
        self.isStreaming = isStreaming
    }

    func updating(messages: [ChatMessage]) -> ChatTranscriptState {
        ChatTranscriptState(messages: messages, isStreaming: isStreaming)
    }

    func updating(isStreaming: Bool) -> ChatTranscriptState {
        ChatTranscriptState(messages: messages, displayItems: displayItems, isStreaming: isStreaming)
    }
}

@MainActor
final class ChatComposerStore: ObservableObject {
    let attachmentStagingStore: AttachmentStagingStore

    @Published var draft = ""
    @Published var routeReadinessIssue: ChatRouteReadinessIssue?
    /// One-tap "answer via privacy proxy" offer for the latest restricted
    /// private send. Cleared on new sends and conversation switches.
    @Published var proxyRetryOffer: ProxyRetryOffer?

    private var cancellables: Set<AnyCancellable> = []

    init(attachmentStagingStore: AttachmentStagingStore? = nil) {
        self.attachmentStagingStore = attachmentStagingStore ?? AttachmentStagingStore()
        self.attachmentStagingStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var pendingAttachments: [ChatAttachment] {
        get { attachmentStagingStore.pendingAttachments }
        set { attachmentStagingStore.replacePendingAttachments(newValue) }
    }

    var isUploadingAttachment: Bool {
        get { attachmentStagingStore.isUploadingAttachment }
        set { attachmentStagingStore.isUploadingAttachment = newValue }
    }

    func clearDraftAndAttachments() {
        draft = ""
        attachmentStagingStore.resetAll()
    }
}

@MainActor
final class ChatDraftScopeStore {
    static let homeScopeID = "home"

    private(set) var scopeID: String = ChatDraftScopeStore.homeScopeID
    private(set) var isSuppressingPersistence = false

    private var accountID: String
    private var defaults: UserDefaults
    private var fileManager: FileManager

    init(
        accountID: String = AccountStorageScope.signedOutAccountID,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.accountID = AccountStorageScope.resolvedAccountID(for: accountID)
        self.defaults = defaults
        self.fileManager = fileManager
    }

    func configure(accountID: String) {
        self.accountID = AccountStorageScope.resolvedAccountID(for: accountID)
    }

    func currentScopeID(selectedConversationID: String?, selectedProjectID: String?) -> String {
        if let conversationID = selectedConversationID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !conversationID.isEmpty {
            return "conversation:\(conversationID)"
        }
        if let projectID = selectedProjectID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !projectID.isEmpty {
            return "project:\(projectID)"
        }
        return Self.homeScopeID
    }

    func transition(
        to scopeID: String,
        loadDraft: Bool,
        applyLoadedDraft: (DraftPersistence.DraftState) -> Void
    ) {
        self.scopeID = scopeID
        guard loadDraft else { return }
        let persistedState = draftPersistence.load(scopeID: scopeID)
        isSuppressingPersistence = true
        applyLoadedDraft(persistedState)
        isSuppressingPersistence = false
    }

    func persistIfNeeded(
        _ state: DraftPersistence.DraftState,
        isResettingAccountScopedState: Bool,
        showSaveFailure: () -> Void
    ) {
        guard !isSuppressingPersistence, !isResettingAccountScopedState else { return }
        guard !draftPersistence.save(state, scopeID: scopeID) else { return }
        showSaveFailure()
    }

    func remove(scopeID: String) {
        draftPersistence.remove(scopeID: scopeID)
    }

    func removeCurrentScope() {
        remove(scopeID: scopeID)
    }

    private var draftPersistence: DraftPersistence {
        DraftPersistence(accountID: accountID, defaults: defaults, fileManager: fileManager)
    }
}

@MainActor
final class ChatSessionCoordinator {
    private let conversationStore: ConversationStore
    private let transcriptStore: ChatTranscriptStore
    private let composerStore: ChatComposerStore
    private let projectStore: ProjectStore?

    init(
        conversationStore: ConversationStore,
        transcriptStore: ChatTranscriptStore,
        composerStore: ChatComposerStore,
        projectStore: ProjectStore? = nil
    ) {
        self.conversationStore = conversationStore
        self.transcriptStore = transcriptStore
        self.composerStore = composerStore
        self.projectStore = projectStore
    }

    @discardableResult
    func openConversation(
        _ conversation: ConversationSummary,
        isStreaming: Bool,
        cancelActiveStream: () -> Void,
        persistCurrentDraft: () -> Void,
        scheduleMessageLoad: (ConversationSummary) -> Void,
        transitionDraftScope: () -> Void,
        showBanner: (String) -> Void
    ) -> Bool {
        // Switching no longer blocks on a running answer: the stream is
        // stopped, its partial text persisted into the chat it belongs to, and
        // the user moves on. cancelActiveStream must run BEFORE the selection
        // changes so the save lands in the right conversation.
        if isStreaming {
            cancelActiveStream()
            showBanner("Stopped the previous answer — its partial text is saved in that chat.")
        }

        composerStore.proxyRetryOffer = nil
        persistCurrentDraft()
        conversationStore.selectConversation(conversation)
        scheduleMessageLoad(conversation)
        transitionDraftScope()
        return true
    }

    @discardableResult
    func startNewConversation(
        isStreaming: Bool,
        cancelActiveStream: () -> Void,
        persistCurrentDraft: () -> Void,
        cancelMessageLoad: () -> Void,
        transitionDraftScope: () -> Void,
        showBanner: (String) -> Void
    ) -> Bool {
        if isStreaming {
            cancelActiveStream()
            showBanner("Stopped the previous answer — its partial text is saved in that chat.")
        }

        composerStore.proxyRetryOffer = nil
        persistCurrentDraft()
        conversationStore.startNewConversation()
        cancelMessageLoad()
        transcriptStore.replaceMessages([])
        transitionDraftScope()
        return true
    }

    @discardableResult
    func openWritablePreview(
        conversation: ConversationSummary,
        messages: [ChatMessage],
        canWrite: Bool,
        cancelMessageLoad: () -> Void,
        showBanner: (String) -> Void
    ) -> Bool {
        guard canWrite else {
            showBanner("This shared conversation is read-only.")
            return false
        }

        cancelMessageLoad()
        conversationStore.selectConversation(conversation)
        transcriptStore.replaceMessages(messages)
        composerStore.clearDraftAndAttachments()
        conversationStore.requestOpenSelectedConversation()
        return true
    }

    @discardableResult
    func selectAllChats(
        persistCurrentDraft: () -> Void,
        transitionDraftScope: () -> Void
    ) -> Bool {
        guard let projectStore else { return false }

        persistCurrentDraft()
        projectStore.selectAllProjects()
        transitionDraftScope()
        return true
    }

    @discardableResult
    func selectProject(
        _ project: ChatProject,
        availableConversations: [ConversationSummary],
        persistCurrentDraft: () -> Void,
        scheduleMessageLoad: (ConversationSummary) -> Void,
        cancelMessageLoad: () -> Void,
        transitionDraftScope: () -> Void
    ) -> Bool {
        guard let projectStore else { return false }

        persistCurrentDraft()
        guard projectStore.selectProject(project) else { return false }
        let selectedProject = projectStore.selectedProject ?? project
        let projectConversationIDs = Set(selectedProject.conversationIDs)

        if let selectedConversation = conversationStore.selectedConversation,
           projectConversationIDs.contains(selectedConversation.id) {
            transitionDraftScope()
            return true
        }

        if let latestConversation = availableConversations
            .filter({ projectConversationIDs.contains($0.id) && !$0.isArchived })
            .sorted(by: { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) })
            .first {
            conversationStore.selectConversation(latestConversation)
            scheduleMessageLoad(latestConversation)
        } else {
            conversationStore.startNewConversation()
            cancelMessageLoad()
            transcriptStore.replaceMessages([])
        }

        transitionDraftScope()
        return true
    }

    @discardableResult
    func archiveProject(
        _ project: ChatProject,
        transitionDraftScope: () -> Void
    ) -> Bool {
        guard let projectStore else { return false }

        let wasSelected = projectStore.selectedProjectID == project.id
        guard projectStore.archiveProject(project) else { return false }
        if wasSelected {
            transitionDraftScope()
        }
        return true
    }

    func activateConversationForSend(
        _ conversation: ConversationSummary,
        transitionDraftScope: () -> Void
    ) {
        conversationStore.selectConversation(conversation)
        transitionDraftScope()
    }
}
