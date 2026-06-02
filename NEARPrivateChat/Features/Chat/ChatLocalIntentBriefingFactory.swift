import Foundation

struct ChatLocalIntentTrackLastDraft: Equatable {
    var title: String
    var subject: String
    var briefing: Briefing
}

enum ChatLocalIntentBriefingFactory {
    static func trackerBriefing(for spec: TrackerSpec, fallbackPrompt: String) -> Briefing {
        Briefing(
            title: spec.title,
            prompt: spec.prompt ?? fallbackPrompt,
            schedule: spec.schedule,
            kind: spec.kind,
            accountID: spec.subject,
            council: spec.council,
            condition: spec.condition
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

    static func nearAccountBriefing(account: String, schedule: BriefingSchedule) -> Briefing {
        Briefing(
            title: "NEAR account",
            prompt: "Track NEAR account \(account).",
            schedule: schedule,
            kind: .nearAccount,
            accountID: account
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
}
