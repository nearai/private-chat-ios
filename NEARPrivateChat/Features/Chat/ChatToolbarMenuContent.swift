import SwiftUI

struct ChatToolbarMenuContent: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var modelCatalogStore: ModelCatalogStore
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var agentStore: AgentStore
    @EnvironmentObject private var conversationStore: ConversationStore
    @ObservedObject var transcriptStore: ChatTranscriptStore
    @Binding var showingShare: Bool
    @Binding var showingSecurity: Bool
    @Binding var showingSharedLink: Bool
    @Binding var showingRename: Bool
    @Binding var showingProjectFiles: Bool
    @Binding var showingSignedExportNotice: Bool
    @Binding var showingFindBar: Bool
    let prepareExport: (ConversationExportFormat) -> Void
    let copyCurrentTranscript: () -> Void

    var body: some View {
        Section("Navigate") {
            Button {
                showingFindBar = true
            } label: {
                Label("Find in Conversation", systemImage: "magnifyingglass")
            }
            .disabled(transcriptStore.messages.isEmpty)
            if shouldShowAgentWorkspaceButton {
                Button {
                    chatStore.selectModel(chatStore.ironclawRemoteWorkstationAvailable ? ModelOption.ironclawModelID : ModelOption.ironclawMobileModelID)
                    chatStore.draft = chatStore.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Agent mission: "
                        : "Agent mission: \(chatStore.draft)"
                } label: {
                    Label("Run as Agent", systemImage: "terminal")
                }
            }
            Button {
                showingSecurity = true
            } label: {
                Label("Proof", systemImage: "checkmark.shield")
            }
            Button {
                showingProjectFiles = true
            } label: {
                Label("Project Context", systemImage: "folder.badge.gearshape")
            }
            .disabled(projectStore.selectedProject == nil)
            Button {
                showingSharedLink = true
            } label: {
                Label("Open Shared Link", systemImage: "link.badge.plus")
            }
        }

        Section("Edit") {
            Button {
                showingRename = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .disabled(conversationStore.selectedConversation == nil)
            Button {
                if let conversation = conversationStore.selectedConversation {
                    chatStore.cloneConversation(conversation)
                }
            } label: {
                Label("Branch from here", systemImage: "doc.on.doc")
            }
            .disabled(conversationStore.selectedConversation == nil)
        }

        Section("Export") {
            Button {
                showingShare = true
            } label: {
                Label("Share Link", systemImage: "link")
            }
            .disabled(conversationStore.selectedConversation == nil)
            Button {
                copyCurrentTranscript()
            } label: {
                Label("Copy Transcript", systemImage: "doc.text")
            }
            .disabled(transcriptStore.messages.isEmpty)
            Button {
                prepareExport(.text)
            } label: {
                Label("Export TXT", systemImage: "doc.plaintext")
            }
            .disabled(transcriptStore.messages.isEmpty)
            Button {
                prepareExport(.markdown)
            } label: {
                Label("Export Markdown", systemImage: "text.alignleft")
            }
            .disabled(transcriptStore.messages.isEmpty)
            Button {
                prepareExport(.json)
            } label: {
                Label("Export JSON", systemImage: "curlybraces")
            }
            .disabled(transcriptStore.messages.isEmpty)
            Button {
                showingSignedExportNotice = true
            } label: {
                Label("Export Signed JSON", systemImage: "checkmark.shield")
            }
            .disabled(transcriptStore.messages.isEmpty)
            Button {
                prepareExport(.pdf)
            } label: {
                Label("Export PDF", systemImage: "doc.richtext")
            }
            .disabled(transcriptStore.messages.isEmpty)
            Button {
                prepareExport(.docx)
            } label: {
                Label("Export Word Document", systemImage: "doc.richtext.fill")
            }
            .disabled(transcriptStore.messages.isEmpty)
        }

        Section("Organize") {
            Button {
                chatStore.createProjectFromSelectedConversation()
            } label: {
                Label("New Project from Chat", systemImage: "folder.badge.plus")
            }
            .disabled(conversationStore.selectedConversation == nil)
            Menu {
                Button {
                    chatStore.assignSelectedConversation(to: nil)
                } label: {
                    Label("No Project", systemImage: "tray")
                }
                ForEach(projectStore.projects) { project in
                    Button {
                        chatStore.assignSelectedConversation(to: project.id)
                    } label: {
                        Label(project.name, systemImage: "folder")
                    }
                }
            } label: {
                Label("Move to Project", systemImage: "folder")
            }
            .disabled(conversationStore.selectedConversation == nil)
            Button {
                if let conversation = conversationStore.selectedConversation {
                    chatStore.togglePinConversation(conversation)
                }
            } label: {
                Label(
                    conversationStore.selectedConversation?.isPinned == true ? "Unpin" : "Pin",
                    systemImage: conversationStore.selectedConversation?.isPinned == true ? "pin.slash" : "pin"
                )
            }
            .disabled(conversationStore.selectedConversation == nil)
            Button {
                if let conversation = conversationStore.selectedConversation {
                    chatStore.archiveConversation(conversation)
                }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .disabled(conversationStore.selectedConversation == nil)
        }

        Section("Destructive") {
            Button(role: .destructive) {
                if let conversation = conversationStore.selectedConversation {
                    conversationStore.requestDeleteConversation(conversation)
                }
            } label: {
                Label("Delete Permanently", systemImage: "trash")
            }
            .disabled(conversationStore.selectedConversation == nil)
        }
    }

    private var shouldShowAgentWorkspaceButton: Bool {
        modelCatalogStore.selectedProviderDisplayName == "IronClaw" || agentStore.ironclawRemoteWorkstationAvailable
    }
}
