import Foundation

@MainActor
extension ChatStore {
    func activeSystemPromptForTesting(model: String? = nil) -> String {
        activeSystemPrompt(memoryForModel: model)
    }

    func activeSystemPrompt(memoryForModel model: String? = nil) -> String {
        let route = model.map(RoutePlanner.routeKind(forModelID:)) ?? .nearCloud
        let soulPrompt = SoulPromptComposer.promptBlock(profile: soulPromptProfile, route: route)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let formatPrompt = SoulPromptComposer.markdownFormatContract.trimmingCharacters(in: .whitespacesAndNewlines)
        // Cap the user's advanced system-prompt field at source; MessageAPI
        // fences + re-caps the full composed block before it reaches the wire.
        let userPrompt = Self.clipped(
            systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            maxCharacters: 4_000
        )
        let modePrompt = ChatPromptContextBuilder.sourceModeInstructions(
            semantics: sourceRoutingSemantics,
            webSearchEnabled: webSearchEnabled
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        // Personal memory is injected ONLY for the private near.ai route; it is
        // never sent to cloud, council cloud legs, or hosted/IronClaw routes.
        let memoryAllowed = route == .nearPrivate
        let memoryPrompt = memoryAllowed
            ? (memoryStore.contextBlock()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            : ""
        let requestedPrompt = researchModeEnabled ? Self.researchModeInstructions(appendingTo: userPrompt) : userPrompt
        let basePrompt = [soulPrompt, formatPrompt, memoryPrompt, requestedPrompt, modePrompt]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard let project = selectedProject else {
            return basePrompt
        }
        guard sourceRoutingSemantics.attachesSavedLinkSourcePack ||
            sourceRoutingSemantics.attachesProjectFileSourcePack ||
            sourceRoutingSemantics.isResearch else {
            return basePrompt
        }

        let projectInstructions = project.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectMemory = project.memorySummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectLinks = shouldIncludeProjectLinksInPrompt ? project.links
            .filter { URL(string: $0.urlString).map(URLSecurity.isPublicHTTPSURL) == true }
            .prefix(12)
            .map { link in
                "- \(link.displayTitle): \(link.urlString)"
            }
            .joined(separator: "\n") : ""
        let projectNotes = ProjectService.projectNotesForPrompt(project.notes, allowLocalOnly: memoryAllowed)
            .prefix(6)
            .map { note in
                "- \(note.title): \(Self.clipped(note.text, maxCharacters: 900))"
            }
            .joined(separator: "\n")
        guard !projectInstructions.isEmpty || !projectMemory.isEmpty || !projectLinks.isEmpty || !projectNotes.isEmpty else {
            return basePrompt
        }

        var projectSections: [String] = []
        if !projectInstructions.isEmpty {
            projectSections.append("""
            Instructions:
            \(projectInstructions)
            """)
        }
        if !projectMemory.isEmpty {
            projectSections.append("""
            Memory:
            \(projectMemory)
            """)
        }
        if !projectLinks.isEmpty {
            projectSections.append("""
            Source links:
            \(projectLinks)
            """)
        }
        if !projectNotes.isEmpty {
            projectSections.append("""
            Saved notes:
            \(projectNotes)
            """)
        }
        let projectPrompt = """
        Project "\(project.name)" context:
        \(projectSections.joined(separator: "\n\n"))
        """
        guard !basePrompt.isEmpty else {
            return projectPrompt
        }
        return """
        \(basePrompt)

        \(projectPrompt)
        """
    }

    private var shouldIncludeProjectLinksInPrompt: Bool {
        guard selectedProject?.links.isEmpty == false else { return false }
        return sourceRoutingSemantics.attachesSavedLinkSourcePack
    }

    static func researchModeInstructions(appendingTo userPrompt: String) -> String {
        let researchPrompt = """
        Research focus:
        - Prefer current information and call web search when available.
        - Start with the direct answer, then give dated evidence and source-backed reasoning.
        - Separate confirmed facts from inference.
        - End with a compact "Sources checked" section when sources are available.
        - If web tools are unavailable, say that clearly before answering from available context.
        """
        guard !userPrompt.isEmpty else {
            return researchPrompt
        }
        return """
        \(userPrompt)

        \(researchPrompt)
        """
    }

    static func clipped(_ text: String, maxCharacters: Int) -> String {
        ChatPromptContextBuilder.clipped(text, maxCharacters: maxCharacters)
    }

    func nearCloudPrompt(
        for text: String,
        attachments: [ChatAttachment],
        webContext: WebGroundingContext?
    ) -> String {
        ChatPromptContextBuilder.nearCloudPrompt(
            text: text,
            attachments: attachments,
            webContext: webContext,
            messages: messages
        )
    }

    func nearCloudSystemPrompt(modelID: String, modelDisplayName: String, hasWebContext: Bool) -> String {
        let userPrompt = activeSystemPrompt(memoryForModel: modelID)
        return ChatPromptContextBuilder.nearCloudSystemPrompt(
            modelDisplayName: modelDisplayName,
            hasWebContext: hasWebContext,
            userPrompt: userPrompt
        )
    }
}
