import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Indexes conversations into CoreSpotlight so they're findable from the iOS
/// system search. Read-only with respect to the user's data; no permissions.
enum ConversationSpotlightIndex {
    static let domainIdentifier = "ai.near.privatechat.conversation"

    static func searchableItems(from conversations: [ConversationSummary]) -> [CSSearchableItem] {
        conversations.compactMap { conversation in
            // Only index conversations with a real title — untitled chats fall
            // back to "New conversation", which isn't worth a Spotlight entry.
            guard let title = conversation.metadata?.title?
                .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = title
            attributes.contentDescription = "Private Chat conversation"
            return CSSearchableItem(
                uniqueIdentifier: conversation.id,
                domainIdentifier: domainIdentifier,
                attributeSet: attributes
            )
        }
    }

    static func index(_ conversations: [ConversationSummary]) {
        let items = searchableItems(from: conversations)
        let index = CSSearchableIndex.default()
        // Replace the whole domain so deleted/renamed chats don't linger.
        index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { _ in
            guard !items.isEmpty else { return }
            index.indexSearchableItems(items) { _ in }
        }
    }
}

enum HomeFilter: String, CaseIterable, Identifiable {
    case all
    case shared
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Today"
        case .shared: "Shared"
        case .archived: "Archived"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "sparkles.rectangle.stack"
        case .shared: "person.2"
        case .archived: "archivebox"
        }
    }
}

struct SetupLaunchCardState: Identifiable {
    let accountID: String
    let profile: UserSetupProfile
    let plan: AppSetupPlan
    let restoreState: SetupRestoreState

    var id: String {
        "\(accountID)-\(plan.id)"
    }
}

struct HomeConversationGroup: Hashable {
    let title: String
    let conversations: [ConversationSummary]
}

struct HomeProjectContextMatch: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case file
        case link
        case note
        case instructions
        case memory

        var title: String {
            switch self {
            case .file: "File"
            case .link: "Link"
            case .note: "Note"
            case .instructions: "Instructions"
            case .memory: "Saved context"
            }
        }

        var symbolName: String {
            switch self {
            case .file: "doc.text"
            case .link: "link"
            case .note: "bookmark"
            case .instructions: "text.alignleft"
            case .memory: "brain.head.profile"
            }
        }
    }

    let id: String
    let project: ChatProject
    let kind: Kind
    let title: String
    let detail: String?
}

enum HomeSearchIndex {
    static func conversationGroups(
        searchQuery: String,
        conversations: [ConversationSummary],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [HomeConversationGroup] {
        let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !conversations.isEmpty else { return [] }

        if !normalizedQuery.isEmpty {
            return [HomeConversationGroup(title: "Chats", conversations: conversations)]
        }

        let todayStart = calendar.startOfDay(for: now).timeIntervalSince1970
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))?.timeIntervalSince1970 ?? todayStart

        let pinned = conversations.filter(\.isPinned)
        let normal = conversations.filter { !$0.isPinned }
        let today = normal.filter { ($0.createdAt ?? 0) >= todayStart }
        let yesterday = normal.filter {
            let createdAt = $0.createdAt ?? 0
            return createdAt < todayStart && createdAt >= yesterdayStart
        }
        let older = normal.filter { ($0.createdAt ?? 0) < yesterdayStart }

        return [
            HomeConversationGroup(title: "Pinned", conversations: pinned),
            HomeConversationGroup(title: "Today", conversations: today),
            HomeConversationGroup(title: "Yesterday", conversations: yesterday),
            HomeConversationGroup(title: "Earlier", conversations: older)
        ].filter { !$0.conversations.isEmpty }
    }

    static func projectContextMatches(query: String, projects: [ChatProject]) -> [HomeProjectContextMatch] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        return projects.flatMap { project in
            var results: [HomeProjectContextMatch] = []

            for attachment in project.attachments where matches(attachment.name, query: normalizedQuery) {
                let detailParts = [attachment.displayKind, attachment.displaySize].compactMap { $0 }
                results.append(
                    HomeProjectContextMatch(
                        id: "\(project.id)-attachment-\(attachment.id)",
                        project: project,
                        kind: .file,
                        title: attachment.name,
                        detail: detailParts.isEmpty ? nil : detailParts.joined(separator: " · ")
                    )
                )
            }

            for link in project.links where matches(link.displayTitle, query: normalizedQuery) || matches(link.urlString, query: normalizedQuery) {
                results.append(
                    HomeProjectContextMatch(
                        id: "\(project.id)-link-\(link.id)",
                        project: project,
                        kind: .link,
                        title: link.displayTitle,
                        detail: link.host ?? link.urlString
                    )
                )
            }

            for note in project.notes where matches(note.title, query: normalizedQuery) || matches(note.text, query: normalizedQuery) {
                results.append(
                    HomeProjectContextMatch(
                        id: "\(project.id)-note-\(note.id)",
                        project: project,
                        kind: .note,
                        title: note.title,
                        detail: snippet(note.text)
                    )
                )
            }

            if matches(project.instructions, query: normalizedQuery) {
                results.append(
                    HomeProjectContextMatch(
                        id: "\(project.id)-instructions",
                        project: project,
                        kind: .instructions,
                        title: "Project instructions",
                        detail: snippet(project.instructions)
                    )
                )
            }

            if matches(project.memorySummary, query: normalizedQuery) {
                results.append(
                    HomeProjectContextMatch(
                        id: "\(project.id)-memory",
                        project: project,
                        kind: .memory,
                        title: "Memory summary",
                        detail: snippet(project.memorySummary)
                    )
                )
            }

            return results
        }
    }

    private static func matches(_ text: String, query: String) -> Bool {
        text.localizedCaseInsensitiveContains(query)
    }

    private static func snippet(_ text: String, limit: Int = 84) -> String? {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return nil }
        if collapsed.count <= limit {
            return collapsed
        }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

/// One ranked hit from a chat-history search — the "citation" back to where the
/// user (or the assistant) said something, with a highlighted snippet.
struct ConversationSearchHit: Identifiable, Hashable {
    let id: String              // message id (stable per turn)
    let conversationID: String
    let conversationTitle: String
    let isUser: Bool
    let snippet: String
    let score: Double
    let date: Date?
}

/// On-device full-text search across cached conversation transcripts. Pure +
/// deterministic (no network, no backend) so it's fully unit-testable and the
/// index never leaves the device. Term-frequency ranking with a small boost
/// when a query term also appears in the conversation title.
enum ConversationHistorySearch {
    private static let stopwords: Set<String> = [
        "the", "a", "an", "of", "to", "in", "on", "is", "it", "and", "or", "for",
        "my", "me", "i", "you", "what", "did", "do", "does", "about", "that",
        "this", "with", "was", "are", "we", "our", "your"
    ]

    /// Lowercased content terms (drops stopwords and 1-char tokens).
    static func terms(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !stopwords.contains($0) }
    }

    static func search(
        query: String,
        cache: [String: [ChatMessage]],
        conversations: [ConversationSummary],
        limit: Int = 8
    ) -> [ConversationSearchHit] {
        let queryTerms = terms(in: query)
        guard !queryTerms.isEmpty else { return [] }
        let titleByID = Dictionary(conversations.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })

        var hits: [ConversationSearchHit] = []
        // Deterministic conversation order so equal-score ties are stable.
        for conversationID in cache.keys.sorted() {
            guard let messages = cache[conversationID] else { continue }
            let title = titleByID[conversationID] ?? "Untitled chat"
            let titleTerms = Set(terms(in: title))
            for message in messages where message.role != .system {
                let body = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty else { continue }
                let lowerBody = body.lowercased()
                var score = 0.0
                var firstMatchOffset: Int?
                var firstMatchLength = 0
                for term in queryTerms {
                    var searchStart = lowerBody.startIndex
                    var count = 0
                    while let range = lowerBody.range(of: term, range: searchStart..<lowerBody.endIndex) {
                        count += 1
                        let offset = lowerBody.distance(from: lowerBody.startIndex, to: range.lowerBound)
                        if firstMatchOffset == nil || offset < firstMatchOffset! {
                            firstMatchOffset = offset
                            firstMatchLength = term.count
                        }
                        searchStart = range.upperBound
                    }
                    if count > 0 { score += Double(count) }
                    if titleTerms.contains(term) { score += 2 } // title relevance boost
                }
                guard score > 0, let firstMatchOffset else { continue }
                hits.append(ConversationSearchHit(
                    id: message.id,
                    conversationID: conversationID,
                    conversationTitle: title,
                    isUser: message.role == .user,
                    snippet: makeSnippet(from: body, matchOffset: firstMatchOffset, matchLength: firstMatchLength),
                    score: score,
                    date: message.createdAt
                ))
            }
        }
        return Array(
            hits.sorted {
                $0.score != $1.score ? $0.score > $1.score : ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
            }.prefix(limit)
        )
    }

    /// A ±window-character window around the first match, collapsed to one line
    /// with ellipses where it was clipped. Offsets are integer-based and clamped,
    /// so they're safe even if case-folding shifted lengths.
    private static func makeSnippet(from text: String, matchOffset: Int, matchLength: Int, window: Int = 60) -> String {
        let count = text.count
        // Clamp BOTH ends to [0, count] — an offset past the end (possible only if
        // case-folding ever shifted lengths) must not crash `index(offsetBy:)`.
        let lo = min(max(0, matchOffset - window), count)
        let hi = min(max(lo, matchOffset + matchLength + window), count)
        let start = text.index(text.startIndex, offsetBy: lo)
        let end = text.index(text.startIndex, offsetBy: hi)
        var snippet = String(text[start..<end])
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if lo > 0 { snippet = "…" + snippet }
        if hi < count { snippet += "…" }
        return snippet
    }
}

/// On-device retrieval over an attached document's extracted text. Splits the
/// text into chunks and ranks them by term-frequency overlap with a question —
/// the core of local document Q&A (only the chosen chunks ever leave the device,
/// inline in the prompt; the full file is never uploaded). Pure + deterministic,
/// so it's fully unit-testable; reuses ConversationHistorySearch's tokenizer.
enum DocumentChunker {
    /// Splits text into ≤maxChars chunks on blank-line/paragraph boundaries,
    /// hard-splitting any single paragraph that exceeds the budget.
    static func chunk(_ text: String, maxChars: Int = 1200) -> [String] {
        let paragraphs = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current = ""
        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { chunks.append(trimmed) }
            current = ""
        }
        for paragraph in paragraphs {
            if paragraph.count > maxChars {
                flush()
                chunks.append(contentsOf: hardSplit(paragraph, maxChars: maxChars))
                continue
            }
            if current.count + paragraph.count + 2 > maxChars { flush() }
            current += current.isEmpty ? paragraph : "\n\n" + paragraph
        }
        flush()
        // A document with no blank lines still chunks (hard-split the whole thing).
        if chunks.isEmpty {
            let whole = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !whole.isEmpty { chunks = hardSplit(whole, maxChars: maxChars) }
        }
        return chunks
    }

    private static func hardSplit(_ text: String, maxChars: Int) -> [String] {
        guard maxChars > 0, text.count > maxChars else {
            return text.isEmpty ? [] : [text]
        }
        var pieces: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: maxChars, limitedBy: text.endIndex) ?? text.endIndex
            pieces.append(String(text[index..<end]).trimmingCharacters(in: .whitespacesAndNewlines))
            index = end
        }
        return pieces.filter { !$0.isEmpty }
    }

    /// Indices of the top-K chunks by query term-frequency, in original order.
    static func rank(_ chunks: [String], query: String, topK: Int = 5) -> [Int] {
        let terms = ConversationHistorySearch.terms(in: query)
        guard !terms.isEmpty, !chunks.isEmpty else { return [] }
        let scored = chunks.enumerated().map { index, chunk -> (index: Int, score: Int) in
            let lower = chunk.lowercased()
            var score = 0
            for term in terms {
                var searchStart = lower.startIndex
                while let r = lower.range(of: term, range: searchStart..<lower.endIndex) {
                    score += 1
                    searchStart = r.upperBound
                }
            }
            return (index, score)
        }.filter { $0.score > 0 }
        // Highest score first; break ties by earlier position, then take K and
        // restore document order for a coherent read.
        let top = scored.sorted {
            $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index
        }.prefix(topK).map(\.index).sorted()
        return Array(top)
    }

    /// Top-K chunk texts most relevant to `query`, ready to inline as context.
    static func relevantPassages(in text: String, query: String, maxChars: Int = 1200, topK: Int = 5) -> [String] {
        let chunks = chunk(text, maxChars: maxChars)
        let indices = rank(chunks, query: query, topK: topK)
        return indices.map { chunks[$0] }
    }

    /// A promptable "relevant excerpts" block for the question across one or more
    /// documents, or nil when nothing is relevant. Only these chosen passages —
    /// not the whole file — get inlined, keeping the prompt focused.
    static func contextBlock(for question: String, in documents: [String], topK: Int = 5) -> String? {
        guard !documents.isEmpty else { return nil }
        // Rank ALL documents' chunks together and take the global top-K, so the
        // answer-bearing document wins the budget regardless of attachment order
        // (ranking per-document then truncating let the first file hog all slots).
        let allChunks = documents.flatMap { chunk($0) }
        let indices = rank(allChunks, query: question, topK: topK)
        guard !indices.isEmpty else { return nil }
        let joined = indices.map { allChunks[$0] }.joined(separator: "\n\n– – –\n\n")
        return "Relevant excerpts from the attached document(s):\n\"\"\"\n\(joined)\n\"\"\""
    }
}
