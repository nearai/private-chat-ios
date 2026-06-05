import SwiftUI

extension InputBar {
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

                sourceModeControl

                if selectedModelSupportsReasoningEffort {
                    Menu {
                        ForEach(ModelReasoningEffort.allCases) { effort in
                            Button {
                                chatStore.setReasoningEffort(effort)
                            } label: {
                                Label(reasoningEffortMenuTitle(for: effort), systemImage: reasoningEffortMenuSymbolName(for: effort))
                            }
                        }
                        Divider()
                        Button {
                            openModelPicker(openingCouncil: false)
                        } label: {
                            Label("Advanced model settings", systemImage: "slider.horizontal.3")
                        }
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
        Menu {
            Section("Source mode") {
                Button {
                    AppHaptics.selection()
                    chatStore.selectSourceMode(.auto)
                } label: {
                    Label("Auto sources", systemImage: sourceModeMenuSymbolName(isActive: sourceModeControlIsAuto, fallback: ChatSourceMode.auto.symbolName))
                }

                Button {
                    AppHaptics.selection()
                    chatStore.selectSourceMode(.web)
                } label: {
                    Label("Live web", systemImage: sourceModeMenuSymbolName(isActive: sourceModeControlIsWeb, fallback: ChatSourceMode.web.symbolName))
                }

                Button {
                    selectProjectSourceMode()
                } label: {
                    Label("Project context", systemImage: sourceModeMenuSymbolName(isActive: sourceModeControlIsProject, fallback: "folder.badge.gearshape"))
                }

                Button {
                    selectResearchSourceMode()
                } label: {
                    Label("Research mode", systemImage: sourceModeMenuSymbolName(isActive: researchButtonActive, fallback: "doc.text.magnifyingglass"))
                }
                .disabled(chatStore.selectedRouteUsesNearCloud)
            }

            Section("Project context") {
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
