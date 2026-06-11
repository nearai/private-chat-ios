import Foundation

struct IronclawMobileProjectContext: Hashable {
    var projectName: String?
    var projectInstructions: String?
    var projectMemory: String?
    var projectNotes: [String]
    var projectLinks: [String]
    var projectFiles: [String]
    var promptFiles: [String]

    var summary: String {
        var lines: [String] = []
        if let projectName, !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Active project: \(projectName)")
        } else {
            lines.append("Active project: none")
        }

        if projectFiles.isEmpty {
            lines.append("Project files: none")
        } else {
            lines.append("Project files: \(projectFiles.joined(separator: ", "))")
        }

        if let projectInstructions,
           !projectInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Project instructions: \(projectInstructions)")
        }

        if let projectMemory,
           !projectMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Project memory: \(projectMemory)")
        }

        if projectNotes.isEmpty {
            lines.append("Project notes: none")
        } else {
            lines.append("Project notes: \(projectNotes.joined(separator: " | "))")
        }

        if projectLinks.isEmpty {
            lines.append("Project source links: none")
        } else {
            lines.append("Project source links: \(projectLinks.joined(separator: " | "))")
        }

        if promptFiles.isEmpty {
            lines.append("Files attached to this prompt: none")
        } else {
            lines.append("Files attached to this prompt: \(promptFiles.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }
}

final class IronclawMobileRuntime {
    private let api: PrivateChatAPI
    private static let visibleOutputTimeout: TimeInterval? = 45

    init(api: PrivateChatAPI) {
        self.api = api
    }

    func cancel() {
        // Reserved for future runtime-owned tasks; streaming is currently
        // cancelled by ChatStore's streamTask.
    }

    func streamTurn(
        prompt: String,
        attachments: [ChatAttachment],
        context: IronclawMobileProjectContext,
        baseModel: String,
        conversationID: String,
        previousResponseID: String?,
        webSearchEnabled: Bool,
        systemPrompt: String,
        toolResults: [IronclawMobileToolResult] = [],
        webContext: WebGroundingContext? = nil,
        onEvent: @escaping (ResponseStreamEvent) async -> Void
    ) async throws {
        let finalPrompt = Self.prompt(prompt, webContext: webContext)
        await onEvent(.reasoningStarted)
        try await api.streamResponse(
            model: baseModel,
            text: finalPrompt,
            attachments: attachments,
            conversationID: conversationID,
            previousResponseID: previousResponseID,
            webSearchEnabled: webSearchEnabled,
            systemPrompt: Self.instructions(
                context: context,
                userSystemPrompt: systemPrompt,
                toolResults: toolResults,
                webContext: webContext
            ),
            visibleOutputTimeout: Self.visibleOutputTimeout,
            onEvent: onEvent
        )
    }

    private static func prompt(_ prompt: String, webContext: WebGroundingContext?) -> String {
        guard let webContext else { return prompt }
        let date = Date.now.formatted(date: .complete, time: .omitted)
        return """
        Current date: \(date).

        User request:
        \(prompt)

        \(webContext.promptSection)

        Use the live web context above as the source pack for this turn. Cite source titles or domains for current claims.
        """
    }

    private static func instructions(
        context: IronclawMobileProjectContext,
        userSystemPrompt: String,
        toolResults: [IronclawMobileToolResult],
        webContext: WebGroundingContext?
    ) -> String {
        let userInstructions = userSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let resultSummary = toolResults.isEmpty
            ? "No local iOS tools were run before this model call."
            : toolResults.map(\.promptContext).joined(separator: "\n\n")
        let webSummary = webContext.map { context in
            """
            App-side live web search already ran for query "\(context.query)" and returned \(context.sources.count) source(s). Use those supplied sources directly. Do not claim that web browsing is unavailable.
            """
        } ?? "No app-side web source pack was supplied for this turn."
        let base = """
        You are IronClaw Mobile Runtime inside NEAR Private Chat for iOS.

        Runtime contract:
        - Run as an iOS-safe on-device orchestrator.
        - Use NEAR Private inference for the actual model call.
        - Use the app-side live web source pack when supplied; otherwise use web search when enabled by the app and the user asks for current information.
        - Use attached files and active project context when present.
        - Produce action-oriented answers with the app-supported Markdown subset: concise headings, lists, tables, fenced code, links, bold, italic, and blockquotes when useful.
        - Lead with the answer. Then add dated evidence, tradeoffs, and next actions only when they help.
        - Never emit fake tool calls, XML tool tags, HTML, Mermaid, LaTeX/math-only markup, raw JSON tool requests, or capability disclaimers after the app has supplied sources.

        Available mobile capabilities:
        - NEAR Private chat model execution.
        - App-side live web grounding before inference, plus NEAR Private web search when enabled.
        - Prompt attachments and project files passed by the app.
        - Local conversation/project context from the iOS app sandbox.
        - Native iOS tool execution for local projects, source links, project memory, project notes, chat organization, file context promotion, source modes, research mode, and web-search settings.

        Hosted IronClaw behavior:
        - The app can hand off git, code editing, tests, shell, package installation, and repo work to a configured Hosted IronClaw connection before this mobile runtime call.
        - If this prompt reached the mobile runtime, no hosted handoff was run for this turn. Be clear about the local iOS limit, then give the best mobile-safe plan or ask the user to connect/run Hosted IronClaw.

        Unavailable locally on iOS:
        - Shell commands, arbitrary host filesystem access, Docker, Postgres, LAN gateways, background desktop daemons, and unsandboxed MCP tools.

        Native iOS tool manifest:
        \(IronclawMobilePlanner.toolManifest)

        Native iOS tool results already executed for this turn:
        \(resultSummary)

        Live web source pack:
        \(webSummary)

        Mobile project context:
        \(context.summary)
        """

        guard !userInstructions.isEmpty else { return base }
        return """
        \(base)

        User system preferences:
        \(userInstructions)
        """
    }
}
