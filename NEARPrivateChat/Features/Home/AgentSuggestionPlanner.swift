import Foundation

/// Builds concrete, project-aware agent task suggestions from what the project
/// actually contains — replacing the generic "Plan the next Agent task: goal,
/// context to inspect, risks, and verification" template that read like an
/// internal prompt rather than something a person would tap.
enum AgentSuggestionPlanner {
    struct Suggestion: Equatable {
        let title: String
        let symbolName: String
        let prompt: String
    }

    static func suggestions(
        projectName: String?,
        attachmentNames: [String],
        linkHosts: [String],
        recentConversationTitles: [String]
    ) -> [Suggestion] {
        var result: [Suggestion] = []

        if let file = attachmentNames.first {
            let displayName = readableFileName(file)
            result.append(Suggestion(
                title: "Summarize \(shortened(displayName))",
                symbolName: "doc.text.magnifyingglass",
                prompt: "Read \(displayName) and turn it into a summary plus a checklist of action items with owners."
            ))
        }
        if let host = linkHosts.first {
            result.append(Suggestion(
                title: "Check \(host)",
                symbolName: "link",
                prompt: "Check the saved \(host) link for anything new or changed since we last looked, and summarize what matters."
            ))
        }
        if let lastTitle = recentConversationTitles.first?.nilIfBlank {
            result.append(Suggestion(
                title: "Continue: \(shortened(lastTitle))",
                symbolName: "arrow.uturn.right",
                prompt: "Pick up where \"\(lastTitle)\" left off: recap the state, then do the next concrete step."
            ))
        }
        if result.count < 3 {
            let scope = projectName.map { " for \($0)" } ?? ""
            result.append(Suggestion(
                title: "Draft a work plan",
                symbolName: "checklist",
                prompt: "Draft a short, concrete work plan\(scope): the goal as you understand it, the next three steps, and what you need from me."
            ))
        }
        if result.count < 3 {
            result.append(Suggestion(
                title: "Find open questions",
                symbolName: "questionmark.circle",
                prompt: "List the open questions and risks in this project's context, ranked by how much they block progress."
            ))
        }
        return Array(result.prefix(4))
    }

    private static func readableFileName(_ name: String) -> String {
        // Extracted-text uploads are named "<original>-pdf-text.txt"; show the
        // original document name in suggestions.
        name
            .replacingOccurrences(of: "-pdf-text.txt", with: ".pdf")
            .replacingOccurrences(of: "-table-text.txt", with: "")
    }

    private static func shortened(_ text: String, max: Int = 28) -> String {
        text.count <= max ? text : String(text.prefix(max - 1)) + "…"
    }
}
