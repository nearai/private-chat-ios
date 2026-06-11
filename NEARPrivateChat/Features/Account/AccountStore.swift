import Foundation

@MainActor
final class AccountStore: ObservableObject {
    @Published var notificationPreferenceEnabled = false
    @Published var appearancePreference: AppAppearancePreference = .system
    @Published var systemPrompt: String {
        didSet {
            guard shouldPersist else { return }
            _ = settingsPersistence.saveSystemPrompt(systemPrompt)
        }
    }
    @Published var soulMarkdown: String {
        didSet {
            guard shouldPersist else { return }
            _ = settingsPersistence.saveSoulMarkdown(soulMarkdown)
        }
    }
    @Published var largeTextAsFileEnabled: Bool = true {
        didSet {
            guard shouldPersist else { return }
            settingsPersistence.saveLargeTextAsFileEnabled(largeTextAsFileEnabled)
        }
    }
    @Published var advancedModelParams: AdvancedModelParams = .defaults {
        didSet {
            guard shouldPersist else { return }
            settingsPersistence.saveAdvancedModelParams(advancedModelParams.sanitized)
        }
    }
    @Published var nearCloudKeyConfigured = false
    @Published var billingSnapshot: BillingSnapshot?
    @Published var isLoadingBilling = false
    @Published var isTestingNearCloudKey = false
    @Published var isConnectingNearCloudAccount = false
    @Published var diagnosticChecks: [AppDiagnosticCheck] = []
    @Published var isRunningDiagnostics = false
    @Published private(set) var isImportingChats = false

    var bannerHandler: ((String) -> Void)?
    var routeInvalidatedHandler: (() -> Void)?
    var cloudRouteDisabledHandler: (() -> Void)?
    var modelCatalogRefreshHandler: (() async throws -> [ModelOption])?
    var conversationsRefreshHandler: (() async -> Void)?

    private let settingsAPI: SettingsAPI
    private let billingAPI: BillingAPI
    private let modelAPI: ModelAPI
    private let chatImportService: ChatImportService
    private let modelCatalogStore: ModelCatalogStore
    private let agentStore: AgentStore
    private let webGroundingService: WebGroundingService
    private var accountID: String
    private var shouldPersist = true
    private var lastRemoteSettings = RemoteUserSettings(
        notification: nil,
        systemPrompt: "",
        webSearch: nil,
        appearance: nil,
        largeTextAsFile: nil,
        temperature: nil,
        topP: nil,
        maxTokens: nil
    )

    init(
        settingsAPI: SettingsAPI,
        billingAPI: BillingAPI,
        modelAPI: ModelAPI,
        conversationAPI: ConversationAPI,
        modelCatalogStore: ModelCatalogStore,
        agentStore: AgentStore,
        webGroundingService: WebGroundingService = WebGroundingService(),
        chatImportService: ChatImportService? = nil,
        accountID: String = AccountStorageScope.signedOutAccountID
    ) {
        self.settingsAPI = settingsAPI
        self.billingAPI = billingAPI
        self.modelAPI = modelAPI
        self.chatImportService = chatImportService ?? ChatImportService(conversationAPI: conversationAPI)
        self.modelCatalogStore = modelCatalogStore
        self.agentStore = agentStore
        self.webGroundingService = webGroundingService
        self.accountID = AccountStorageScope.resolvedAccountID(for: accountID)
        self.systemPrompt = ""
        self.soulMarkdown = ""
        loadAccountScopedState()
    }

    var currentBillingPlanName: String {
        billingSnapshot?.activeSubscription?.plan ?? "free"
    }

    func configure(accountID: String) {
        let resolvedAccountID = AccountStorageScope.resolvedAccountID(for: accountID)
        guard resolvedAccountID != self.accountID else {
            loadAccountScopedState()
            return
        }
        self.accountID = resolvedAccountID
        loadAccountScopedState()
    }

    func reset() {
        billingSnapshot = nil
        modelCatalogStore.updatePlan(allowedModelIDs: nil, planName: "free")
        diagnosticChecks = []
        nearCloudKeyConfigured = false
        isLoadingBilling = false
        isTestingNearCloudKey = false
        isConnectingNearCloudAccount = false
        isRunningDiagnostics = false
        isImportingChats = false
    }

    func loadAccountScopedState() {
        shouldPersist = false
        largeTextAsFileEnabled = settingsPersistence.loadLargeTextAsFileEnabled(default: true)
        advancedModelParams = settingsPersistence.loadAdvancedModelParams()
        systemPrompt = settingsPersistence.loadSystemPrompt()
        soulMarkdown = settingsPersistence.loadSoulMarkdown()
        shouldPersist = true
        nearCloudKeyConfigured = loadNearCloudAPIKey()?.isEmpty == false
    }

    func refreshUserSettings(showErrors: Bool = true) async {
        do {
            let response = try await settingsAPI.fetchUserSettings()
            apply(remoteSettings: response.settings)
        } catch {
            if showErrors {
                showBanner(ErrorMessageMapper.displayFailureMessage(error.localizedDescription))
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
            let response = try await settingsAPI.updateUserSettings(
                systemPrompt: systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
                webSearchEnabled: webSearchEnabled,
                notificationEnabled: notificationEnabled,
                appearance: appearancePreference.rawValue,
                largeTextAsFile: largeTextAsFileEnabled,
                advancedParams: sanitizedParams
            )
            apply(remoteSettings: response.settings)
            self.advancedModelParams = sanitizedParams
            showBanner("Account preferences saved.")
        } catch {
            showBanner(ErrorMessageMapper.displayFailureMessage(error.localizedDescription))
        }
    }

    func refreshBilling(showErrors: Bool = true) async {
        guard !isLoadingBilling else { return }
        isLoadingBilling = true
        defer { isLoadingBilling = false }
        do {
            async let plansLoad = billingAPI.fetchSubscriptionPlans()
            async let subscriptionsLoad = billingAPI.fetchSubscriptions(includeInactive: false)
            let (plans, subscriptions) = try await (plansLoad, subscriptionsLoad)
            billingSnapshot = BillingSnapshot(plans: plans, subscriptions: subscriptions, fetchedAt: Date())
            modelCatalogStore.updatePlan(
                allowedModelIDs: currentPlanAllowedModelIDs,
                planName: currentBillingPlanName
            )
            modelCatalogStore.ensureSelectedModelIsAvailable(shouldShowBanner: false)
        } catch {
            if showErrors {
                showBanner("Billing unavailable: \(ErrorMessageMapper.displayFailureMessage(error.localizedDescription))")
            }
        }
    }

    func importChats(from url: URL) async {
        guard !isImportingChats else { return }
        isImportingChats = true
        defer { isImportingChats = false }

        do {
            let summary = try await chatImportService.importChats(from: url)
            await conversationsRefreshHandler?()
            showBanner(summary.bannerMessage)
        } catch {
            showBanner(ErrorMessageMapper.displayFailureMessage(error.localizedDescription))
        }
    }

    func saveNearCloudAPIKey(_ apiKey: String) {
        let trimmedKey = PrivateChatAPI.normalizedNearCloudAPIKey(apiKey)
        guard !trimmedKey.isEmpty else {
            showBanner("Paste a NEAR AI Cloud key first.")
            return
        }

        do {
            try settingsPersistence.saveNearCloudAPIKey(trimmedKey)
            nearCloudKeyConfigured = true
            routeInvalidatedHandler?()
            showBanner("NEAR AI Cloud key saved.")
        } catch {
            showBanner(ErrorMessageMapper.displayFailureMessage(error.localizedDescription))
        }
    }

    func connectNearCloudAccount() async -> Bool {
        isConnectingNearCloudAccount = true
        defer { isConnectingNearCloudAccount = false }

        do {
            let response = try await modelAPI.connectNearCloudAccount()
            let apiKey = PrivateChatAPI.normalizedNearCloudAPIKey(response.apiKey)
            guard !apiKey.isEmpty else {
                let message = response.message?.trimmingCharacters(in: .whitespacesAndNewlines)
                showBanner(message?.isEmpty == false ? message! : "Cloud auto-connect is not available yet. Open Cloud, create a key, then paste it here.")
                return false
            }

            let fetchedCloud = response.models.isEmpty
                ? try await modelAPI.fetchNearCloudModels(apiKey: apiKey)
                : response.models
            try settingsPersistence.saveNearCloudAPIKey(apiKey)
            nearCloudKeyConfigured = true
            routeInvalidatedHandler?()
            let routeModels = ModelCatalogStore.nearCloudRouteModels(from: fetchedCloud)
            modelCatalogStore.replaceNearCloudModels(routeModels)
            showBanner(routeModels.isEmpty ? "NEAR AI Cloud connected, but no models were returned." : "NEAR AI Cloud connected. \(routeModels.count) models ready.")
            return true
        } catch APIError.status(let code, _) where code == 404 || code == 405 {
            showBanner("Cloud auto-connect is not available yet. Open Cloud, create a key, then paste it here.")
            return false
        } catch {
            showBanner("Cloud auto-connect failed: \(ErrorMessageMapper.displayFailureMessage(error.localizedDescription))")
            return false
        }
    }

    func connectNearCloudAPIKey(_ apiKey: String) async -> Bool {
        let trimmedKey = PrivateChatAPI.normalizedNearCloudAPIKey(apiKey)
        guard !trimmedKey.isEmpty else {
            showBanner("Paste a NEAR AI Cloud key first.")
            return false
        }

        isTestingNearCloudKey = true
        defer { isTestingNearCloudKey = false }

        do {
            let fetchedCloud = try await modelAPI.fetchNearCloudModels(apiKey: trimmedKey)
            try settingsPersistence.saveNearCloudAPIKey(trimmedKey)
            nearCloudKeyConfigured = true
            routeInvalidatedHandler?()
            let routeModels = ModelCatalogStore.nearCloudRouteModels(from: fetchedCloud)
            modelCatalogStore.replaceNearCloudModels(routeModels)
            showBanner(routeModels.isEmpty ? "NEAR AI Cloud connected, but no models were returned." : "NEAR AI Cloud connected. \(routeModels.count) models ready.")
            return true
        } catch {
            showBanner("NEAR AI Cloud key was not saved: \(ErrorMessageMapper.displayFailureMessage(error.localizedDescription))")
            return false
        }
    }

    func clearNearCloudAPIKey() {
        settingsPersistence.deleteNearCloudAPIKey()
        nearCloudKeyConfigured = false
        if modelCatalogStore.selectedModelOption?.isNearCloudModel == true {
            cloudRouteDisabledHandler?()
        }
        routeInvalidatedHandler?()
        showBanner("NEAR AI Cloud disconnected.")
    }

    func runDiagnostics() async {
        guard !isRunningDiagnostics else { return }
        isRunningDiagnostics = true
        diagnosticChecks = [
            AppDiagnosticCheck(title: "Model catalog", detail: "Checking NEAR Private API models.", state: .running),
            AppDiagnosticCheck(title: "Web grounding", detail: "Searching a live AI-news query.", state: .running),
            AppDiagnosticCheck(title: "Agent connection", detail: "Checking Hosted IronClaw URL and bearer token.", state: .running),
            AppDiagnosticCheck(title: "Hosted tools", detail: "Checking hosted shell/git tools.", state: .running),
            AppDiagnosticCheck(title: "NEAR AI Cloud", detail: nearCloudKeyConfigured ? "Connected." : "Not connected.", state: nearCloudKeyConfigured ? .passed : .warning)
        ]
        defer {
            isRunningDiagnostics = false
            showBanner("Diagnostics complete.")
        }

        do {
            let fetched: [ModelOption]
            if let modelCatalogRefreshHandler {
                fetched = try await modelCatalogRefreshHandler()
            } else {
                fetched = try await modelAPI.fetchModels()
            }
            modelCatalogStore.replaceModels(fetched)
            modelCatalogStore.ensureSelectedModelIsAvailable(shouldShowBanner: false)
            updateDiagnostic(
                title: "Model catalog",
                detail: "\(modelCatalogStore.pickerModels.count) curated chat models available.",
                state: modelCatalogStore.pickerModels.isEmpty ? .warning : .passed
            )
        } catch {
            updateDiagnostic(
                title: "Model catalog",
                detail: "Private API model fetch failed: \(ErrorMessageMapper.displayFailureMessage(error.localizedDescription))",
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
                detail: "Search failed: \(ErrorMessageMapper.displayFailureMessage(error.localizedDescription))",
                state: .failed
            )
        }

        guard agentStore.ironclawSettings.hasUsableHostedEndpoint else {
            updateDiagnostic(
                title: "Agent connection",
                detail: agentStore.ironclawSettings.endpointValidationMessage ?? "Add a Hosted IronClaw URL.",
                state: .warning
            )
            updateDiagnostic(
                title: "Hosted tools",
                detail: "Add a Hosted IronClaw URL before testing tools.",
                state: .warning
            )
            return
        }

        var bridgePassed = false
        do {
            let message = try await IronclawAPI().testConnection(
                settings: agentStore.ironclawSettings,
                authToken: agentStore.loadIronclawAuthToken()
            )
            agentStore.applyConnectionDiagnosticStatus(message)
            updateDiagnostic(title: "Agent connection", detail: message, state: .passed)
            bridgePassed = true
        } catch {
            let message = ErrorMessageMapper.displayFailureMessage(error.localizedDescription)
            agentStore.applyConnectionDiagnosticStatus(message)
            updateDiagnostic(title: "Agent connection", detail: message, state: .failed)
        }
        guard bridgePassed else {
            updateDiagnostic(
                title: "Hosted tools",
                detail: "Agent connection failed before tool preflight.",
                state: .warning
            )
            return
        }

        do {
            let message = try await IronclawAPI().testWorkstationCapability(
                settings: agentStore.ironclawSettings,
                authToken: agentStore.loadIronclawAuthToken()
            )
            agentStore.applyWorkstationDiagnosticSuccess(message)
            updateDiagnostic(title: "Hosted tools", detail: message, state: message.contains("checked") ? .passed : .warning)
        } catch {
            let message = ErrorMessageMapper.displayFailureMessage(error.localizedDescription)
            agentStore.applyConnectionDiagnosticStatus(message)
            updateDiagnostic(title: "Hosted tools", detail: message, state: .failed)
        }
    }

    func loadNearCloudAPIKey() -> String? {
        settingsPersistence.loadNearCloudAPIKey()
    }

    func apply(remoteSettings: RemoteUserSettings) {
        lastRemoteSettings = remoteSettings
        notificationPreferenceEnabled = remoteSettings.notification ?? false
        appearancePreference = AppAppearancePreference(remoteValue: remoteSettings.appearance)
        if let remoteWebSearch = remoteSettings.webSearch {
            modelCatalogStore.webSearchEnabled = remoteWebSearch
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

    private func updateDiagnostic(title: String, detail: String, state: AppDiagnosticCheck.State) {
        if let index = diagnosticChecks.firstIndex(where: { $0.title == title }) {
            diagnosticChecks[index].detail = detail
            diagnosticChecks[index].state = state
        } else {
            diagnosticChecks.append(AppDiagnosticCheck(title: title, detail: detail, state: state))
        }
    }

    private var settingsPersistence: SettingsPersistence {
        SettingsPersistence(accountID: accountID)
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

    func showBanner(_ message: String) {
        bannerHandler?(message)
    }

}
