import Foundation

struct AppEnvironment {
    let api: PrivateChatAPI
    let authAPI: AuthAPI
    let conversationAPI: ConversationAPI
    let messageAPI: MessageAPI
    let modelAPI: ModelAPI
    let fileAPI: FileAPI
    let shareAPI: ShareAPI
    let settingsAPI: SettingsAPI
    let billingAPI: BillingAPI
    let attestationAPI: AttestationAPI
    let sessionStore: SessionStore
    let modelCatalogStore: ModelCatalogStore
    let fileStore: FileStore
    let projectStore: ProjectStore
    let conversationStore: ConversationStore
    let agentStore: AgentStore
    let accountStore: AccountStore
    let securityStore: SecurityStore
    let chatStore: ChatStore
    let shareStore: ShareStore
    let briefingStore: BriefingStore
    let routeHealthMonitor: RouteHealthMonitor
    let connectionDiagnostics: ConnectionDiagnostics

    @MainActor
    static func production() -> AppEnvironment {
        let api = PrivateChatAPI(configuration: .production)
        let sessionStore = SessionStore(api: api)
        let modelCatalogStore = ModelCatalogStore()
        let fileService = FileService(fileAPI: api)
        let fileStore = FileStore(service: fileService)
        let projectStore = ProjectStore()
        let conversationStore = ConversationStore(repository: ConversationRepository(api: api))
        let agentStore = AgentStore()
        let securityStore = SecurityStore(attestationAPI: api)
        let accountStore = AccountStore(
            settingsAPI: api,
            billingAPI: api,
            modelAPI: api,
            conversationAPI: api,
            modelCatalogStore: modelCatalogStore,
            agentStore: agentStore
        )
        accountStore.conversationsRefreshHandler = { [weak conversationStore] in
            await conversationStore?.refreshConversations(showErrors: false)
        }
        let routeHealthMonitor = RouteHealthMonitor()
        let connectionDiagnostics = ConnectionDiagnostics()
        let chatStore = ChatStore(
            api: api,
            fileService: fileService,
            fileStore: fileStore,
            modelCatalogStore: modelCatalogStore,
            projectStore: projectStore,
            conversationStore: conversationStore,
            agentStore: agentStore,
            accountStore: accountStore,
            securityStore: securityStore,
            routeHealth: routeHealthMonitor,
            diagnostics: connectionDiagnostics,
            initialAccountID: AccountStorageScope.signedOutAccountID
        )
        fileStore.bannerHandler = { [weak chatStore] message in
            chatStore?.bannerMessage = message
        }
        projectStore.bannerHandler = { [weak chatStore] message in
            chatStore?.bannerMessage = message
        }
        let shareStore = ShareStore(service: SharingService(shareAPI: api, conversationAPI: api))
        shareStore.bannerHandler = { [weak chatStore] message in
            chatStore?.bannerMessage = message
        }
        #if DEBUG
        // Demo capture uses an isolated briefings file so its seeded samples
        // (and the saves their scheduled runs trigger) never pollute the real
        // briefings.json a normal/interactive session loads.
        let briefingStore = DemoCapture.isEnabled
            ? BriefingStore(fileURL: BriefingStore.demoFileURL())
            : BriefingStore()
        if DemoCapture.isEnabled {
            briefingStore.seedDemoSamples()
        } else {
            briefingStore.load()
        }
        #else
        let briefingStore = BriefingStore()
        briefingStore.load()
        #endif
        briefingStore.runner = { [weak chatStore] briefing in
            guard let chatStore else {
                return .failed("The app is still launching. Try running it again in a moment.")
            }
            let outcome = await chatStore.runBriefing(briefing)
            if case .delivered = outcome {
                chatStore.activityLog.record("Ran briefing “\(briefing.title)”")
            }
            return outcome
        }
        configureTrackerPersistence(chatStore: chatStore, briefingStore: briefingStore)
        return AppEnvironment(
            api: api,
            authAPI: api,
            conversationAPI: api,
            messageAPI: api,
            modelAPI: api,
            fileAPI: api,
            shareAPI: api,
            settingsAPI: api,
            billingAPI: api,
            attestationAPI: api,
            sessionStore: sessionStore,
            modelCatalogStore: modelCatalogStore,
            fileStore: fileStore,
            projectStore: projectStore,
            conversationStore: conversationStore,
            agentStore: agentStore,
            accountStore: accountStore,
            securityStore: securityStore,
            chatStore: chatStore,
            shareStore: shareStore,
            briefingStore: briefingStore,
            routeHealthMonitor: routeHealthMonitor,
            connectionDiagnostics: connectionDiagnostics
        )
    }

    @MainActor
    static func configureTrackerPersistence(chatStore: ChatStore, briefingStore: BriefingStore) {
        chatStore.onCreateTracker = { [weak briefingStore] briefing in
            briefingStore?.add(briefing)
        }
        chatStore.trackersProvider = { [weak briefingStore] in briefingStore?.briefings ?? [] }
    }
}
