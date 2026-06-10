import SwiftUI
import UniformTypeIdentifiers

// MARK: - ProjectFilesView (Claude Design — Project Context spec)
//
// Sheet opened from the chat-thread ellipsis menu. Main sections:
// sources, instructions, notes, conversations, and next actions.
//
// Empty state (no files, no instructions): NearMark + caption + primary
// "Add a file" button.

struct ProjectFilesView: View {
    @EnvironmentObject private var projectStore: ProjectStore
    @Environment(\.dismiss) private var dismiss
    private let projectContextRoutePreview: @MainActor () -> ProjectContextRoutePreview?
    private let addProjectAttachment: @MainActor (URL) async -> Void
    private let removeProjectAttachment: @MainActor (ChatAttachment) -> Void
    private let onOpenConversation: @MainActor (ConversationSummary) -> Void
    private let onStagePrompt: @MainActor (String) -> Void

    @State private var showingFileImporter = false
    @State private var showingNewProject = false
    @State private var showingInstructionsEditor = false
    @State private var showingLinkEditor = false
    @State private var showingNoteEditor = false
    @State private var projectInstructions = ""
    @State private var projectMemory = ""
    @State private var linkTitle = ""
    @State private var linkURL = ""
    @State private var noteTitle = ""
    @State private var noteText = ""
    @State private var noteIsLocalOnly = false
    @State private var pendingAttachmentDelete: ChatAttachment?
    @State private var pendingLinkDelete: ProjectLink?
    @State private var pendingNoteDelete: ProjectNote?
    @State private var activeNoteDetail: ProjectNote?
    @State private var editingNote: ProjectNote?

    init(
        projectContextRoutePreview: @escaping @MainActor () -> ProjectContextRoutePreview?,
        addProjectAttachment: @escaping @MainActor (URL) async -> Void,
        removeProjectAttachment: @escaping @MainActor (ChatAttachment) -> Void,
        onOpenConversation: @escaping @MainActor (ConversationSummary) -> Void,
        onStagePrompt: @escaping @MainActor (String) -> Void
    ) {
        self.projectContextRoutePreview = projectContextRoutePreview
        self.addProjectAttachment = addProjectAttachment
        self.removeProjectAttachment = removeProjectAttachment
        self.onOpenConversation = onOpenConversation
        self.onStagePrompt = onStagePrompt
    }

    var body: some View {
        NavigationStack {
            Group {
                if projectStore.selectedProject == nil {
                    projectSelectionState
                } else if isEmptyProject {
                    emptyState
                } else {
                    populatedScroll
                }
            }
            .background(Color.appBackground)
            .navigationTitle(projectStore.selectedProject?.name ?? "Choose Project")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if projectStore.selectedProject == nil {
                        Button {
                            showingNewProject = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.body.weight(.semibold))
                        }
                        .accessibilityLabel("New Project")
                    } else {
                        Menu {
                            Button {
                                showingFileImporter = true
                            } label: {
                                Label("Add File", systemImage: "paperclip")
                            }
                            Button {
                                showingLinkEditor = true
                            } label: {
                                Label("Add Link", systemImage: "link.badge.plus")
                            }
                            Button {
                                beginAddingNote()
                            } label: {
                                Label("Add Note", systemImage: "note.text.badge.plus")
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
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [
                    .pdf,
                    .plainText,
                    .text,
                    .commaSeparatedText,
                    .json,
                    .image,
                    UTType(filenameExtension: "tsv") ?? .text,
                    UTType(filenameExtension: "xlsx") ?? .data,
                    UTType(filenameExtension: "xls") ?? .data,
                    .data
                ],
                allowsMultipleSelection: true
            ) { result in
                if case let .success(urls) = result {
                    Task {
                        for url in urls.prefix(12) {
                            await addProjectAttachment(url)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingNewProject) {
                NewProjectView()
                    .environmentObject(projectStore)
            }
            .sheet(isPresented: $showingInstructionsEditor) {
                ProjectInstructionsEditorSheet(
                    instructions: $projectInstructions,
                    memory: $projectMemory,
                    instructionsChanged: instructionsChanged,
                    memoryChanged: memoryChanged,
                    saveAction: {
                        if instructionsChanged {
                            projectStore.updateSelectedProjectInstructions(projectInstructions)
                        }
                        if memoryChanged {
                            projectStore.updateSelectedProjectMemory(projectMemory)
                        }
                    }
                )
            }
            .sheet(isPresented: $showingLinkEditor) {
                ProjectLinkEditorSheet(title: $linkTitle, url: $linkURL) {
                    projectStore.addSelectedProjectLink(title: linkTitle, url: linkURL)
                    linkTitle = ""
                    linkURL = ""
                }
            }
            .sheet(isPresented: $showingNoteEditor) {
                ProjectNoteEditorSheet(
                    title: $noteTitle,
                    text: $noteText,
                    isLocalOnly: $noteIsLocalOnly
                ) {
                    projectStore.addSelectedProjectNote(title: noteTitle, text: noteText, isLocalOnly: noteIsLocalOnly)
                    noteTitle = ""
                    noteText = ""
                    noteIsLocalOnly = false
                }
            }
            .sheet(item: $editingNote) { note in
                ProjectNoteEditorSheet(
                    title: $noteTitle,
                    text: $noteText,
                    isLocalOnly: $noteIsLocalOnly,
                    navigationTitle: "Edit Note",
                    confirmationTitle: "Save"
                ) {
                    projectStore.updateSelectedProjectNote(
                        note,
                        title: noteTitle,
                        text: noteText,
                        isLocalOnly: noteIsLocalOnly
                    )
                }
            }
            .sheet(item: $activeNoteDetail) { note in
                ProjectNoteDetailSheet(
                    note: note,
                    onEdit: { beginEditingNoteFromDetail(note) },
                    onDelete: { beginDeletingNoteFromDetail(note) }
                )
            }
            .confirmationDialog(
                "Remove this file from the project?",
                isPresented: pendingAttachmentDeletePresented,
                titleVisibility: .visible
            ) {
                Button("Remove File", role: .destructive) {
                    if let pendingAttachmentDelete {
                        removeProjectAttachment(pendingAttachmentDelete)
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
                        projectStore.deleteProjectLink(pendingLinkDelete)
                    }
                    pendingLinkDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingLinkDelete = nil
                }
            }
            .confirmationDialog(
                "Delete this note?",
                isPresented: pendingNoteDeletePresented,
                titleVisibility: .visible
            ) {
                Button("Delete Note", role: .destructive) {
                    if let pendingNoteDelete {
                        projectStore.deleteProjectNote(pendingNoteDelete)
                    }
                    pendingNoteDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingNoteDelete = nil
                }
            }
        }
        .platformLargeDetent()
        .onAppear { syncProjectFields() }
        .onChange(of: projectStore.selectedProject?.id) { syncProjectFields() }
    }

    // MARK: - Populated layout

    private var projectSelectionState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    NearMark(size: 52)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Choose a Project first")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Project context keeps files, links, notes, and action drafts together so chat can turn any input into next moves.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        showingNewProject = true
                    } label: {
                        Label("Create Project", systemImage: "plus")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.actionPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 0.5)
                }

                if projectStore.visibleProjects.isEmpty {
                    Text("No Projects yet. Create one to attach files, save links, keep notes, and route Project-aware prompts from chat.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ProjectSectionLabel("Recent Projects")
                        VStack(spacing: 0) {
                            ForEach(Array(projectStore.visibleProjects.prefix(8).enumerated()), id: \.element.id) { index, project in
                                Button {
                                    projectStore.selectProject(project)
                                } label: {
                                    ProjectRow(
                                        title: project.name,
                                        subtitle: projectSelectionSubtitle(for: project),
                                        symbolName: project.projectIconName,
                                        isSelected: false,
                                        tintColor: project.tintColor,
                                        tintBackground: project.tintBackgroundColor
                                    )
                                }
                                .buttonStyle(.plain)

                                if index != min(projectStore.visibleProjects.count, 8) - 1 {
                                    Divider()
                                        .padding(.leading, 54)
                                }
                            }
                        }
                        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.appBorder, lineWidth: 0.5)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var populatedScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let preview = projectContextRoutePreview() {
                    ProjectContextRoutePreviewRow(preview: preview)
                        .padding(.horizontal, 16)
                }
                if let project = projectStore.selectedProject {
                    ProjectContextSummaryBar(project: project)
                        .padding(.horizontal, 16)
                }
                actionShelfSection
                // Chats lead: a project is primarily its conversations
                // (matching how the best AI-chat project surfaces read), with
                // files and instructions as supporting context.
                chatsSection
                knowledgeSection
                instructionsSection
                memoryNotesSection
            }
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var knowledgeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProjectSectionLabel("Sources")
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(projectStore.selectedProjectAttachments) { attachment in
                        ProjectFilePill(
                            title: attachment.name,
                            subtitle: attachment.displaySize ?? attachment.displayKind,
                            action: {
                                stageKnowledgeItemPrompt(title: attachment.name, kind: attachment.displayKind)
                            },
                            removeAction: {
                                pendingAttachmentDelete = attachment
                            }
                        )
                    }

                    ForEach(projectStore.selectedProjectLinks) { link in
                        ProjectFilePill(
                            title: link.displayTitle,
                            subtitle: link.host ?? "Saved link",
                            symbolName: "link",
                            action: {
                                stageKnowledgeItemPrompt(title: link.displayTitle, kind: "link")
                            },
                            removeAction: {
                                pendingLinkDelete = link
                            }
                        )
                    }

                    ProjectAddFilePill {
                        showingFileImporter = true
                    }
                    ProjectAddFilePill(title: "Add link", symbolName: "link") {
                        showingLinkEditor = true
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
    private var memoryNotesSection: some View {
        let memory = projectStore.selectedProjectMemorySummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = projectStore.selectedProjectNotes
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ProjectSectionLabel("Saved answers")
                Spacer(minLength: 0)
                Button {
                    beginAddingNote()
                } label: {
                    Label("Add note", systemImage: "plus")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.actionPrimary)
            }
            .padding(.horizontal, 16)

            if memory.isEmpty && notes.isEmpty {
                Button {
                    beginAddingNote()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "note.text.badge.plus")
                            .foregroundStyle(Color.actionPrimary)
                        Text("Answers you save land here, plus notes, decisions, and local-only details.")
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.appBorder, lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    if !memory.isEmpty {
                        ProjectMemoryRow(
                            title: "Saved context",
                            text: memory,
                            symbolName: "brain.head.profile",
                            showsDivider: !notes.isEmpty
                        )
                    }
                    ForEach(Array(notes.prefix(6).enumerated()), id: \.element.id) { index, note in
                        ProjectNoteRow(
                            note: note,
                            showsDivider: index != min(notes.count, 6) - 1,
                            onOpen: { activeNoteDetail = note },
                            onEdit: { beginEditingNote(note) },
                            onDelete: { pendingNoteDelete = note }
                        )
                    }
                }
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 0.5)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private var chatsSection: some View {
        let conversations = projectConversations
        VStack(alignment: .leading, spacing: 10) {
            ProjectSectionLabel("Conversations")
                .padding(.horizontal, 16)

            if conversations.isEmpty {
                Text("New conversations in this Project will appear here.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                                onOpenConversation(conversation)
                                dismiss()
                            }
                        )
                    }
                }
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 0.5)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            VStack(spacing: 20) {
                NearMark(size: 56)
                Text("Add sources or start the first Project conversation.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Add a file", systemImage: "plus")
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 22)
                        .frame(height: 50)
                        .background(Color.actionPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                HStack(spacing: 12) {
                    Button {
                        showingLinkEditor = true
                    } label: {
                        Label("Add link", systemImage: "link")
                    }
                    Button {
                        beginAddingNote()
                    } label: {
                        Label("Add note", systemImage: "note.text")
                    }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.actionPrimary)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
            ProjectActionShelf(
                projectName: projectStore.selectedProject?.name,
                hasContext: false,
                onSelect: stageProjectAction
            )
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionShelfSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProjectSectionLabel("Next actions")
                .padding(.horizontal, 16)
            ProjectActionShelf(
                projectName: projectStore.selectedProject?.name,
                hasContext: !isEmptyProject,
                onSelect: stageProjectAction
            )
            .padding(.horizontal, 16)
        }
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

    private var pendingNoteDeletePresented: Binding<Bool> {
        Binding(
            get: { pendingNoteDelete != nil },
            set: { if !$0 { pendingNoteDelete = nil } }
        )
    }

    // MARK: - Derived state

    private var isEmptyProject: Bool {
        projectStore.selectedProjectAttachments.isEmpty &&
            projectStore.selectedProjectLinks.isEmpty &&
            projectStore.selectedProjectNotes.isEmpty &&
            projectStore.selectedProjectMemorySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !hasInstructions
    }

    private var hasInstructions: Bool {
        !projectStore.selectedProjectInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var instructionsBodyText: String {
        let trimmed = projectStore.selectedProjectInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No project instructions yet." : trimmed
    }

    private func projectSelectionSubtitle(for project: ChatProject) -> String {
        var parts: [String] = []
        let contextItemCount = project.attachments.count + project.links.count + project.notes.count
        if contextItemCount > 0 {
            parts.append("\(contextItemCount) item\(contextItemCount == 1 ? "" : "s")")
        }
        if !project.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Instructions")
        }
        if !project.conversationIDs.isEmpty {
            parts.append("\(project.conversationIDs.count) chat\(project.conversationIDs.count == 1 ? "" : "s")")
        }
        if parts.isEmpty {
            return "Ready for files, links, notes, and prompts"
        }
        return parts.joined(separator: " · ")
    }

    private var projectConversations: [ConversationSummary] {
        guard let selectedProject = projectStore.selectedProject else { return [] }
        let ids = Set(selectedProject.conversationIDs)
        return projectStore.conversations.filter { ids.contains($0.id) && !$0.isArchived }
    }

    private var instructionsChanged: Bool {
        projectInstructions.trimmingCharacters(in: .whitespacesAndNewlines) !=
            projectStore.selectedProjectInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var memoryChanged: Bool {
        projectMemory.trimmingCharacters(in: .whitespacesAndNewlines) !=
            projectStore.selectedProjectMemorySummary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func syncProjectFields() {
        projectInstructions = projectStore.selectedProjectInstructions
        projectMemory = projectStore.selectedProjectMemorySummary
    }

    private func beginAddingNote() {
        noteTitle = ""
        noteText = ""
        noteIsLocalOnly = false
        showingNoteEditor = true
    }

    private func beginEditingNote(_ note: ProjectNote) {
        noteTitle = note.title
        noteText = note.text
        noteIsLocalOnly = note.isLocalOnly
        editingNote = note
    }

    private func beginEditingNoteFromDetail(_ note: ProjectNote) {
        activeNoteDetail = nil
        DispatchQueue.main.async {
            beginEditingNote(note)
        }
    }

    private func beginDeletingNoteFromDetail(_ note: ProjectNote) {
        activeNoteDetail = nil
        DispatchQueue.main.async {
            pendingNoteDelete = note
        }
    }

    private func stageProjectAction(_ action: ProjectActionKind) {
        let prompt = ProjectActionPromptFactory.prompt(
            for: action,
            projectName: projectStore.selectedProject?.name
        )
        stagePrompt(prompt)
    }

    private func stageKnowledgeItemPrompt(title: String, kind: String) {
        let projectName = (projectStore.selectedProject?.name).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let projectLine: String
        if let projectName, !projectName.isEmpty {
            projectLine = " in the \(projectName) project"
        } else {
            projectLine = ""
        }
        let prompt = """
        Review \(kind) "\(title)"\(projectLine) and turn it into actionable next moves. Identify trackers, briefings, reminders, calendar-worthy items, tasks, decisions, risks, open questions, and things I should care about. Preserve concrete names, quantities, dates, cadences, timing, and caveats. Preview exact app commands before creating anything.
        """
        stagePrompt(prompt)
    }

    private func stagePrompt(_ prompt: String) {
        onStagePrompt(prompt)
        AppHaptics.selection()
        dismiss()
    }
}
