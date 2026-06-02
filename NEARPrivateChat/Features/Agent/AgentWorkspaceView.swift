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
