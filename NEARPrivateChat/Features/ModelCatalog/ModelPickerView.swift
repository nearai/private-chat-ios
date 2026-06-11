import SwiftUI

struct ModelPickerView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var modelCatalogStore: ModelCatalogStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedTab: ModelPickerTab = .models
    private let onOpenNearCloudKeys: (() -> Void)?

    private enum ModelPickerTab: String, CaseIterable, Identifiable {
        case models = "Models"
        case council = "Council"

        var id: String { rawValue }
    }

    init(openingCouncil: Bool = false, onOpenNearCloudKeys: (() -> Void)? = nil) {
        _selectedTab = State(initialValue: openingCouncil ? .council : .models)
        self.onOpenNearCloudKeys = onOpenNearCloudKeys
    }

    // MARK: - Computed pickers

    private var allPickerModels: [ModelOption] {
        Self.routeDistinctPickerModels(modelCatalogStore.pickerModels)
    }

    static func routeDistinctPickerModels(_ models: [ModelOption]) -> [ModelOption] {
        var seenIDs = Set<String>()
        var output: [ModelOption] = []
        for model in models {
            let key = model.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, seenIDs.insert(key).inserted else { continue }
            output.append(model)
        }
        return output
    }

    private var defaultPrivateModel: ModelOption? {
        allPickerModels.first(where: { isDefaultPrivateModel($0) }) ??
            allPickerModels.first(where: { $0.isPrivateVerifiableChatModel })
    }

    private var primaryPrivateModels: [ModelOption] {
        let defaultID = defaultPrivateModel?.id
        let privateAlternatives = modelCatalogStore.rankedModels(
            from: allPickerModels.filter { model in
                model.id != defaultID &&
                    !model.isExternalModel &&
                    !model.isIronclawModel &&
                    model.isPrivateVerifiableChatModel &&
                    model.isRecommendedReasoningModel &&
                    !model.isLowerPriorityModel
            }
        )
        return ModelCatalogStore.uniqueModels(([defaultPrivateModel].compactMap { $0 }) + Array(privateAlternatives.prefix(1)))
    }

    private var reasoningChoices: [ModelOption] {
        let primaryIDs = Set(primaryPrivateModels.map(\.id))
        let choices = allPickerModels.filter { model in
            !primaryIDs.contains(model.id) &&
                model.isRecommendedReasoningModel &&
                !model.isNearCloudModel &&
                !model.isIronclawModel &&
                !model.isLowerPriorityModel
        }
        return Array(choices.prefix(2))
    }

    private var privateModelChoices: [ModelOption] {
        let shownIDs = Set(primaryPrivateModels.map(\.id) + reasoningChoices.map(\.id))
        let choices = allPickerModels.filter { model in
            !shownIDs.contains(model.id) &&
                !model.isExternalModel &&
                !model.isIronclawModel &&
                model.id != ModelOption.llmCouncilSynthesisModelID
        }
        return modelCatalogStore.rankedModels(from: choices)
    }

    private var agentChoices: [ModelOption] {
        let availableIDs = Set(allPickerModels.map(\.id))
        return modelCatalogStore.agentModels.filter { availableIDs.contains($0.id) }
    }

    private var cloudModelChoices: [ModelOption] {
        modelCatalogStore.rankedModels(from: allPickerModels.filter { $0.isNearCloudModel })
    }

    private var primaryCloudModels: [ModelOption] {
        guard chatStore.nearCloudKeyConfigured else { return [] }
        return Array(cloudModelChoices.prefix(2))
    }

    private var councilPrivateCandidates: [ModelOption] {
        ModelCatalogStore.uniqueModels(modelCatalogStore.councilCandidateModels.filter { !$0.isExternalModel })
    }

    private var councilCloudCandidates: [ModelOption] {
        ModelCatalogStore.uniqueModels(modelCatalogStore.councilCandidateModels.filter { $0.isNearCloudModel })
    }

    private var selectedSingleModelID: String? {
        modelCatalogStore.isCouncilModeEnabled ? nil : modelCatalogStore.selectedModel
    }

    private func isSelectedSingleModel(_ model: ModelOption) -> Bool {
        guard let selectedSingleModelID else { return false }
        return ModelCatalogStore.model(model, matchesCandidateID: selectedSingleModelID)
    }

    private func modelRowTrailing(for model: ModelOption) -> ModelSpecTrailing {
        isSelectedSingleModel(model) ? .checkmark : .none
    }

    private func modelRowTitle(for model: ModelOption, defaultTitle: String? = nil) -> String {
        return defaultTitle ?? model.displayName
    }

    private func modelRowBadges(for model: ModelOption, prefix: String? = nil) -> [String] {
        var badges = model.routeDisclosureBadges
        if let prefix {
            badges.insert(prefix, at: 0)
        }
        return Array(badges.prefix(3))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Picker("Model picker mode", selection: $selectedTab) {
                        ForEach(ModelPickerTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Model picker section")
                    .accessibilityHint("Switches between single model routes and Council lineups.")
                    .accessibilityIdentifier("modelPicker.modeTabs")
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 16)

                    activeRouteSummaryCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 18)

                    if selectedTab == .models {
                        modelsTab
                    } else {
                        councilTab
                    }
                }
                .padding(.bottom, 34)
            }
            .background(Color.appBackground)
            .navigationTitle(selectedTab == .models ? "Model" : "Council")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await chatStore.refreshModels(loadCloudCatalog: chatStore.nearCloudKeyConfigured)
            }
        }
        .platformLargeDetent()
    }

    // MARK: - Models tab

    private var activeRouteSummaryCard: some View {
        let summary = activeRouteSummary
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: summary.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(summary.tint)
                .frame(width: 30, height: 30)
                .background(summary.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(summary.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(summary.detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !summary.badges.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(summary.badges, id: \.self) { badge in
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                                .padding(.horizontal, 7)
                                .frame(height: 20)
                                .background(Color.appSecondaryBackground, in: Capsule())
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 0.5)
        }
    }

    private var activeRouteSummary: (title: String, detail: String, badges: [String], symbolName: String, tint: Color) {
        if modelCatalogStore.isCouncilModeEnabled {
            let count = max(modelCatalogStore.activeCouncilModels.count, modelCatalogStore.defaultCouncilModels.count)
            let proof = modelCatalogStore.activeCouncilHasExternalRoutes ? "Mixed proof" : "Proof when fetched"
            return (
                "Council",
                "\(max(count, 2)) models answer independently. The app synthesizes one result.",
                ["Multiple models", proof],
                "person.3.fill",
                Color.routeCouncil
            )
        }

        switch modelCatalogStore.selectedRouteKind {
        case .nearPrivate:
            return (
                "NEAR Private",
                "Private route. Fetch a proof report to see route and model Attestation for this model.",
                ["Proof when fetched", "Private route"],
                "lock.shield.fill",
                Color.proofVerified
            )
        case .nearCloud:
            return (
                "NEAR AI Cloud",
                "External model. Routed through NEAR AI Cloud over the privacy proxy.",
                ["Privacy proxy", "External model"],
                "cloud.fill",
                Color.routeCloud
            )
        case .ironclawMobile:
            return (
                "IronClaw Mobile",
                "On-device Agent for small local tasks. Outside NEAR Private proof.",
                ["IronClaw Mobile", "Outside proof"],
                "iphone",
                Color.routeAgent
            )
        case .ironclawHosted:
            return (
                "Hosted IronClaw",
                "Hosted IronClaw. Prompt text leaves the phone. File bytes stay unless you include excerpts.",
                ["Hosted IronClaw", "File names only"],
                "terminal.fill",
                Color.proofStale
            )
        }
    }

    @ViewBuilder
    private var modelsTab: some View {
        VStack(alignment: .leading, spacing: 22) {
            // SINGLE ROUTE
            ModelSpecSection(
                title: "Single Model Route",
                subtitle: "Private is always available. Cloud routes need a NEAR AI Cloud key."
            ) {
                ForEach(Array(primaryPrivateModels.enumerated()), id: \.element.id) { index, model in
                    ModelSpecRow(
                        symbolName: "cpu",
                        symbolColor: Color.actionPrimary,
                        title: modelRowTitle(for: model),
                        subtitle: index == 0
                            ? "NEAR Private model · one answer with proof support."
                            : privateModelSubtitle(for: model),
                        badges: model.routeDisclosureBadges,
                        trailing: modelRowTrailing(for: model),
                        isSelected: isSelectedSingleModel(model),
                        showsDivider: index != primaryPrivateModels.count - 1 || !primaryCloudModels.isEmpty || !chatStore.nearCloudKeyConfigured,
                        action: { selectModelAndDismiss(model) }
                    )
                }

                if !primaryCloudModels.isEmpty {
                    ForEach(Array(primaryCloudModels.enumerated()), id: \.element.id) { index, model in
                        ModelSpecRow(
                            symbolName: "cloud.fill",
                            symbolColor: Color.routeCloud,
                            title: modelRowTitle(for: model),
                            subtitle: "NEAR AI Cloud model · one external answer through the privacy proxy.",
                            badges: model.routeDisclosureBadges,
                            trailing: modelRowTrailing(for: model),
                            isSelected: isSelectedSingleModel(model),
                            showsDivider: index != primaryCloudModels.count - 1,
                            action: { selectModelAndDismiss(model) }
                        )
                    }
                } else if !chatStore.nearCloudKeyConfigured {
                    ModelSpecRow(
                        symbolName: "cloud",
                        symbolColor: Color.textSecondary,
                        title: "Connect NEAR AI Cloud",
                        subtitle: "Add a Cloud key to select external single-model routes.",
                        badges: ["Privacy proxy", "External models"],
                        trailing: .chevron,
                        isSelected: false,
                        showsDivider: false,
                        action: connectOrOpenNearCloud
                    )
                }
            }

            // REASONING
            if !reasoningChoices.isEmpty {
                ModelSpecSection(title: "Reasoning") {
                    ForEach(Array(reasoningChoices.enumerated()), id: \.element.id) { index, model in
                        ModelSpecRow(
                            symbolName: "sparkles",
                            symbolColor: Color.textSecondary,
                            title: modelRowTitle(for: model),
                            subtitle: reasoningSubtitle(for: model, index: index),
                            badges: modelRowBadges(for: model, prefix: index == 0 ? "Expert" : "Heavy"),
                            trailing: modelRowTrailing(for: model),
                            isSelected: isSelectedSingleModel(model),
                            showsDivider: index != reasoningChoices.count - 1,
                            action: { selectModelAndDismiss(model) }
                        )
                    }
                }
            }

            if !privateModelChoices.isEmpty {
                ModelSpecSection(
                    title: "Private Models",
                    subtitle: "Available without Cloud keys or Agent setup."
                ) {
                    ForEach(Array(privateModelChoices.enumerated()), id: \.element.id) { index, model in
                        ModelSpecRow(
                            symbolName: model.isOpenWeightCandidate ? "shippingbox" : "cpu",
                            symbolColor: Color.textSecondary,
                            title: modelRowTitle(for: model),
                            subtitle: privateModelSubtitle(for: model),
                            badges: model.routeDisclosureBadges,
                            trailing: modelRowTrailing(for: model),
                            isSelected: isSelectedSingleModel(model),
                            showsDivider: index != privateModelChoices.count - 1,
                            action: { selectModelAndDismiss(model) }
                        )
                    }
                }
            }

            if !agentChoices.isEmpty {
                ModelSpecSection(
                    title: "Agents",
                    subtitle: "Phone-safe Agent can run locally; hosted repo, shell, and code tasks require Hosted IronClaw setup."
                ) {
                    ForEach(Array(agentChoices.enumerated()), id: \.element.id) { index, model in
                        ModelSpecRow(
                            symbolName: model.isIronclawMobileRuntime ? "iphone" : "terminal",
                            symbolColor: Color.textSecondary,
                            title: modelRowTitle(for: model),
                            subtitle: agentSubtitle(for: model),
                            badges: model.routeDisclosureBadges,
                            trailing: modelRowTrailing(for: model),
                            isSelected: isSelectedSingleModel(model),
                            showsDivider: index != agentChoices.count - 1,
                            action: { selectModelAndDismiss(model) }
                        )
                    }
                }
            }

            // NEAR CLOUD
            ModelSpecSection(
                title: "NEAR AI Cloud",
                subtitle: chatStore.nearCloudKeyConfigured
                    ? "Cloud routes are connected through the privacy proxy."
                    : "Requires a Cloud key before external models can answer."
            ) {
                ModelSpecRow(
                    symbolName: chatStore.nearCloudKeyConfigured ? "cloud.fill" : "cloud",
                    symbolColor: Color.textSecondary,
                    title: chatStore.nearCloudKeyConfigured ? "Connected" : "Add Cloud key in Account",
                    subtitle: chatStore.nearCloudKeyConfigured
                        ? "Refresh catalog or open account"
                        : "Use the in-app key panel to unlock external models",
                    badges: ["Privacy proxy", "External models"],
                    trailing: .chevron,
                    isSelected: false,
                    showsDivider: false,
                    action: connectOrOpenNearCloud
                )
            }

            // CLOUD MODELS
            if chatStore.nearCloudKeyConfigured && !cloudModelChoices.isEmpty {
                ModelSpecSection(
                    title: "Cloud Models",
                    subtitle: "External model answers use NEAR AI Cloud through the privacy proxy."
                ) {
                    ForEach(Array(cloudModelChoices.enumerated()), id: \.element.id) { index, model in
                        ModelSpecRow(
                            symbolName: "cpu",
                            symbolColor: Color.textSecondary,
                            title: modelRowTitle(for: model),
                            subtitle: cloudModelSubtitle(for: model),
                            badges: model.routeDisclosureBadges,
                            trailing: modelRowTrailing(for: model),
                            isSelected: isSelectedSingleModel(model),
                            showsDivider: index != cloudModelChoices.count - 1,
                            action: { selectModelAndDismiss(model) }
                        )
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cloud Models".uppercased())
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 16)
                    Text(chatStore.nearCloudKeyConfigured ? "No Cloud models returned for this account yet." : "Connect NEAR AI Cloud to browse external models on your account.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 18)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.appHairline, lineWidth: 0.5)
                        }
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Council tab

    private var councilTab: some View {
        let lineup = councilDisplayLineup()
        let isActive = modelCatalogStore.isCouncilModeEnabled

        return VStack(alignment: .leading, spacing: 22) {
            councilCandidatesSection

            ModelSpecSection(
                title: isActive ? "Active Council" : "Recommended Council",
                subtitle: "Needs at least two available models. Cloud members require a Cloud key; hosted Agent members require setup."
            ) {
                if lineup.isEmpty {
                    ModelSpecRow(
                        symbolName: "person.3",
                        symbolColor: Color.textSecondary,
                        title: "Council unavailable",
                        subtitle: "Needs two or more chat models",
                        badges: ["2-3 models", "Route varies"],
                        trailing: .none,
                        isSelected: false,
                        showsDivider: false,
                        action: {}
                    )
                } else {
                    ForEach(Array(lineup.enumerated()), id: \.element.id) { index, model in
                        CouncilNumberedRow(
                            number: index + 1,
                            title: modelRowTitle(for: model),
                            subtitle: councilSubtitle(for: model, index: index),
                            showsDivider: index != lineup.count - 1
                        )
                    }
                }
            }

            VStack(spacing: 10) {
                Button {
                    if isActive {
                        modelCatalogStore.clearCouncilMode()
                    } else {
                        modelCatalogStore.useDefaultCouncilLineup()
                    }
                    dismiss()
                } label: {
                    Text(isActive ? "Turn off Council" : "Use recommended Council")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(Color.white)
                        .background(Color.actionPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(lineup.count < 2 && !isActive)
                .opacity(lineup.count < 2 && !isActive ? 0.4 : 1)
            }
            .padding(.horizontal, 16)

            if !modelCatalogStore.councilPresets.isEmpty {
                ModelSpecSection(title: "Presets") {
                    let presets = modelCatalogStore.councilPresets
                    ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                        ModelSpecRow(
                            symbolName: presetSymbol(for: preset),
                            symbolColor: preset.isAvailable ? Color.textSecondary : Color.textTertiary,
                            title: preset.title,
                            subtitle: preset.isAvailable ? preset.previewNames : "Some models unavailable",
                            badges: ["Council", "Route varies"],
                            trailing: .chevron,
                            isSelected: false,
                            showsDivider: index != presets.count - 1,
                            isEnabled: preset.isAvailable,
                            action: {
                                modelCatalogStore.useCouncilPreset(preset.id)
                                dismiss()
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func councilDisplayLineup() -> [ModelOption] {
        let active = modelCatalogStore.activeCouncilModels
        if active.count > 1 {
            return Array(active.prefix(4))
        }
        return Array(modelCatalogStore.defaultCouncilModels.prefix(4))
    }

    private func councilSubtitle(for model: ModelOption, index: Int) -> String {
        let suffix = index == 0 ? "Primary answer" : "Independent comparison"
        return "\(model.routeDisclosureBadges.prefix(2).joined(separator: " · ")) · \(suffix)"
    }

    private func presetSymbol(for preset: CouncilPresetOption) -> String {
        if !preset.symbolName.isEmpty { return preset.symbolName }
        return "person.3"
    }

    private func isDefaultPrivateModel(_ model: ModelOption) -> Bool {
        model.id.localizedCaseInsensitiveCompare(ModelOption.nearPrivateDefaultModelID) == .orderedSame ||
            model.displayName.localizedCaseInsensitiveContains("NEAR Private")
    }

    private func reasoningSubtitle(for model: ModelOption, index: Int) -> String {
        if let description = compactCatalogDescription(for: model) {
            return description
        }
        return index == 0 ? "Multi-step reasoning, slower." : "Deeper analysis for hard prompts."
    }

    private func privateModelSubtitle(for model: ModelOption) -> String {
        if let description = compactCatalogDescription(for: model) {
            return description
        }
        if model.isOpenWeightCandidate {
            return "Open-weight private route."
        }
        return model.isPrivateVerifiableChatModel ? "Private route with proof support." : "Private chat model."
    }

    private func agentSubtitle(for model: ModelOption) -> String {
        if model.isIronclawHostedModel, !chatStore.ironclawRemoteWorkstationAvailable {
            if !chatStore.ironclawSettings.hasUsableHostedEndpoint {
                return chatStore.ironclawSettings.endpointValidationMessage ?? "Add a Hosted IronClaw URL before sending."
            }
            if !chatStore.ironclawTokenConfigured {
                return "Hosted URL saved. Add an Agent token before sending hosted tasks."
            }
            return "Turn on Hosted IronClaw in Account before sending hosted tasks."
        }
        if let description = compactCatalogDescription(for: model) {
            return description
        }
        return model.isIronclawMobileRuntime
            ? "Local agent route for phone-safe tasks."
            : "Hosted agent route for code, shell, and repo tasks."
    }

    private func cloudModelSubtitle(for model: ModelOption) -> String {
        if let description = compactCatalogDescription(for: model) {
            return description
        }
        return "\(providerLabel(for: model)) via NEAR AI Cloud"
    }

    @ViewBuilder
    private var councilCandidatesSection: some View {
        ModelSpecSection(
            title: "Choose Council Models",
            subtitle: "Private candidates are available now; Cloud and Agent candidates depend on their setup state."
        ) {
            Text(councilSelectionStatusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appSecondaryBackground.opacity(0.72))
        }

        if !councilPrivateCandidates.isEmpty {
            councilCandidateGroupSection(
                title: "NEAR Private Council Models",
                candidates: Array(councilPrivateCandidates.prefix(6))
            )
        }

        if !councilCloudCandidates.isEmpty {
            councilCandidateGroupSection(
                title: "NEAR AI Cloud Council Models",
                candidates: Array(councilCloudCandidates.prefix(8))
            )
        } else {
            ModelSpecSection(
                title: "NEAR AI Cloud Council Models",
                subtitle: chatStore.nearCloudKeyConfigured
                    ? "Cloud Council members can answer through the privacy proxy."
                    : "Add a Cloud key before Cloud Council members can answer."
            ) {
                ModelSpecRow(
                    symbolName: chatStore.nearCloudKeyConfigured ? "cloud.fill" : "cloud",
                    symbolColor: Color.textSecondary,
                    title: chatStore.nearCloudKeyConfigured ? "Refresh NEAR AI Cloud" : "Connect NEAR AI Cloud",
                    subtitle: chatStore.nearCloudKeyConfigured
                        ? "No Cloud Council models are available yet."
                        : "Add a Cloud key to include external Council models.",
                    badges: ["Privacy proxy", "External models"],
                    trailing: .chevron,
                    isSelected: false,
                    showsDivider: false,
                    action: connectOrOpenNearCloud
                )
            }
        }
    }

    private func councilCandidateGroupSection(title: String, candidates: [ModelOption]) -> some View {
        ModelSpecSection(title: title) {
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, model in
                councilCandidateRow(
                    model: model,
                    showsDivider: index != candidates.count - 1
                )
            }
        }
    }

    private func councilCandidateRow(model: ModelOption, showsDivider: Bool) -> some View {
        councilCandidateRow(model: model, showsDivider: showsDivider, snapshot: modelCatalogStore.councilSelectionSnapshot())
    }

    private func councilCandidateRow(
        model: ModelOption,
        showsDivider: Bool,
        snapshot: (ids: Set<String>, slots: [String: Int])
    ) -> some View {
        let isSelected = snapshot.ids.contains(model.id)
        let isEnabled = isSelected || snapshot.ids.count < modelCatalogStore.maxCouncilModelCount
        return ModelSpecRow(
            symbolName: isSelected ? "checkmark.circle.fill" : "plus.circle",
            symbolColor: isSelected ? Color.actionPrimary : (model.isNearCloudModel ? Color.routeCloud : Color.textSecondary),
            title: modelRowTitle(for: model),
            subtitle: manualCouncilSubtitle(for: model),
            badges: model.routeDisclosureBadges,
            trailing: isSelected ? .checkmark : .none,
            isSelected: isSelected,
            showsDivider: showsDivider,
            isEnabled: isEnabled,
            action: { modelCatalogStore.toggleCouncilModel(model.id) }
        )
        .accessibilityIdentifier("council.candidate.\(model.id)")
    }

    private func manualCouncilSubtitle(for model: ModelOption) -> String {
        if let index = modelCatalogStore.councilIndex(for: model.id) {
            return "Council slot \(index)"
        }
        if modelCatalogStore.activeCouncilModels.count >= modelCatalogStore.maxCouncilModelCount {
            return "Remove a model to add this one"
        }
        return "Add to Council"
    }

    private var councilSelectionStatusText: String {
        "\(modelCatalogStore.activeCouncilModels.count) selected · 2 required · \(modelCatalogStore.maxCouncilModelCount) max"
    }

    private func compactCatalogDescription(for model: ModelOption) -> String? {
        guard let raw = model.metadata?.modelDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        let firstSentence = raw.split(separator: ".", maxSplits: 1).first.map(String.init) ?? raw
        return String(firstSentence.prefix(90))
    }

    private func providerLabel(for model: ModelOption) -> String {
        let id = (model.nearCloudUnderlyingModelID ?? model.id)
            .split(separator: "/")
            .first
            .map(String.init) ?? "External model"
        return ModelOption.humanize(modelID: id)
    }

    private func selectModelAndDismiss(_ model: ModelOption) {
        _ = modelCatalogStore.selectModel(model.id)
        dismiss()
    }

    private func connectOrOpenNearCloud() {
        if chatStore.nearCloudKeyConfigured {
            openNearCloudSignup()
            Task { _ = await chatStore.connectNearCloudAccount() }
            return
        }

        if let onOpenNearCloudKeys {
            dismiss()
            DispatchQueue.main.async {
                onOpenNearCloudKeys()
            }
        } else {
            openNearCloudSignup()
        }
    }

    private func openNearCloudSignup() {
        guard let url = URL(string: "https://cloud.near.ai") else { return }
        openURL(url)
    }
}
