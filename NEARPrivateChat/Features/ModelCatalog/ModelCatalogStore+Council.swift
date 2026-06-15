import Foundation

extension ModelCatalogStore {
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
                    ["Qwen/Qwen3.5-122B-A10B", "Qwen/Qwen3.6-35B-A3B-FP8", "Qwen/Qwen3-30B-A3B-Instruct-2507"]
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
        if ids.count <= 1,
           canUseInCouncil(selectedModel),
           !ids.contains(where: { Self.modelIDsEquivalent($0, selectedModel) }) {
            ids = [selectedModel]
        }
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
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix(ModelOption.nearCloudModelPrefix) {
            return trimmed.count > ModelOption.nearCloudModelPrefix.count
        }
        return Self.canonicalModelAliases(for: ModelOption.nearPrivateDefaultModelID).contains {
            $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
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

    func isAllowedByCurrentPlan(_ model: ModelOption) -> Bool {
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

    static func normalizeAllowedModelIDs(_ allowedModelIDs: Set<String>?) -> Set<String> {
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

    static func allowedModelCandidates(for modelID: String) -> Set<String> {
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

    static func normalizedModelID(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
