import Foundation
import Combine

final class ModelCatalogStore: ObservableObject {
    static let defaultModelID = ModelOption.nearPrivateDefaultModelID
    static let maxCouncilModels = 3
    static let maxPinnedModels = 12

    static let preferredModelIDs = [
        ModelOption.nearPrivateDefaultModelID,
        "anthropic/claude-sonnet-4-6",
        "anthropic/claude-opus-4-6",
        "deepseek-ai/DeepSeek-V4-Flash",
        "Qwen/Qwen3.6-35B-A3B-FP8",
        "Qwen/Qwen3.6-27B-FP8",
        "zai-org/GLM-latest",
        "Qwen/Qwen3.5-122B-A10B",
        "Qwen/Qwen3-30B-A3B-Instruct-2507",
        "Qwen/Qwen3-VL-30B-A3B-Instruct",
        "moonshotai/Kimi-K2-Thinking",
        "moonshotai/Kimi-K2-Instruct",
        "MoonshotAI/Kimi-K2-Instruct",
        "deepseek-ai/DeepSeek-V3.2",
        "deepseek-ai/DeepSeek-V3.1",
        "deepseek-ai/DeepSeek-R1"
    ]
    static let nearCloudPreferredModelIDs: [String] = [
        "anthropic/claude-sonnet-4-6",
        "anthropic/claude-opus-4-6",
        "Qwen/Qwen3.6-35B-A3B-FP8",
        "Qwen/Qwen3.6-27B-FP8",
        "deepseek-ai/DeepSeek-V4-Flash",
        "Qwen/Qwen3.5-122B-A10B",
        "Qwen/Qwen3-30B-A3B-Instruct-2507",
        "zai-org/GLM-5.1-FP8"
    ]
    static let defaultCouncilCandidateGroups = [
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
    private var cachedActiveCouncilModels: [ModelOption]?
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

    var activeCouncilModels: [ModelOption] {
        if let cachedActiveCouncilModels { return cachedActiveCouncilModels }
        let resolved = normalizedCouncilModels(from: councilModelIDs)
        cachedActiveCouncilModels = resolved
        return resolved
    }

    /// O(1) selection lookups for the council picker: membership set + slot
    /// numbers, computed once per render instead of per row.
    func councilSelectionSnapshot() -> (ids: Set<String>, slots: [String: Int]) {
        let models = activeCouncilModels
        var slots: [String: Int] = [:]
        for (index, model) in models.enumerated() where slots[model.id] == nil {
            slots[model.id] = index
        }
        return (Set(models.map(\.id)), slots)
    }

    var maxCouncilModelCount: Int {
        Self.maxCouncilModels
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

    var councilCandidateModels: [ModelOption] {
        rankedModels(from: chatModels.filter(isCouncilEligible))
    }

    var councilPresets: [CouncilPresetOption] {
        [
            councilPreset(
                id: "balanced",
                title: "Balanced",
                subtitle: "Private proof plus frontier cloud diversity.",
                symbolName: "square.grid.2x2",
                candidateGroups: Self.defaultCouncilCandidateGroups,
                candidateModels: chatModels.filter(isCouncilEligible),
                fallbackModels: chatModels.filter(isCouncilEligible)
            ),
            councilPreset(
                id: "private-proof",
                title: "Private Proof",
                subtitle: "Only NEAR Private or open-weight private routes.",
                symbolName: "checkmark.shield.fill",
                candidateGroups: [
                    [ModelOption.nearPrivateDefaultModelID],
                    ["deepseek-ai/DeepSeek-V4-Flash"],
                    ["Qwen/Qwen3.5-122B-A10B", "Qwen/Qwen3.6-35B-A3B-FP8", "Qwen/Qwen3-30B-A3B-Instruct-2507"],
                    ["moonshotai/Kimi-K2-Thinking", "moonshotai/Kimi-K2-Instruct"],
                    ["deepseek-ai/DeepSeek-V3.2", "deepseek-ai/DeepSeek-V3.1", "deepseek-ai/DeepSeek-R1"]
                ],
                candidateModels: chatModels.filter { isCouncilEligible($0) && !$0.isExternalModel },
                fallbackModels: chatModels.filter { isCouncilEligible($0) && !$0.isExternalModel }
            ),
            councilPreset(
                id: "cloud-frontier",
                title: "Cloud models",
                subtitle: "External models available through NEAR AI Cloud.",
                symbolName: "cloud.fill",
                candidateGroups: [],
                candidateModels: cloudRouteModels.filter(isCouncilEligible),
                fallbackModels: cloudRouteModels
            ),
            councilPreset(
                id: "fast-scout",
                title: "Fast Scout",
                subtitle: "Lower-latency scan before deeper synthesis.",
                symbolName: "bolt.fill",
                candidateGroups: [
                    [ModelOption.nearPrivateDefaultModelID]
                ],
                candidateModels: chatModels.filter(isCouncilEligible),
                fallbackModels: chatModels.filter(isCouncilEligible)
            )
        ]
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

    func canUseInCouncil(_ modelID: String) -> Bool {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let model = chatModels.first(where: { Self.model($0, matchesCandidateID: trimmed) }) else {
            return canPreserveCouncilModelID(trimmed)
        }
        return isCouncilEligible(model)
    }

    func councilIndex(for modelID: String) -> Int? {
        return activeCouncilModels.firstIndex(where: {
            Self.model($0, matchesCandidateID: modelID)
        }).map { $0 + 1 }
    }

    func isPinnedModel(_ modelID: String) -> Bool {
        return pinnedModelIDs.contains { Self.modelIDsEquivalent($0, modelID) }
    }

    func togglePinnedModel(_ modelID: String) {
        guard let model = pickerModels.first(where: { Self.model($0, matchesCandidateID: modelID) }) else {
            showBanner("That model is not available on this account.")
            return
        }

        var ids = Self.uniqueStrings(pinnedModelIDs)
        if let index = ids.firstIndex(where: { Self.modelIDsEquivalent($0, modelID) }) {
            ids.remove(at: index)
            pinnedModelIDs = ids
            showBanner("Removed \(model.displayName) from pinned models.")
            return
        }

        guard ids.count < Self.maxPinnedModels else {
            showBanner("You can pin up to \(Self.maxPinnedModels) models.")
            return
        }
        ids.insert(model.id, at: 0)
        pinnedModelIDs = ids
        showBanner("Pinned \(model.displayName).")
    }

    func toggleCouncilModel(_ modelID: String) {
        guard let model = chatModels.first(where: {
            Self.model($0, matchesCandidateID: modelID)
        }), isCouncilEligible(model) else {
            showBanner("Council mode supports available NEAR Private and NEAR AI Cloud chat models.")
            return
        }

        var ids = normalizedCouncilModelIDs(councilModelIDs)
        if let index = ids.firstIndex(where: { Self.modelIDsEquivalent($0, modelID) }) {
            ids.remove(at: index)
            if ids.count == 1, selectedModel != ids[0] {
                selectedModel = ids[0]
            }
            councilModelIDs = ids
            let removalBanner = ids.count > 1 ? "Removed \(model.displayName) from the council." : "Council mode off."
            Task { @MainActor in
                self.routeDidChangeHandler?()
                self.showBanner(removalBanner)
            }
            return
        }

        if ids.isEmpty, canUseInCouncil(selectedModel) {
            ids.append(selectedModel)
        }
        guard ids.count < Self.maxCouncilModels else {
            showBanner("Council mode supports up to \(Self.maxCouncilModels) models at once.")
            return
        }
        ids.append(model.id)
        councilModelIDs = normalizedCouncilModelIDs(ids)
        if selectedModelOption?.isIronclawModel == true {
            selectedModel = councilModelIDs.first ?? modelID
        }
        let additionBanner = councilModelIDs.count > 1 ? "LLM Council enabled with \(councilModelIDs.count) models." : "Added \(model.displayName)."
        Task { @MainActor in
            self.routeDidChangeHandler?()
            self.showBanner(additionBanner)
        }
    }

    func useDefaultCouncilLineup() {
        let ids = defaultCouncilModelIDs()
        guard ids.count > 1 else {
            showBanner("No complete LLM Council lineup is available on this account.")
            return
        }
        councilModelIDs = ids
        selectedModel = ids[0]
        routeDidChangeHandler?()
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
        routeDidChangeHandler?()
        showBanner("\(preset.title) Council enabled with \(councilModelIDs.count) models.")
    }

    func clearCouncilMode() {
        councilModelIDs = canUseInCouncil(selectedModel) ? [selectedModel] : []
        routeDidChangeHandler?()
        showBanner("Council mode off.")
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

    func normalizeCouncilSelection(shouldShowBanner: Bool = false) {
        let originalIDs = councilModelIDs
        let normalized = normalizedCouncilModelIDs(councilModelIDs)
        let nextIDs: [String]
        if normalized.isEmpty, canUseInCouncil(selectedModel) {
            nextIDs = [selectedModel]
        } else {
            nextIDs = normalized
        }
        guard nextIDs != originalIDs else { return }
        councilModelIDs = nextIDs
        let removedCount = originalIDs.filter { !nextIDs.contains($0) }.count
        if shouldShowBanner, removedCount > 0 {
            let suffix = removedCount == 1 ? "model is" : "models are"
            showBanner("Council lineup updated: \(removedCount) \(suffix) no longer available.")
        }
    }

    func defaultCouncilModelIDs() -> [String] {
        let catalogBackedModels = Self.uniqueModels(models + cloudRouteModels)
            .filter(isCouncilEligible)
        guard !catalogBackedModels.isEmpty else {
            return []
        }
        let eligibleIDs = Set(chatModels.filter(isCouncilEligible).map { Self.normalizedModelID($0.id) })
        guard !eligibleIDs.isEmpty else {
            return []
        }
        var ids: [String] = []
        for group in Self.defaultCouncilCandidateGroups {
            if let modelID = group.first(where: { eligibleIDs.contains(Self.normalizedModelID($0)) }),
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

    func requestCouncilModelIDs(for requestModel: String) -> [String] {
        guard Self.normalizedModelID(requestModel) == Self.normalizedModelID(selectedModel),
              selectedModelOption?.isIronclawModel != true else {
            return []
        }
        var ids = normalizedCouncilModelIDs(councilModelIDs)
        // When the user hasn't built a lineup yet, seed it with the selected
        // model. But once they HAVE an explicit multi-model lineup, honor it
        // exactly — do NOT force-inject the selected model. Force-injecting was
        // adding GLM (the default selected model) to an all-cloud council the
        // user deliberately chose, and the maxCouncilModels cap then dropped
        // one of their picks.
        if ids.isEmpty, canUseInCouncil(requestModel) {
            ids = [requestModel]
        }
        return Array(ids.prefix(Self.maxCouncilModels))
    }

    func routeCouncilIfNeeded(for text: String) -> Bool {
        guard RoutePlanner.promptRequestsCouncil(text),
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
        routeDidChangeHandler?()
        showBanner("LLM Council selected for a multi-model answer.")
        return true
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

    func normalizedCouncilModelIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        let eligibleIDs = Set(chatModels.filter(isCouncilEligible).map { Self.normalizedModelID($0.id) })
        for modelID in ids {
            let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTrimmed = Self.normalizedModelID(trimmed)
            guard !trimmed.isEmpty, seen.insert(normalizedTrimmed).inserted else {
                continue
            }
            if eligibleIDs.isEmpty || eligibleIDs.contains(normalizedTrimmed) || canPreserveCouncilModelID(trimmed) {
                normalized.append(trimmed)
            }
            if normalized.count == Self.maxCouncilModels {
                break
            }
        }
        return normalized
    }

    func normalizedCouncilModels(from ids: [String]) -> [ModelOption] {
        let normalizedIDs = normalizedCouncilModelIDs(ids)
        return normalizedIDs.compactMap { modelID in
            if let model = chatModels.first(where: {
                Self.normalizedModelID($0.id) == Self.normalizedModelID(modelID) && isCouncilEligible($0)
            }) {
                return model
            }
            guard canPreserveCouncilModelID(modelID) else { return nil }
            return ModelOption(modelID: modelID, publicModel: true, metadata: nil)
        }
    }

    func isCouncilEligible(_ model: ModelOption) -> Bool {
        !model.isIronclawModel &&
            !model.isUtilityModel &&
            !model.isDeprecatedPickerModel &&
            isAllowedByCurrentPlan(model)
    }

    func canPreserveCouncilModelID(_ modelID: String) -> Bool {
        let route = RoutePlanner.routeKind(forModelID: modelID)
        return route == .nearPrivate || route == .nearCloud
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

    private func isAllowedByCurrentPlan(_ model: ModelOption) -> Bool {
        if model.isExternalModel {
            return true
        }
        if Self.normalizedModelID(model.id) == Self.normalizedModelID(ModelOption.nearPrivateDefaultModelID) {
            return true
        }
        guard let allowedModelIDs else {
            return true
        }
        return Self.allowedModelCandidates(for: model.id).contains {
            allowedModelIDs.contains($0)
        }
    }

    private static func normalizeAllowedModelIDs(_ allowedModelIDs: Set<String>?) -> Set<String> {
        guard let allowedModelIDs else { return Set<String>() }
        var normalized: Set<String> = []
        for rawID in allowedModelIDs {
            let normalizedID = normalizedModelID(rawID)
            guard !normalizedID.isEmpty else { continue }
            normalized.insert(normalizedID)

            if normalizedID == normalizedModelID(ModelOption.nearPrivateDefaultModelID) {
                for alias in canonicalModelAliases(for: ModelOption.nearPrivateDefaultModelID) {
                    normalized.insert(normalizedModelID(alias))
                }
            }
        }
        return normalized
    }

    private static func allowedModelCandidates(for modelID: String) -> Set<String> {
        var output: Set<String> = [normalizedModelID(modelID)]

        if let underlying = ModelOption(
            modelID: modelID,
            publicModel: true,
            metadata: nil
        ).nearCloudUnderlyingModelID {
            output.insert(normalizedModelID(underlying))
        }

        for alias in canonicalModelAliases(for: modelID) {
            output.insert(normalizedModelID(alias))
        }

        let defaultCanonical = canonicalModelID(for: modelID)
        if !defaultCanonical.isEmpty {
            output.insert(normalizedModelID(defaultCanonical))
        }

        return output
    }

    private static func normalizedModelID(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

    private func showBanner(_ message: String) {
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

    static func ironclawMobileModel() -> ModelOption {
        ModelOption(
            modelID: ModelOption.ironclawMobileModelID,
            publicModel: true,
            metadata: ModelOption.Metadata(
                verifiable: false,
                contextLength: nil,
                modelDisplayName: "IronClaw Mobile",
                modelDescription: "Runs an iOS-safe IronClaw runtime with NEAR Private inference, web search, attachments, projects, and optional Hosted IronClaw handoff for git/code/shell tasks.",
                modelIcon: nil,
                aliases: ["IronClaw", "mobile runtime", "agent", "iOS", "workstation", "git", "code"]
            )
        )
    }

    static func ironclawModel() -> ModelOption {
        ModelOption(
            modelID: ModelOption.ironclawModelID,
            publicModel: true,
            metadata: ModelOption.Metadata(
                verifiable: false,
                contextLength: nil,
                modelDisplayName: "Hosted IronClaw",
                modelDescription: "Connect Hosted IronClaw for git, code, shell, research, and software tasks.",
                modelIcon: nil,
                aliases: ["IronClaw", "Hosted IronClaw", "agent", "hosted endpoint", "workstation", "git", "code", "shell"]
            )
        )
    }

    static func fallbackNearCloudModels() -> [ModelOption] {
        []
    }

    static func fallbackPrivateModels() -> [ModelOption] {
        [
            ModelOption(
                modelID: ModelOption.nearPrivateDefaultModelID,
                publicModel: true,
                metadata: ModelOption.Metadata(
                    verifiable: true,
                    contextLength: nil,
                    modelDisplayName: "GLM 5.1",
                    modelDescription: "Default NEAR Private route with proof support.",
                    modelIcon: nil,
                    aliases: ["NEAR Private", "verified", "private", "GLM"]
                )
            ),
            ModelOption(
                modelID: "deepseek-ai/DeepSeek-V4-Flash",
                publicModel: true,
                metadata: ModelOption.Metadata(
                    verifiable: true,
                    contextLength: 1_048_576,
                    modelDisplayName: "DeepSeek V4 Flash",
                    modelDescription: "NEAR Private DeepSeek V4 Flash route with proof support.",
                    modelIcon: nil,
                    aliases: ["DeepSeek", "private", "reasoning", "fast", "TDX"]
                )
            ),
            ModelOption(
                modelID: "Qwen/Qwen3.5-122B-A10B",
                publicModel: true,
                metadata: ModelOption.Metadata(
                    verifiable: true,
                    contextLength: nil,
                    modelDisplayName: "Qwen3.5 122B A10B",
                    modelDescription: "NEAR Private open-weight reasoning route with proof support.",
                    modelIcon: nil,
                    aliases: ["Qwen", "private", "open-weight", "reasoning"]
                )
            ),
            ModelOption(
                modelID: "Qwen/Qwen3.6-35B-A3B-FP8",
                publicModel: true,
                metadata: ModelOption.Metadata(
                    verifiable: true,
                    contextLength: nil,
                    modelDisplayName: "Qwen 3.6 35B A3B FP8",
                    modelDescription: "NEAR Private open-weight fast reasoning route with proof support.",
                    modelIcon: nil,
                    aliases: ["Qwen", "private", "open-weight", "fast"]
                )
            ),
            ModelOption(
                modelID: "Qwen/Qwen3.6-27B-FP8",
                publicModel: true,
                metadata: ModelOption.Metadata(
                    verifiable: true,
                    contextLength: 262_144,
                    modelDisplayName: "Qwen 3.6 27B FP8",
                    modelDescription: "NEAR Private dense reasoning route with proof support.",
                    modelIcon: nil,
                    aliases: ["Qwen", "private", "open-weight", "reasoning"]
                )
            ),
            ModelOption(
                modelID: "Qwen/Qwen3-30B-A3B-Instruct-2507",
                publicModel: true,
                metadata: ModelOption.Metadata(
                    verifiable: true,
                    contextLength: 262_144,
                    modelDisplayName: "Qwen3 30B A3B Instruct 2507",
                    modelDescription: "NEAR Private instruction route with proof support.",
                    modelIcon: nil,
                    aliases: ["Qwen", "private", "open-weight", "instruct"]
                )
            ),
            ModelOption(
                modelID: "Qwen/Qwen3-VL-30B-A3B-Instruct",
                publicModel: true,
                metadata: ModelOption.Metadata(
                    verifiable: true,
                    contextLength: 256_000,
                    modelDisplayName: "Qwen3-VL-30B-A3B-Instruct",
                    modelDescription: "NEAR Private vision-language route with proof support.",
                    modelIcon: nil,
                    aliases: ["Qwen", "private", "open-weight", "vision"]
                )
            )
        ]
    }

    static func nearCloudRouteModels(from cloudModels: [ModelOption]) -> [ModelOption] {
        var seen = Set<String>()
        return cloudModels.compactMap { model in
            let cloudID = model.nearCloudUnderlyingModelID ?? model.id
            let normalizedID = cloudID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedID.isEmpty, seen.insert(normalizedID.lowercased()).inserted else {
                return nil
            }
            let aliases = uniqueStrings(["NEAR AI Cloud", "privacy proxy", "external model", normalizedID, model.displayName] + (model.metadata?.aliases ?? []))
            let description = model.metadata?.modelDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
            let routeDescription = description?.isEmpty == false
                ? "\(description!) Routes through NEAR AI Cloud with privacy proxy forwarding."
                : "Routes \(model.displayName) through NEAR AI Cloud with privacy proxy forwarding."
            return ModelOption(
                modelID: nearCloudRouteModelID(for: normalizedID),
                publicModel: model.publicModel,
                metadata: ModelOption.Metadata(
                    verifiable: false,
                    contextLength: model.metadata?.contextLength,
                    modelDisplayName: model.displayName,
                    modelDescription: routeDescription,
                    modelIcon: model.metadata?.modelIcon,
                    aliases: aliases
                )
            )
        }
    }

    static func uniqueModels(_ models: [ModelOption]) -> [ModelOption] {
        var seen = Set<String>()
        var output: [ModelOption] = []
        for model in models {
            let key = (model.nearCloudUnderlyingModelID ?? model.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else {
                continue
            }
            output.append(model)
        }
        return output
    }

    static func model(_ model: ModelOption, matchesCandidateID candidateID: String) -> Bool {
        let candidate = candidateID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return false }
        let comparableIDs = uniqueStrings(
            [model.id, model.nearCloudUnderlyingModelID].compactMap { $0 } +
                canonicalModelAliases(for: model.id)
        )
        return comparableIDs.contains { $0.localizedCaseInsensitiveCompare(candidate) == .orderedSame }
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

    private static func canonicalModelID(for modelID: String) -> String {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedModelID(trimmed) == normalizedModelID(Self.defaultModelID) {
            return Self.defaultModelID
        }
        if canonicalModelAliases(for: Self.defaultModelID).contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            return Self.defaultModelID
        }
        return trimmed
    }

    private static func modelIDsEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return false
        }
        return Self.model(ModelOption(modelID: lhs, publicModel: true, metadata: nil), matchesCandidateID: rhs) ||
            Self.model(ModelOption(modelID: rhs, publicModel: true, metadata: nil), matchesCandidateID: lhs) ||
            Self.normalizedModelID(lhs) == Self.normalizedModelID(rhs)
    }

    private static func canonicalModelAliases(for modelID: String) -> [String] {
        if modelID.localizedCaseInsensitiveCompare(ModelOption.nearPrivateDefaultModelID) == .orderedSame ||
            modelID.localizedCaseInsensitiveCompare("zai-org/GLM-latest") == .orderedSame {
            return ["zai-org/GLM-latest"]
        }
        return []
    }

    private static func nearCloudRouteModelID(for cloudModelID: String) -> String {
        let normalized = cloudModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return ModelOption.nearCloudModelID(for: normalized)
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
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
}
