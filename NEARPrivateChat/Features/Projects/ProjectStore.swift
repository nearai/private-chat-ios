import Foundation

enum ProjectPromptFileAddStatus: Equatable {
    case failed
    case skipped
    case completed
}

typealias ProjectToolMutationStatus = ProjectPromptFileAddStatus

struct ProjectPromptFileAddResult: Equatable {
    var status: ProjectToolMutationStatus
    var summary: String
    var detail: String?
}

struct ProjectToolMutationResult: Equatable {
    var status: ProjectToolMutationStatus
    var summary: String
    var detail: String?
}

struct ProjectHostedHandoffDisclosure: Equatable, Hashable {
    var disclosedItems: [String]
    var fingerprint: String
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [ChatProject]
    @Published private(set) var selectedProjectID: String?
    @Published private(set) var conversations: [ConversationSummary]

    var bannerHandler: (@MainActor (String) -> Void)?

    private var persistence: ProjectPersistence?
    private let service: ProjectService

    init(
        persistence: ProjectPersistence? = nil,
        projects: [ChatProject] = [],
        selectedProjectID: String? = nil,
        conversations: [ConversationSummary] = [],
        service: ProjectService = ProjectService()
    ) {
        self.persistence = persistence
        self.projects = projects
        self.selectedProjectID = selectedProjectID
        self.conversations = conversations
        self.service = service
    }

    func configure(accountID: String) {
        persistence = ProjectPersistence(accountID: accountID)
        loadPersistedState()
    }

    func loadPersistedState() {
        guard let persistence else { return }
        projects = persistence.loadProjects()
        selectedProjectID = persistence.loadSelectedProjectID()
    }

    func reset(persistSelectedProject: Bool = false) {
        projects = []
        selectedProjectID = nil
        conversations = []
        if persistSelectedProject {
            persistence?.saveSelectedProjectID(nil)
        }
    }

    func replaceProjects(_ projects: [ChatProject], persist: Bool = true) {
        self.projects = projects
        guard persist else { return }
        persistProjects()
    }

    func replaceConversations(_ conversations: [ConversationSummary]) {
        self.conversations = conversations
    }

    func selectProjectID(_ projectID: String?, persist: Bool = true) {
        selectedProjectID = projectID
        guard persist else { return }
        persistence?.saveSelectedProjectID(projectID)
    }

    var selectedProject: ChatProject? {
        guard let selectedProjectID else { return nil }
        return projects.first(where: { $0.id == selectedProjectID && !$0.isArchived })
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

    var selectedHostedHandoffDisclosure: ProjectHostedHandoffDisclosure? {
        guard let selectedProject else { return nil }
        return Self.hostedHandoffDisclosure(for: selectedProject)
    }

    var visibleProjects: [ChatProject] {
        projects
            .filter { !$0.isArchived }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var archivedProjects: [ChatProject] {
        projects
            .filter(\.isArchived)
            .sorted { ($0.archivedAt ?? $0.createdAt) > ($1.archivedAt ?? $1.createdAt) }
    }

    var projectScopedConversations: [ConversationSummary] {
        guard let selectedProject else { return conversations }
        let ids = Set(selectedProject.conversationIDs)
        return conversations.filter { ids.contains($0.id) }
    }

    var visibleConversations: [ConversationSummary] {
        projectScopedConversations
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return (lhs.createdAt ?? 0) > (rhs.createdAt ?? 0)
            }
    }

    var allVisibleConversations: [ConversationSummary] {
        conversations
            .filter { !$0.isArchived }
            .sorted { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) }
    }

    var archivedConversations: [ConversationSummary] {
        conversations
            .filter(\.isArchived)
            .sorted { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) }
    }

    @discardableResult
    func selectProject(_ project: ChatProject) -> Bool {
        guard !project.isArchived else {
            showBanner("Unarchive this project before opening it.")
            return false
        }
        selectProjectID(project.id)
        return true
    }

    static func hostedHandoffDisclosure(for project: ChatProject) -> ProjectHostedHandoffDisclosure {
        var disclosedItems = ["Project: \(project.name)"]
        if !project.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            disclosedItems.append("Project instructions")
        }
        if !project.memorySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            disclosedItems.append("Project memory")
        }
        let hostedNotes = ProjectService.projectNotesForPrompt(project.notes, allowLocalOnly: false)
        if !hostedNotes.isEmpty {
            disclosedItems.append("Saved notes: \(min(hostedNotes.count, 6))")
        }
        let omittedLocalOnlyNotes = project.notes.count - hostedNotes.count
        if omittedLocalOnlyNotes > 0 {
            disclosedItems.append("Local-only notes stay on this phone: \(omittedLocalOnlyNotes)")
        }
        let publicLinks = project.links.filter { link in
            URL(string: link.urlString).map(URLSecurity.isPublicHTTPSURL) == true
        }
        if !publicLinks.isEmpty {
            disclosedItems.append("Source links: \(min(publicLinks.count, 12))")
        }
        if !project.attachments.isEmpty {
            disclosedItems.append("Project file names: \(project.attachments.map(\.name).joined(separator: ", "))")
        }
        let fingerprint = [
            project.id,
            project.instructions,
            project.memorySummary,
            hostedNotes.map { note in
                [note.id, note.title, note.text].joined(separator: "\u{1F}")
            }.joined(separator: "|"),
            project.links.map(\.urlString).joined(separator: "|"),
            project.attachments.map(\.id).joined(separator: "|")
        ].joined(separator: "|")
        return ProjectHostedHandoffDisclosure(disclosedItems: disclosedItems, fingerprint: fingerprint)
    }

    func selectAllProjects() {
        selectProjectID(nil)
    }

    @discardableResult
    func createProject(
        named name: String,
        conversationID: String? = nil,
        instructions: String = "",
        iconName: String = ProjectIcon.folder.symbolName,
        paletteName: String = ProjectPalette.sky.rawValue
    ) -> ChatProject? {
        guard let project = service.makeProject(
            name: name,
            conversationID: conversationID,
            instructions: instructions,
            iconName: iconName,
            paletteName: paletteName
        ) else {
            showBanner("Name the project first.")
            return nil
        }
        projects.insert(project, at: 0)
        selectProjectID(project.id)
        persistProjects()
        showBanner("Project created.")
        return project
    }

    @discardableResult
    func updateProject(
        _ projectID: String,
        name: String,
        iconName: String,
        paletteName: String,
        instructions: String? = nil
    ) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else {
            showBanner("Project not found.")
            return false
        }
        let trimmedName = service.normalizedProjectName(name)
        guard !trimmedName.isEmpty else {
            showBanner("Name the project first.")
            return false
        }
        projects[index].name = trimmedName
        projects[index].iconName = iconName
        projects[index].paletteName = paletteName
        if let instructions {
            projects[index].instructions = service.normalizedInstructions(instructions)
        }
        persistProjects()
        showBanner("Project updated.")
        return true
    }

    @discardableResult
    func archiveProject(_ project: ChatProject) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else {
            showBanner("Project not found.")
            return false
        }
        guard !projects[index].isArchived else {
            showBanner("Project already archived.")
            return false
        }
        projects[index].archivedAt = Date()
        if selectedProjectID == project.id {
            selectProjectID(nil)
        }
        persistProjects()
        showBanner("Project archived.")
        return true
    }

    @discardableResult
    func unarchiveProject(_ project: ChatProject) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else {
            showBanner("Project not found.")
            return false
        }
        guard projects[index].isArchived else {
            showBanner("Project is already active.")
            return false
        }
        projects[index].archivedAt = nil
        persistProjects()
        showBanner("Project restored.")
        return true
    }

    @discardableResult
    func updateSelectedProjectInstructions(_ instructions: String) -> Bool {
        guard let index = selectedProjectIndex() else {
            showBanner("Select a project first.")
            return false
        }
        projects[index].instructions = service.normalizedInstructions(instructions)
        persistProjects()
        showBanner("Project instructions saved.")
        return true
    }

    func setSelectedProjectInstructionsForTool(_ instructions: String) -> ProjectToolMutationResult {
        guard let index = selectedProjectIndex() else {
            return ProjectToolMutationResult(status: .failed, summary: "Create or select a project first.", detail: nil)
        }
        let normalized = service.normalizedInstructions(instructions)
        guard !normalized.isEmpty else {
            return ProjectToolMutationResult(status: .failed, summary: "Missing project instructions.", detail: nil)
        }
        projects[index].instructions = normalized
        persistProjects()
        return ProjectToolMutationResult(
            status: .completed,
            summary: "Updated instructions for project \"\(projects[index].name)\".",
            detail: projects[index].instructions
        )
    }

    @discardableResult
    func updateSelectedProjectMemory(_ memory: String) -> Bool {
        guard let index = selectedProjectIndex() else {
            showBanner("Select a project first.")
            return false
        }
        projects[index].memorySummary = service.normalizedMemory(memory)
        persistProjects()
        showBanner("Project memory saved.")
        return true
    }

    func updateSelectedProjectMemoryForTool(_ memory: String, append: Bool) -> ProjectToolMutationResult {
        guard let index = selectedProjectIndex() else {
            return ProjectToolMutationResult(status: .failed, summary: "Create or select a project first.", detail: nil)
        }
        guard let updatedMemory = service.appendMemory(
            existing: projects[index].memorySummary,
            memory: memory,
            shouldAppend: append
        ) else {
            return ProjectToolMutationResult(status: .failed, summary: "Missing project memory.", detail: nil)
        }
        projects[index].memorySummary = updatedMemory
        persistProjects()
        return ProjectToolMutationResult(
            status: .completed,
            summary: "Updated memory for project \"\(projects[index].name)\".",
            detail: projects[index].memorySummary
        )
    }

    @discardableResult
    func addSelectedProjectLink(title: String, url rawURL: String) -> ProjectLink? {
        guard let index = selectedProjectIndex() else {
            showBanner("Select a project first.")
            return nil
        }
        let result = service.makeLink(title: title, rawURL: rawURL, existingLinks: projects[index].links)
        guard let link = result.link else {
            showBanner(result.message)
            return nil
        }
        projects[index].links.insert(link, at: 0)
        persistProjects()
        showBanner(result.message)
        return link
    }

    func addSourceLinkToSelectedProject(title: String, url rawURL: String) -> ProjectToolMutationResult {
        guard let index = selectedProjectIndex() else {
            return ProjectToolMutationResult(status: .failed, summary: "Create or select a project first.", detail: nil)
        }
        let result = service.makeLink(title: title, rawURL: rawURL, existingLinks: projects[index].links)
        guard let link = result.link else {
            let status: ProjectToolMutationStatus = result.message == "That link is already in this project." ? .skipped : .failed
            let detail = ProjectService.normalizedProjectLinkURL(rawURL)?.absoluteString
            let summary = status == .skipped
                ? "That source link is already saved in \"\(projects[index].name)\"."
                : result.message
            return ProjectToolMutationResult(status: status, summary: summary, detail: detail)
        }
        projects[index].links.insert(link, at: 0)
        persistProjects()
        return ProjectToolMutationResult(
            status: .completed,
            summary: "Added source link to project \"\(projects[index].name)\".",
            detail: "\(link.displayTitle): \(link.urlString)"
        )
    }

    @discardableResult
    func deleteProjectLink(_ link: ProjectLink) -> Bool {
        guard let index = selectedProjectIndex() else { return false }
        projects[index].links.removeAll { $0.id == link.id }
        persistProjects()
        showBanner("Project link removed.")
        return true
    }

    @discardableResult
    func addSelectedProjectNote(title: String, text: String, isLocalOnly: Bool = false) -> ProjectNote? {
        guard let index = selectedProjectIndex() else {
            showBanner("Select a project first.")
            return nil
        }
        let result = service.makeNote(
            title: title,
            text: text,
            isLocalOnly: isLocalOnly,
            existingNotes: projects[index].notes
        )
        guard let note = result.note else {
            showBanner(result.message)
            return nil
        }
        projects[index].notes.insert(note, at: 0)
        persistProjects()
        showBanner(result.message)
        return note
    }

    func saveToolNoteToSelectedProject(title: String?, text: String) -> ProjectToolMutationResult {
        guard let index = selectedProjectIndex() else {
            return ProjectToolMutationResult(status: .failed, summary: "Create or select a project first.", detail: nil)
        }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return ProjectToolMutationResult(status: .failed, summary: "Missing note text.", detail: nil)
        }
        guard projects[index].notes.count < ProjectService.maxNotes else {
            return ProjectToolMutationResult(
                status: .failed,
                summary: "Project \"\(projects[index].name)\" already has the maximum notes.",
                detail: nil
            )
        }
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let note = ProjectNote(
            title: trimmedTitle.isEmpty ? ProjectService.noteTitle(from: trimmedText) : String(trimmedTitle.prefix(ProjectService.maxNameCharacters)),
            text: ProjectService.clipped(trimmedText, maxCharacters: ProjectService.maxNoteTextCharacters),
            sourceMessageID: nil
        )
        projects[index].notes.insert(note, at: 0)
        persistProjects()
        return ProjectToolMutationResult(
            status: .completed,
            summary: "Saved a note to project \"\(projects[index].name)\".",
            detail: note.title
        )
    }

    @discardableResult
    func updateSelectedProjectNote(_ note: ProjectNote, title: String, text: String, isLocalOnly: Bool) -> Bool {
        guard let projectIndex = selectedProjectIndex() else {
            showBanner("Select a project first.")
            return false
        }
        guard let noteIndex = projects[projectIndex].notes.firstIndex(where: { $0.id == note.id }) else {
            showBanner("Project note not found.")
            return false
        }
        let result = service.updatedNote(note, title: title, text: text, isLocalOnly: isLocalOnly)
        guard let updatedNote = result.note else {
            showBanner(result.message)
            return false
        }
        projects[projectIndex].notes[noteIndex] = updatedNote
        persistProjects()
        showBanner(result.message)
        return true
    }

    @discardableResult
    func deleteProjectNote(_ note: ProjectNote) -> Bool {
        guard let index = selectedProjectIndex() else { return false }
        projects[index].notes.removeAll { $0.id == note.id }
        persistProjects()
        showBanner("Project note removed.")
        return true
    }

    func isOutputSavedToSelectedProject(text: String, sourceMessageID: String?) -> Bool {
        guard let project = selectedProject else { return false }
        let clippedText = ProjectService.clipped(
            text.trimmingCharacters(in: .whitespacesAndNewlines),
            maxCharacters: ProjectService.maxNoteTextCharacters
        )
        return project.notes.contains { note in
            (sourceMessageID != nil && note.sourceMessageID == sourceMessageID) ||
                (!clippedText.isEmpty && note.text == clippedText)
        }
    }

    @discardableResult
    func saveOutputAsProjectNote(
        text: String,
        sourceMessageID: String?,
        toProjectID projectID: String? = nil
    ) -> Bool {
        let resolvedProjectID = projectID ?? selectedProjectID
        guard let resolvedProjectID,
              let index = projects.firstIndex(where: { $0.id == resolvedProjectID && !$0.isArchived }) else {
            showBanner("Project not found.")
            return false
        }
        guard let note = service.makeSavedOutputNote(text: text, sourceMessageID: sourceMessageID) else {
            showBanner("No output to save.")
            return false
        }
        if projects[index].notes.contains(where: { existing in
            existing.sourceMessageID == sourceMessageID || existing.text == note.text
        }) {
            showBanner("Already saved to \(projects[index].name).")
            return true
        }
        projects[index].notes.insert(note, at: 0)
        if projects[index].notes.count > ProjectService.maxNotes {
            projects[index].notes = Array(projects[index].notes.prefix(ProjectService.maxNotes))
        }
        selectProjectID(projects[index].id)
        persistProjects()
        showBanner("Saved to \(projects[index].name).")
        return true
    }

    @discardableResult
    func createProjectAndSaveOutputAsNote(
        text: String,
        sourceMessageID: String?,
        named name: String,
        conversationID: String? = nil,
        instructions: String = ""
    ) -> ChatProject? {
        guard let project = createProject(
            named: name,
            conversationID: conversationID,
            instructions: instructions
        ) else {
            return nil
        }
        _ = saveOutputAsProjectNote(text: text, sourceMessageID: sourceMessageID, toProjectID: project.id)
        return selectedProject
    }

    @discardableResult
    func assign(conversationID: String, to projectID: String?) -> Bool {
        var didChange = false
        for index in projects.indices {
            let before = projects[index].conversationIDs.count
            projects[index].conversationIDs.removeAll { $0 == conversationID }
            didChange = didChange || projects[index].conversationIDs.count != before
        }
        if let projectID,
           let index = projects.firstIndex(where: { $0.id == projectID }) {
            if !projects[index].conversationIDs.contains(conversationID) {
                projects[index].conversationIDs.append(conversationID)
                didChange = true
            }
            showBanner("Moved to \(projects[index].name).")
        } else {
            showBanner("Removed from projects.")
        }
        if didChange {
            persistProjects()
        }
        return didChange
    }

    @discardableResult
    func removeConversationFromAllProjects(_ conversationID: String) -> Bool {
        var didChange = false
        for index in projects.indices {
            let before = projects[index].conversationIDs.count
            projects[index].conversationIDs.removeAll { $0 == conversationID }
            didChange = didChange || before != projects[index].conversationIDs.count
        }
        if didChange {
            persistProjects()
        }
        return didChange
    }

    @discardableResult
    func addAttachmentToSelectedProject(
        _ attachment: ChatAttachment,
        maxAttachments: Int,
        notice: String? = nil,
        localDocumentText: String? = nil
    ) -> Bool {
        guard let index = selectedProjectIndex() else {
            showBanner("Select a project first.")
            return false
        }
        return addAttachment(
            attachment,
            toProjectAt: index,
            maxAttachments: maxAttachments,
            notice: notice,
            localDocumentText: localDocumentText
        )
    }

    @discardableResult
    func addAttachment(
        _ attachment: ChatAttachment,
        toProjectID projectID: String,
        maxAttachments: Int,
        notice: String? = nil,
        localDocumentText: String? = nil
    ) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else {
            showBanner("Project not found.")
            return false
        }
        return addAttachment(
            attachment,
            toProjectAt: index,
            maxAttachments: maxAttachments,
            notice: notice,
            localDocumentText: localDocumentText
        )
    }

    @discardableResult
    func removeAttachmentFromSelectedProject(_ attachment: ChatAttachment) -> Bool {
        guard let index = selectedProjectIndex() else { return false }
        projects[index].attachments.removeAll { $0.id == attachment.id }
        persistProjects()
        showBanner("Project file removed.")
        return true
    }

    @discardableResult
    func removeAttachmentFromAllProjects(id attachmentID: String) -> Bool {
        var didChange = false
        for index in projects.indices {
            let before = projects[index].attachments.count
            projects[index].attachments.removeAll { $0.id == attachmentID }
            didChange = didChange || before != projects[index].attachments.count
        }
        if didChange {
            persistProjects()
        }
        return didChange
    }

    @discardableResult
    func addLinkIfNeeded(projectID: String, title: String, urlString: String) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return false }
        guard let normalizedURL = ProjectService.normalizedProjectLinkURL(urlString) else { return false }
        guard !projects[index].links.contains(where: { $0.urlString == normalizedURL.absoluteString }) else { return false }
        projects[index].links.insert(ProjectLink(title: title, urlString: normalizedURL.absoluteString), at: 0)
        persistProjects()
        return true
    }

    @discardableResult
    func ensureProject(named rawName: String, includeConversationID conversationID: String?) -> ChatProject {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = projectIndex(matching: name) {
            var didChange = false
            if projects[index].isArchived {
                projects[index].archivedAt = nil
                didChange = true
            }
            selectProjectID(projects[index].id)
            if let conversationID, !projects[index].conversationIDs.contains(conversationID) {
                projects[index].conversationIDs.append(conversationID)
                didChange = true
            }
            if didChange {
                persistProjects()
            }
            return projects[index]
        }

        let project = ChatProject(
            id: "project-\(UUID().uuidString)",
            name: name.isEmpty ? "Untitled Project" : service.normalizedProjectName(name),
            createdAt: Date(),
            conversationIDs: conversationID.map { [$0] } ?? []
        )
        projects.insert(project, at: 0)
        selectProjectID(project.id)
        persistProjects()
        return project
    }

    func projectIndex(matching rawName: String) -> Int? {
        let normalizedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedName.isEmpty else { return nil }
        if let exactIndex = projects.firstIndex(where: { $0.name.lowercased() == normalizedName }) {
            return exactIndex
        }
        return projects.firstIndex {
            let candidate = $0.name.lowercased()
            return candidate.contains(normalizedName) || normalizedName.contains(candidate)
        }
    }

    @discardableResult
    func seedSetupMetadata(projectID: String, profile: UserSetupProfile, plan: AppSetupPlan) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return false }
        var project = projects[index]
        let didChange = service.applySetupMetadata(to: &project, profile: profile, plan: plan)
        guard didChange else { return false }
        projects[index] = project
        persistProjects()
        return true
    }

    @discardableResult
    func updateInstructionsIfEmpty(projectID: String, instructions: String) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return false }
        guard projects[index].instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        projects[index].instructions = service.normalizedInstructions(instructions)
        persistProjects()
        return true
    }

    @discardableResult
    func appendMemoryToSelectedProject(_ memory: String, append: Bool) -> Bool {
        guard let index = selectedProjectIndex(),
              let updatedMemory = service.appendMemory(
                existing: projects[index].memorySummary,
                memory: memory,
                shouldAppend: append
              ) else {
            return false
        }
        projects[index].memorySummary = updatedMemory
        persistProjects()
        showBanner("Updated memory for project \"\(projects[index].name)\".")
        return true
    }

    @discardableResult
    func addPromptFilesToSelectedProject(_ promptAttachments: [ChatAttachment], maxAttachments: Int) -> ProjectPromptFileAddResult {
        guard let index = selectedProjectIndex() else {
            return ProjectPromptFileAddResult(
                status: .failed,
                summary: "Select or create a project before adding prompt files.",
                detail: nil
            )
        }
        guard !promptAttachments.isEmpty else {
            return ProjectPromptFileAddResult(
                status: .skipped,
                summary: "No prompt-only files were attached.",
                detail: nil
            )
        }

        var existingIDs = Set(projects[index].attachments.map(\.id))
        let filesToAdd = promptAttachments.filter { existingIDs.insert($0.id).inserted }
        guard !filesToAdd.isEmpty else {
            return ProjectPromptFileAddResult(
                status: .skipped,
                summary: "Those files are already in the project.",
                detail: nil
            )
        }

        let remainingSlots = max(0, maxAttachments - projects[index].attachments.count)
        let acceptedFiles = Array(filesToAdd.prefix(remainingSlots))
        guard !acceptedFiles.isEmpty else {
            return ProjectPromptFileAddResult(
                status: .failed,
                summary: "Project context already has the maximum twelve files.",
                detail: nil
            )
        }

        projects[index].attachments.append(contentsOf: acceptedFiles)
        persistProjects()
        return ProjectPromptFileAddResult(
            status: .completed,
            summary: "Added \(acceptedFiles.count) attached file\(acceptedFiles.count == 1 ? "" : "s") to project \"\(projects[index].name)\".",
            detail: acceptedFiles.map(\.name).joined(separator: ", ")
        )
    }

    @discardableResult
    func persistProjects() -> Bool {
        guard let persistence else { return true }
        let succeeded = persistence.saveProjects(projects)
        if !succeeded {
            showBanner("Project cache could not be saved securely.")
        }
        return succeeded
    }

    private func selectedProjectIndex() -> Int? {
        guard let selectedProjectID else { return nil }
        return projects.firstIndex(where: { $0.id == selectedProjectID })
    }

    private func addAttachment(
        _ attachment: ChatAttachment,
        toProjectAt index: Int,
        maxAttachments: Int,
        notice: String?,
        localDocumentText: String?
    ) -> Bool {
        guard !projects[index].attachments.contains(where: { $0.id == attachment.id }) else {
            showBanner("\(attachment.name) is already in this project.")
            return false
        }
        switch FileStore.projectAttachmentLimit(
            projectAttachmentCount: projects[index].attachments.count,
            maxProjectAttachments: maxAttachments
        ) {
        case .allowed:
            break
        case let .blocked(message):
            showBanner(message)
            return false
        }

        projects[index].attachments.append(attachment)
        if let localDocumentText {
            persistLocalDocumentRowsIfNeeded(localDocumentText, attachment: attachment, projectIndex: index)
        }
        persistProjects()
        showBanner(notice ?? "Added \(attachment.name) to \(projects[index].name).")
        return true
    }

    private func persistLocalDocumentRowsIfNeeded(_ text: String, attachment: ChatAttachment, projectIndex: Int) {
        guard attachment.kind == ChatAttachment.localTableKind else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let clippedText = ProjectService.clipped(trimmed, maxCharacters: ProjectService.maxNoteTextCharacters)
        let title = "Table rows: \(attachment.name)"
        guard !projects[projectIndex].notes.contains(where: { note in
            note.title == title || note.text == clippedText
        }) else {
            return
        }
        projects[projectIndex].notes.insert(
            ProjectNote(title: title, text: clippedText, isLocalOnly: true),
            at: 0
        )
        if projects[projectIndex].notes.count > ProjectService.maxNotes {
            projects[projectIndex].notes = Array(projects[projectIndex].notes.prefix(ProjectService.maxNotes))
        }
    }

    private func showBanner(_ message: String) {
        bannerHandler?(message)
    }
}
