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
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    var onOpenConversation: ((ConversationSummary) -> Void)?
    var onStagePrompt: ((String) -> Void)?

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

    var body: some View {
        NavigationStack {
            Group {
                if chatStore.selectedProject == nil {
                    projectSelectionState
                } else if isEmptyProject {
                    emptyState
                } else {
                    populatedScroll
                }
            }
            .background(Color.appBackground)
            .navigationTitle(chatStore.selectedProject?.name ?? "Choose Project")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if chatStore.selectedProject == nil {
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
                            await chatStore.addProjectAttachment(from: url)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingNewProject) {
                NewProjectView()
                    .environmentObject(chatStore)
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
            .sheet(isPresented: $showingLinkEditor) {
                ProjectLinkEditorSheet(title: $linkTitle, url: $linkURL) {
                    chatStore.addSelectedProjectLink(title: linkTitle, url: linkURL)
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
                    chatStore.addSelectedProjectNote(title: noteTitle, text: noteText, isLocalOnly: noteIsLocalOnly)
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
                    chatStore.updateSelectedProjectNote(
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
            .confirmationDialog(
                "Delete this note?",
                isPresented: pendingNoteDeletePresented,
                titleVisibility: .visible
            ) {
                Button("Delete Note", role: .destructive) {
                    if let pendingNoteDelete {
                        chatStore.deleteProjectNote(pendingNoteDelete)
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
        .onChange(of: chatStore.selectedProject?.id) { syncProjectFields() }
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
                        Text("Project context keeps files, links, notes, and action drafts together so chat can turn arbitrary inputs into next moves.")
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

                if chatStore.visibleProjects.isEmpty {
                    Text("No existing Projects yet. Create one to attach files, save links, keep notes, and route project-aware prompts from chat.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ProjectSectionLabel("Recent Projects")
                        VStack(spacing: 0) {
                            ForEach(Array(chatStore.visibleProjects.prefix(8).enumerated()), id: \.element.id) { index, project in
                                Button {
                                    chatStore.selectProject(project)
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

                                if index != min(chatStore.visibleProjects.count, 8) - 1 {
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
                if let preview = chatStore.projectContextRoutePreview {
                    ProjectContextRoutePreviewRow(preview: preview)
                        .padding(.horizontal, 16)
                }
                actionShelfSection
                knowledgeSection
                instructionsSection
                memoryNotesSection
                chatsSection
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
                    ForEach(chatStore.selectedProjectAttachments) { attachment in
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

                    ForEach(chatStore.selectedProjectLinks) { link in
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
        let memory = chatStore.selectedProjectMemorySummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = chatStore.selectedProjectNotes
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ProjectSectionLabel("Notes")
                Spacer(minLength: 0)
                Button {
                    beginAddingNote()
                } label: {
                    Label("Add Note", systemImage: "plus")
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
                        Text("Add a note, decision, reminder, or local-only detail.")
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
                Text("New conversations started inside this Project will appear here.")
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
                                if let onOpenConversation {
                                    onOpenConversation(conversation)
                                } else {
                                    chatStore.selectConversation(conversation)
                                    dismiss()
                                }
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
                projectName: chatStore.selectedProject?.name,
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
                projectName: chatStore.selectedProject?.name,
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
        chatStore.selectedProjectAttachments.isEmpty &&
            chatStore.selectedProjectLinks.isEmpty &&
            chatStore.selectedProjectNotes.isEmpty &&
            chatStore.selectedProjectMemorySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !hasInstructions
    }

    private var hasInstructions: Bool {
        !chatStore.selectedProjectInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var instructionsBodyText: String {
        let trimmed = chatStore.selectedProjectInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
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
            projectName: chatStore.selectedProject?.name
        )
        stagePrompt(prompt)
    }

    private func stageKnowledgeItemPrompt(title: String, kind: String) {
        let projectName = (chatStore.selectedProject?.name).map {
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
        if let onStagePrompt {
            onStagePrompt(prompt)
        } else {
            chatStore.draft = prompt
            chatStore.bannerMessage = "Project prompt ready."
            AppHaptics.selection()
            dismiss()
        }
    }
}

// MARK: - Project action shelf

enum ProjectActionKind: String, CaseIterable, Identifiable {
    case createPrompt
    case findActions
    case makeTracker
    case askAgent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .createPrompt:
            return "Start conversation"
        case .findActions:
            return "Find next actions"
        case .makeTracker:
            return "Make tracker"
        case .askAgent:
            return "Run Agent"
        }
    }

    var subtitle: String {
        switch self {
        case .createPrompt:
            return "Shape this Project"
        case .findActions:
            return "Tasks, risks, decisions"
        case .makeTracker:
            return "Briefings and reminders"
        case .askAgent:
            return "Preview a run"
        }
    }

    var symbolName: String {
        switch self {
        case .createPrompt:
            return "text.badge.plus"
        case .findActions:
            return "checklist"
        case .makeTracker:
            return "calendar.badge.clock"
        case .askAgent:
            return "point.3.connected.trianglepath.dotted"
        }
    }
}

enum ProjectActionPromptFactory {
    static func prompt(for action: ProjectActionKind, projectName: String?) -> String {
        let subject = projectSubject(projectName)
        switch action {
        case .createPrompt:
            return """
            Help me turn \(subject) into a useful working project. Ask one question at a time until you know what should be remembered, what should be tracked, what should become a recurring briefing, what belongs on my calendar, and what actions should be created. Preview the resulting project instructions and starter commands before saving anything.
            """
        case .findActions:
            return """
            Review \(subject) and turn the context into actionable next moves. Identify trackers, briefings, reminders, calendar-worthy events, tasks, decisions, risks, open questions, and anything I am likely to care about. For each item include why it matters, missing details, structured fields where known (source, date, time, recurrence, timezone, attendees, confidence), and the exact app command that would create or stage it. If useful, emit a near-widget action_plan with missing_fields. Preview first.
            """
        case .makeTracker:
            return """
            Use \(subject) to propose recurring trackers, scheduled briefings, reminders, or calendar invites. Preserve concrete names, quantities, dates, cadences, timing, and caveats from the source context. For each proposal include the trigger or schedule, source, notification behavior, structured fields, missing_fields, confidence, and exact app command. Emit a near-widget action_plan when there is more than one candidate. Do not create anything until I confirm.
            """
        case .askAgent:
            return """
            Use \(subject) to design an agent run. Show what project context or files would be sent, the route and capabilities needed, the steps the agent would take, risks or irreversible actions, and the expected output. Wait for my confirmation before running the agent.
            """
        }
    }

    private static func projectSubject(_ projectName: String?) -> String {
        let trimmed = projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "this project" }
        return "the \(trimmed) project"
    }
}

private struct ProjectActionShelf: View {
    let projectName: String?
    let hasContext: Bool
    let onSelect: (ProjectActionKind) -> Void

    private var actions: [ProjectActionKind] {
        hasContext ? [.findActions, .makeTracker, .askAgent] : ProjectActionKind.allCases
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(actions) { action in
                Button {
                    onSelect(action)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: action.symbolName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.actionPrimary)
                            .frame(width: 30, height: 30)
                            .background(Color.actionTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                            Text(action.subtitle)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.appBorder, lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(action.title), \(action.subtitle)")
            }
        }
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
    }
}

// MARK: - Route/source preview

private struct ProjectContextRoutePreviewRow: View {
    let preview: ProjectContextRoutePreview

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: preview.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(preview.usesAttentionStyle ? Color.proofStale : Color.actionPrimary)
                .frame(width: 26, height: 26)
                .background(
                    (preview.usesAttentionStyle ? Color.proofStale.opacity(0.12) : Color.actionTint),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(preview.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = preview.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - File pill

private struct ProjectFilePill: View {
    let title: String
    let subtitle: String
    var symbolName: String = "doc.text"
    let action: () -> Void
    let removeAction: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.actionTint)
                        Image(systemName: symbolName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.actionPrimary)
                    }
                    .frame(width: 28, height: 28)

                    Spacer(minLength: 0)

                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 24, height: 24)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.footnote)
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.caption2)
                        .fontWeight(.regular)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 132, height: 116, alignment: .topLeading)
            .padding(12)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                removeAction()
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .accessibilityLabel("\(title), \(subtitle). Tap to stage an action prompt.")
        .accessibilityAction(named: "Remove", removeAction)
    }
}

// MARK: - Add file pill

private struct ProjectAddFilePill: View {
    var title: String = "Add file"
    var symbolName: String = "plus"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(.system(size: 22, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
                .foregroundStyle(Color.actionPrimary)
                .frame(width: 132, height: 116)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.appBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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
                            .font(.subheadline.weight(.medium))
                    )
                    .font(.subheadline)
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
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Project memory row

private struct ProjectMemoryRow: View {
    let title: String
    let text: String
    let symbolName: String
    let showsDivider: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.actionPrimary)
                    .frame(width: 28, height: 28)
                    .background(Color.actionTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsDivider {
                Rectangle()
                    .fill(Color.appHairline)
                    .frame(height: 0.5)
                    .padding(.leading, 54)
            }
        }
    }
}

private struct ProjectNoteRow: View {
    let note: ProjectNote
    let showsDivider: Bool
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: onOpen) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "note.text")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.actionPrimary)
                            .frame(width: 28, height: 28)
                            .background(Color.actionTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(note.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(1)
                                ProjectNoteStatusBadge(note: note)
                            }
                            Text(note.text)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Menu {
                    Button {
                        onOpen()
                    } label: {
                        Label("View Details", systemImage: "doc.text.magnifyingglass")
                    }
                    Button {
                        onEdit()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("Note actions")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsDivider {
                Rectangle()
                    .fill(Color.appHairline)
                    .frame(height: 0.5)
                    .padding(.leading, 54)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ProjectNoteStatusBadge: View {
    let note: ProjectNote

    var body: some View {
        Label(note.projectContextStatusTitle, systemImage: note.projectContextStatusSymbolName)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(note.isLocalOnly ? Color.proofStale : Color.actionPrimary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                (note.isLocalOnly ? Color.proofStale.opacity(0.12) : Color.actionTint),
                in: Capsule()
            )
            .accessibilityLabel(note.projectContextStatusDescription)
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
                        .font(.body)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(relativeTimeText)
                        .font(.footnote)
                        .fontWeight(.regular)
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

private struct ProjectLinkEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var title: String
    @Binding var url: String
    let saveAction: () -> Void

    private var canSave: Bool {
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Link") {
                    TextField("Title", text: $title)
                    TextField("https://example.com/source", text: $url)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Add Link")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveAction()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .platformMediumDetent()
    }
}

private struct ProjectNoteDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let note: ProjectNote
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(note.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        ProjectNoteStatusBadge(note: note)
                    }

                    Text(note.text)
                        .font(.body)
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let sourceMessageID = note.sourceMessageID {
                        Label("Saved from message \(sourceMessageID)", systemImage: "text.bubble")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.appBackground)
            .navigationTitle("Project Note")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            onEdit()
                            dismiss()
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Note actions")
                }
            }
        }
        .platformMediumDetent()
    }
}

private struct ProjectNoteEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var title: String
    @Binding var text: String
    @Binding var isLocalOnly: Bool
    var navigationTitle = "Add Note"
    var confirmationTitle = "Add"
    let saveAction: () -> Void

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Note") {
                    TextField("Title", text: $title)
                    TextField("Decision, reminder, context, or next action", text: $text, axis: .vertical)
                        .lineLimit(4...8)
                }

                Section {
                    Toggle("Keep on this phone", isOn: $isLocalOnly)
                } footer: {
                    Text("Local-only notes are omitted from Hosted IronClaw and cloud routes.")
                }
            }
            .navigationTitle(navigationTitle)
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmationTitle) {
                        saveAction()
                        dismiss()
                    }
                    .disabled(!canSave)
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
