import Foundation

extension ChatStore {
    var composerState: ComposerState {
        ComposerState(
            draft: draft,
            pendingAttachments: pendingAttachments,
            isStreaming: isStreaming,
            routeReadinessTitle: routeReadinessIssue?.title,
            routeReadinessMessage: routeReadinessIssue?.message
        )
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
        SetupRouteDefaultResolver.currentDefaults(
            selectedModelID: selectedModel,
            isCouncilModeEnabled: isCouncilModeEnabled,
            councilModelIDs: isCouncilModeEnabled ? councilModelIDs : defaultCouncilModelIDs(),
            agentModelIDs: Set(agentModels.map(\.id)),
            preferredAvailableModelID: preferredAvailableModel(),
            defaultModelID: Self.defaultModelID,
            maxCouncilModels: Self.maxCouncilModels
        )
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
}
