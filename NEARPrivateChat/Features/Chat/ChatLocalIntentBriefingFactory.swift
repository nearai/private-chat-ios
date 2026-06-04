import Foundation

struct ChatLocalIntentTrackLastDraft: Equatable {
    var title: String
    var subject: String
    var briefing: Briefing
}

enum ChatLocalIntentBriefingFactory {
    static func trackerBriefing(for spec: TrackerSpec, fallbackPrompt: String) -> Briefing {
        let keepsStructuredKind = spec.condition != nil
        return Briefing(
            title: spec.title,
            prompt: prompt(for: spec, fallbackPrompt: fallbackPrompt, keepsStructuredKind: keepsStructuredKind),
            schedule: spec.schedule,
            kind: keepsStructuredKind ? spec.kind : .customPrompt,
            accountID: keepsStructuredKind ? spec.subject : nil,
            council: spec.council,
            condition: keepsStructuredKind ? spec.condition : nil
        )
    }

    static func trackLastDraft(priorUserText: String, schedule: BriefingSchedule) -> ChatLocalIntentTrackLastDraft? {
        let priorText = priorUserText.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = QuickIntentParser.subjectFromQuery(priorText)
        guard priorText.count >= 3, subject.count >= 2 else { return nil }

        let title = QuickIntentParser.prettyTrackerTitle(from: subject)
        let briefing = Briefing(
            title: title,
            prompt: "Using web search, find the latest \(subject) and report it concisely — lead with the current number/price (with its currency) and the as-of date. If it's a price or numeric value, present it as a metric or chart widget.",
            schedule: schedule,
            kind: .customPrompt
        )
        return ChatLocalIntentTrackLastDraft(title: title, subject: subject, briefing: briefing)
    }

    static func nearAccountBriefing(
        account: String,
        schedule: BriefingSchedule,
        structured: Bool = false
    ) -> Briefing {
        Briefing(
            title: "NEAR account",
            prompt: modelRoutedPrompt("Track NEAR account \(account)."),
            schedule: schedule,
            kind: structured ? .nearAccount : .customPrompt,
            accountID: structured ? account : nil
        )
    }

    static func trackerActivitySummary(for spec: TrackerSpec) -> String {
        "Created tracker “\(spec.title)” · \(spec.confirmation)"
    }

    static func trackLastActivitySummary(title: String) -> String {
        "Created tracker “\(title)” from “track that”"
    }

    static func nearAccountActivitySummary(account: String, schedule: BriefingSchedule) -> String {
        "Created tracker “NEAR account” · NEAR account · \(account) · \(schedule.scheduleLabel)"
    }

    private static func prompt(
        for spec: TrackerSpec,
        fallbackPrompt: String,
        keepsStructuredKind: Bool
    ) -> String {
        if let prompt = spec.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
            return keepsStructuredKind ? prompt : enhancedRecurringPrompt(prompt)
        }
        if keepsStructuredKind {
            return fallbackPrompt
        }
        switch spec.kind {
        case .nearAccount:
            if let account = spec.subject {
                return modelRoutedPrompt("Track NEAR account \(account).")
            }
        case .cryptoPrice, .ethPrice:
            let subject = spec.subject.map { LiveDataService.symbol(forCoinID: $0) } ?? spec.title
            return modelRoutedPrompt("What is the current \(subject) price? Include the source, as-of time, and what changed.")
        case .stockPrice:
            let subject = spec.subject ?? spec.title
            return modelRoutedPrompt("Track \(subject) stock price. Include the source, as-of time, and what changed.")
        case .watchlist:
            let label = spec.subject.map(watchlistPromptLabel(from:)) ?? spec.title
            return modelRoutedPrompt("Track this watchlist: \(label). Include current sources, movement, and the most important change.")
        case .dailyNews:
            return modelRoutedPrompt("Give me today's top news with current sources and a concise explanation of what matters.")
        case .dailyBrief:
            return modelRoutedPrompt("Brief me on the highest-value updates, risks, and next actions.")
        case .customPrompt:
            break
        }
        return modelRoutedPrompt(fallbackPrompt)
    }

    private static func enhancedRecurringPrompt(_ prompt: String) -> String {
        if prompt.lowercased().contains("calendar-worthy") {
            return prompt
        }
        return """
        \(prompt)

        Return a concise update with what changed, why it matters, any calendar-worthy or follow-up actions, and the next useful action.
        """
    }

    private static func modelRoutedPrompt(_ task: String) -> String {
        """
        Run this recurring workflow through chat: \(task)

        Let the model decide which current sources, searches, calculations, charts, or action previews are needed. Do not rely on app hardcoded defaults. Return a concise update with what changed, why it matters, any calendar-worthy or follow-up actions, and the next useful action.
        """
    }

    private static func watchlistPromptLabel(from serialized: String) -> String {
        let labels = serialized.split(separator: "|").compactMap { item -> String? in
            let value = String(item)
            if value.hasPrefix("crypto:") {
                let coinID = String(value.dropFirst("crypto:".count))
                return LiveDataService.symbol(forCoinID: coinID)
            }
            if value.hasPrefix("stock:") {
                return String(value.dropFirst("stock:".count))
            }
            return value.nilIfEmpty
        }
        return labels.isEmpty ? serialized : labels.joined(separator: ", ")
    }
}
