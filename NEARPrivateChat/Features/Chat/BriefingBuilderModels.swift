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
            draft.prompt = "Track NEAR account \(account)."
            draft.accountID = account
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
            let schedule = current.schedule
            let draft = BriefingBuilderDraft(
                title: "NEAR account",
                prompt: account.map { "Track NEAR account \($0)." } ?? "Track my NEAR account.",
                schedule: schedule,
                kind: .nearAccount,
                accountID: account
            )
            let reply = account == nil
                ? "I can do that. Send the NEAR account id and I will finish the draft."
                : Self.reply(for: draft)
            return BriefingBuilderPlan(draft: draft, reply: reply)
        case .news:
            let draft = BriefingBuilderDraft(
                title: "Daily news brief",
                prompt: "Today's top news",
                schedule: current.schedule,
                kind: .dailyNews
            )
            return BriefingBuilderPlan(draft: draft, reply: reply(for: draft))
        case let .price(coinID, symbol):
            let kind: BriefingKind = coinID == "ethereum" ? .ethPrice : .cryptoPrice
            let draft = BriefingBuilderDraft(
                title: "\(symbol) price",
                prompt: "What is the \(symbol) price?",
                schedule: current.schedule,
                kind: kind,
                accountID: kind == .cryptoPrice ? coinID : nil
            )
            return BriefingBuilderPlan(draft: draft, reply: reply(for: draft))
        case let .stock(symbol, company):
            let draft = BriefingBuilderDraft(
                title: "\(company) stock",
                prompt: "Track \(company) (\(symbol)) stock price.",
                schedule: current.schedule,
                kind: .stockPrice,
                accountID: symbol
            )
            return BriefingBuilderPlan(draft: draft, reply: reply(for: draft))
        case let .watchlist(serialized):
            let draft = BriefingBuilderDraft(
                title: "Watchlist",
                prompt: "Track this watchlist.",
                schedule: current.schedule,
                kind: .watchlist,
                accountID: serialized
            )
            return BriefingBuilderPlan(draft: draft, reply: reply(for: draft))
        case .briefMe:
            let draft = BriefingBuilderDraft(
                title: "Daily Brief",
                prompt: "Brief me",
                schedule: current.schedule,
                kind: .dailyBrief
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
        let prompt: String
        if let specPrompt = spec.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !specPrompt.isEmpty {
            prompt = spec.kind == .customPrompt ? enhancedRecurringPrompt(specPrompt) : specPrompt
        } else if spec.kind == .nearAccount, let account = spec.subject {
            prompt = "Track NEAR account \(account)."
        } else {
            let confirmation = spec.confirmation.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            prompt = spec.kind == .customPrompt
                ? genericPrompt(from: fallbackText)
                : (confirmation ?? genericPrompt(from: fallbackText))
        }
        return BriefingBuilderDraft(
            title: title,
            prompt: prompt,
            schedule: spec.schedule,
            kind: spec.kind,
            accountID: spec.subject,
            council: spec.council,
            condition: spec.condition
        )
    }

    static func actionCandidates(for draft: BriefingBuilderDraft) -> [WidgetActionItem] {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty || !prompt.isEmpty else { return [] }

            let baseTitle = title.isEmpty ? "Recurring workflow" : title
            var actions: [WidgetActionItem] = [
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

        let normalized = "\(title) \(prompt)".lowercased()
        if normalized.contains("supplement") ||
            normalized.contains("workbook") ||
            normalized.contains("table") ||
            normalized.contains("dose") ||
            normalized.contains("calendar invite") {
            actions.append(
                WidgetActionItem(
                    title: "Phone reminder candidates",
                    type: "reminder",
                    detail: "Extract rows into reminder cards before anything is written to the phone.",
                    source: title.isEmpty ? nil : title,
                    recurrence: "per row",
                    missingFields: ["exact waking time", "bedtime if used", "start date"],
                    confidence: 0.72,
                    tone: .warn
                )
            )
            actions.append(
                WidgetActionItem(
                    title: "Calendar invite preview",
                    type: "calendar",
                    detail: "Create calendar-worthy events only after concrete dates and times are confirmed.",
                    source: title.isEmpty ? nil : title,
                    missingFields: ["date", "time", "duration"],
                    confidence: 0.62,
                    tone: .neutral
                )
            )
        }

        if normalized.contains("risk") || normalized.contains("decision") || normalized.contains("follow-up") || normalized.contains("follow up") {
            actions.append(
                WidgetActionItem(
                    title: "Decision and follow-up log",
                    type: "decision",
                    detail: "Save durable decisions, risks, and follow-ups back into the project after review.",
                    command: "Save this decision: \(baseTitle)",
                    source: title.isEmpty ? nil : title,
                    confidence: 0.7,
                    tone: .good
                )
            )
        }

        return actions
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
