import SwiftUI

struct ModelPickerView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var modelCatalogStore: ModelCatalogStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedTab: ModelPickerTab = .models

    private enum ModelPickerTab: String, CaseIterable, Identifiable {
        case models = "Models"
        case council = "Council"

        var id: String { rawValue }
    }

    init(openingCouncil: Bool = false) {
        _selectedTab = State(initialValue: openingCouncil ? .council : .models)
    }

    // MARK: - Computed pickers

    private var allPickerModels: [ModelOption] {
        modelCatalogStore.pickerModels
    }

    private var defaultPrivateModel: ModelOption? {
        allPickerModels.first(where: { isDefaultPrivateModel($0) }) ??
            allPickerModels.first(where: { $0.isPrivateVerifiableChatModel })
    }

    private var reasoningChoices: [ModelOption] {
        let defaultID = defaultPrivateModel?.id
        let choices = allPickerModels.filter { model in
            model.id != defaultID &&
                model.isRecommendedReasoningModel &&
                !model.isNearCloudModel &&
                !model.isIronclawModel &&
                !model.isLowerPriorityModel
        }
        return Array(choices.prefix(2))
    }

    private var privateModelChoices: [ModelOption] {
        let shownIDs = Set(([defaultPrivateModel?.id].compactMap { $0 }) + reasoningChoices.map(\.id))
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

    private var selectedSingleModelID: String? {
        modelCatalogStore.isCouncilModeEnabled ? nil : modelCatalogStore.selectedModel
    }

    private func isSelectedSingleModel(_ model: ModelOption) -> Bool {
        selectedSingleModelID == model.id
    }

    private func modelRowTrailing(for model: ModelOption) -> ModelSpecTrailing {
        isSelectedSingleModel(model) ? .checkmark : .none
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
                Color.brandBlue
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
                Color.brandBlue
            )
        case .ironclawMobile:
            return (
                "IronClaw Mobile",
                "On-device Agent for small local tasks. Outside NEAR Private proof.",
                ["IronClaw Mobile", "Outside proof"],
                "iphone",
                Color.brandBlue
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
            // DEFAULT
            ModelSpecSection(title: "Default") {
                if let model = defaultPrivateModel {
                    ModelSpecRow(
                        symbolName: "cpu",
                        symbolColor: Color.actionPrimary,
                        title: model.displayName,
                        subtitle: "Private inference. Proof when fetched.",
                        badges: model.routeDisclosureBadges,
                        trailing: modelRowTrailing(for: model),
                        isSelected: isSelectedSingleModel(model),
                        showsDivider: false,
                        action: { selectModelAndDismiss(model) }
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
                            title: model.displayName,
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
                ModelSpecSection(title: "Private Models") {
                    ForEach(Array(privateModelChoices.enumerated()), id: \.element.id) { index, model in
                        ModelSpecRow(
                            symbolName: model.isOpenWeightCandidate ? "shippingbox" : "cpu",
                            symbolColor: Color.textSecondary,
                            title: model.displayName,
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
                ModelSpecSection(title: "Agents") {
                    ForEach(Array(agentChoices.enumerated()), id: \.element.id) { index, model in
                        ModelSpecRow(
                            symbolName: model.isIronclawMobileRuntime ? "iphone" : "terminal",
                            symbolColor: Color.textSecondary,
                            title: model.displayName,
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
            ModelSpecSection(title: "NEAR AI Cloud") {
                ModelSpecRow(
                    symbolName: chatStore.nearCloudKeyConfigured ? "cloud.fill" : "cloud",
                    symbolColor: Color.textSecondary,
                    title: chatStore.nearCloudKeyConfigured ? "Connected" : "Connect NEAR AI Cloud",
                    subtitle: chatStore.nearCloudKeyConfigured
                        ? "Refresh catalog or open account"
                        : "Add your key to use external models",
                    badges: ["Privacy proxy", "External models"],
                    trailing: .chevron,
                    isSelected: false,
                    showsDivider: false,
                    action: connectOrOpenNearCloud
                )
            }

            // CLOUD MODELS
            if chatStore.nearCloudKeyConfigured && !cloudModelChoices.isEmpty {
                ModelSpecSection(title: "Cloud Models") {
                    ForEach(Array(cloudModelChoices.enumerated()), id: \.element.id) { index, model in
                        ModelSpecRow(
                            symbolName: "cpu",
                            symbolColor: Color.textSecondary,
                            title: model.displayName,
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
            ModelSpecSection(title: isActive ? "Active Council" : "Recommended Council") {
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
                            title: model.displayName,
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

	            councilCandidatesSection

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
        model.id == ModelOption.nearPrivateDefaultModelID ||
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
        let candidates = Array(modelCatalogStore.councilCandidateModels.prefix(8))
        if !candidates.isEmpty {
            ModelSpecSection(title: "Choose Models") {
                Text(councilSelectionStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSecondaryBackground.opacity(0.72))

                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, model in
                    let isSelected = modelCatalogStore.councilIndex(for: model.id) != nil
                    let isEnabled = isSelected || modelCatalogStore.activeCouncilModels.count < modelCatalogStore.maxCouncilModelCount
                    ModelSpecRow(
                        symbolName: isSelected ? "checkmark.circle.fill" : "plus.circle",
                        symbolColor: isSelected ? Color.actionPrimary : Color.textSecondary,
                        title: model.displayName,
                        subtitle: manualCouncilSubtitle(for: model),
                        badges: model.routeDisclosureBadges,
                        trailing: isSelected ? .checkmark : .none,
                        isSelected: isSelected,
                        showsDivider: index != candidates.count - 1,
                        isEnabled: isEnabled,
                        action: { modelCatalogStore.toggleCouncilModel(model.id) }
                    )
                }
            }
        }
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
        // Always open the NEAR AI Cloud web page. Previously the
        // unconnected path called `connectNearCloudAccount()` (an
        // authenticated API request) which silently failed when the
        // session token couldn't reach the server — leaving the user
        // tapping with no visible result. Opening the web flow gives
        // them a concrete path to manage their cloud key in every
        // state.
        openNearCloudSignup()
        if chatStore.nearCloudKeyConfigured {
            Task { _ = await chatStore.connectNearCloudAccount() }
        }
    }

    private func openNearCloudSignup() {
        guard let url = URL(string: "https://cloud.near.ai") else { return }
        openURL(url)
    }
}

// MARK: - Components

private struct ModelSpecSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                content
            }
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 0.5)
            }
            .padding(.horizontal, 16)
        }
    }
}

private enum ModelSpecTrailing {
    case none
    case checkmark
    case chevron
}

private struct ModelSpecRow: View {
    let symbolName: String
    let symbolColor: Color
    let title: String
    let subtitle: String
    var badges: [String] = []
    let trailing: ModelSpecTrailing
    let isSelected: Bool
    let showsDivider: Bool
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: symbolName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isEnabled ? symbolColor : Color.textTertiary)
                        .frame(width: 22, height: 22)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.body)
                            .foregroundStyle(isEnabled ? Color.primary : Color.textSecondary)
                            .lineLimit(1)

                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if !badges.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(Array(badges.prefix(3)), id: \.self) { badge in
                                    Text(badge)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color.textSecondary)
                                        .lineLimit(1)
                                        .padding(.horizontal, 7)
                                        .frame(height: 20)
                                        .background(Color.appSecondaryBackground, in: Capsule())
                                }
                            }
                            .padding(.top, 3)
                        }
                    }

                    Spacer(minLength: 0)

                    trailingView
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(minHeight: 60)
                .background(isSelected ? Color.actionPrimary.opacity(0.10) : Color.clear)
                .contentShape(Rectangle())

                if showsDivider {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: 52)
                        Rectangle()
                            .fill(Color.appHairline)
                            .frame(height: 0.5)
                    }
                    .frame(height: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
    }

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case .none:
            EmptyView()
        case .checkmark:
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.actionPrimary)
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
        }
    }
}

private struct CouncilNumberedRow: View {
    let number: Int
    let title: String
    let subtitle: String
    let showsDivider: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .center, spacing: 14) {
                Text("\(number)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.actionPrimary)
                    .frame(width: 22, height: 22)
                    .background(Color.actionPrimary.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 60)

            if showsDivider {
                HStack(spacing: 0) {
                    Color.clear.frame(width: 52)
                    Rectangle()
                        .fill(Color.appHairline)
                        .frame(height: 0.5)
                }
            }
        }
    }
}

private extension ModelOption {
    var routeDisclosureBadges: [String] {
        if isNearCloudModel {
            return ["NEAR AI Cloud", "Privacy proxy"]
        }
        if isIronclawHostedModel {
            return ["Hosted IronClaw", "File names only"]
        }
        if isIronclawMobileRuntime {
            return ["IronClaw Mobile", "Outside proof"]
        }
        if isPrivateVerifiableChatModel {
            return ["NEAR Private", "Proof when fetched"]
        }
        return Array((["NEAR Private"] + capabilityBadges).prefix(3))
    }
}
