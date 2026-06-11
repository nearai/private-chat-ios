import SwiftUI

extension InputBar {
    /// Recovery surfaces above the composer: route-readiness issues and the
    /// one-tap proxy retry for restricted private sends. Extracted from the
    /// InputBar body to keep the type-checker happy.
    @ViewBuilder
    var composerRecoveryCards: some View {
        if let issue = composerStore.routeReadinessIssue {
            RouteReadinessRecoveryCard(
                issue: issue,
                onPrimaryAction: { handleRouteReadinessRecovery(issue.recoveryAction) },
                onSwitchPrivate: { chatStore.performRouteReadinessRecovery(.switchToPrivate) },
                onViewCapabilities: { showingCapabilities = true }
            )
        }

        if let offer = composerStore.proxyRetryOffer {
            ProxyRetryCard(
                offer: offer,
                proxyDisplayName: offer.proxyModelID.map { chatStore.pickerModels.first(where: { $0.id == offer.proxyModelID })?.displayName ?? ModelOption.humanize(modelID: $0) },
                onAccept: { chatStore.acceptProxyRetry() },
                onAddCloudKey: {
                    chatStore.declineProxyRetry()
                    chatStore.performRouteReadinessRecovery(.addNearCloudKey)
                },
                onDecline: { chatStore.declineProxyRetry() }
            )
        }
    }

    @ViewBuilder
    var composerRoutingControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let summary = composerRouteSummary {
                Button {
                    AppHaptics.selection()
                    showingRouteConfig = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: summary.symbolName)
                            .font(.caption.weight(.semibold))
                        Text(summary.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(summary.detail)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(minHeight: 44)
                    .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.appBorder, lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("composer.routeSummary")
                .accessibilityLabel("\(summary.title). \(summary.detail)")
                .accessibilityHint("Opens the full send configuration.")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    Button {
                        openModelPicker(openingCouncil: false)
                    } label: {
                        ComposerRouteChip(
                            title: chatStore.selectedModelDisplayName,
                            symbolName: composerModelSymbolName,
                            isActive: true,
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("composer.chip.model")
                    .accessibilityLabel("Model \(chatStore.selectedModelDisplayName)")
                    .accessibilityHint("Choose a private, Cloud, Council, or Agent model for the next message.")

                    Button {
                        openModelPicker(openingCouncil: true)
                    } label: {
                        ComposerRouteChip(
                            title: chatStore.isCouncilModeEnabled ? "Council \(chatStore.activeCouncilModels.count)" : "Council",
                            symbolName: "person.3",
                            isActive: chatStore.isCouncilModeEnabled,
                            showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("composer.chip.council")
                    .accessibilityLabel(chatStore.isCouncilModeEnabled ? "LLM Council active" : "Configure LLM Council")
                    .accessibilityHint("Opens the Council lineup for the next message.")

                    sourceModeControl

                    if routeHealth.isTripped(.nearPrivate) {
                        Button {
                            AppHaptics.selection()
                            chatStore.retryPrivateRouteNow()
                        } label: {
                            ComposerRouteChip(
                                title: "Private busy",
                                symbolName: "exclamationmark.shield",
                                isActive: true,
                                showsChevron: false
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("composer.chip.privateBusy")
                        .accessibilityLabel("Private route busy")
                        .accessibilityHint("Tap to re-enable the private route and retry on the next message.")
                    }

                    if selectedModelSupportsReasoningEffort {
                        Button {
                            AppHaptics.selection()
                            showingReasoningEffortOptions = true
                        } label: {
                            ComposerRouteIconChip(
                                symbolName: "gauge.medium",
                                isActive: chatStore.advancedModelParams.reasoningEffort != .automatic
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reasoning effort \(chatStore.advancedModelParams.reasoningEffort.title)")
                        .accessibilityHint("Changes reasoning effort from the chat window.")
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var composerRouteSummary: (title: String, detail: String, symbolName: String)? {
        var details: [String] = []

        if chatStore.isCouncilModeEnabled {
            let count = max(chatStore.activeCouncilModels.count, chatStore.defaultCouncilModels.count)
            details.append("Council \(max(count, 2))")
        } else if chatStore.selectedRouteKind != .nearPrivate {
            details.append(chatStore.selectedRouteKind.disclosureTitle)
        }

        if chatStore.sourceMode != .auto {
            details.append(composerSourceTitle)
        }

        if researchButtonActive {
            details.append("Research")
        }

        if chatStore.advancedModelParams.reasoningEffort != .automatic {
            details.append("\(chatStore.advancedModelParams.reasoningEffort.title) effort")
        }

        if chatStore.selectedRouteKind == .nearCloud, !chatStore.nearCloudKeyConfigured {
            details.append("key needed")
        }

        if chatStore.selectedRouteKind == .ironclawHosted, !chatStore.ironclawRemoteWorkstationAvailable {
            details.append("Agent setup needed")
        }

        guard !details.isEmpty else { return nil }
        let title = chatStore.isCouncilModeEnabled ? "Route config" : "Next send"
        let symbol = chatStore.isCouncilModeEnabled ? "person.3.fill" : composerModelSymbolName
        return (title, details.joined(separator: " · "), symbol)
    }

    var selectedModelSupportsReasoningEffort: Bool {
        guard let model = chatStore.selectedModelOption else { return false }
        return model.isRecommendedReasoningModel || model.isNearCloudModel
    }

    func reasoningEffortMenuTitle(for effort: ModelReasoningEffort) -> String {
        effort == .automatic ? "Auto effort" : "\(effort.title) effort"
    }

    func reasoningEffortMenuSymbolName(for effort: ModelReasoningEffort) -> String {
        effort == chatStore.advancedModelParams.reasoningEffort ? "checkmark" : "gauge.medium"
    }

    var composerModelSymbolName: String {
        if chatStore.selectedModelOption?.isIronclawModel == true {
            return "terminal"
        }
        if chatStore.selectedRouteUsesNearCloud {
            return "cloud"
        }
        return "cpu"
    }

    func openModelPicker(openingCouncil: Bool) {
        AppHaptics.selection()
        modelPickerOpeningCouncil = openingCouncil
        showingModelPicker = true
    }

    var composerSourceTitle: String {
        if researchButtonActive {
            return "Research"
        }
        switch chatStore.sourceMode {
        case .auto:
            return "Source"
        case .web:
            return "Web"
        case .links:
            return "Links"
        case .files:
            return "Files"
        case .all:
            return "Web + Files"
        }
    }

    var exactProjectSourceModes: [ChatSourceMode] {
        [.links, .files, .all]
    }

    var quickStartSuggestions: [EmptyChatStarterSuggestion] {
        EmptyChatStarterCoordinator.suggestions(for: chatStore)
    }

    var sourceModeControl: some View {
        Button {
            AppHaptics.selection()
            showingSourceModeOptions = true
        } label: {
            ComposerRouteChip(
                title: composerSourceTitle,
                symbolName: composerSourceSymbolName,
                isActive: chatStore.sourceMode != .auto || chatStore.researchModeEnabled,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("composer.chip.source")
        .accessibilityLabel("Source mode \(composerSourceTitle)")
        .accessibilityHint("Choose web, saved link, file, combined, or research context for the next message.")
    }

    @ViewBuilder
    var sourceModeOptionsDialog: some View {
        Button("Auto sources") {
            AppHaptics.selection()
            chatStore.selectSourceMode(.auto)
        }

        Button("Live web") {
            AppHaptics.selection()
            chatStore.selectSourceMode(.web)
        }

        Button("Project context") {
            selectProjectSourceMode()
        }

        Button("Research mode") {
            selectResearchSourceMode()
        }
        .disabled(chatStore.selectedRouteUsesNearCloud)

        ForEach(exactProjectSourceModes) { mode in
            Button(sourceModeMenuTitle(for: mode)) {
                AppHaptics.selection()
                chatStore.selectSourceMode(mode)
                if mode == .files && chatStore.selectedProject == nil && composerStore.pendingAttachments.isEmpty {
                    showingProjectFiles = true
                }
            }
        }
    }

    @ViewBuilder
    var reasoningEffortOptionsDialog: some View {
        ForEach(ModelReasoningEffort.allCases) { effort in
            Button(reasoningEffortMenuTitle(for: effort)) {
                chatStore.setReasoningEffort(effort)
            }
        }

        Button("Advanced model settings") {
            openModelPicker(openingCouncil: false)
        }
    }
}

struct ComposerRouteConfigSheet: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss

    let onChooseModel: () -> Void
    let onChooseCouncil: () -> Void
    let onChooseSource: () -> Void
    let onOpenAccount: () -> Void
    let onOpenAgent: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    configHeader
                    configRow(
                        symbolName: routeSymbolName,
                        title: "Model",
                        value: chatStore.selectedModelDisplayName,
                        detail: routeDetail,
                        actionTitle: "Change",
                        action: onChooseModel
                    )
                    configRow(
                        symbolName: "sparkles",
                        title: "Sources",
                        value: sourceTitle,
                        detail: sourceDetail,
                        actionTitle: "Change",
                        action: onChooseSource
                    )
                    configRow(
                        symbolName: "person.3",
                        title: "Council",
                        value: chatStore.isCouncilModeEnabled ? "On" : "Off",
                        detail: councilDetail,
                        actionTitle: chatStore.isCouncilModeEnabled ? "Edit" : "Set up",
                        action: onChooseCouncil
                    )
                    configRow(
                        symbolName: "gauge.medium",
                        title: "Reasoning",
                        value: chatStore.advancedModelParams.reasoningEffort.title,
                        detail: chatStore.advancedModelParams.reasoningEffort == .automatic
                            ? "The selected route chooses effort automatically."
                            : "Custom effort applies to supported models.",
                        actionTitle: nil,
                        action: nil
                    )
                    readinessActions
                }
                .padding(18)
            }
            .background(Color.appBackground)
            .navigationTitle("Send Config")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .platformMediumDetent()
    }

    private var configHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Next send")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.textPrimary)
            Text(summarySentence)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.control))
        .overlay {
            RoundedRectangle.app(AppRadius.control)
                .stroke(Color.appBorder, lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var readinessActions: some View {
        if chatStore.selectedRouteKind == .nearCloud, !chatStore.nearCloudKeyConfigured {
            Button(action: onOpenAccount) {
                Label("Add NEAR AI Cloud key", systemImage: "key")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.actionPrimary)
        }
        if chatStore.selectedRouteKind == .ironclawHosted, !chatStore.ironclawRemoteWorkstationAvailable {
            Button(action: onOpenAgent) {
                Label("Set up Hosted Agent", systemImage: "terminal")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.actionPrimary)
        }
    }

    private func configRow(
        symbolName: String,
        title: String,
        value: String,
        detail: String,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.controlAccent)
                .frame(width: 30, height: 30)
                .background(Color.actionTint, in: RoundedRectangle.app(AppRadius.pill))

            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 44)
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.control))
        .overlay {
            RoundedRectangle.app(AppRadius.control)
                .stroke(Color.appBorder, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private var summarySentence: String {
        "\(chatStore.selectedModelDisplayName) · \(sourceTitle) · Council \(chatStore.isCouncilModeEnabled ? "on" : "off") · Reasoning \(chatStore.advancedModelParams.reasoningEffort.title.lowercased())."
    }

    private var routeSymbolName: String {
        switch chatStore.selectedRouteKind {
        case .nearPrivate: return "lock.shield"
        case .nearCloud: return "cloud"
        case .ironclawMobile: return "iphone"
        case .ironclawHosted: return "terminal"
        }
    }

    private var routeDetail: String {
        switch chatStore.selectedRouteKind {
        case .nearPrivate:
            return "Private route. Proof can be fetched for supported models."
        case .nearCloud:
            return chatStore.nearCloudKeyConfigured
                ? "External Cloud model through the privacy proxy."
                : "Requires a NEAR AI Cloud key before sending."
        case .ironclawMobile:
            return "Phone-safe Agent route for local app actions."
        case .ironclawHosted:
            return chatStore.ironclawRemoteWorkstationAvailable
                ? "Hosted Agent can run repo, shell, and research tasks."
                : "Requires Hosted IronClaw setup before sending."
        }
    }

    private var sourceTitle: String {
        switch chatStore.sourceMode {
        case .auto: return "Sources as needed"
        case .web: return "Web"
        case .links: return "Links"
        case .files: return "Files"
        case .all: return "Web + Files"
        }
    }

    private var sourceDetail: String {
        switch chatStore.sourceMode {
        case .auto:
            return "The route decides whether files, links, or web context should be used."
        case .web:
            return "Favor live web context where the route supports it."
        case .links:
            return "Use saved links and explicit URL context."
        case .files:
            return "Use attached and project files where allowed by route privacy."
        case .all:
            return "Use web context plus attached and project files where the route allows them."
        }
    }

    private var councilDetail: String {
        if chatStore.isCouncilModeEnabled {
            let count = max(chatStore.activeCouncilModels.count, chatStore.defaultCouncilModels.count)
            return "\(max(count, 2)) models answer independently, then synthesize."
        }
        return "Single selected model answers this send."
    }
}
