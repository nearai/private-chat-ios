import SwiftUI

struct AgentWorkspaceView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var agentStore: AgentStore
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingAccountSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AgentReadinessBreadcrumb {
                        showingAccountSettings = true
                    }
                        .environmentObject(agentStore)

                    if agentStore.ironclawRemoteWorkstationAvailable {
                        AgentMissionControlPanel()
                            .environmentObject(chatStore)
                            .environmentObject(agentStore)
                    } else {
                        AgentWorkspaceHeader()
                            .environmentObject(agentStore)
                        AgentWorkspaceSetupPanel {
                            showingAccountSettings = true
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
                .frame(maxWidth: 640, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .background(Color.appBackground)
            .navigationTitle(agentStore.ironclawRemoteWorkstationAvailable ? "Agent" : "Connect Agent")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAccountSettings) {
                AccountSettingsView(
                    initialDeepLink: .ironclawAgent,
                    onRunSetupAgain: {},
                    isCurrentChatEmpty: { chatStore.selectedConversation == nil && chatStore.transcriptStore.messages.isEmpty }
                )
                    .environmentObject(agentStore)
                    .environmentObject(accountStore)
                    .environmentObject(sessionStore)
            }
        }
        .platformLargeDetent()
    }
}

private struct AgentReadinessBreadcrumb: View {
    @EnvironmentObject private var agentStore: AgentStore
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: agentStore.ironclawRemoteWorkstationAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(agentStore.ironclawRemoteWorkstationAvailable ? Color.proofVerified : Color.proofStale)
                    .frame(width: 26, height: 26)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(readinessTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text(readinessDetail)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if !agentStore.ironclawRemoteWorkstationAvailable {
                Button(action: onOpenSettings) {
                    Label("Open Agent setup", systemImage: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.actionPrimary)
            }
        }
        .padding(10)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(readinessTitle). \(readinessDetail)")
    }

    private var readinessTitle: String {
        if agentStore.ironclawRemoteWorkstationAvailable {
            return "Agent — Ready (2/2)"
        }
        return "Agent — Not ready (\(completedStepCount)/2)"
    }

    private var readinessDetail: String {
        let missing = missingItems
        if missing.isEmpty {
            if agentStore.ironclawTokenConfigured {
                return "Hosted URL and Agent token are saved. Check hosted tools if commands fail."
            }
            return "Hosted URL is usable. Add an Agent token for authenticated hosted tools."
        }
        return "Missing \(missing.joined(separator: " and "))."
    }

    private var missingItems: [String] {
        var items: [String] = []
        if !agentStore.ironclawSettings.hasUsableHostedEndpoint {
            items.append("Hosted IronClaw URL")
        } else if !agentStore.ironclawSettings.isEnabled {
            items.append("Hosted IronClaw toggle")
        }
        if !agentStore.ironclawTokenConfigured {
            items.append("Agent token")
        }
        return items
    }

    private var completedStepCount: Int {
        max(0, 2 - missingItems.count)
    }
}
