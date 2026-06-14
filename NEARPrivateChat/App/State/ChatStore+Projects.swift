import Foundation

@MainActor
extension ChatStore {
    var visibleProjects: [ChatProject] {
        projectStore.visibleProjects
    }

    var archivedProjects: [ChatProject] {
        projectStore.archivedProjects
    }

    var selectedProject: ChatProject? {
        projectStore.selectedProject
    }

    var selectedProjectAttachments: [ChatAttachment] {
        selectedProject?.attachments ?? []
    }

    var selectedProjectInstructions: String {
        selectedProject?.instructions ?? ""
    }

    var selectedProjectMemorySummary: String {
        selectedProject?.memorySummary ?? ""
    }

    var selectedProjectNotes: [ProjectNote] {
        selectedProject?.notes ?? []
    }

    var selectedProjectLinks: [ProjectLink] {
        selectedProject?.links ?? []
    }

    var projectContextRoutePreview: ProjectContextRoutePreview? {
        guard let project = selectedProject else { return nil }
        let semantics = sourceRoutingSemantics
        let publicLinkCount = project.links.filter { link in
            URL(string: link.urlString).map(URLSecurity.isPublicHTTPSURL) == true
        }.count
        let routeTitle = isCouncilModeEnabled ? activeCouncilRouteSummary : selectedRouteKind.disclosureTitle
        return ProjectService.projectContextRoutePreview(
            fileCount: project.attachments.count,
            linkCount: publicLinkCount,
            noteCount: project.notes.count,
            localOnlyNoteCount: project.notes.filter(\.isLocalOnly).count,
            hasInstructions: !project.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasMemory: !project.memorySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            semantics: semantics,
            routeTitle: routeTitle,
            allowsLocalOnlyNotes: projectContextAllowsLocalOnlyNotes
        )
    }

    func isMessageSavedToSelectedProject(_ message: ChatMessage) -> Bool {
        guard message.role == .assistant else {
            return false
        }
        return projectStore.isOutputSavedToSelectedProject(text: message.text, sourceMessageID: message.id)
    }

    func selectProject(_ project: ChatProject) {
        chatSessionCoordinator.selectProject(
            project,
            availableConversations: conversations,
            persistCurrentDraft: { self.persistCurrentDraftIfNeeded() },
            scheduleMessageLoad: { self.scheduleMessageLoad(for: $0) },
            cancelMessageLoad: { self.cancelMessageLoad() },
            transitionDraftScope: { self.transitionDraftScopeToCurrentSelection(loadDraft: true) }
        )
    }

    func createProject(
        named name: String,
        instructions: String = "",
        iconName: String = ProjectIcon.folder.symbolName,
        paletteName: String = ProjectPalette.sky.rawValue
    ) {
        _ = projectStore.createProject(
            named: name,
            conversationID: selectedConversation?.id,
            instructions: instructions,
            iconName: iconName,
            paletteName: paletteName
        )
    }

    func createProjectFromSelectedConversation() {
        guard let selectedConversation else {
            showBanner("Open a chat first.")
            return
        }
        createProject(named: selectedConversation.title)
    }

    func updateProject(
        _ projectID: String,
        name: String,
        iconName: String,
        paletteName: String,
        instructions: String? = nil
    ) {
        projectStore.updateProject(
            projectID,
            name: name,
            iconName: iconName,
            paletteName: paletteName,
            instructions: instructions
        )
    }

    func archiveProject(_ project: ChatProject) {
        chatSessionCoordinator.archiveProject(
            project,
            transitionDraftScope: { self.transitionDraftScopeToCurrentSelection(loadDraft: true) }
        )
    }

    func unarchiveProject(_ project: ChatProject) {
        projectStore.unarchiveProject(project)
    }

    func updateSelectedProjectInstructions(_ instructions: String) {
        projectStore.updateSelectedProjectInstructions(instructions)
    }

    func updateSelectedProjectMemory(_ memory: String) {
        projectStore.updateSelectedProjectMemory(memory)
    }

    func addSelectedProjectLink(title: String, url rawURL: String) {
        projectStore.addSelectedProjectLink(title: title, url: rawURL)
    }

    func addSelectedProjectNote(title: String, text: String, isLocalOnly: Bool = false) {
        projectStore.addSelectedProjectNote(title: title, text: text, isLocalOnly: isLocalOnly)
    }

    func updateSelectedProjectNote(_ note: ProjectNote, title: String, text: String, isLocalOnly: Bool) {
        projectStore.updateSelectedProjectNote(note, title: title, text: text, isLocalOnly: isLocalOnly)
    }

    func deleteProjectLink(_ link: ProjectLink) {
        projectStore.deleteProjectLink(link)
    }

    func saveMessageAsProjectNote(_ message: ChatMessage) {
        guard message.role == .assistant else { return }
        guard selectedProjectID != nil else {
            pendingProjectNoteSaveMessage = message
            showBanner("Create or choose a project to save this output.")
            return
        }
        _ = projectStore.saveOutputAsProjectNote(text: message.text, sourceMessageID: message.id)
    }

    func requestProjectNoteSave(for message: ChatMessage) {
        guard message.role == .assistant else { return }
        guard !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showBanner("No output to save.")
            return
        }
        pendingProjectNoteSaveMessage = message
    }

    func saveMessageAsProjectNote(_ message: ChatMessage, toProjectID projectID: String) {
        guard message.role == .assistant else { return }
        guard projects.contains(where: { $0.id == projectID && !$0.isArchived }) else {
            showBanner("Project not found.")
            return
        }
        if projectStore.saveOutputAsProjectNote(text: message.text, sourceMessageID: message.id, toProjectID: projectID) {
            clearPendingProjectNoteSave()
        }
    }

    func createProjectAndSaveMessageAsNote(
        _ message: ChatMessage,
        named name: String,
        instructions: String = ""
    ) {
        guard message.role == .assistant else { return }
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            showBanner("No output to save.")
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showBanner("Name the project first.")
            return
        }

        _ = projectStore.createProjectAndSaveOutputAsNote(
            text: message.text,
            sourceMessageID: message.id,
            named: trimmed,
            conversationID: selectedConversation?.id,
            instructions: instructions
        )
        clearPendingProjectNoteSave()
    }

    func clearPendingProjectNoteSave() {
        pendingProjectNoteSaveMessage = nil
    }

    func suggestedProjectNameForSavedNote(_ message: ChatMessage) -> String {
        if let conversationTitle = selectedConversation?.title.trimmingCharacters(in: .whitespacesAndNewlines),
           !conversationTitle.isEmpty,
           conversationTitle.localizedCaseInsensitiveCompare("New chat") != .orderedSame {
            return String(conversationTitle.prefix(64))
        }
        return ProjectService.noteTitle(from: message.text)
    }

    func deleteProjectNote(_ note: ProjectNote) {
        projectStore.deleteProjectNote(note)
    }

    func assignSelectedConversation(to projectID: String?) {
        guard let selectedConversation else { return }
        assign(conversationID: selectedConversation.id, to: projectID)
    }

    func assign(conversationID: String, to projectID: String?) {
        projectStore.assign(conversationID: conversationID, to: projectID)
    }

    private var projectContextAllowsLocalOnlyNotes: Bool {
        if isCouncilModeEnabled {
            return !activeCouncilHasExternalRoutes
        }
        return selectedRouteKind == .nearPrivate || selectedRouteKind == .ironclawMobile
    }
}
