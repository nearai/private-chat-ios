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

    var composerRoutingControls: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
