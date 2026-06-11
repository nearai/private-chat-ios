import SwiftUI

extension ShareInviteRecipient {
    var displayName: String {
        value
    }

    var shareSheetFieldValue: String {
        value
    }
}

struct PublicLinkPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let conversation: ConversationSummary
    let messageCount: Int
    let sourceCount: Int
    let attestationStatus: AttestationStatus
    let isWorking: Bool
    let onConfirm: () async -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "globe")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color.primaryAction)
                                .frame(width: 42, height: 42)
                                .background(Color.primaryAction.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(conversation.title)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text("Anyone with the URL can read this Conversation until you disable the link.")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(Color.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        AttestationStatusBadge(status: attestationStatus, modelID: nil)
                    }
                    .padding(.vertical, 4)
                }

                Section("Preview") {
                    SharePreviewRow(title: "Permission", value: "Read-only", symbolName: "eye")
                    SharePreviewRow(title: "Messages", value: "\(messageCount)", symbolName: "bubble.left.and.bubble.right")
                    SharePreviewRow(title: "Sources", value: sourceCount == 0 ? "None attached" : "\(sourceCount)", symbolName: "link")
                    SharePreviewRow(title: "Account metadata", value: "Owner identity stays off the link preview.", symbolName: "person.crop.circle.badge.xmark")
                }

                Section {
                    Button {
                        Task {
                            await onConfirm()
                            dismiss()
                        }
                    } label: {
                        Label("Create link", systemImage: "link.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.primaryAction)
                    .disabled(isWorking)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.surface)
            .navigationTitle("Public link")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .platformMediumDetent()
    }
}

private struct SharePreviewRow: View {
    let title: String
    let value: String
    let symbolName: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.primaryAction)
                .frame(width: 28, height: 28)
                .background(Color.primaryAction.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(value)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }
}

struct ShareGroupsView: View {
    @EnvironmentObject private var shareStore: ShareStore
    @Environment(\.dismiss) private var dismiss
    @State private var groupName = ""
    @State private var groupMembers = ""
    @State private var editingShareGroup: ShareGroupInfo?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "person.3")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.brandAccent)
                            .frame(width: 42, height: 42)
                            .background(Color.appBlueTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Share Groups")
                                .font(.headline)
                            Text("Reusable groups for people you share with.")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Groups") {
                    if shareStore.isLoadingShareGroups {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading groups")
                                .foregroundStyle(.secondary)
                        }
                    } else if shareStore.shareGroups.isEmpty {
                        ContentUnavailableView("No share groups", systemImage: "person.3")
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(shareStore.shareGroups) { group in
                            HStack(spacing: 10) {
                                Image(systemName: "person.3")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.brandAccent)
                                    .frame(width: 30, height: 30)
                                    .background(Color.appBlueTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text(shareGroupSubtitle(group))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                Button {
                                    beginEditing(group)
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.borderless)
                                .disabled(isWorking)
                                .accessibilityLabel("Edit Share Group")

                                Button(role: .destructive) {
                                    Task { await delete(group) }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .disabled(isWorking)
                                .accessibilityLabel("Delete Share Group")
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                Section(editingShareGroup == nil ? "Create Group" : "Edit Group") {
                    if let editingShareGroup {
                        HStack {
                            Label("Editing \(editingShareGroup.name)", systemImage: "pencil")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.brandAccent)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Button("Cancel") {
                                cancelEditing()
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }

                    TextField("Group name", text: $groupName)
                        .textFieldStyle(.plain)
                        .padding(11)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    TextField("email@company.com, alice.near", text: $groupMembers, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .lineLimit(2...4)
                        .textFieldStyle(.plain)
                        .padding(11)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Button {
                        Task { await saveGroup() }
                    } label: {
                        Label(editingShareGroup == nil ? "Create Group" : "Save Group", systemImage: editingShareGroup == nil ? "plus" : "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.actionPrimary)
                    .disabled(saveDisabled)
                }
            }
            .navigationTitle("Share Groups")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await shareStore.refreshShareGroups(showErrors: false)
            }
        }
        .platformMediumDetent()
    }

    private var saveDisabled: Bool {
        groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            groupMembers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            isWorking
    }

    private func saveGroup() async {
        isWorking = true
        defer { isWorking = false }

        if let editingShareGroup {
            await shareStore.updateShareGroup(editingShareGroup, name: groupName, rawMembers: groupMembers)
            cancelEditing()
        } else {
            await shareStore.createShareGroup(name: groupName, rawMembers: groupMembers)
            groupName = ""
            groupMembers = ""
        }
    }

    private func delete(_ group: ShareGroupInfo) async {
        isWorking = true
        defer { isWorking = false }
        await shareStore.deleteShareGroup(group)
        if editingShareGroup?.id == group.id {
            cancelEditing()
        }
    }

    private func beginEditing(_ group: ShareGroupInfo) {
        editingShareGroup = group
        groupName = group.name
        groupMembers = group.members.map(\.shareSheetFieldValue).joined(separator: ", ")
    }

    private func cancelEditing() {
        editingShareGroup = nil
        groupName = ""
        groupMembers = ""
    }

    private func shareGroupSubtitle(_ group: ShareGroupInfo) -> String {
        let count = "\(group.members.count) member\(group.members.count == 1 ? "" : "s")"
        let preview = group.members.prefix(2).map(\.displayName).joined(separator: ", ")
        guard !preview.isEmpty else { return count }
        return "\(count) · \(preview)\(group.members.count > 2 ? ", +" : "")"
    }
}
