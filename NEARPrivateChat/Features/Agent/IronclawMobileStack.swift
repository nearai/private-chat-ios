import Foundation

struct IronclawMobileToolDefinition: Hashable {
    var name: String
    var summary: String
    var destructive: Bool
}

struct IronclawMobileToolCall: Identifiable, Hashable {
    var id = "tool-\(UUID().uuidString)"
    var name: String
    var arguments: [String: String]
    var reason: String
}

struct IronclawMobileToolResult: Hashable {
    enum Status: String, Hashable {
        case completed
        case skipped
        case failed
    }

    var callName: String
    var status: Status
    var summary: String
    var detail: String?

    var markdownLine: String {
        switch status {
        case .completed:
            return "- \(summary)"
        case .skipped:
            return "- Skipped \(callName): \(summary)"
        case .failed:
            return "- Could not run \(callName): \(summary)"
        }
    }

    var promptContext: String {
        guard let detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return markdownLine
        }
        return "\(markdownLine)\n\(detail)"
    }
}

struct IronclawMobileActionPlan: Hashable {
    var calls: [IronclawMobileToolCall]

    var isEmpty: Bool { calls.isEmpty }
}

struct IronclawMobileWorkspaceSnapshot: Hashable {
    struct Project: Hashable {
        var id: String
        var name: String
        var conversationCount: Int
        var fileNames: [String]
        var linkCount: Int
        var noteCount: Int
        var hasInstructions: Bool
        var hasMemory: Bool
    }

    var selectedConversationID: String?
    var selectedConversationTitle: String
    var selectedProjectID: String?
    var selectedProjectName: String?
    var projects: [Project]
    var visibleConversationTitles: [String]
    var archivedConversationCount: Int
    var webSearchEnabled: Bool
    var promptFileNames: [String]

    var summary: String {
        let projectList = projects.isEmpty
            ? "none"
            : projects.map { project in
                var parts = [
                    "\(project.conversationCount) chats",
                    "\(project.fileNames.count) files",
                    "\(project.linkCount) links",
                    "\(project.noteCount) notes"
                ]
                if project.hasInstructions {
                    parts.append("instructions")
                }
                if project.hasMemory {
                    parts.append("memory")
                }
                return "\(project.name) (\(parts.joined(separator: ", ")))"
            }.joined(separator: "; ")
        let promptFiles = promptFileNames.isEmpty ? "none" : promptFileNames.joined(separator: ", ")
        let visibleChats = visibleConversationTitles.isEmpty ? "none" : visibleConversationTitles.prefix(8).joined(separator: "; ")

        return """
        Selected conversation: \(selectedConversationTitle)
        Selected project: \(selectedProjectName ?? "none")
        Projects: \(projectList)
        Visible chats: \(visibleChats)
        Archived chats: \(archivedConversationCount)
        Web search: \(webSearchEnabled ? "enabled" : "disabled")
        Prompt files: \(promptFiles)
        """
    }
}

enum IronclawMobileToolNames {
    static let workspaceSnapshot = "workspace.snapshot"
    static let runtimeCapabilities = "runtime.capabilities"
    static let projectCreate = "project.create"
    static let projectSelect = "project.select"
    static let projectAddPromptFiles = "project.add_prompt_files"
    static let projectAddLink = "project.add_link"
    static let projectSetInstructions = "project.set_instructions"
    static let projectUpdateMemory = "project.update_memory"
    static let projectSaveNote = "project.save_note"
    static let conversationMoveToProject = "conversation.move_to_project"
    static let conversationRename = "conversation.rename"
    static let conversationPinSet = "conversation.pin"
    static let conversationArchiveSet = "conversation.archive"
    static let webSearchSet = "settings.web_search"
    static let sourceModeSet = "settings.source_mode"
    static let researchModeSet = "settings.research_mode"
}

enum IronclawMobilePlanner {
    static let toolDefinitions: [IronclawMobileToolDefinition] = [
        IronclawMobileToolDefinition(
            name: IronclawMobileToolNames.workspaceSnapshot,
            summary: "Read current iOS Project/chat state: selected project, chats, files, and web-search setting.",
            destructive: false
        ),
        IronclawMobileToolDefinition(
            name: IronclawMobileToolNames.runtimeCapabilities,
            summary: "Explain which IronClaw capabilities are available on iPhone and which desktop-only tools are blocked.",
            destructive: false
        ),
        IronclawMobileToolDefinition(
            name: IronclawMobileToolNames.projectCreate,
            summary: "Create and select a local NEAR Private Chat project on this iPhone.",
            destructive: false
        ),
        IronclawMobileToolDefinition(
            name: IronclawMobileToolNames.projectSelect,
            summary: "Select an existing local project.",
            destructive: false
        ),
        IronclawMobileToolDefinition(
            name: IronclawMobileToolNames.projectAddPromptFiles,
            summary: "Promote files attached to this prompt into the selected project's reusable context.",
            destructive: false
        ),
        IronclawMobileToolDefinition(
            name: IronclawMobileToolNames.projectAddLink,
            summary: "Add a URL to the selected project's reusable Source links.",
            destructive: false
        ),
        IronclawMobileToolDefinition(
            name: IronclawMobileToolNames.projectSetInstructions,
            summary: "Set instructions that are included on every future request in the selected project.",
            destructive: false
        ),
        IronclawMobileToolDefinition(
            name: IronclawMobileToolNames.projectUpdateMemory,
            summary: "Append to or replace the selected project's memory summary.",
            destructive: false
        ),
        IronclawMobileToolDefinition(
            name: IronclawMobileToolNames.projectSaveNote,
            summary: "Save a short note into the selected project's reusable notes.",
            destructive: false
        ),
        IronclawMobileToolDefinition(
            name: IronclawMobileToolNames.conversationMoveToProject,
            summary: "Move the current chat into a local project.",
            destructive: false
        ),
        IronclawMobileToolDefinition(
            name: IronclawMobileToolNames.conversationRename,
            summary: "Rename the current conversation through the NEAR Private Chat API.",
            destructive: false
        ),
        IronclawMobileToolDefinition(
            name: IronclawMobileToolNames.conversationPinSet,
            summary: "Pin or unpin the current chat in the local chat list.",
            destructive: false
        ),
        IronclawMobileToolDefinition(
            name: IronclawMobileToolNames.conversationArchiveSet,
            summary: "Archive or unarchive the current chat in the local chat list.",
            destructive: false
        ),
        IronclawMobileToolDefinition(
            name: IronclawMobileToolNames.webSearchSet,
            summary: "Turn NEAR Private web search on or off for future model calls.",
            destructive: false
        ),
        IronclawMobileToolDefinition(
            name: IronclawMobileToolNames.sourceModeSet,
            summary: "Set the active source mode: Auto, Web, Saved links, Files, or Web + Files.",
            destructive: false
        ),
        IronclawMobileToolDefinition(
            name: IronclawMobileToolNames.researchModeSet,
            summary: "Turn research mode on or off for future NEAR Private model calls.",
            destructive: false
        )
    ]

    static var toolManifest: String {
        toolDefinitions
            .map { "- \($0.name): \($0.summary)" }
            .joined(separator: "\n")
    }

    static func plan(prompt: String, snapshot: IronclawMobileWorkspaceSnapshot) -> IronclawMobileActionPlan {
        let lowercased = prompt.lowercased()
        let capturedURL = captureURL(in: prompt)
        let repoBackedProjectName = capturedURL.flatMap(repoProjectNameFromURL)
        let requestedWebSearchEnabled = requestedWebSearchState(lowercased)
        let requestedSourceMode = requestedSourceMode(lowercased)
        let requestedResearchModeEnabled = requestedResearchModeState(lowercased)
        let needsFreshResearch = promptNeedsFreshResearch(lowercased)
        var calls: [IronclawMobileToolCall] = []

        if asksForCapabilities(lowercased) {
            calls.append(IronclawMobileToolCall(
                name: IronclawMobileToolNames.runtimeCapabilities,
                arguments: [:],
                reason: "The user asked what IronClaw can do on iPhone."
            ))
        }

        if asksForWorkspaceState(lowercased) {
            calls.append(IronclawMobileToolCall(
                name: IronclawMobileToolNames.workspaceSnapshot,
                arguments: [:],
                reason: "The user asked about projects, files, chats, or current runtime state."
            ))
        }

        guard allowsPersistentMutation(prompt) else {
            return IronclawMobileActionPlan(calls: deduplicate(calls))
        }

        if let webSearchEnabled = requestedWebSearchEnabled {
            calls.append(IronclawMobileToolCall(
                name: IronclawMobileToolNames.webSearchSet,
                arguments: ["enabled": webSearchEnabled ? "true" : "false"],
                reason: "The user requested a web-search setting change."
            ))
        } else if needsFreshResearch && !snapshot.webSearchEnabled {
            calls.append(IronclawMobileToolCall(
                name: IronclawMobileToolNames.webSearchSet,
                arguments: ["enabled": "true"],
                reason: "The user asked for current information, so the iPhone source pack should be available."
            ))
        }

        if let sourceMode = requestedSourceMode {
            calls.append(IronclawMobileToolCall(
                name: IronclawMobileToolNames.sourceModeSet,
                arguments: ["mode": sourceMode],
                reason: "The user requested a source-mode change."
            ))
        } else if needsFreshResearch {
            calls.append(IronclawMobileToolCall(
                name: IronclawMobileToolNames.sourceModeSet,
                arguments: ["mode": snapshot.promptFileNames.isEmpty ? ChatSourceMode.web.rawValue : ChatSourceMode.all.rawValue],
                reason: "The user asked for current information, so live sources should be used."
            ))
        }

        if let researchModeEnabled = requestedResearchModeEnabled {
            calls.append(IronclawMobileToolCall(
                name: IronclawMobileToolNames.researchModeSet,
                arguments: ["enabled": researchModeEnabled ? "true" : "false"],
                reason: "The user requested a research-mode setting change."
            ))
        } else if needsFreshResearch {
            calls.append(IronclawMobileToolCall(
                name: IronclawMobileToolNames.researchModeSet,
                arguments: ["enabled": "true"],
                reason: "The user asked for latest or current information."
            ))
        }

        var createdOrSelectedProjectName: String?
        if var projectName = captureName(
            in: prompt,
            patterns: [
                "(?:create|make|start|set up|setup)\\s+(?:a\\s+)?(?:new\\s+)?project\\s+(?:called|named|for)?\\s*[\"']?([^\"'\\.\\n,;!?]+)",
                "(?:project)\\s+(?:called|named)\\s*[\"']?([^\"'\\.\\n,;!?]+)"
            ]
        ) {
            if projectNameLooksLikeURL(projectName), let repoBackedProjectName {
                projectName = repoBackedProjectName
            }
            createdOrSelectedProjectName = projectName
            calls.append(IronclawMobileToolCall(
                name: IronclawMobileToolNames.projectCreate,
                arguments: ["name": projectName],
                reason: "The user asked to create a project."
            ))
        } else if let repoBackedProjectName, shouldCreateProjectForRepoURL(lowercased) {
            createdOrSelectedProjectName = repoBackedProjectName
            calls.append(IronclawMobileToolCall(
                name: IronclawMobileToolNames.projectCreate,
                arguments: ["name": repoBackedProjectName],
                reason: "The user asked to set up a repo-backed project."
            ))
        } else if let projectName = captureName(
            in: prompt,
            patterns: [
                "(?:open|select|switch to|use)\\s+(?:the\\s+)?project\\s+[\"']?([^\"'\\.\\n,;!?]+)"
            ]
        ) {
            createdOrSelectedProjectName = projectName
            calls.append(IronclawMobileToolCall(
                name: IronclawMobileToolNames.projectSelect,
                arguments: ["name": projectName],
                reason: "The user asked to select a project."
            ))
        }

        if let instructions = captureLongText(
            in: prompt,
            patterns: [
                "(?:set|update|save)\\s+(?:the\\s+)?(?:project\\s+)?instructions\\s+(?:to|as)\\s+(.+)",
                "(?:project\\s+instructions:)\\s*(.+)"
            ]
        ) {
            calls.append(IronclawMobileToolCall(
                name: IronclawMobileToolNames.projectSetInstructions,
                arguments: ["instructions": instructions],
                reason: "The user asked to update project instructions."
            ))
        }

        if let memory = captureLongText(
            in: prompt,
            patterns: [
                "(?:remember|save\\s+memory)\\s+(?:that\\s+)?(.+)",
                "(?:set|update|save)\\s+(?:the\\s+)?(?:project\\s+)?memory\\s+(?:to|as)\\s+(.+)",
                "(?:project\\s+memory:)\\s*(.+)"
            ]
        ) {
            let shouldReplace = lowercased.contains("set project memory") ||
                lowercased.contains("replace project memory") ||
                lowercased.contains("project memory:")
            calls.append(IronclawMobileToolCall(
                name: IronclawMobileToolNames.projectUpdateMemory,
                arguments: ["memory": memory, "append": shouldReplace ? "false" : "true"],
                reason: "The user asked to update project memory."
            ))
        }

        if let linkCall = requestedProjectLinkCall(prompt: prompt, lowercased: lowercased) {
            calls.append(linkCall)
        }

        if let note = captureLongText(
            in: prompt,
            patterns: [
                "(?:save|add|create)\\s+(?:a\\s+)?(?:project\\s+)?note\\s*(?:called|named)?\\s*[\"']?([^\\n]+)",
                "(?:project\\s+note:)\\s*(.+)"
            ]
        ) {
            calls.append(IronclawMobileToolCall(
                name: IronclawMobileToolNames.projectSaveNote,
                arguments: ["text": note],
                reason: "The user asked to save a project note."
            ))
        }

        if let title = captureName(
            in: prompt,
            patterns: [
                "(?:rename|title)\\s+(?:this\\s+)?(?:chat|conversation|thread)\\s+(?:to|as|called|named)?\\s*[\"']?([^\"'\\.\\n,;!?]+)",
                "(?:call)\\s+(?:this\\s+)?(?:chat|conversation|thread)\\s+[\"']?([^\"'\\.\\n,;!?]+)"
            ]
        ) {
            calls.append(IronclawMobileToolCall(
                name: IronclawMobileToolNames.conversationRename,
                arguments: ["title": title],
                reason: "The user asked to rename the current chat."
            ))
        }

        if let pinned = requestedPinState(lowercased) {
            calls.append(IronclawMobileToolCall(
                name: IronclawMobileToolNames.conversationPinSet,
                arguments: ["pinned": pinned ? "true" : "false"],
                reason: "The user asked to pin or unpin this chat."
            ))
        }

        if let archived = requestedArchiveState(lowercased) {
            calls.append(IronclawMobileToolCall(
                name: IronclawMobileToolNames.conversationArchiveSet,
                arguments: ["archived": archived ? "true" : "false"],
                reason: "The user asked to archive or unarchive this chat."
            ))
        }

        if let projectName = captureName(
            in: prompt,
            patterns: [
                "(?:move|put|add)\\s+(?:this\\s+)?(?:chat|conversation|thread)\\s+(?:to|into|under)\\s+(?:the\\s+)?(?:project\\s+)?[\"']?([^\"'\\.\\n,;!?]+)"
            ]
        ) ?? createdOrSelectedProjectNameIfMoveRequested(createdOrSelectedProjectName, lowercased: lowercased) {
            calls.append(IronclawMobileToolCall(
                name: IronclawMobileToolNames.conversationMoveToProject,
                arguments: ["project_name": projectName, "create_if_missing": "true"],
                reason: "The user asked to organize this chat into a project."
            ))
        }

        if shouldPromotePromptFiles(lowercased), !snapshot.promptFileNames.isEmpty {
            calls.append(IronclawMobileToolCall(
                name: IronclawMobileToolNames.projectAddPromptFiles,
                arguments: [:],
                reason: "The user asked to add attached files to project context."
            ))
        }

        return IronclawMobileActionPlan(calls: deduplicate(calls))
    }

    private static func allowsPersistentMutation(_ prompt: String) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("/") ||
            trimmed.hasPrefix("ironclaw:") ||
            trimmed.hasPrefix("agent:") ||
            trimmed.hasPrefix("near:")
    }

    private static func asksForCapabilities(_ lowercased: String) -> Bool {
        lowercased.contains("what can ironclaw do") ||
            lowercased.contains("ironclaw capabilities") ||
            lowercased.contains("available tools") ||
            lowercased.contains("what tools") ||
            lowercased.contains("runtime stack")
    }

    private static func asksForWorkspaceState(_ lowercased: String) -> Bool {
        lowercased.contains("list projects") ||
            lowercased.contains("show projects") ||
            lowercased.contains("project files") ||
            lowercased.contains("workspace") ||
            lowercased.contains("current state")
    }

    private static func requestedWebSearchState(_ lowercased: String) -> Bool? {
        if lowercased.contains("turn on web") ||
            lowercased.contains("enable web") ||
            lowercased.contains("web search on") ||
            lowercased.contains("use web search") {
            return true
        }
        if lowercased.contains("turn off web") ||
            lowercased.contains("disable web") ||
            lowercased.contains("web search off") ||
            lowercased.contains("no web search") {
            return false
        }
        return nil
    }

    private static func requestedSourceMode(_ lowercased: String) -> String? {
        if lowercased.contains("web + files") ||
            lowercased.contains("web and files") ||
            lowercased.contains("all sources") ||
            lowercased.contains("combine web") {
            return ChatSourceMode.all.rawValue
        }
        if lowercased.contains("saved links") ||
            lowercased.contains("source links") ||
            lowercased.contains("links mode") ||
            lowercased.contains("use links") {
            return ChatSourceMode.links.rawValue
        }
        if lowercased.contains("files only") ||
            lowercased.contains("file mode") ||
            (lowercased.contains("use files") && !lowercased.contains("web")) {
            return ChatSourceMode.files.rawValue
        }
        if lowercased.contains("web only") ||
            lowercased.contains("web mode") ||
            lowercased.contains("use web search") {
            return ChatSourceMode.web.rawValue
        }
        if lowercased.contains("auto source") ||
            lowercased.contains("auto mode") ||
            lowercased.contains("source mode auto") {
            return ChatSourceMode.auto.rawValue
        }
        return nil
    }

    private static func requestedResearchModeState(_ lowercased: String) -> Bool? {
        if lowercased.contains("turn on research") ||
            lowercased.contains("enable research") ||
            lowercased.contains("research mode on") ||
            lowercased.contains("use research mode") {
            return true
        }
        if lowercased.contains("turn off research") ||
            lowercased.contains("disable research") ||
            lowercased.contains("research mode off") {
            return false
        }
        return nil
    }

    private static func promptNeedsFreshResearch(_ lowercased: String) -> Bool {
        if lowercased.contains("turn off web") ||
            lowercased.contains("disable web") ||
            lowercased.contains("no web search") ||
            lowercased.contains("without web") {
            return false
        }
        return lowercased.contains("latest") ||
            lowercased.contains("current") ||
            lowercased.contains("today") ||
            lowercased.contains("this week") ||
            lowercased.contains("recent") ||
            lowercased.contains("news") ||
            lowercased.contains("search the web") ||
            lowercased.contains("web search") ||
            lowercased.contains("find sources") ||
            lowercased.contains("with sources") ||
            lowercased.contains("cite sources") ||
            lowercased.contains("as of ")
    }

    private static func requestedPinState(_ lowercased: String) -> Bool? {
        if lowercased.contains("unpin this chat") ||
            lowercased.contains("unpin this conversation") ||
            lowercased.contains("unpin this thread") {
            return false
        }
        if lowercased.contains("pin this chat") ||
            lowercased.contains("pin this conversation") ||
            lowercased.contains("pin this thread") {
            return true
        }
        return nil
    }

    private static func requestedArchiveState(_ lowercased: String) -> Bool? {
        if lowercased.contains("unarchive this chat") ||
            lowercased.contains("restore this chat") ||
            lowercased.contains("unarchive this conversation") {
            return false
        }
        if lowercased.contains("archive this chat") ||
            lowercased.contains("archive this conversation") ||
            lowercased.contains("archive this thread") {
            return true
        }
        return nil
    }

    private static func requestedProjectLinkCall(prompt: String, lowercased: String) -> IronclawMobileToolCall? {
        guard let url = captureURL(in: prompt) else { return nil }
        let shouldSaveURL = lowercased.contains("link") ||
            lowercased.contains("url") ||
            lowercased.contains("source") ||
            lowercased.contains("repo") ||
            lowercased.contains("repository") ||
            lowercased.contains("github") ||
            lowercased.contains("project")
        guard shouldSaveURL else { return nil }
        let title = captureProjectLinkTitle(in: prompt, url: url)
        var arguments = ["url": url]
        if let title {
            arguments["title"] = title
        }
        return IronclawMobileToolCall(
            name: IronclawMobileToolNames.projectAddLink,
            arguments: arguments,
            reason: "The user asked to save a project source link."
        )
    }

    private static func captureProjectLinkTitle(in prompt: String, url: String) -> String? {
        let escapedURL = NSRegularExpression.escapedPattern(for: url)
        return captureName(
            in: prompt,
            patterns: [
                "\(escapedURL)\\s+(?:as|called|named|titled)\\s*[\"']?([^\"'\\.\\n,;!?]+)",
                "(?:add|save)\\s+(?:source\\s+)?link\\s+(?:called|named|as|titled)\\s*[\"']?([^\"'\\.\\n,;!?]+)",
                "(?:add|save)\\s+(?:source\\s+)?link\\s+[\"']?([^\"'\\.\\n,;!?]+)[\"']?\\s+\(escapedURL)"
            ]
        )
    }

    private static func createdOrSelectedProjectNameIfMoveRequested(
        _ projectName: String?,
        lowercased: String
    ) -> String? {
        guard let projectName,
              lowercased.contains("move") ||
              lowercased.contains("put this chat") ||
              lowercased.contains("add this chat") ||
              lowercased.contains("organize this chat") else {
            return nil
        }
        return projectName
    }

    private static func shouldPromotePromptFiles(_ lowercased: String) -> Bool {
        lowercased.contains("add these files") ||
            lowercased.contains("add the files") ||
            lowercased.contains("drop files") ||
            lowercased.contains("project context") ||
            lowercased.contains("put these files")
    }

    private static func shouldCreateProjectForRepoURL(_ lowercased: String) -> Bool {
        lowercased.contains("repo") ||
            lowercased.contains("repository") ||
            lowercased.contains("github") ||
            lowercased.contains("gitlab") ||
            lowercased.contains("clone") ||
            lowercased.contains("codebase") ||
            lowercased.contains("project")
    }

    private static func projectNameLooksLikeURL(_ name: String) -> Bool {
        let lowercased = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowercased.hasPrefix("http") ||
            lowercased.contains("://") ||
            lowercased.contains("github") ||
            lowercased.contains("gitlab") ||
            lowercased.contains(".com")
    }

    private static func repoProjectNameFromURL(_ rawURL: String) -> String? {
        let candidate = rawURL.contains("://") ? rawURL : "https://\(rawURL)"
        guard let components = URLComponents(string: candidate),
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }

        let pathParts = components.path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !pathParts.isEmpty else { return nil }

        let repoHost = host.contains("github.") ||
            host.contains("gitlab.") ||
            host.contains("bitbucket.")
        if repoHost, pathParts.count >= 2 {
            return cleanName("\(pathParts[0])/\(strippedGitSuffix(pathParts[1]))")
        }
        return cleanName(strippedGitSuffix(pathParts.last ?? ""))
    }

    private static func strippedGitSuffix(_ value: String) -> String {
        value.replacingOccurrences(of: #"\.git$"#, with: "", options: .regularExpression)
    }

    private static func captureName(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let capturedRange = Range(match.range(at: 1), in: text) else {
                continue
            }

            if let cleaned = cleanName(String(text[capturedRange])) {
                return cleaned
            }
        }
        return nil
    }

    private static func cleanName(_ rawName: String) -> String? {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" and ", " then ", " with ", " using ", " for https://", " for http://", " please", " pls"] {
            if let range = name.range(of: separator, options: [.caseInsensitive]) {
                name = String(name[..<range.lowerBound])
            }
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"'` "))
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return String(name.prefix(80))
    }

    private static func captureLongText(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let capturedRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            let cleaned = cleanLongText(String(text[capturedRange]))
            if !cleaned.isEmpty {
                return String(cleaned.prefix(4_000))
            }
        }
        return nil
    }

    private static func cleanLongText(_ rawText: String) -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" then ", "\n\n"] {
            if let range = text.range(of: separator, options: [.caseInsensitive]) {
                text = String(text[..<range.lowerBound])
            }
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'` "))
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func captureURL(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s,;)"']+"#, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }
        let url = String(text[matchRange])
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}"))
        return url.isEmpty ? nil : url
    }

    private static func deduplicate(_ calls: [IronclawMobileToolCall]) -> [IronclawMobileToolCall] {
        var seen = Set<String>()
        var output: [IronclawMobileToolCall] = []
        for call in calls {
            let key = "\(call.name):\(call.arguments.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "|"))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(call)
        }
        return output
    }
}
