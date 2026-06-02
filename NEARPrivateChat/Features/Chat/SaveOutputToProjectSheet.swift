import SwiftUI

struct SaveOutputToProjectSheet: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss

    let message: ChatMessage

    @State private var projectName = ""
    @State private var instructions = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Save output", systemImage: "bookmark.fill")
                            .font(.headline)
                        Text("Create a Project for this chat or save into an existing Project.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Create Project")
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(Color.textSecondary)

                        TextField("Project name", text: $projectName)
                            .font(.body)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        TextField("Project instructions", text: $instructions, axis: .vertical)
                            .font(.subheadline)
                            .textFieldStyle(.plain)
                            .lineLimit(3...6)
                            .padding(12)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Button {
                            chatStore.createProjectAndSaveMessageAsNote(
                                message,
                                named: projectName,
                                instructions: instructions
                            )
                            dismiss()
                        } label: {
                            Label("Create Project and Save", systemImage: "folder.badge.plus")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.actionPrimary)
                        .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(14)
                    .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.appBorder, lineWidth: 1)
                    }

                    if !chatStore.visibleProjects.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Existing Projects")
                                .font(.caption.weight(.semibold))
                                .textCase(.uppercase)
                                .foregroundStyle(Color.textSecondary)

                            ForEach(chatStore.visibleProjects) { project in
                                Button {
                                    chatStore.saveMessageAsProjectNote(message, toProjectID: project.id)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: project.projectIconName)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(project.tintColor)
                                            .frame(width: 34, height: 34)
                                            .background(project.tintBackgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(project.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            Text(project.notes.count == 1 ? "1 note" : "\(project.notes.count) notes")
                                                .font(.caption)
                                                .foregroundStyle(Color.textSecondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "arrow.down.forward.circle")
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                    .padding(12)
                                    .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.appBorder, lineWidth: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.appBackground)
            .navigationTitle("Save to Project")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        chatStore.clearPendingProjectNoteSave()
                        dismiss()
                    }
                }
            }
        }
        .platformMediumDetent()
        .onAppear {
            if projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                projectName = chatStore.suggestedProjectNameForSavedNote(message)
            }
        }
    }
}
