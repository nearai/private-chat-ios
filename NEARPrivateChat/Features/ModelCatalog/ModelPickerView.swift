import SwiftUI

struct ModelPickerView: View {
    @EnvironmentObject private var chatStore: ChatStore
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
        chatStore.pickerModels
    }

    private var defaultPrivateModel: ModelOption? {
        allPickerModels.first(where: { isDefaultPrivateModel($0) }) ??
            allPickerModels.first(where: { $0.displayName.localizedCaseInsensitiveContains("GLM 5.1") }) ??
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

    private var cloudPreviewCount: Int {
        chatStore.cloudModels.count
    }

    private var frontierCloudModels: [ModelOption] {
        let cloud = chatStore.cloudModels
        let frontier = cloud.filter { model in
            model.isEliteModel ||
                model.displayName.localizedCaseInsensitiveContains("opus") ||
                model.displayName.localizedCaseInsensitiveContains("gpt") ||
                model.displayName.localizedCaseInsensitiveContains("gemini") ||
                model.displayName.localizedCaseInsensitiveContains("qwen") ||
                model.displayName.localizedCaseInsensitiveContains("kimi")
        }
        return Array((frontier.isEmpty ? cloud : frontier).prefix(3))
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
                if chatStore.models.isEmpty {
                    await chatStore.refreshModels(loadCloudCatalog: chatStore.nearCloudKeyConfigured)
                }
            }
        }
        .platformLargeDetent()
    }

    // MARK: - Models tab

    @ViewBuilder
    private var modelsTab: some View {
        VStack(alignment: .leading, spacing: 22) {
            // DEFAULT
            ModelSpecSection(title: "Default") {
                if let model = defaultPrivateModel {
                    ModelSpecRow(
                        symbolName: "cpu",
                        symbolColor: Color.actionPrimary,
                        title: "GLM 5.1",
                        subtitle: "Strong default for private chat",
                        trailing: .checkmark,
                        isSelected: model.id == chatStore.selectedModel && !chatStore.isCouncilModeEnabled,
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
                            title: index == 0 ? "Expert" : "Heavy",
                            subtitle: index == 0
                                ? "Multi-step reasoning, slower"
                                : "Deep analysis for complex prompts",
                            trailing: model.id == chatStore.selectedModel && !chatStore.isCouncilModeEnabled
                                ? .checkmark
                                : .none,
                            isSelected: model.id == chatStore.selectedModel && !chatStore.isCouncilModeEnabled,
                            showsDivider: index != reasoningChoices.count - 1,
                            action: { selectModelAndDismiss(model) }
                        )
                    }
                }
            }

            // NEAR CLOUD
            ModelSpecSection(title: "NEAR Cloud") {
                ModelSpecRow(
                    symbolName: chatStore.nearCloudKeyConfigured ? "cloud.fill" : "cloud",
                    symbolColor: Color.textSecondary,
                    title: chatStore.nearCloudKeyConfigured ? "NEAR Cloud connected" : "Connect NEAR Cloud",
                    subtitle: chatStore.nearCloudKeyConfigured
                        ? "Refresh cloud catalog or open account"
                        : "Use Claude, GPT, and Gemini via your cloud key",
                    trailing: .chevron,
                    isSelected: false,
                    showsDivider: false,
                    action: connectOrOpenNearCloud
                )
            }

            // FRONTIER
            if chatStore.nearCloudKeyConfigured && !frontierCloudModels.isEmpty {
                ModelSpecSection(title: "Frontier (via Cloud)") {
                    ForEach(Array(frontierCloudModels.enumerated()), id: \.element.id) { index, model in
                        ModelSpecRow(
                            symbolName: "cpu",
                            symbolColor: Color.textSecondary,
                            title: model.displayName,
                            subtitle: frontierSubtitle(for: model),
                            trailing: model.id == chatStore.selectedModel && !chatStore.isCouncilModeEnabled
                                ? .checkmark
                                : .none,
                            isSelected: model.id == chatStore.selectedModel && !chatStore.isCouncilModeEnabled,
                            showsDivider: index != frontierCloudModels.count - 1,
                            action: { selectModelAndDismiss(model) }
                        )
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Frontier (via Cloud)".uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .tracking(0.5)
                        .padding(.horizontal, 16)
                    Text("Connect NEAR Cloud to use Claude Opus 4.5, GPT-5.5, Gemini 3 Pro.")
                        .font(.footnote)
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
        let isActive = chatStore.isCouncilModeEnabled

        return VStack(alignment: .leading, spacing: 22) {
            ModelSpecSection(title: isActive ? "Active Council" : "Recommended Council") {
                if lineup.isEmpty {
                    ModelSpecRow(
                        symbolName: "person.3",
                        symbolColor: Color.textSecondary,
                        title: "Council unavailable",
                        subtitle: "Need at least two eligible chat models",
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
                        chatStore.clearCouncilMode()
                    } else {
                        chatStore.useDefaultCouncilLineup()
                    }
                    dismiss()
                } label: {
                    Text(isActive ? "Turn Off Council" : "Use Recommended Council")
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

            if !chatStore.councilPresets.isEmpty {
                ModelSpecSection(title: "Preset Combos") {
                    let presets = chatStore.councilPresets
                    ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                        ModelSpecRow(
                            symbolName: presetSymbol(for: preset),
                            symbolColor: preset.isAvailable ? Color.textSecondary : Color.textTertiary,
                            title: preset.title,
                            subtitle: preset.isAvailable ? preset.previewNames : "Needs available models",
                            trailing: .chevron,
                            isSelected: false,
                            showsDivider: index != presets.count - 1,
                            isEnabled: preset.isAvailable,
                            action: {
                                chatStore.useCouncilPreset(preset.id)
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
        let active = chatStore.activeCouncilModels
        if active.count > 1 {
            return Array(active.prefix(4))
        }
        return Array(chatStore.defaultCouncilModels.prefix(4))
    }

    private func councilSubtitle(for model: ModelOption, index: Int) -> String {
        if model.isPrivateVerifiableChatModel {
            return "Verification-first answer"
        }
        if model.isNearCloudModel {
            return "Cloud comparison"
        }
        if index == 0 {
            return "Primary answer"
        }
        return "Independent comparison"
    }

    private func presetSymbol(for preset: CouncilPresetOption) -> String {
        if !preset.symbolName.isEmpty { return preset.symbolName }
        return "person.3"
    }

    private func isDefaultPrivateModel(_ model: ModelOption) -> Bool {
        model.id == "zai-org/GLM-5.1-FP8" ||
            model.id == "zai-org/GLM-latest" ||
            model.displayName.localizedCaseInsensitiveContains("GLM 5.1")
    }

    private func frontierSubtitle(for model: ModelOption) -> String {
        let name = model.displayName.lowercased()
        if name.contains("opus") || name.contains("claude") { return "Anthropic · long-context" }
        if name.contains("gpt") { return "OpenAI · general-purpose" }
        if name.contains("gemini") { return "Google · multimodal" }
        if name.contains("qwen") { return "Alibaba · multilingual" }
        if name.contains("kimi") { return "Moonshot · long-context" }
        return model.metadata?.modelDescription ?? "Frontier model via NEAR Cloud"
    }

    private func selectModelAndDismiss(_ model: ModelOption) {
        chatStore.selectModel(model.id)
        dismiss()
    }

    private func connectOrOpenNearCloud() {
        if chatStore.nearCloudKeyConfigured {
            openNearCloudSignup()
        } else {
            Task {
                _ = await chatStore.connectNearCloudAccount()
            }
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
    let trailing: ModelSpecTrailing
    let isSelected: Bool
    let showsDivider: Bool
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottom) {
                HStack(alignment: .center, spacing: 14) {
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
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    trailingView
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
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
                        .font(.footnote)
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
