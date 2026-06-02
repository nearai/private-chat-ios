import Foundation

struct ProjectMutationResult: Equatable {
    var didChange: Bool
    var message: String?

    static let unchanged = ProjectMutationResult(didChange: false, message: nil)
}

struct ProjectService {
    static let maxNameCharacters = 80
    static let maxInstructionsCharacters = 4_000
    static let maxMemoryCharacters = 4_000
    static let maxLinks = 24
    static let maxNotes = 20
    static let maxNoteTextCharacters = 12_000
    static let maxPromptNotes = 6
    static let maxPromptLinks = 12

    func makeProject(
        name rawName: String,
        conversationID: String? = nil,
        instructions: String = "",
        iconName: String = ProjectIcon.folder.symbolName,
        paletteName: String = ProjectPalette.sky.rawValue
    ) -> ChatProject? {
        let name = normalizedProjectName(rawName)
        guard !name.isEmpty else { return nil }
        return ChatProject(
            id: "project-\(UUID().uuidString)",
            name: name,
            createdAt: Date(),
            conversationIDs: conversationID.map { [$0] } ?? [],
            instructions: clipped(instructions.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: Self.maxInstructionsCharacters),
            iconName: iconName,
            paletteName: paletteName
        )
    }

    func normalizedProjectName(_ rawName: String) -> String {
        clipped(rawName.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: Self.maxNameCharacters)
    }

    func normalizedInstructions(_ rawValue: String) -> String {
        clipped(rawValue.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: Self.maxInstructionsCharacters)
    }

    func normalizedMemory(_ rawValue: String) -> String {
        clipped(rawValue.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: Self.maxMemoryCharacters)
    }

    func makeLink(title: String, rawURL: String, existingLinks: [ProjectLink]) -> (link: ProjectLink?, message: String) {
        guard existingLinks.count < Self.maxLinks else {
            return (nil, "This project already has enough links.")
        }
        guard let normalizedURL = Self.normalizedProjectLinkURL(rawURL) else {
            return (nil, "Enter a public HTTPS link.")
        }
        if existingLinks.contains(where: { $0.urlString == normalizedURL.absoluteString }) {
            return (nil, "That link is already in this project.")
        }
        return (
            ProjectLink(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                urlString: normalizedURL.absoluteString
            ),
            "Project link added."
        )
    }

    func makeNote(title: String, text: String, isLocalOnly: Bool, existingNotes: [ProjectNote]) -> (note: ProjectNote?, message: String) {
        guard existingNotes.count < Self.maxNotes else {
            return (nil, "This project already has enough notes.")
        }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return (nil, "Write a note first.")
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = ProjectNote(
            title: trimmedTitle.isEmpty ? Self.noteTitle(from: trimmedText) : clipped(trimmedTitle, maxCharacters: Self.maxNameCharacters),
            text: clipped(trimmedText, maxCharacters: Self.maxNoteTextCharacters),
            isLocalOnly: isLocalOnly
        )
        return (note, isLocalOnly ? "Local-only note added." : "Project note added.")
    }

    func updatedNote(_ note: ProjectNote, title: String, text: String, isLocalOnly: Bool) -> (note: ProjectNote?, message: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return (nil, "Write a note first.")
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = note
        updated.title = trimmedTitle.isEmpty ? Self.noteTitle(from: trimmedText) : clipped(trimmedTitle, maxCharacters: Self.maxNameCharacters)
        updated.text = clipped(trimmedText, maxCharacters: Self.maxNoteTextCharacters)
        updated.isLocalOnly = isLocalOnly
        return (updated, isLocalOnly ? "Local-only note updated." : "Project note updated.")
    }

    func makeSavedOutputNote(text: String, sourceMessageID: String?) -> ProjectNote? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }
        return ProjectNote(
            title: Self.noteTitle(from: trimmedText),
            text: clipped(trimmedText, maxCharacters: Self.maxNoteTextCharacters),
            sourceMessageID: sourceMessageID
        )
    }

    func appendMemory(existing: String, memory: String, shouldAppend: Bool) -> String? {
        let trimmedMemory = memory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMemory.isEmpty else { return nil }
        let existing = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated: String
        if shouldAppend, !existing.isEmpty, !existing.localizedCaseInsensitiveContains(trimmedMemory) {
            updated = "\(existing)\n- \(trimmedMemory)"
        } else {
            updated = trimmedMemory
        }
        return normalizedMemory(updated)
    }

    func applySetupMetadata(
        to project: inout ChatProject,
        profile: UserSetupProfile,
        plan: AppSetupPlan
    ) -> Bool {
        var didChange = false
        let style = Self.setupProjectStyle(for: profile)
        if project.iconName == ProjectIcon.folder.symbolName {
            project.iconName = style.iconName
            didChange = true
        }
        if project.paletteName == ProjectPalette.sky.rawValue, style.paletteName != ProjectPalette.sky.rawValue {
            project.paletteName = style.paletteName
            didChange = true
        }

        let managedTitles = Set([
            Self.setupGuideNoteTitle,
            Self.setupPromptNoteTitle,
            Self.setupSkillsNoteTitle
        ])
        let existingManagedNotes = project.notes.reduce(into: [String: ProjectNote]()) { result, note in
            guard managedTitles.contains(note.title), result[note.title] == nil else { return }
            result[note.title] = note
        }
        let userNotes = project.notes.filter { !managedTitles.contains($0.title) }
        let desiredManagedNotes = [
            (Self.setupGuideNoteTitle, Self.setupGuideNoteText(for: profile)),
            (Self.setupPromptNoteTitle, Self.setupPromptNoteText(for: plan)),
            (Self.setupSkillsNoteTitle, Self.setupSkillsNoteText(for: plan))
        ].compactMap { title, text -> ProjectNote? in
            guard let text else { return nil }
            if var note = existingManagedNotes[title] {
                note.text = text
                return note
            }
            return ProjectNote(title: title, text: text)
        }

        for note in desiredManagedNotes {
            if existingManagedNotes[note.title]?.text != note.text {
                didChange = true
            }
        }
        let removedManagedTitles = Set(existingManagedNotes.keys).subtracting(desiredManagedNotes.map(\.title))
        if !removedManagedTitles.isEmpty {
            didChange = true
        }

        let updatedNotes = Array((desiredManagedNotes + userNotes).prefix(Self.maxNotes))
        if project.notes != updatedNotes {
            project.notes = updatedNotes
            didChange = true
        }
        return didChange
    }

    static func projectNotesForPrompt(_ notes: [ProjectNote], allowLocalOnly: Bool) -> [ProjectNote] {
        notes.filter { allowLocalOnly || !$0.isLocalOnly }
    }

    static func projectContextRoutePreview(
        fileCount: Int,
        linkCount: Int,
        noteCount: Int,
        localOnlyNoteCount: Int,
        hasInstructions: Bool,
        hasMemory: Bool,
        semantics: ChatSourceRoutingSemantics,
        routeTitle: String,
        allowsLocalOnlyNotes: Bool
    ) -> ProjectContextRoutePreview {
        let includesProjectContext = semantics.attachesSavedLinkSourcePack ||
            semantics.attachesProjectFileSourcePack ||
            semantics.isResearch
        let includedNoteCount = includesProjectContext
            ? max(0, noteCount - (allowsLocalOnlyNotes ? 0 : localOnlyNoteCount))
            : 0
        let routedNoteCount = min(includedNoteCount, Self.maxPromptNotes)
        let routedLinkCount = min(linkCount, Self.maxPromptLinks)
        var parts: [String] = []

        if semantics.modelNativeWebToolEnabledByDefault || semantics.appWebGroundingPolicy.isEnabledByDefault {
            parts.append("live web")
        }
        if includesProjectContext, hasInstructions {
            parts.append("instructions")
        }
        if includesProjectContext, hasMemory {
            parts.append("memory")
        }
        if semantics.attachesProjectFileSourcePack, fileCount > 0 {
            parts.append(contextCountLabel(fileCount, singular: "file"))
        }
        if semantics.attachesSavedLinkSourcePack, routedLinkCount > 0 {
            parts.append(contextCountLabel(routedLinkCount, singular: "link"))
        }
        if routedNoteCount > 0 {
            parts.append(contextCountLabel(routedNoteCount, singular: "note"))
        }

        let title = parts.isEmpty
            ? "Next answer has no Project sources selected."
            : "Next answer can use \(parts.joined(separator: ", "))."
        let omittedLocalOnlyNotes = includesProjectContext && !allowsLocalOnlyNotes ? localOnlyNoteCount : 0
        let detail = omittedLocalOnlyNotes > 0
            ? "Local-only notes stay on phone for \(routeTitle)."
            : nil

        return ProjectContextRoutePreview(
            title: title,
            detail: detail,
            symbolName: detail == nil ? "scope" : "iphone",
            usesAttentionStyle: detail != nil
        )
    }

    static func normalizedProjectLinkURL(_ rawURL: String) -> URL? {
        URLSecurity.normalizedPublicHTTPSURL(from: rawURL)
    }

    static func noteTitle(from text: String) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first?
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Saved output"
        let clippedTitle = String(firstLine.prefix(64)).trimmingCharacters(in: .whitespacesAndNewlines)
        return clippedTitle.isEmpty ? "Saved output" : clippedTitle
    }

    func clipped(_ text: String, maxCharacters: Int) -> String {
        Self.clipped(text, maxCharacters: maxCharacters)
    }

    static func clipped(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: maxCharacters)
        return "\(text[..<endIndex])..."
    }

    private static let setupGuideNoteTitle = "Setup guide"
    private static let setupPromptNoteTitle = "Starter prompts"
    private static let setupSkillsNoteTitle = "Agent skills"

    private static func setupProjectStyle(for profile: UserSetupProfile) -> (iconName: String, paletteName: String) {
        if profile.useCases.contains(.buildAgents) {
            return (ProjectIcon.agent.symbolName, ProjectPalette.violet.rawValue)
        }
        if profile.useCases.contains(.research) {
            return (ProjectIcon.research.symbolName, ProjectPalette.mint.rawValue)
        }
        if profile.useCases.contains(.teamProjects) {
            return (ProjectIcon.memo.symbolName, ProjectPalette.amber.rawValue)
        }
        return (ProjectIcon.folder.symbolName, ProjectPalette.sky.rawValue)
    }

    private static func setupGuideNoteText(for profile: UserSetupProfile) -> String {
        var lines = [
            "This Project was created from setup so your first chats can reuse the same sources, notes, and instructions.",
            "",
            "Suggested next steps:"
        ]
        if profile.useCases.contains(.research) {
            lines.append("- Add one source link, then ask for a cited research brief.")
        }
        if profile.useCases.contains(.buildAgents) {
            lines.append("- Paste a repo or issue link, then ask IronClaw to plan the first patch and test pass.")
        }
        if profile.useCases.contains(.teamProjects) {
            lines.append("- Save project decisions here so future chats inherit the context.")
        }
        if profile.useCases.contains(.privateChat) {
            lines.append("- Ask privately first; turn on web or files only when the task needs them.")
        }
        let goal = profile.normalizedGoalText
        if !goal.isEmpty {
            lines.append("")
            lines.append("Setup goal: \(goal)")
        }
        return lines.joined(separator: "\n")
    }

    private static func setupPromptNoteText(for plan: AppSetupPlan) -> String? {
        let prompts = Array(plan.starterPromptSuggestions.prefix(3))
        guard !prompts.isEmpty else { return nil }

        var lines = [
            "Use these starter prompts from setup when you want a fast first turn.",
            ""
        ]
        lines.append(contentsOf: prompts.map { "- \($0.title): \($0.prompt)" })
        return lines.joined(separator: "\n")
    }

    private static func setupSkillsNoteText(for plan: AppSetupPlan) -> String? {
        let skills = Array(plan.starterSkillSuggestions.prefix(4))
        guard !skills.isEmpty else { return nil }

        var lines = [
            "Suggested Agent skills for this Project:",
            ""
        ]
        lines.append(contentsOf: skills.map { "- \($0.title): \($0.summary)" })
        return lines.joined(separator: "\n")
    }

    private static func contextCountLabel(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }
}
