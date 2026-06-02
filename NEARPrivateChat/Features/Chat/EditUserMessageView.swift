import SwiftUI

struct EditUserMessageView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    let message: ChatMessage
    @State private var prompt: String

    init(message: ChatMessage) {
        self.message = message
        _prompt = State(initialValue: message.text)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Edit prompt", text: $prompt, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(5...12)
                        .padding(10)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } header: {
                    Text("Edit Prompt")
                } footer: {
                    Text("Starts a new branch from the original turn.")
                }

                if !message.attachments.isEmpty {
                    Section("Kept Files") {
                        ForEach(message.attachments) { attachment in
                            Label {
                                Text(attachment.name)
                                    .lineLimit(1)
                            } icon: {
                                Image(systemName: attachment.systemImageName)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Edit Message")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        chatStore.editAndResend(message, replacementText: prompt)
                        dismiss()
                    }
                    .disabled(trimmedPrompt.isEmpty && message.attachments.isEmpty)
                }
            }
        }
        .platformMediumDetent()
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
