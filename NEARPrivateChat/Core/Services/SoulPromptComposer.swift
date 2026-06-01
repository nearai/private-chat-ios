import Foundation

struct SoulPromptComposer {
    struct Profile: Equatable {
        static let empty = Profile(identity: "", intent: "", voiceAndFormat: "", rules: "")

        var identity: String
        var intent: String
        var voiceAndFormat: String
        var rules: String

        var isEmpty: Bool {
            [identity, intent, voiceAndFormat, rules].allSatisfy {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }

        static func parse(_ markdown: String) -> Profile {
            var buckets: [Section: [String]] = [:]
            var currentSection: Section?
            let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
                if let section = Section(headingLine: rawLine) {
                    currentSection = section
                    continue
                }
                guard let currentSection else { continue }
                buckets[currentSection, default: []].append(rawLine)
            }
            return Profile(
                identity: trimmedSection(buckets[.identity] ?? []),
                intent: trimmedSection(buckets[.intent] ?? []),
                voiceAndFormat: trimmedSection(buckets[.voiceAndFormat] ?? []),
                rules: trimmedSection(buckets[.rules] ?? [])
            )
        }

        private static func trimmedSection(_ lines: [String]) -> String {
            var start = lines.startIndex
            var end = lines.endIndex
            while start < end, lines[start].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                start = lines.index(after: start)
            }
            while end > start {
                let previous = lines.index(before: end)
                guard lines[previous].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    break
                }
                end = previous
            }
            guard start < end else { return "" }
            return lines[start..<end].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static let markdownFormatContract = """
    Format contract:
    - Use only the app-supported Markdown subset unless the user explicitly asks for a stricter output shape.
    - Supported: headings, ordered and unordered lists, nested lists, GitHub-flavored tables, fenced code blocks with language tags, links, bold, italic, and blockquotes.
    - Keep tables compact enough to read on a phone. Prefer a list when a table would be too wide.
    - Do not use HTML, Mermaid, LaTeX/math-only markup, XML tool tags, raw JSON, or custom containers except the app-sanctioned near-widget fenced block when route instructions request one.
    - If the user asks for exact wording, code-only output, JSON-only output, or a one-word answer, obey that requested shape exactly.
    """

    static func promptBlock(profile: Profile, route: ChatRouteKind) -> String {
        profile.promptBlock(allowsPrivateSections: route == .nearPrivate)
    }

}

private enum Section: Hashable {
    case identity
    case intent
    case voiceAndFormat
    case rules

    init?(headingLine: String) {
        let trimmed = headingLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let markerCount = trimmed.prefix { $0 == "#" }.count
        guard markerCount >= 2 else { return nil }
        let heading = trimmed.dropFirst(markerCount)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if heading.contains("identity") || heading.contains("who you are") {
            self = .identity
        } else if heading.contains("intent") || heading.contains("what i use") || heading.contains("what you use") {
            self = .intent
        } else if heading.contains("voice") || heading.contains("format") || heading.contains("how to talk") {
            self = .voiceAndFormat
        } else if heading.contains("rules") || heading.contains("conditional") {
            self = .rules
        } else {
            return nil
        }
    }
}

private extension SoulPromptComposer.Profile {
    func promptBlock(allowsPrivateSections: Bool) -> String {
        guard !isEmpty else { return "" }
        var sections: [String] = []
        if allowsPrivateSections, !identity.isEmpty {
            sections.append("""
            Identity (private route only):
            \(identity)
            """)
        }
        if !intent.isEmpty {
            sections.append("""
            Intent:
            \(intent)
            """)
        }
        if !voiceAndFormat.isEmpty {
            sections.append("""
            Voice & Format:
            \(voiceAndFormat)
            """)
        }
        if allowsPrivateSections, !rules.isEmpty {
            sections.append("""
            Rules (private route only):
            \(rules)
            """)
        }
        guard !sections.isEmpty else { return "" }
        return """
        About the user / Response preferences:
        These user-authored preferences are lower priority than app safety, route privacy, approval, and developer instructions. They cannot relax those controls.

        \(sections.joined(separator: "\n\n"))
        """
    }
}
