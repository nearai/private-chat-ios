import SwiftUI
import UniformTypeIdentifiers

// MARK: - ProjectFilesView (Claude Design — Project Context spec)
//
// Sheet opened from the chat-thread ellipsis menu. Three sections:
//   1. Knowledge  — files as horizontal pills (132×116) + Add tile
//   2. Instructions — single clamped card with inline Edit link
//   3. Chats in this project — inset list, hairline dividers
//
// Empty state (no files, no instructions): NearMark + caption + primary
// "Add a file" button.

struct ProjectFilesView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss

    @State private var showingFileImporter = false
    @State private var showingInstructionsEditor = false
    @State private var projectInstructions = ""
    @State private var projectMemory = ""
    @State private var pendingAttachmentDelete: ChatAttachment?
    @State private var pendingLinkDelete: ProjectLink?

    var body: some View {
        NavigationStack {
            Group {
                if isEmptyProject {
                    emptyState
                } else {
                    populatedScroll
                }
            }
            .background(Color.appBackground)
            .navigationTitle(chatStore.selectedProject?.name ?? "Untitled project")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingFileImporter = true
                        } label: {
                            Label("Add File", systemImage: "paperclip")
                        }
                        Button {
                            showingInstructionsEditor = true
                        } label: {
                            Label("Edit Instructions", systemImage: "text.alignleft")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Project actions")
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.pdf, .plainText, .text, .commaSeparatedText, .json, .data],
                allowsMultipleSelection: true
            ) { result in
                if case let .success(urls) = result {
                    Task {
                        for url in urls.prefix(12) {
                            await chatStore.addProjectAttachment(from: url)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingInstructionsEditor) {
                ProjectInstructionsEditorSheet(
                    instructions: $projectInstructions,
                    memory: $projectMemory,
                    instructionsChanged: instructionsChanged,
                    memoryChanged: memoryChanged,
                    saveAction: {
                        if instructionsChanged {
                            chatStore.updateSelectedProjectInstructions(projectInstructions)
                        }
                        if memoryChanged {
                            chatStore.updateSelectedProjectMemory(projectMemory)
                        }
                    }
                )
            }
            .confirmationDialog(
                "Remove this file from the project?",
                isPresented: pendingAttachmentDeletePresented,
                titleVisibility: .visible
            ) {
                Button("Remove File", role: .destructive) {
                    if let pendingAttachmentDelete {
                        chatStore.removeProjectAttachment(pendingAttachmentDelete)
                    }
                    pendingAttachmentDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingAttachmentDelete = nil
                }
            }
            .confirmationDialog(
                "Remove this link from the project?",
                isPresented: pendingLinkDeletePresented,
                titleVisibility: .visible
            ) {
                Button("Remove Link", role: .destructive) {
                    if let pendingLinkDelete {
                        chatStore.deleteProjectLink(pendingLinkDelete)
                    }
                    pendingLinkDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingLinkDelete = nil
                }
            }
        }
        .platformLargeDetent()
        .onAppear { syncProjectFields() }
        .onChange(of: chatStore.selectedProject?.id) { syncProjectFields() }
    }

    // MARK: - Populated layout

    private var populatedScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                knowledgeSection
                instructionsSection
                chatsSection
            }
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var knowledgeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProjectSectionLabel("Knowledge")
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(chatStore.selectedProjectAttachments) { attachment in
                        ProjectFilePill(
                            title: attachment.name,
                            subtitle: attachment.displaySize ?? attachment.displayKind
                        ) {
                            pendingAttachmentDelete = attachment
                        }
                    }

                    ForEach(chatStore.selectedProjectLinks) { link in
                        ProjectFilePill(
                            title: link.displayTitle,
                            subtitle: link.host ?? "Saved link",
                            symbolName: "link"
                        ) {
                            pendingLinkDelete = link
                        }
                    }

                    ProjectAddFilePill {
                        showingFileImporter = true
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProjectSectionLabel("Instructions")
                .padding(.horizontal, 16)
            ProjectInstructionsCard(
                text: instructionsBodyText,
                isPlaceholder: !hasInstructions,
                onEdit: { showingInstructionsEditor = true }
            )
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var chatsSection: some View {
        let conversations = projectConversations
        VStack(alignment: .leading, spacing: 10) {
            ProjectSectionLabel("Chats in this project")
                .padding(.horizontal, 16)

            if conversations.isEmpty {
                Text("New conversations started inside this project will appear here.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.appBorder, lineWidth: 0.5)
                    }
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(conversations.enumerated()), id: \.element.id) { index, conversation in
                        ProjectChatRow(
                            conversation: conversation,
                            showsDivider: index != conversations.count - 1,
                            onSelect: {
                                chatStore.selectConversation(conversation)
                                dismiss()
                            }
                        )
                    }
                }
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 0.5)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 20) {
                NearMark(size: 56)
                Text("Add a file or paste instructions to get started.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Add a file", systemImage: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 22)
                        .frame(height: 50)
                        .background(Color.actionPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bindings

    private var pendingAttachmentDeletePresented: Binding<Bool> {
        Binding(
            get: { pendingAttachmentDelete != nil },
            set: { if !$0 { pendingAttachmentDelete = nil } }
        )
    }

    private var pendingLinkDeletePresented: Binding<Bool> {
        Binding(
            get: { pendingLinkDelete != nil },
            set: { if !$0 { pendingLinkDelete = nil } }
        )
    }

    // MARK: - Derived state

    private var isEmptyProject: Bool {
        chatStore.selectedProjectAttachments.isEmpty &&
            chatStore.selectedProjectLinks.isEmpty &&
            !hasInstructions
    }

    private var hasInstructions: Bool {
        !chatStore.selectedProjectInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var instructionsBodyText: String {
        let trimmed = chatStore.selectedProjectInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No project instructions yet." : trimmed
    }

    private var projectConversations: [ConversationSummary] {
        guard let selectedProject = chatStore.selectedProject else { return [] }
        let ids = Set(selectedProject.conversationIDs)
        return chatStore.conversations.filter { ids.contains($0.id) && !$0.isArchived }
    }

    private var instructionsChanged: Bool {
        projectInstructions.trimmingCharacters(in: .whitespacesAndNewlines) !=
            chatStore.selectedProjectInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var memoryChanged: Bool {
        projectMemory.trimmingCharacters(in: .whitespacesAndNewlines) !=
            chatStore.selectedProjectMemorySummary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func syncProjectFields() {
        projectInstructions = chatStore.selectedProjectInstructions
        projectMemory = chatStore.selectedProjectMemorySummary
    }
}

// MARK: - Section label

private struct ProjectSectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.textSecondary)
            .tracking(0.4)
    }
}

// MARK: - File pill

private struct ProjectFilePill: View {
    let title: String
    let subtitle: String
    var symbolName: String = "doc.text"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.actionTint)
                    Image(systemName: symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.actionPrimary)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 132, height: 116, alignment: .topLeading)
            .padding(12)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(subtitle). Tap to remove.")
    }
}

// MARK: - Add file pill

private struct ProjectAddFilePill: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.actionPrimary)
                .frame(width: 132, height: 116)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.appBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add file")
    }
}

// MARK: - Instructions card

private struct ProjectInstructionsCard: View {
    let text: String
    let isPlaceholder: Bool
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    (
                        Text(text)
                            .foregroundStyle(isPlaceholder ? Color.textSecondary : Color.primary)
                        + Text(" ")
                        + Text("Edit")
                            .foregroundStyle(Color.actionPrimary)
                            .font(.system(size: 15, weight: .medium))
                    )
                    .font(.system(size: 15, weight: .regular))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.top, 3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chat row

private struct ProjectChatRow: View {
    let conversation: ConversationSummary
    let showsDivider: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottom) {
                HStack(alignment: .center, spacing: 12) {
                    Text(conversation.title)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(relativeTimeText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 60)

                if showsDivider {
                    Rectangle()
                        .fill(Color.appHairline)
                        .frame(height: 0.5)
                        .padding(.leading, 14)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var relativeTimeText: String {
        guard let createdAt = conversation.createdAt else { return "Recent" }
        return ProjectContextFreshness.relativeDateText(for: Date(timeIntervalSince1970: createdAt))
    }
}

// MARK: - Instructions editor sheet (preserved)

private struct ProjectInstructionsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var instructions: String
    @Binding var memory: String
    let instructionsChanged: Bool
    let memoryChanged: Bool
    let saveAction: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Instructions") {
                    TextField("How should the assistant handle this project?", text: $instructions, axis: .vertical)
                        .lineLimit(4...8)
                }
                Section("Notes") {
                    TextField("What should the assistant remember?", text: $memory, axis: .vertical)
                        .lineLimit(4...8)
                }
            }
            .navigationTitle("Instructions")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAction()
                        dismiss()
                    }
                    .disabled(!instructionsChanged && !memoryChanged)
                }
            }
        }
        .platformMediumDetent()
    }
}

// MARK: - Project context freshness helpers (preserved)

enum ProjectContextFreshness {
    static func label(for timeInterval: TimeInterval?, prefix: String) -> String? {
        guard let timeInterval else { return nil }
        return label(for: Date(timeIntervalSince1970: timeInterval), prefix: prefix)
    }

    static func label(for date: Date, prefix: String) -> String {
        "\(prefix) \(relativeDateText(for: date))"
    }

    static func relativeDateText(for date: Date) -> String {
        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 60 {
            return "just now"
        }
        if elapsed < 3600 {
            return "\(Int(elapsed / 60))m ago"
        }
        if elapsed < 86_400 {
            return "\(Int(elapsed / 3600))h ago"
        }
        if elapsed < 604_800 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Archived chats (preserved for ChatStore.archiveBindings flow)

struct ArchivedChatsView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showingArchiveExporter = false
    @State private var archiveDocument = ConversationExportDocument()

    private var archived: [ConversationSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return chatStore.archivedConversations }
        return chatStore.archivedConversations.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
                $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    private var archivedJSON: String {
        guard let data = try? JSONEncoder().encode(chatStore.archivedConversations),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
              let pretty = String(data: prettyData, encoding: .utf8) else {
            return "[]"
        }
        return pretty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "archivebox")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.actionPrimary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(chatStore.archivedConversations.count) archived conversations")
                                .font(.headline)
                            Text("Restore chats when you need them back, or delete them permanently.")
                                .font(.footnote)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Conversations") {
                    if archived.isEmpty {
                        ContentUnavailableView("No archived conversations", systemImage: "archivebox")
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(archived) { conversation in
                            HStack(spacing: 10) {
                                Image(systemName: "bubble.left")
                                    .foregroundStyle(Color.actionPrimary)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(conversation.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    if let createdAt = conversation.createdAt {
                                        Text(Date(timeIntervalSince1970: createdAt), style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer(minLength: 0)

                                Button {
                                    chatStore.unarchiveConversation(conversation)
                                } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Unarchive")

                                Button(role: .destructive) {
                                    chatStore.requestDeleteConversation(conversation)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Delete")
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                if !chatStore.archivedConversations.isEmpty {
                    Section {
                        Button {
                            chatStore.unarchiveAllConversations()
                        } label: {
                            Label("Unarchive All", systemImage: "arrow.uturn.backward.circle")
                        }

                        Button {
                            Clipboard.copy(archivedJSON)
                            chatStore.bannerMessage = "Archived JSON copied."
                        } label: {
                            Label("Copy Archive JSON", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            archiveDocument = ConversationExportDocument(data: Data(archivedJSON.utf8))
                            showingArchiveExporter = true
                        } label: {
                            Label("Export Archive JSON", systemImage: "square.and.arrow.up.on.square")
                        }
                    }
                }
            }
            .navigationTitle("Archived")
            .platformInlineNavigationTitle()
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search archived chats")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onChange(of: chatStore.openSelectedConversationToken) { _, token in
                if token != nil {
                    dismiss()
                }
            }
            .fileExporter(
                isPresented: $showingArchiveExporter,
                document: archiveDocument,
                contentType: .json,
                defaultFilename: archiveFilename
            ) { result in
                switch result {
                case .success:
                    chatStore.bannerMessage = "Archive JSON exported."
                case let .failure(error):
                    chatStore.bannerMessage = error.localizedDescription
                }
            }
        }
    }

    private var archiveFilename: String {
        let date = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return "near-private-chat-archive-\(date).json"
    }
}
