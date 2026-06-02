import SwiftUI

extension InputBar {
    var composerRoutingControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
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
                .accessibilityLabel(chatStore.isCouncilModeEnabled ? "LLM Council active" : "Configure LLM Council")
                .accessibilityHint("Opens the Council lineup for the next message.")

                if selectedModelSupportsReasoningEffort {
                    Menu {
                        ForEach(ModelReasoningEffort.allCases) { effort in
                            Button {
                                chatStore.setReasoningEffort(effort)
                            } label: {
                                Label(effort.title, systemImage: effort == chatStore.advancedModelParams.reasoningEffort ? "checkmark" : "circle")
                            }
                        }
                        Divider()
                        Button {
                            openModelPicker(openingCouncil: false)
                        } label: {
                            Label("Open model settings", systemImage: "slider.horizontal.3")
                        }
                    } label: {
                        ComposerRouteChip(
                            title: "Effort \(chatStore.advancedModelParams.reasoningEffort.title)",
                            symbolName: "gauge.medium",
                            isActive: chatStore.advancedModelParams.reasoningEffort != .automatic,
                            showsChevron: false
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

    var composerRouteControl: some View {
        Menu {
            Button {
                openModelPicker(openingCouncil: false)
            } label: {
                Label("Model: \(chatStore.selectedModelDisplayName)", systemImage: composerModelSymbolName)
            }

            Button {
                openModelPicker(openingCouncil: true)
            } label: {
                Label(
                    chatStore.isCouncilModeEnabled ? "Council: \(chatStore.activeCouncilModels.count) models" : "Use Council",
                    systemImage: "person.3"
                )
            }

            if selectedModelSupportsReasoningEffort {
                Divider()
                ForEach(ModelReasoningEffort.allCases) { effort in
                    Button {
                        chatStore.setReasoningEffort(effort)
                    } label: {
                        Label("Effort: \(effort.title)", systemImage: effort == chatStore.advancedModelParams.reasoningEffort ? "checkmark" : "gauge.medium")
                    }
                }
            }

            Divider()

            Button {
                AppHaptics.selection()
                chatStore.selectSourceMode(.auto)
            } label: {
                Label("Auto sources", systemImage: sourceModeMenuSymbolName(isActive: sourceModeControlIsAuto))
            }

            Button {
                AppHaptics.selection()
                chatStore.selectSourceMode(.web)
            } label: {
                Label("Web", systemImage: sourceModeMenuSymbolName(isActive: sourceModeControlIsWeb))
            }

            Button {
                selectProjectSourceMode()
            } label: {
                Label("Project", systemImage: sourceModeMenuSymbolName(isActive: sourceModeControlIsProject))
            }

            Button {
                selectResearchSourceMode()
            } label: {
                Label("Research", systemImage: sourceModeMenuSymbolName(isActive: researchButtonActive, fallback: "doc.text.magnifyingglass"))
            }
            .disabled(chatStore.selectedRouteUsesNearCloud)

            Divider()

            ForEach(exactProjectSourceModes) { mode in
                Button {
                    AppHaptics.selection()
                    chatStore.selectSourceMode(mode)
                    if mode == .files && chatStore.selectedProject == nil && composerStore.pendingAttachments.isEmpty {
                        showingProjectFiles = true
                    }
                } label: {
                    Label(sourceModeMenuTitle(for: mode), systemImage: exactSourceModeMenuSymbolName(for: mode))
                }
            }

            if !quickStartSuggestions.isEmpty {
                Divider()

                Section("Quick starts") {
                    ForEach(quickStartSuggestions) { suggestion in
                        Button {
                            applyQuickStartSuggestion(suggestion)
                        } label: {
                            Label(suggestion.title, systemImage: suggestion.symbolName)
                        }
                    }
                }
            }
        } label: {
            ComposerRouteChip(
                title: composerRouteSummaryTitle,
                symbolName: composerRouteSummarySymbolName,
                isActive: composerRouteIsCustomized,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Route \(composerRouteSummaryTitle)")
        .accessibilityHint("Choose model, Council, effort, web, research, project files, or saved links for the next message.")
    }

    var composerRouteSummaryTitle: String {
        var parts: [String] = []
        if chatStore.isCouncilModeEnabled {
            parts.append("Council \(chatStore.activeCouncilModels.count)")
        } else if chatStore.selectedRouteKind == .nearPrivate {
            parts.append("Private")
        } else {
            parts.append(chatStore.selectedProviderDisplayName)
        }

        if chatStore.sourceMode != .auto || chatStore.researchModeEnabled {
            parts.append(composerSourceTitle)
        }

        if chatStore.advancedModelParams.reasoningEffort != .automatic {
            parts.append(chatStore.advancedModelParams.reasoningEffort.title)
        }

        return parts.prefix(2).joined(separator: " · ")
    }

    var composerRouteSummarySymbolName: String {
        if chatStore.isCouncilModeEnabled {
            return "person.3"
        }
        if researchButtonActive {
            return "doc.text.magnifyingglass"
        }
        if chatStore.sourceMode == .web {
            return "globe"
        }
        if chatStore.sourceMode != .auto {
            return "folder"
        }
        return composerModelSymbolName
    }

    var composerRouteIsCustomized: Bool {
        chatStore.isCouncilModeEnabled ||
            chatStore.sourceMode != .auto ||
            chatStore.researchModeEnabled ||
            chatStore.selectedRouteKind != .nearPrivate ||
            chatStore.advancedModelParams.reasoningEffort != .automatic
    }

    var selectedModelSupportsReasoningEffort: Bool {
        guard let model = chatStore.selectedModelOption else { return false }
        return model.isRecommendedReasoningModel || model.isNearCloudModel
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
            return "Auto"
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
        Menu {
            Button {
                AppHaptics.selection()
                chatStore.selectSourceMode(.auto)
            } label: {
                Label("Auto", systemImage: sourceModeMenuSymbolName(isActive: sourceModeControlIsAuto))
            }

            Button {
                AppHaptics.selection()
                chatStore.selectSourceMode(.web)
            } label: {
                Label("Web", systemImage: sourceModeMenuSymbolName(isActive: sourceModeControlIsWeb))
            }

            Button {
                selectProjectSourceMode()
            } label: {
                Label("Project", systemImage: sourceModeMenuSymbolName(isActive: sourceModeControlIsProject))
            }

            Button {
                selectResearchSourceMode()
            } label: {
                Label("Research", systemImage: sourceModeMenuSymbolName(isActive: researchButtonActive, fallback: "doc.text.magnifyingglass"))
            }
            .disabled(chatStore.selectedRouteUsesNearCloud)

            Divider()

            ForEach(exactProjectSourceModes) { mode in
                Button {
                    AppHaptics.selection()
                    chatStore.selectSourceMode(mode)
                    if mode == .files && chatStore.selectedProject == nil && composerStore.pendingAttachments.isEmpty {
                        showingProjectFiles = true
                    }
                } label: {
                    Label(sourceModeMenuTitle(for: mode), systemImage: exactSourceModeMenuSymbolName(for: mode))
                }
            }
        } label: {
            ComposerRouteChip(
                title: composerSourceTitle,
                symbolName: composerSourceSymbolName,
                isActive: chatStore.sourceMode != .auto || chatStore.researchModeEnabled,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Source mode \(composerSourceTitle)")
        .accessibilityHint("Choose web, saved link, file, combined, or research context for the next message.")
    }
}
