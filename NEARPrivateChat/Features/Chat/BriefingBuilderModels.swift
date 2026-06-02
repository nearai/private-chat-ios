import Foundation

struct BriefingBuilderMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case assistant
        case user
    }

    let id = UUID()
    let role: Role
    let text: String
}

struct BriefingBuilderDraft: Equatable {
    var title: String = ""
    var prompt: String = ""
    var schedule: BriefingSchedule = .weekdays(hour: 8, minute: 0)
    var kind: BriefingKind = .customPrompt
    var accountID: String? = nil
    var council: Bool = false
    var condition: BriefingCondition? = nil
}

struct BriefingBuilderPlan: Equatable {
    var draft: BriefingBuilderDraft
    var reply: String
    var actions: [WidgetActionItem]

    init(draft: BriefingBuilderDraft, reply: String, actions: [WidgetActionItem]? = nil) {
        self.draft = draft
        self.reply = reply
        self.actions = actions ?? BriefingBuilderPlanner.actionCandidates(for: draft)
    }
}

enum BriefingBuilderPlanner {
    static func plan(from rawText: String, current: BriefingBuilderDraft = BriefingBuilderDraft()) -> BriefingBuilderPlan {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return BriefingBuilderPlan(draft: current, reply: "Tell me what to turn into a workflow and how often it should run.")
        }

        if current.kind == .nearAccount,
           current.accountID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           let account = QuickIntentParser.extractAccount(from: text.lowercased()) {
            var draft = current
            draft.title = "NEAR account"
            draft.prompt = modelRoutedPrompt("Track NEAR account \(account).")
            draft.kind = .customPrompt
            draft.accountID = nil
            return BriefingBuilderPlan(draft: draft, reply: reply(for: draft))
        }

        if !current.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let revision = QuickIntentParser.parse("create a tracker for \(current.title) \(text)"),
           case let .createTracker(spec) = revision {
            var draft = current
            draft.schedule = spec.schedule
            draft.council = spec.council || current.council
            return BriefingBuilderPlan(draft: draft, reply: reply(for: draft))
        }

        let parsed = QuickIntentParser.parse(text)
            ?? QuickIntentParser.parse("create a tracker for \(text)")
            ?? QuickIntentParser.parse("make a recurring briefing for \(text)")

        switch parsed {
        case let .createTracker(spec):
            let draft = draft(from: spec, fallbackText: text)
            return BriefingBuilderPlan(draft: draft, reply: reply(for: draft))
        case let .requestNearAccountTracker(schedule):
            let draft = BriefingBuilderDraft(
                title: "NEAR account",
                prompt: "Track my NEAR account.",
                schedule: schedule,
                kind: .nearAccount
            )
            return BriefingBuilderPlan(
                draft: draft,
                reply: "I can do that. Send the NEAR account id and I will finish the draft."
            )
        case let .nearAccount(account):
            if let account {
                let prompt = modelRoutedPrompt("Track NEAR account \(account).")
                let draft = BriefingBuilderDraft(
                    title: "NEAR account",
                    prompt: prompt,
                    schedule: current.schedule,
                    kind: .customPrompt
                )
                return BriefingBuilderPlan(draft: draft, reply: reply(for: draft))
            }
            let schedule = current.schedule
            let draft = BriefingBuilderDraft(
                title: "NEAR account",
                prompt: "Track my NEAR account.",
                schedule: schedule,
                kind: .nearAccount
            )
            let reply = "I can do that. Send the NEAR account id and I will finish the draft."
            return BriefingBuilderPlan(draft: draft, reply: reply)
        case .news:
            let draft = BriefingBuilderDraft(
                title: "Daily news brief",
                prompt: modelRoutedPrompt("Give me today's top news with current sources and a concise explanation of what matters."),
                schedule: current.schedule,
                kind: .customPrompt
            )
            return BriefingBuilderPlan(draft: draft, reply: reply(for: draft))
        case let .price(_, symbol):
            let draft = BriefingBuilderDraft(
                title: "\(symbol) price",
                prompt: modelRoutedPrompt("What is the current \(symbol) price? Include the source and as-of time."),
                schedule: current.schedule,
                kind: .customPrompt
            )
            return BriefingBuilderPlan(draft: draft, reply: reply(for: draft))
        case let .stock(symbol, company):
            let draft = BriefingBuilderDraft(
                title: "\(company) stock",
                prompt: modelRoutedPrompt("Track \(company) (\(symbol)) stock price. Include the source, as-of time, and what changed."),
                schedule: current.schedule,
                kind: .customPrompt
            )
            return BriefingBuilderPlan(draft: draft, reply: reply(for: draft))
        case let .watchlist(serialized):
            let draft = BriefingBuilderDraft(
                title: "Watchlist",
                prompt: modelRoutedPrompt("Track this watchlist: \(watchlistPromptLabel(from: serialized)). Include current sources, movement, and the most important change."),
                schedule: current.schedule,
                kind: .customPrompt
            )
            return BriefingBuilderPlan(draft: draft, reply: reply(for: draft))
        case .briefMe:
            let draft = BriefingBuilderDraft(
                title: "Daily Brief",
                prompt: modelRoutedPrompt("Brief me on the highest-value updates, risks, and next actions."),
                schedule: current.schedule,
                kind: .customPrompt
            )
            return BriefingBuilderPlan(draft: draft, reply: reply(for: draft))
        default:
            let draft = genericDraft(from: text, current: current)
            return BriefingBuilderPlan(draft: draft, reply: reply(for: draft))
        }
    }

    private static func draft(from spec: TrackerSpec, fallbackText: String) -> BriefingBuilderDraft {
        let rawTitle = spec.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? title(from: fallbackText)
        let title = self.title(from: rawTitle)
        let keepsStructuredKind = spec.condition != nil
        let prompt = prompt(from: spec, fallbackText: fallbackText, keepsStructuredKind: keepsStructuredKind)
        return BriefingBuilderDraft(
            title: title,
            prompt: prompt,
            schedule: spec.schedule,
            kind: keepsStructuredKind ? spec.kind : .customPrompt,
            accountID: keepsStructuredKind ? spec.subject : nil,
            council: spec.council,
            condition: keepsStructuredKind ? spec.condition : nil
        )
    }

    private static func prompt(
        from spec: TrackerSpec,
        fallbackText: String,
        keepsStructuredKind: Bool
    ) -> String {
        if let specPrompt = spec.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !specPrompt.isEmpty {
            return keepsStructuredKind ? specPrompt : enhancedRecurringPrompt(specPrompt)
        }
        if keepsStructuredKind {
            if spec.kind == .nearAccount, let account = spec.subject {
                return "Track NEAR account \(account)."
            }
            return spec.confirmation.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? genericPrompt(from: fallbackText)
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
        return genericPrompt(from: fallbackText)
    }

    static func actionCandidates(for draft: BriefingBuilderDraft) -> [WidgetActionItem] {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty || !prompt.isEmpty else { return [] }

        let baseTitle = title.isEmpty ? "Recurring workflow" : title
        return [
            WidgetActionItem(
                title: baseTitle,
                type: "workflow",
                detail: prompt.isEmpty ? "Run a recurring check and summarize what changed." : prompt,
                schedule: draft.schedule.scheduleLabel,
                command: "Create a tracker for \(prompt.isEmpty ? baseTitle : prompt) \(draft.schedule.scheduleLabel.lowercased())",
                source: draft.kind == .customPrompt ? nil : draft.kind.rawValue,
                recurrence: draft.schedule.scheduleLabel,
                missingFields: draft.kind == .nearAccount && draft.accountID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false ? ["NEAR account"] : [],
                confidence: 0.84,
                tone: .neutral
            )
        ]
    }

    private static func genericDraft(from text: String, current: BriefingBuilderDraft) -> BriefingBuilderDraft {
        BriefingBuilderDraft(
            title: title(from: text),
            prompt: genericPrompt(from: text),
            schedule: current.schedule,
            kind: .customPrompt,
            accountID: nil,
            council: current.council,
            condition: nil
        )
    }

    private static func title(from text: String) -> String {
        var title = text
            .replacingOccurrences(of: #"\b(create|make|set up|build|start|add)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\b(a|an|the)\s+(briefing|tracker|watcher|brief|digest)\s+(for|about|on)?\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b(track|watch|monitor|brief me on|brief me about|keep an eye on)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b(every|daily|weekly|biweekly|monthly|weekdays|weekday|hourly|at)\b.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,:;-").union(.whitespacesAndNewlines))
        if title.isEmpty {
            title = "Workflow"
        }
        return String(title.prefix(48))
    }

    private static func genericPrompt(from text: String) -> String {
        """
        Run this recurring workflow: \(text)

        Use provided or project sources first. If current external data is needed, state what source was checked. Return a concise update with what changed, why it matters, any calendar-worthy or follow-up actions, and the next useful action.
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

    private static func enhancedRecurringPrompt(_ prompt: String) -> String {
        if prompt.lowercased().contains("calendar-worthy") {
            return prompt
        }
        return """
        \(prompt)

        Return a concise update with what changed, why it matters, any calendar-worthy or follow-up actions, and the next useful action.
        """
    }

    private static func reply(for draft: BriefingBuilderDraft) -> String {
        let schedule = draft.schedule.scheduleLabel
        if draft.kind == .nearAccount,
           draft.accountID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return "I staged the NEAR account automation for \(schedule). Send the account id before saving."
        }
        return "Drafted workflow: \(draft.title) - \(schedule). Save it, or tell me what to change."
    }
}
