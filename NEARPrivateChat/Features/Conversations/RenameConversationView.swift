import SwiftUI

struct RenameConversationView: View {
    @EnvironmentObject private var conversationStore: ConversationStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Conversation Title")
                    .font(.headline)
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                Spacer()
            }
            .padding()
            .navigationTitle("Rename")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                }
            }
            .onAppear {
                title = conversationStore.selectedConversationTitle
            }
        }
        .platformMediumDetent()
    }

    private func save() async {
        isWorking = true
        defer { isWorking = false }
        guard let conversation = conversationStore.selectedConversation else {
            conversationStore.showBanner("Select a conversation first.")
            return
        }
        do {
            try await conversationStore.renameConversation(conversation, title: title)
            dismiss()
        } catch {
            conversationStore.showBanner(error.localizedDescription)
        }
    }
}
