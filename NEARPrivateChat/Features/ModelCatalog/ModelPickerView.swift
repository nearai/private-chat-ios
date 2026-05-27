import SwiftUI

private enum ModelCapabilityFilter: String, CaseIterable, Identifiable {
    case privateRoute
    case openWeights
    case reasoning
    case code
    case vision
    case longContext

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privateRoute: "Private"
        case .openWeights: "Open weights"
        case .reasoning: "Reasoning"
        case .code: "Code"
        case .vision: "Vision"
        case .longContext: "Long context"
        }
    }

    var symbolName: String {
        switch self {
        case .privateRoute: "lock.shield"
        case .openWeights: "shippingbox"
        case .reasoning: "brain.head.profile"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .vision: "eye"
        case .longContext: "text.rectangle"
        }
    }

    func matches(_ model: ModelOption) -> Bool {
        switch self {
        case .privateRoute:
            return !model.isExternalModel && model.isVerifiable
        case .openWeights:
            return model.isOpenWeightCandidate
        case .reasoning:
            return model.isRecommendedReasoningModel
        case .code:
            return model.isCodeModel
        case .vision:
            return model.isVisionModel
        case .longContext:
            return model.isLongContextModel
        }
    }
}

struct ModelPickerView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var searchText = ""
    @State private var selectedTab: ModelPickerTab = .models
    @State private var showingCouncilCustomizer = false
    @State private var activeFilters: Set<ModelCapabilityFilter> = []

    private enum ModelPickerTab: String, CaseIterable, Identifiable {
        case models = "Models"
        case council = "Council"

        var id: String { rawValue }
    }

    init(openingCouncil: Bool = false) {
        _selectedTab = State(initialValue: openingCouncil ? .council : .models)
    }

    private var eliteModels: [ModelOption] {
        filtered(chatStore.eliteModels)
    }

    private var openWeightModels: [ModelOption] {
        filtered(chatStore.openWeightModels)
    }

    private var privateModels: [ModelOption] {
        filtered(chatStore.privateModels)
    }

    private var standardModels: [ModelOption] {
        filtered(chatStore.standardModels)
    }

    private var cloudModels: [ModelOption] {
        filtered(chatStore.cloudModels)
    }

    private var featuredModels: [ModelOption] {
        filtered(chatStore.featuredPickerModels)
    }

    private var pinnedModels: [ModelOption] {
        filtered(chatStore.pinnedPickerModels)
    }

    private var recommendedModelIDs: Set<String> {
        Set(unpinned(featuredModels).map(\.id))
    }

    private var defaultPrivateModel: ModelOption? {
        let allModels = filtered(chatStore.pickerModels)
        return allModels.first(where: { isDefaultPrivateModel($0) }) ??
            allModels.first(where: { $0.displayName.localizedCaseInsensitiveContains("GLM 5.1") }) ??
            allModels.first(where: { $0.isPrivateVerifiableChatModel })
    }

    private var reasoningChoices: [ModelOption] {
        let defaultID = defaultPrivateModel?.id
        let choices = filtered(chatStore.pickerModels).filter { model in
            model.id != defaultID &&
                model.isRecommendedReasoningModel &&
                !model.isNearCloudModel &&
                !model.isIronclawModel &&
                !model.isLowerPriorityModel
        }
        return Array(choices.prefix(2))
    }

    private var searchResults: [ModelOption] {
        filtered(chatStore.pickerModels)
    }

    private var cloudPreviewModels: [ModelOption] {
        Array(cloudModels.prefix(4))
    }

    private var frontierCloudModels: [ModelOption] {
        let frontier = cloudModels.filter { model in
            model.isEliteModel ||
                model.displayName.localizedCaseInsensitiveContains("opus") ||
                model.displayName.localizedCaseInsensitiveContains("gpt") ||
                model.displayName.localizedCaseInsensitiveContains("gemini") ||
                model.displayName.localizedCaseInsensitiveContains("qwen") ||
                model.displayName.localizedCaseInsensitiveContains("kimi")
        }
        return Array((frontier.isEmpty ? cloudModels : frontier).prefix(5))
    }

    private var isSearchingModels: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var councilCandidateModels: [ModelOption] {
        let candidates = filtered(chatStore.pickerModels.filter { chatStore.canUseInCouncil($0.id) })
        let activeIDs = chatStore.activeCouncilModels.map(\.id)
        let activeIDSet = Set(activeIDs)
        let activeModels = activeIDs.compactMap { id in candidates.first { $0.id == id } }
        return activeModels + candidates.filter { !activeIDSet.contains($0.id) }
    }

    private var selectedSingleModelProviderName: String {
        guard let model = chatStore.selectedModelOption else {
            return "NEAR Private"
        }
        if model.isIronclawModel {
            return "IronClaw"
        }
        if model.isNearCloudModel {
            return "NEAR Cloud"
        }
        return "NEAR Private"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Model picker mode", selection: $selectedTab) {
                        ForEach(ModelPickerTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    if selectedTab == .models {
                        modelsTab
                    } else {
                        councilTab
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .background(Color.appBackground)
            .navigationTitle(selectedTab == .models ? "Model" : "Council")
            .platformInlineNavigationTitle()
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(modelSearchPrompt))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                if chatStore.models.isEmpty {
                    await chatStore.refreshModels(loadCloudCatalog: chatStore.nearCloudKeyConfigured)
                }
            }
        }
        .platformMediumDetent()
    }

    @ViewBuilder
    private var modelsTab: some View {
        if isSearchingModels || !activeFilters.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                ModelCapabilityFilterBar(activeFilters: $activeFilters)
                    .padding(.horizontal, 16)
                V2ModelSection(title: "Matching Models") {
                    ForEach(searchResults) { model in
                        V2ModelRow(
                            title: model.displayName,
                            subtitle: modelRowSubtitle(model),
                            symbolName: modelRowSymbol(model),
                            tint: modelRowTint(model),
                            badge: modelBadge(model),
                            isSelected: model.id == chatStore.selectedModel,
                            isEnabled: true,
                            action: { selectModelAndDismiss(model) }
                        )
                        .dividerIfNeeded(model.id != searchResults.last?.id)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 22) {
                V2ModelSection(title: "Default") {
                    if let model = defaultPrivateModel {
                        V2ModelRow(
                            title: "GLM 5.1",
                            subtitle: "\(model.id) · Strong default for private chat",
                            symbolName: "cpu",
                            tint: Color.actionPrimary,
                            badge: "Verified",
                            isSelected: model.id == chatStore.selectedModel && !chatStore.isCouncilModeEnabled,
                            isEnabled: true,
                            action: { selectModelAndDismiss(model) }
                        )
                    }
                }

                V2ModelSection(title: "Reasoning") {
                    ForEach(Array(reasoningChoices.enumerated()), id: \.element.id) { index, model in
                        V2ModelRow(
                            title: index == 0 ? "Expert" : "Heavy",
                            subtitle: "\(model.displayName) · \(index == 0 ? "Multi-step reasoning, balanced" : "Deeper reasoning, slower")",
                            symbolName: "brain.head.profile",
                            tint: Color.textSecondary,
                            badge: modelBadge(model),
                            isSelected: model.id == chatStore.selectedModel && !chatStore.isCouncilModeEnabled,
                            isEnabled: true,
                            action: { selectModelAndDismiss(model) }
                        )
                        .dividerIfNeeded(index != reasoningChoices.count - 1)
                    }
                    ReasoningEffortInlineControl(
                        selectedEffort: chatStore.advancedModelParams.reasoningEffort,
                        onSelect: { chatStore.setReasoningEffort($0) }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .dividerIfNeeded(false)
                }

                NearCloudGuidedCard(
                    isConnected: chatStore.nearCloudKeyConfigured,
                    isConnecting: chatStore.isConnectingNearCloudAccount,
                    modelCount: cloudPreviewModels.count,
                    connectAction: connectNearCloudAccount,
                    openCloudAction: openNearCloudSignup
                )

                if chatStore.nearCloudKeyConfigured {
                    V2ModelSection(title: "Frontier Via Cloud") {
                        ForEach(frontierCloudModels) { model in
                            V2ModelRow(
                                title: model.displayName,
                                subtitle: modelRowSubtitle(model),
                                symbolName: "cloud.fill",
                                tint: Color.textSecondary,
                                badge: "Privacy proxy",
                                isSelected: model.id == chatStore.selectedModel && !chatStore.isCouncilModeEnabled,
                                isEnabled: true,
                                action: { selectModelAndDismiss(model) }
                            )
                            .dividerIfNeeded(model.id != frontierCloudModels.last?.id)
                        }
                    }
                } else {
                    FrontierLockedCard()
                }
            }
        }
    }

    private var councilTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            CouncilLineupCard(
                activeModels: chatStore.activeCouncilModels,
                defaultModels: chatStore.defaultCouncilModels,
                useDefaultAction: { chatStore.useDefaultCouncilLineup() },
                clearAction: { chatStore.clearCouncilMode() }
            )

            CouncilPresetSection(
                presets: chatStore.councilPresets,
                usePreset: { chatStore.useCouncilPreset($0) },
                customizeAction: { showingCouncilCustomizer.toggle() },
                isCustomizing: showingCouncilCustomizer
            )

            if showingCouncilCustomizer || isSearchingModels {
                V2ModelSection(title: "Choose Models") {
                    ForEach(councilCandidateModels) { model in
                        V2ModelRow(
                            title: model.displayName,
                            subtitle: modelRowSubtitle(model),
                            symbolName: modelRowSymbol(model),
                            tint: modelRowTint(model),
                            badge: councilBadge(for: model),
                            isSelected: chatStore.councilIndex(for: model.id) != nil,
                            isEnabled: chatStore.canUseInCouncil(model.id),
                            action: { chatStore.toggleCouncilModel(model.id) }
                        )
                        .dividerIfNeeded(model.id != councilCandidateModels.last?.id)
                    }
                }
            }
        }
    }

    private var modelSearchPrompt: String {
        let count = chatStore.pickerModels.count
        return count > 0 ? "Search \(count) models" : "Search models"
    }

    private func filtered(_ models: [ModelOption]) -> [ModelOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched: [ModelOption]
        if query.isEmpty {
            searched = models
        } else {
            searched = models.filter { model in
                let aliases = model.metadata?.aliases?.joined(separator: " ") ?? ""
                return model.id.localizedCaseInsensitiveContains(query) ||
                    model.displayName.localizedCaseInsensitiveContains(query) ||
                    aliases.localizedCaseInsensitiveContains(query) ||
                    (model.metadata?.modelDescription ?? "").localizedCaseInsensitiveContains(query)
            }
        }
        guard !activeFilters.isEmpty else { return searched }
        return searched.filter { model in
            activeFilters.allSatisfy { $0.matches(model) }
        }
    }

    private func unpinned(_ models: [ModelOption]) -> [ModelOption] {
        models.filter { !chatStore.isPinnedModel($0.id) }
    }

    private func secondaryModels(_ models: [ModelOption]) -> [ModelOption] {
        let primaryIDs = recommendedModelIDs
        return unpinned(models).filter { !primaryIDs.contains($0.id) }
    }

    private func isDefaultPrivateModel(_ model: ModelOption) -> Bool {
        model.id == "zai-org/GLM-5.1-FP8" ||
            model.id == "zai-org/GLM-latest" ||
            model.displayName.localizedCaseInsensitiveContains("GLM 5.1")
    }

    private func modelRowSubtitle(_ model: ModelOption) -> String {
        if model.isNearCloudModel {
            return model.metadata?.modelDescription ?? "Runs through NEAR Cloud privacy proxy."
        }
        if model.isPrivateVerifiableChatModel {
            return model.metadata?.modelDescription ?? "Private route with verification coverage when proof is available."
        }
        return model.metadata?.modelDescription ?? model.id
    }

    private func modelRowSymbol(_ model: ModelOption) -> String {
        if model.isNearCloudModel { return "cloud.fill" }
        if model.isRecommendedReasoningModel { return "brain.head.profile" }
        if model.isOpenWeightCandidate { return "shippingbox" }
        if model.isPrivateVerifiableChatModel { return "checkmark.shield.fill" }
        return "cpu"
    }

    private func modelRowTint(_ model: ModelOption) -> Color {
        if model.isPrivateVerifiableChatModel || isDefaultPrivateModel(model) {
            return Color.actionPrimary
        }
        return Color.textSecondary
    }

    private func modelBadge(_ model: ModelOption) -> String? {
        if model.isNearCloudModel {
            return chatStore.nearCloudKeyConfigured ? "Cloud" : "Connect"
        }
        if model.isPrivateVerifiableChatModel {
            switch chatStore.currentAttestationStatus.coverage(for: model.id) {
            case .covered:
                return "Verified"
            case .stale:
                return "Stale"
            default:
                return "Private"
            }
        }
        if model.isRecommendedReasoningModel {
            return "Reasoning"
        }
        return nil
    }

    private func councilBadge(for model: ModelOption) -> String? {
        if let index = chatStore.councilIndex(for: model.id) {
            return "#\(index)"
        }
        return modelBadge(model)
    }

    private func selectModelAndDismiss(_ model: ModelOption) {
        chatStore.selectModel(model.id)
        dismiss()
    }

    private func connectNearCloudAccount() {
        Task {
            _ = await chatStore.connectNearCloudAccount()
        }
    }

    private func openNearCloudSignup() {
        guard let url = URL(string: "https://cloud.near.ai") else { return }
        openURL(url)
    }

    @ViewBuilder
    private func modelSection(_ title: String, models: [ModelOption], showsCouncilButton: Bool, dismissOnSelect: Bool = true) -> some View {
        if !models.isEmpty {
            Section(title) {
                ForEach(models) { model in
                    ModelPickerRow(
                        model: model,
                        isSelected: model.id == chatStore.selectedModel,
                        councilIndex: chatStore.councilIndex(for: model.id),
                        canUseInCouncil: chatStore.canUseInCouncil(model.id),
                        showsCouncilButton: showsCouncilButton,
                        isPinned: chatStore.isPinnedModel(model.id),
                        attestationStatus: chatStore.currentAttestationStatus,
                        togglePinAction: {
                            chatStore.togglePinnedModel(model.id)
                        },
                        selectAction: {
                            if dismissOnSelect {
                                chatStore.selectModel(model.id)
                                dismiss()
                            } else {
                                chatStore.toggleCouncilModel(model.id)
                            }
                        }
                    )
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
    }
}

private struct V2ModelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                content
            }
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 0.5)
            }
            .padding(.horizontal, 16)
        }
    }
}

private struct V2ModelRow: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let tint: Color
    let badge: String?
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isEnabled ? tint : Color.textTertiary)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(isEnabled ? Color.primary : Color.textSecondary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if let badge {
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : tint)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(isSelected ? tint : tint.opacity(0.10), in: Capsule())
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.actionPrimary)
                }
            }
            .frame(minHeight: 60)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Color.actionTint : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
    }
}

private struct DividerIfNeeded: ViewModifier {
    let show: Bool

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
            if show {
                Rectangle()
                    .fill(Color.appHairline)
                    .frame(height: 0.5)
                    .padding(.leading, 54)
            }
        }
    }
}

private extension View {
    func dividerIfNeeded(_ show: Bool) -> some View {
        modifier(DividerIfNeeded(show: show))
    }
}

private struct ReasoningEffortInlineControl: View {
    let selectedEffort: ModelReasoningEffort
    let onSelect: (ModelReasoningEffort) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default reasoning effort")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: 6) {
                ForEach(ModelReasoningEffort.allCases) { effort in
                    Button {
                        onSelect(effort)
                    } label: {
                        Text(effort.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(effort == selectedEffort ? Color.white : Color.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(effort == selectedEffort ? Color.actionPrimary : Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(effort.detail)
                }
            }
        }
    }
}

private struct NearCloudGuidedCard: View {
    let isConnected: Bool
    let isConnecting: Bool
    let modelCount: Int
    let connectAction: () -> Void
    let openCloudAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isConnected ? "cloud.fill" : "cloud")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.actionPrimary)
                    .frame(width: 34, height: 34)
                    .background(Color.actionTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("NEAR Cloud")
                        .font(.headline)
                    Text(isConnected ? "\(max(modelCount, 1)) Cloud models ready. Use Frontier below when you want a SOTA override." : "Connect your NEAR account to unlock Qwen Max, Claude Opus, GPT, Gemini, and more.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button(action: connectAction) {
                    Label(isConnecting ? "Connecting" : (isConnected ? "Refresh Cloud" : "Connect Account"), systemImage: isConnected ? "arrow.clockwise" : "person.crop.circle.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.actionPrimary)
                .disabled(isConnecting)

                Button(action: openCloudAction) {
                    Image(systemName: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 42)
                }
                .buttonStyle(.bordered)
                .tint(Color.actionPrimary)
                .accessibilityLabel("Open NEAR Cloud")
            }
        }
        .padding(16)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 0.5)
        }
        .padding(.horizontal, 16)
    }
}

private struct FrontierLockedCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FRONTIER VIA CLOUD")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)
            Text("Connect NEAR Cloud to use Claude Opus, Qwen Max, GPT, Gemini, and Kimi routes.")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.appHairline, lineWidth: 0.5)
                }
        }
        .padding(.horizontal, 16)
    }
}

private struct CouncilLineupCard: View {
    let activeModels: [ModelOption]
    let defaultModels: [ModelOption]
    let useDefaultAction: () -> Void
    let clearAction: () -> Void

    private var displayModels: [ModelOption] {
        activeModels.count > 1 ? activeModels : defaultModels
    }

    private var isActive: Bool {
        activeModels.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.actionPrimary)
                    .frame(width: 34, height: 34)
                    .background(Color.actionTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(isActive ? "Council active" : "Recommended Council")
                        .font(.headline)
                    Text("Several models answer the same prompt; the synthesis keeps agreement and disagreement visible.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(displayModels.prefix(4).enumerated()), id: \.element.id) { index, model in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.actionPrimary)
                            .frame(width: 24, height: 24)
                            .background(Color.actionTint, in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.displayName)
                                .font(.footnote.weight(.semibold))
                            Text(index == 0 ? "Verification-first answer" : "Independent comparison")
                                .font(.caption2)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                    }
                }
            }

            HStack(spacing: 8) {
                Button(action: useDefaultAction) {
                    Label(isActive ? "Reset Lineup" : "Use Council", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.actionPrimary)

                if isActive {
                    Button(action: clearAction) {
                        Label("Single", systemImage: "1.circle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.actionPrimary)
                }
            }
        }
        .padding(16)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 0.5)
        }
        .padding(.horizontal, 16)
    }
}

private struct CouncilPresetSection: View {
    let presets: [CouncilPresetOption]
    let usePreset: (String) -> Void
    let customizeAction: () -> Void
    let isCustomizing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRESETS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach(presets) { preset in
                    Button {
                        usePreset(preset.id)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: preset.symbolName)
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(preset.isAvailable ? Color.actionPrimary : Color.textTertiary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.title)
                                    .font(.body)
                                    .foregroundStyle(Color.primary)
                                Text(preset.isAvailable ? preset.subtitle : "Needs available models")
                                    .font(.footnote)
                                    .foregroundStyle(Color.textSecondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textTertiary)
                        }
                        .frame(minHeight: 60)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .disabled(!preset.isAvailable)
                    .dividerIfNeeded(preset.id != presets.last?.id)
                }

                Button(action: customizeAction) {
                    HStack(spacing: 14) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Color.actionPrimary)
                            .frame(width: 24)
                        Text(isCustomizing ? "Hide custom models" : "Custom")
                            .font(.body)
                            .foregroundStyle(Color.primary)
                        Spacer()
                    }
                    .frame(minHeight: 60)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 0.5)
            }
            .padding(.horizontal, 16)
        }
    }
}

private struct ReasoningEffortPickerCard: View {
    let selectedEffort: ModelReasoningEffort
    let appliesToCurrentRoute: Bool
    let onSelect: (ModelReasoningEffort) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 24, height: 24)
                    .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Reasoning effort")
                        .font(.caption.weight(.semibold))
                    Text(appliesToCurrentRoute ? "Applied to NEAR Cloud requests when supported" : "Saved for Cloud models and mixed Council runs")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                ForEach(ModelReasoningEffort.allCases) { effort in
                    Button {
                        onSelect(effort)
                    } label: {
                        Text(effort.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .foregroundStyle(effort == selectedEffort ? Color.white : Color.textSecondary)
                            .background(effort == selectedEffort ? Color.primaryAction : Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reasoning effort \(effort.title)")
                    .accessibilityHint(effort.detail)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ModelCapabilityFilterBar: View {
    @Binding var activeFilters: Set<ModelCapabilityFilter>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(activeFilters.isEmpty ? "All models" : "\(activeFilters.count) filter\(activeFilters.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !activeFilters.isEmpty {
                    Button("Clear") {
                        activeFilters.removeAll()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.brandBlue)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ModelCapabilityFilter.allCases) { filter in
                        Button {
                            toggle(filter)
                        } label: {
                            Label(filter.title, systemImage: filter.symbolName)
                                .font(.caption.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .lineLimit(1)
                                .foregroundStyle(activeFilters.contains(filter) ? Color.white : Color.textSecondary)
                                .padding(.horizontal, 10)
                                .frame(height: 34)
                                .background(activeFilters.contains(filter) ? Color.primaryAction : Color.appPanelBackground, in: Capsule())
                                .overlay {
                                    Capsule()
                                        .stroke(activeFilters.contains(filter) ? Color.clear : Color.appBorder, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(filter.title) filter")
                        .accessibilityAddTraits(activeFilters.contains(filter) ? [.isSelected] : [])
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.vertical, 2)
    }

    private func toggle(_ filter: ModelCapabilityFilter) {
        if activeFilters.contains(filter) {
            activeFilters.remove(filter)
        } else {
            activeFilters.insert(filter)
        }
    }
}

private struct CouncilPickerCard: View {
    let models: [ModelOption]
    let defaultModels: [ModelOption]
    let presets: [CouncilPresetOption]
    let maxModels: Int
    @Binding var isCustomizing: Bool
    let onUseDefault: () -> Void
    let onUsePreset: (String) -> Void
    let onClear: () -> Void
    let onRemoveModel: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 30, height: 30)
                    .background(Color.brandSky.opacity(0.34), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Council")
                        .font(.subheadline.weight(.semibold))
                    Text("Choose models manually, or start from a recommended lineup")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Label(councilStateTitle, systemImage: councilStateSymbol)
                    .font(.caption2.weight(.bold))
                    .labelStyle(.iconOnly)
                    .foregroundStyle(isCouncilActive ? Color.trustVerified : .secondary)
                    .frame(width: 30, height: 30)
                    .background((isCouncilActive ? Color.trustVerified : Color.secondary).opacity(0.10), in: Circle())
                    .accessibilityLabel(councilStateTitle)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(councilStateTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCouncilActive ? Color.trustVerified : .secondary)

                Text(councilStateDetail)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ChipFlowLayout(spacing: 6, lineSpacing: 6) {
                if !displayModels.isEmpty {
                    ForEach(displayModels) { model in
                        Button {
                            if isCouncilActive {
                                onRemoveModel(model.id)
                            }
                        } label: {
                            Label(model.displayName, systemImage: isCouncilActive ? "xmark.circle.fill" : "sparkles")
                                .font(.caption.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(isCouncilActive ? Color.brandBlue : .secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(isCouncilActive ? Color.brandBlue.opacity(0.10) : Color.appSecondaryBackground, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!isCouncilActive)
                        .accessibilityLabel(isCouncilActive ? "Remove \(model.displayName) from Council" : "Recommended lineup includes \(model.displayName)")
                    }
                } else {
                    StatusChip(title: "Waiting for available models", symbolName: "clock", isPrimary: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                Button {
                    onUseDefault()
                } label: {
                    Label(autoCouncilButtonTitle, systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandBlue)
                .disabled(defaultModels.count < 2 || isAutoCouncilActive)
                .accessibilityHint("Use the recommended Council lineup for the next message")

                HStack(spacing: 8) {
                    Button {
                        isCustomizing.toggle()
                    } label: {
                        Label(isCustomizing ? "Hide Models" : "Choose Models", systemImage: "slider.horizontal.3")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(isCustomizing ? "Hide Council model controls" : "Show Council model controls")

                    if isCouncilActive {
                        Button {
                            onClear()
                        } label: {
                            Label("Single", systemImage: "1.circle")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Return to a single model")
                    }
                }
            }

            if isCustomizing, !presets.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 7) {
                    Text("Lineups")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presets) { preset in
                                Button {
                                    onUsePreset(preset.id)
                                } label: {
                                    CouncilPresetPill(preset: preset)
                                }
                                .buttonStyle(.plain)
                                .disabled(!preset.isAvailable)
                                .accessibilityLabel("Use \(preset.title) Council lineup")
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.brandBlue.opacity(0.12), lineWidth: 1)
        }
    }

    private var isCouncilActive: Bool {
        models.count > 1
    }

    private var isAutoCouncilActive: Bool {
        isCouncilActive && models.map(\.id) == defaultModels.map(\.id)
    }

    private var displayModels: [ModelOption] {
        let lineup = isCouncilActive ? models : defaultModels
        return Array(lineup.prefix(maxModels))
    }

    private var autoCouncilButtonTitle: String {
        isAutoCouncilActive ? "Recommended On" : "Use Recommended"
    }

    private var councilStateTitle: String {
        if isAutoCouncilActive {
            return "Recommended lineup active"
        }
        if isCouncilActive {
            return "Custom Council active"
        }
        return defaultModels.count > 1 ? "Recommended lineup ready" : "Council unavailable"
    }

    private var councilStateDetail: String {
        if isCouncilActive {
            return "\(models.count) models will answer in parallel."
        }
        if defaultModels.count > 1 {
            return "\(defaultModels.count) recommended models are ready."
        }
        return "At least two eligible chat models are needed."
    }

    private var councilStateSymbol: String {
        if isCouncilActive {
            return isAutoCouncilActive ? "checkmark.seal.fill" : "slider.horizontal.3"
        }
        return defaultModels.count > 1 ? "sparkles" : "exclamationmark.triangle"
    }
}

private struct CouncilPresetPill: View {
    let preset: CouncilPresetOption

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: preset.symbolName)
                    .font(.caption.weight(.bold))
                Text(preset.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(preset.isAvailable ? preset.previewNames : "Needs available models")
                .font(.caption2.weight(.medium))
                .foregroundStyle(preset.isAvailable ? Color.secondary : Color.secondary.opacity(0.72))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(preset.isAvailable ? Color.brandBlue : .secondary)
        .frame(width: 150, alignment: .topLeading)
        .frame(minHeight: 70, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(preset.isAvailable ? Color.brandBlue.opacity(0.08) : Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(preset.isAvailable ? Color.brandBlue.opacity(0.14) : Color.appBorder, lineWidth: 1)
        }
        .opacity(preset.isAvailable ? 1 : 0.58)
    }
}

private struct ModelPickerSummary: View {
    let selectedModelName: String
    let selectedModelID: String
    let providerName: String
    let modelCount: Int
    let councilModelNames: [String]
    let webSearchEnabled: Bool
    let appWebGroundingEnabled: Bool
    let planName: String
    let hiddenPlanLockedModelCount: Int
    let ironclawRemoteWorkstationAvailable: Bool
    let ironclawTokenConfigured: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: isIronclawProvider ? "point.3.connected.trianglepath.dotted" : "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 30, height: 30)
                    .background(Color.brandBlue.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedModelName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            ChipFlowLayout(spacing: 6, lineSpacing: 6) {
                StatusChip(title: providerChipTitle, symbolName: providerChipSymbol, isPrimary: false)
                StatusChip(title: routeCostTitle, symbolName: routeCostSymbol, isPrimary: isNearCloudProvider || isIronclawProvider)
                if isNearCloudProvider {
                    StatusChip(title: "Not attested", symbolName: "shield.slash", isPrimary: false)
                }
                if councilModelNames.count > 1, !isNearCloudProvider, !isIronclawProvider {
                    StatusChip(title: "Council \(councilModelNames.count)", symbolName: "square.grid.2x2", isPrimary: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hiddenPlanLockedModelCount > 0, !isNearCloudProvider, !isIronclawProvider {
                HStack(spacing: 7) {
                    Image(systemName: "lock.open")
                        .font(.caption2.weight(.bold))
                    Text("Unlock \(hiddenPlanLockedModelCount) more models")
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                    Text("Upgrade")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(Color.brandBlue)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.appHairline)
                .frame(height: 1)
        }
    }

    private var summaryText: String {
        if isIronclawProvider {
            return isHostedIronclaw ? "Hosted git, code, shell, and research route" : "Phone-safe agent with hosted handoff"
        }
        if isNearCloudProvider {
            return "Privacy proxy route with app-supplied context"
        }
        if councilModelNames.count > 1 {
            return councilModelNames.prefix(3).joined(separator: " · ") +
                (councilModelNames.count > 3 ? " · +" : "")
        }
        let locked = hiddenPlanLockedModelCount > 0 ? " · upgrade for \(hiddenPlanLockedModelCount) more" : ""
        return "\(modelCount) curated chat models · \(planName.capitalized) plan\(locked)"
    }

    private var providerChipTitle: String {
        if isIronclawProvider {
            return isHostedIronclaw ? "IronClaw hosted" : "IronClaw mobile"
        }
        return providerName
    }

    private var providerChipSymbol: String {
        if isIronclawProvider {
            return isHostedIronclaw ? "terminal" : "iphone"
        }
        if isNearCloudProvider {
            return "cloud"
        }
        return "lock.shield"
    }

    private var routeCostTitle: String {
        if isIronclawProvider {
            return ironclawTokenConfigured ? "Token saved" : "Connect token"
        }
        if isNearCloudProvider {
            return "Privacy proxy"
        }
        return "\(planName.capitalized) plan"
    }

    private var routeCostSymbol: String {
        if isIronclawProvider {
            return ironclawTokenConfigured ? "key.fill" : "key"
        }
        if isNearCloudProvider {
            return "eye.slash"
        }
        return "creditcard"
    }

    private var isIronclawProvider: Bool {
        providerName == "IronClaw"
    }

    private var isHostedIronclaw: Bool {
        selectedModelID == ModelOption.ironclawModelID
    }

    private var isNearCloudProvider: Bool {
        providerName == "NEAR Cloud"
    }
}

private struct ModelPickerRow: View {
    let model: ModelOption
    let isSelected: Bool
    let councilIndex: Int?
    let canUseInCouncil: Bool
    let showsCouncilButton: Bool
    let isPinned: Bool
    let attestationStatus: AttestationStatus
    let togglePinAction: () -> Void
    let selectAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: modelSymbol)
                .foregroundStyle(model.isEliteModel || model.isPrivateVerifiableChatModel ? Color.brandBlue : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
                Text(model.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(modelDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                HStack(spacing: 6) {
                    modelFact(title: routeFactTitle, symbolName: routeFactSymbol, tint: routeFactTint)
                    if let proofFactTitle {
                        modelFact(title: proofFactTitle, symbolName: proofFactSymbol, tint: proofFactTint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ChipFlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(Array(model.capabilityBadges.prefix(2)), id: \.self) { badge in
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(badge == "DeepSeek alias" ? Color.brandBlue : .secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.appSecondaryBackground, in: Capsule())
                    }

                    if model.capabilityBadges.count < 2, let contextLength = model.metadata?.contextLength {
                        Text("\(contextLength.formatted()) ctx")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            VStack(spacing: 9) {
                if !showsCouncilButton {
                    Button {
                        togglePinAction()
                    } label: {
                        Image(systemName: isPinned ? "star.fill" : "star")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isPinned ? Color.primaryAction : .secondary)
                            .frame(width: 32, height: 32)
                            .background(isPinned ? Color.primaryAction.opacity(0.10) : Color.appSecondaryBackground, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPinned ? "Unpin \(model.displayName)" : "Pin \(model.displayName)")
                }

                if isSelected, !showsCouncilButton {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.brandBlue)
                }

                if showsCouncilButton {
                    HStack(spacing: 5) {
                        Image(systemName: councilSymbol)
                            .font(.caption.weight(.bold))
                        Text(councilActionTitle)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(councilIndex == nil ? Color.brandBlue : Color.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(councilIndex == nil ? Color.brandBlue.opacity(0.08) : Color.brandBlue, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(councilIndex == nil ? Color.brandBlue.opacity(0.16) : Color.clear, lineWidth: 1)
                    }
                    .opacity(canUseInCouncil ? 1 : 0.35)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(rowIsActive ? Color.brandBlue.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !showsCouncilButton || canUseInCouncil else { return }
            selectAction()
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(showsCouncilButton ? councilAccessibilityHint : "Select this model")
    }

    private var councilSymbol: String {
        councilIndex == nil ? "plus.circle.fill" : "minus.circle.fill"
    }

    private var councilActionTitle: String {
        councilIndex == nil ? "Add" : "Remove"
    }

    private var rowIsActive: Bool {
        showsCouncilButton ? councilIndex != nil : isSelected
    }

    private var councilAccessibilityHint: String {
        councilIndex == nil ? "Add this model to LLM Council" : "Remove this model from LLM Council"
    }

    private var modelSymbol: String {
        if model.isNearCloudModel {
            "cloud"
        } else if model.isEliteModel {
            "sparkles"
        } else if model.isRecommendedReasoningModel {
            "brain.head.profile"
        } else if model.isVerifiable {
            "checkmark.shield.fill"
        } else {
            "cpu"
        }
    }

    private var modelDescription: String {
        guard let value = model.metadata?.modelDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return model.id
        }
        return value
    }

    private func modelFact(title: String, symbolName: String, tint: Color) -> some View {
        Label(title, systemImage: symbolName)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(tint.opacity(0.09), in: Capsule())
    }

    private var routeFactTitle: String {
        if model.isNearCloudModel {
            return "NEAR Cloud"
        }
        if model.isIronclawModel {
            return model.isIronclawHostedModel ? "Hosted agent" : "Phone agent"
        }
        if model.isLowerPriorityModel {
            return "Older"
        }
        return "Included"
    }

    private var routeFactSymbol: String {
        if model.isNearCloudModel {
            return "cloud"
        }
        if model.isIronclawModel {
            return "terminal"
        }
        if model.isLowerPriorityModel {
            return "tray.and.arrow.down"
        }
        return "creditcard"
    }

    private var routeFactTint: Color {
        if model.isNearCloudModel {
            return Color.brandBlue
        }
        if model.isIronclawModel {
            return Color.primaryAction
        }
        if model.isLowerPriorityModel {
            return Color.secondary
        }
        return Color.textSecondary
    }

    private var proofFactTitle: String? {
        if model.isNearCloudModel {
            return "Privacy proxy"
        }
        if model.isIronclawModel {
            return model.isIronclawHostedModel ? "Hosted" : "On phone"
        }
        guard model.isPrivateVerifiableChatModel else { return nil }
        switch attestationStatus.coverage(for: model.id) {
        case .covered:
            if let freshness = attestationStatus.freshness()?.shortLabel {
                return "Proof \(freshness)"
            }
            return "Proof fetched"
        case .stale:
            return "Proof stale"
        case .notCovered:
            return "Not covered"
        case .unknown:
            return "Proof not checked"
        }
    }

    private var proofFactSymbol: String {
        if model.isNearCloudModel {
            return "eye.slash"
        }
        if model.isIronclawModel {
            return model.isIronclawHostedModel ? "network" : "iphone"
        }
        switch attestationStatus.coverage(for: model.id) {
        case .covered:
            return "checkmark.shield.fill"
        case .stale:
            return "clock.badge.exclamationmark"
        case .notCovered:
            return "shield.slash"
        case .unknown:
            return "shield.lefthalf.filled"
        }
    }

    private var proofFactTint: Color {
        if model.isNearCloudModel || model.isIronclawModel {
            return Color.secondary
        }
        switch attestationStatus.coverage(for: model.id) {
        case .covered:
            return Color.trustVerified
        case .stale:
            return Color.warningState
        case .notCovered, .unknown:
            return Color.secondary
        }
    }
}
