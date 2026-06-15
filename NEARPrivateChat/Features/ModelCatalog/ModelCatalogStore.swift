import Foundation
import Combine

@MainActor
final class ModelCatalogStore: ObservableObject {
    nonisolated static let defaultModelID = ModelOption.nearPrivateDefaultModelID
    nonisolated static let maxCouncilModels = 3
    nonisolated static let maxPinnedModels = 12

    // Only a thin pin to float the default private model and the live frontier
    // privates to the top. Everything else (and any Kimi/DeepSeek/GLM family
    // member) is ranked by the durable capability heuristics in `modelRank`,
    // so this list never has to chase model-version churn. Do NOT re-introduce
    // exact version IDs for families already covered by those heuristics.
    nonisolated static let preferredModelIDs = [
        ModelOption.nearPrivateDefaultModelID,
        "anthropic/claude-sonnet-4-6",
        "anthropic/claude-opus-4-6",
        "Qwen/Qwen3.6-35B-A3B-FP8",
        "Qwen/Qwen3.6-27B-FP8",
        "Qwen/Qwen3.5-122B-A10B"
    ]
    nonisolated static let nearCloudPreferredModelIDs: [String] = [
        "anthropic/claude-sonnet-4-6",
        "anthropic/claude-opus-4-6",
        "Qwen/Qwen3.6-35B-A3B-FP8",
        "Qwen/Qwen3.6-27B-FP8",
        "deepseek-ai/DeepSeek-V4-Flash",
        "Qwen/Qwen3.5-122B-A10B",
        "Qwen/Qwen3-30B-A3B-Instruct-2507",
        "zai-org/GLM-5.1-FP8"
    ]
    nonisolated static let defaultCouncilCandidateGroups = [
        [
            ModelOption.nearPrivateDefaultModelID
        ]
    ]

    @Published private(set) var models: [ModelOption]
    @Published private(set) var nearCloudModels: [ModelOption]
    @Published private(set) var allowedModelIDs: Set<String>?
    @Published var selectedModel: String {
        didSet {
            persistSelectedModel()
        }
    }
    @Published var councilModelIDs: [String] {
        didSet {
            persistCouncilModelIDs()
            cachedActiveCouncilModels = nil
        }
    }
    /// Resolving council IDs against the catalog is O(catalog) and was being
    /// recomputed per picker row per render — cache it; invalidated when the
    /// lineup or the catalog changes.
    var cachedActiveCouncilModels: [ModelOption]?
    @Published var pinnedModelIDs: [String] {
        didSet {
            persistPinnedModelIDs()
        }
    }
    @Published var webSearchEnabled: Bool {
        didSet {
            persistWebSearchEnabled()
        }
    }
    @Published var sourceMode: ChatSourceMode {
        didSet {
            persistSourceMode()
        }
    }
    @Published var researchModeEnabled: Bool {
        didSet {
            persistResearchModeEnabled()
        }
    }

    let preferredModelIDs: [String]
    let nearCloudPreferredModelIDs: [String]
    var bannerHandler: ((String) -> Void)?
    var routeDidChangeHandler: (() -> Void)?

    private var settingsPersistence: SettingsPersistence?
    private var shouldPersist = false
    private var currentBillingPlanName = "free"
    private static let modelDefaultRepairMigrationKey = "modelDefaultRepairMigrationV1"
    private static let deprecatedAutomaticDefaultModelIDs = [
        "zai-org/GLM-latest",
        "Qwen/Qwen3.5-122B-A10B"
    ]

    init(
        models: [ModelOption] = [],
        nearCloudModels: [ModelOption] = [],
        allowedModelIDs: Set<String>? = nil,
        preferredModelIDs: [String] = ModelCatalogStore.preferredModelIDs,
        nearCloudPreferredModelIDs: [String] = ModelCatalogStore.nearCloudPreferredModelIDs,
        selectedModel: String = ModelCatalogStore.defaultModelID,
        councilModelIDs: [String] = [ModelCatalogStore.defaultModelID],
        pinnedModelIDs: [String] = [],
        webSearchEnabled: Bool = false,
        sourceMode: ChatSourceMode = .auto,
        researchModeEnabled: Bool = false
    ) {
        self.models = models
        self.nearCloudModels = nearCloudModels
        self.allowedModelIDs = allowedModelIDs
        self.preferredModelIDs = preferredModelIDs
        self.nearCloudPreferredModelIDs = nearCloudPreferredModelIDs
        self.selectedModel = selectedModel
        self.councilModelIDs = Array(Self.uniqueStrings(councilModelIDs).prefix(Self.maxCouncilModels))
        self.pinnedModelIDs = Array(Self.uniqueStrings(pinnedModelIDs).prefix(Self.maxPinnedModels))
        self.webSearchEnabled = webSearchEnabled
        self.sourceMode = sourceMode
        self.researchModeEnabled = researchModeEnabled
    }

    func configure(accountID: String, effectiveDefaultModelID: String? = nil) {
        settingsPersistence = SettingsPersistence(accountID: accountID)
        shouldPersist = false
        let fallbackDefault = effectiveDefaultModelID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDefault = fallbackDefault?.isEmpty == false ? fallbackDefault! : self.effectiveDefaultModelID
        let storedModel = settingsPersistence?.loadSelectedModelID()
        let initialModel = repairedInitialModel(storedModel, resolvedDefault: resolvedDefault)
        selectedModel = RoutePlanner.routeKind(forModelID: initialModel).isIronclawRoute ? resolvedDefault : initialModel
        let storedCouncilModelIDs = Array(Self.uniqueStrings(settingsPersistence?.loadCouncilModelIDs() ?? []).prefix(Self.maxCouncilModels))
        councilModelIDs = storedCouncilModelIDs.isEmpty ? [selectedModel] : storedCouncilModelIDs
        normalizeCouncilSelection(shouldShowBanner: true)
        pinnedModelIDs = settingsPersistence?.loadPinnedModelIDs(maxCount: Self.maxPinnedModels) ?? []
        webSearchEnabled = settingsPersistence?.loadWebSearchEnabled(default: false) ?? false
        sourceMode = settingsPersistence?.loadSourceMode(default: .auto) ?? .auto
        researchModeEnabled = settingsPersistence?.loadResearchModeEnabled() ?? false
        shouldPersist = true
    }

    func reset() {
        shouldPersist = false
        models = []
        nearCloudModels = []
        allowedModelIDs = nil
        selectedModel = Self.defaultModelID
        councilModelIDs = [Self.defaultModelID]
        pinnedModelIDs = []
        webSearchEnabled = false
        sourceMode = .auto
        researchModeEnabled = false
        currentBillingPlanName = "free"
        shouldPersist = settingsPersistence != nil
    }

    func resetInteractionDefaults() {
        selectedModel = Self.defaultModelID
        councilModelIDs = [Self.defaultModelID]
        webSearchEnabled = false
        sourceMode = .auto
        researchModeEnabled = false
        routeDidChangeHandler?()
    }

    func replaceModels(_ newModels: [ModelOption]) {
        cachedActiveCouncilModels = nil
        guard models != newModels else { return }
        models = newModels
    }

    func replaceNearCloudModels(_ newModels: [ModelOption]) {
        guard nearCloudModels != newModels else { return }
        cachedActiveCouncilModels = nil
        nearCloudModels = newModels
    }

    func updatePlan(allowedModelIDs: Set<String>?, planName: String) {
        self.allowedModelIDs = Self.normalizeAllowedModelIDs(allowedModelIDs)
        currentBillingPlanName = planName
    }

    func refreshModels(
        modelAPI: ModelAPI,
        loadCloudCatalog: Bool = false,
        nearCloudAPIKey: String? = nil
    ) async throws {
        do {
            let fetched = try await modelAPI.fetchModels()
            let fetchedCloud = loadCloudCatalog
                ? (try? await modelAPI.fetchNearCloudModels(apiKey: nearCloudAPIKey)) ?? []
                : []
            replaceModels(fetched)
            if loadCloudCatalog {
                replaceNearCloudModels(Self.nearCloudRouteModels(from: fetchedCloud))
            }
            ensureSelectedModelIsAvailable(shouldShowBanner: false)
            normalizeCouncilSelection(shouldShowBanner: false)
        } catch {
            if models.isEmpty {
                replaceModels(Self.fallbackPrivateModels())
                normalizeCouncilSelection(shouldShowBanner: false)
            }
            throw error
        }
    }

    var externalModels: [ModelOption] {
        [Self.ironclawMobileModel(), Self.ironclawModel()] + cloudRouteModels
    }

    var agentModels: [ModelOption] {
        [Self.ironclawMobileModel(), Self.ironclawModel()]
    }

    var cloudRouteModels: [ModelOption] {
        Self.uniqueModels(nearCloudModels + Self.fallbackNearCloudModels())
            .filter { !$0.isUtilityModel }
    }

    var cloudModels: [ModelOption] {
        rankedModels(from: cloudRouteModels)
    }

    var chatModels: [ModelOption] {
        let privateModels = Self.uniqueModels(Self.fallbackPrivateModels() + models)
        return (privateModels + externalModels).filter { model in
            !model.isUtilityModel && isAllowedByCurrentPlan(model)
        }
    }

    var pickerModels: [ModelOption] {
        chatModels.filter { !$0.isDeprecatedPickerModel }
    }

    var selectedModelOption: ModelOption? {
        return chatModels.first(where: { Self.model($0, matchesCandidateID: selectedModel) })
    }

    var selectedModelDisplayName: String {
        selectedModelOption?.displayName ?? selectedModel.split(separator: "/").last.map(String.init) ?? selectedModel
    }

    var activeModelDisplayName: String {
        isCouncilModeEnabled ? "LLM Council \(activeCouncilModels.count)" : selectedModelDisplayName
    }

    var preferredDefaultModelID: String? {
        get { settingsPersistence?.loadPreferredDefaultModelID() }
        set {
            settingsPersistence?.savePreferredDefaultModelID(newValue)
            objectWillChange.send()
        }
    }

    var effectiveDefaultModelID: String {
        if let preferred = preferredDefaultModelID, !preferred.isEmpty {
            return preferred
        }
        return Self.defaultModelID
    }

    var preferredDefaultModelCandidates: [ModelOption] {
        pickerModels.filter { option in
            !option.isIronclawModel && option.modelID != ModelOption.llmCouncilSynthesisModelID
        }
    }

    func setPreferredDefaultModel(_ modelID: String?, shouldSwitchCurrentEmptyChat: Bool) {
        preferredDefaultModelID = modelID
        if shouldSwitchCurrentEmptyChat,
           let resolved = modelID,
           let model = pickerModels.first(where: {
               Self.model($0, matchesCandidateID: resolved)
           }) {
            selectedModel = model.id
            routeDidChangeHandler?()
        }
    }

    var featuredPickerModels: [ModelOption] {
        let featuredIDs =
            [Self.defaultModelID] +
            rankedModels(from: pickerModels.filter { !$0.isExternalModel }).prefix(2).map(\.id) +
            rankedModels(from: cloudRouteModels).prefix(3).map(\.id) +
            [ModelOption.ironclawModelID, ModelOption.ironclawMobileModelID]
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
        pinnedPickerModels(from: pinnedModelIDs)
    }

    func pinnedPickerModels(from pinnedModelIDs: [String]) -> [ModelOption] {
        let available = pickerModels
        return pinnedModelIDs.compactMap { id in
            available.first { Self.model($0, matchesCandidateID: id) }
        }
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

    var selectedRouteKind: ChatRouteKind {
        RoutePlanner.routeKind(forModelID: selectedModel)
    }

    var hiddenPlanLockedModelCount: Int {
        guard allowedModelIDs != nil else { return 0 }
        return models.filter { !$0.isUtilityModel && !isAllowedByCurrentPlan($0) }.count
    }

    func sourceRoutingSemantics(for route: ChatRouteKind) -> ChatSourceRoutingSemantics {
        RoutePlanner.sourceRoutingSemantics(
            sourceMode: sourceMode,
            researchModeEnabled: researchModeEnabled,
            webSearchEnabled: webSearchEnabled,
            route: route
        )
    }

    func modelDisplayName(for modelID: String) -> String {
        return chatModels.first(where: { Self.model($0, matchesCandidateID: modelID) })?.displayName ??
            modelID.split(separator: "/").last.map(String.init) ??
            modelID
    }

    func switchToPrivateFallbackModel() -> Bool {
        guard let replacement = preferredAvailableModel() ?? pickerModels.first(where: { !$0.isExternalModel && !$0.isIronclawModel })?.id else {
            showBanner("No NEAR Private chat model is available on this account.")
            return false
        }
        selectedModel = replacement
        councilModelIDs = canUseInCouncil(replacement) ? [replacement] : []
        routeDidChangeHandler?()
        showBanner("Switched to \(modelDisplayName(for: replacement)).")
        return true
    }

    func selectModel(_ modelID: String) -> Bool {
        guard let model = pickerModels.first(where: {
            Self.model($0, matchesCandidateID: modelID)
        }) else {
            showBanner("That model is not available on this account.")
            return false
        }
        selectedModel = model.id
        councilModelIDs = isCouncilEligible(model) ? [model.id] : []
        routeDidChangeHandler?()
        return true
    }

    func setWebSearchEnabled(_ isEnabled: Bool) {
        webSearchEnabled = isEnabled
    }

    func setSourceMode(_ mode: ChatSourceMode) {
        sourceMode = mode
        if mode != .web, mode != .all {
            researchModeEnabled = false
        }
        if mode == .web || mode == .all {
            webSearchEnabled = true
        }
    }

    func setResearchModeEnabled(_ isEnabled: Bool) {
        researchModeEnabled = isEnabled
        if isEnabled {
            webSearchEnabled = true
        }
    }

    func ensureSelectedModelIsAvailable(shouldShowBanner: Bool) {
        guard !models.isEmpty else {
            return
        }
        let selectedModelCandidate = selectedModel
        guard pickerModels.contains(where: { Self.model($0, matchesCandidateID: selectedModelCandidate) }) else {
            guard let replacement = preferredAvailableModel() ?? pickerModels.first?.id else {
                return
            }
            let previousModel = selectedModelCandidate
            selectedModel = replacement
            normalizeCouncilSelection(shouldShowBanner: shouldShowBanner)
            routeDidChangeHandler?()
            if shouldShowBanner {
                showBanner("\(modelDisplayName(for: previousModel)) is not available on the \(currentBillingPlanName) plan. Switched to \(modelDisplayName(for: replacement)).")
            }
            return
        }
        normalizeCouncilSelection(shouldShowBanner: shouldShowBanner)
    }

    func routeToHostedIronclawIfNeeded(text: String, hostedIronclawAvailable: Bool) -> Bool {
        let routedModel = RoutePlanner.modelAfterHostedAutoRoute(
            selectedModelID: selectedModel,
            text: text,
            hostedIronclawAvailable: hostedIronclawAvailable
        )
        guard routedModel != selectedModel else { return false }
        selectedModel = routedModel
        routeDidChangeHandler?()
        showBanner("Switched to IronClaw because this prompt needs Hosted IronClaw tools.")
        return true
    }

    func routeToPrivateForNativeWebIfNeeded(
        text: String,
        shouldUseAppWebGrounding: Bool
    ) -> Bool {
        guard selectedModelOption?.isNearCloudModel == true,
              RoutePlanner.promptNeedsLiveWeb(text),
              !shouldUseAppWebGrounding,
              let privateModel = preferredAvailableModel() else {
            return false
        }
        selectedModel = privateModel
        routeDidChangeHandler?()
        showBanner("Switched to \(modelDisplayName(for: privateModel)) because this prompt needs NEAR Private web search.")
        return true
    }

    func preferredAvailableModel(excluding unavailableModel: String? = nil) -> String? {
        preferredAvailableModel(excluding: unavailableModel.map { Set([$0]) } ?? Set<String>())
    }

    /// The cloud privacy-proxy model offered when the private route is
    /// restricted. Requires a configured NEAR AI Cloud key (owned by the
    /// caller); never returns agent routes.
    func preferredPrivacyProxyModel(nearCloudKeyConfigured: Bool) -> String? {
        guard nearCloudKeyConfigured else { return nil }
        let cloudModels = pickerModels.filter { $0.isNearCloudModel && !$0.isDeprecatedPickerModel }
        return rankedModels(from: cloudModels).first?.id ?? cloudModels.first?.id
    }

    func preferredAvailableModel(excluding unavailableModels: Set<String>) -> String? {
        let availableModels = pickerModels.filter { !$0.isExternalModel }
        let availableIDs = Set(availableModels.map { Self.normalizedModelID($0.id) })
        let excludedIDs = Set(unavailableModels.map { Self.normalizedModelID($0) })
        let prioritizedIDs = preferredModelIDs + rankedModels(from: availableModels).map(\.id)

        return prioritizedIDs.first { modelID in
            let normalizedModelID = Self.normalizedModelID(modelID)
            return availableIDs.contains(normalizedModelID) &&
                !excludedIDs.contains(normalizedModelID)
        } ?? rankedModels(from: availableModels).first(where: {
            !excludedIDs.contains(Self.normalizedModelID($0.id))
        })?.id
    }

    func rankedModels(from source: [ModelOption]) -> [ModelOption] {
        source.sorted { lhs, rhs in
            let lhsRank = modelRank(lhs)
            let rhsRank = modelRank(rhs)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }


    private func modelRank(_ model: ModelOption) -> Int {
        let comparableIDs = Self.uniqueStrings([model.id, model.nearCloudUnderlyingModelID].compactMap { $0 })
        if model.isNearCloudModel,
           let cloudIndex = nearCloudPreferredModelIDs.firstIndex(where: { preferredID in
               comparableIDs.contains { $0.localizedCaseInsensitiveCompare(preferredID) == .orderedSame }
           }) {
            return cloudIndex
        }
        if let preferredIndex = preferredModelIDs.firstIndex(where: { preferredID in
            comparableIDs.contains { $0.localizedCaseInsensitiveCompare(preferredID) == .orderedSame }
        }) {
            return preferredIndex
        }
        if model.isEliteModel {
            return 100
        }
        if model.isRecommendedReasoningModel && !model.isLowerPriorityModel {
            return 200
        }
        if model.isPrivateVerifiableChatModel {
            return 300
        }
        if model.isLowerPriorityModel {
            return 1_000
        }
        return model.isAnthropicModel ? 450 : 500
    }

    func showBanner(_ message: String) {
        bannerHandler?(message)
    }

    private func persistSelectedModel() {
        guard shouldPersist else { return }
        settingsPersistence?.saveSelectedModelID(selectedModel)
    }

    private func persistCouncilModelIDs() {
        guard shouldPersist else { return }
        settingsPersistence?.saveCouncilModelIDs(councilModelIDs)
    }

    private func persistPinnedModelIDs() {
        guard shouldPersist else { return }
        settingsPersistence?.savePinnedModelIDs(pinnedModelIDs)
    }

    private func persistWebSearchEnabled() {
        guard shouldPersist else { return }
        settingsPersistence?.saveWebSearchEnabled(webSearchEnabled)
    }

    private func persistSourceMode() {
        guard shouldPersist else { return }
        settingsPersistence?.saveSourceMode(sourceMode)
    }

    private func persistResearchModeEnabled() {
        guard shouldPersist else { return }
        settingsPersistence?.saveResearchModeEnabled(researchModeEnabled)
    }


    private func repairedInitialModel(_ storedModel: String?, resolvedDefault: String) -> String {
        guard let storedModel,
              !storedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return resolvedDefault
        }
        guard let settingsPersistence,
              !settingsPersistence.defaults.bool(forKey: settingsPersistence.scopedDefaultsKey(Self.modelDefaultRepairMigrationKey)) else {
            return Self.canonicalModelID(for: storedModel)
        }
        settingsPersistence.defaults.set(true, forKey: settingsPersistence.scopedDefaultsKey(Self.modelDefaultRepairMigrationKey))
        if Self.deprecatedAutomaticDefaultModelIDs.contains(where: { $0.localizedCaseInsensitiveCompare(storedModel) == .orderedSame }) {
            return resolvedDefault
        }
        return Self.canonicalModelID(for: storedModel)
    }

}
