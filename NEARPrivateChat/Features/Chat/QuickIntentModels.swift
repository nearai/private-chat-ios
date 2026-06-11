import Foundation

/// What a typed prompt appears to request. Explicit app-control commands can be
/// handled locally; answer/data intents are routed through the model.
enum QuickIntent: Equatable {
    case price(coinID: String, symbol: String)
    case stock(symbol: String, company: String)
    case watchlist(serialized: String)
    case trendingCrypto
    case cryptoMarket
    case briefMe
    case nearAccount(account: String?)
    case news
    case weather(query: String)
    case worldTime(query: String)
    case fx(amount: Double, from: String, to: String)
    case unitConvert(value: Double, from: String, to: String)
    case define(word: String)
    case math(expression: String, result: String)
    case dateMath(question: String, answer: String)
    case tipSplit(summary: String)
    case remember(text: String)
    case recallMemory
    case forget(text: String?)
    case forgetAutoLearned
    case setMemoryCapture(enabled: Bool)
    case setDocumentPrivacy(onDevice: Bool)
    case activityLog
    case listTrackers
    case capabilities
    case searchHistory(query: String)
    case createReminder(PersonalReminder)
    case createTracker(TrackerSpec)
    case requestNearAccountTracker(schedule: BriefingSchedule)
    /// "track that" — make a tracker from whatever the previous answer was about.
    case trackLast(schedule: BriefingSchedule)
}

/// A one-off personal reminder parsed from natural language ("remind me to call
/// mom at 5pm"). Delivered as a local notification at `date`.
struct PersonalReminder: Equatable {
    var title: String
    var date: Date
}

/// Generic "make this useful" steering for turns where the user wants context
/// converted into concrete next moves. This is deliberately domain-agnostic:
/// supplements, client sheets, repo notes, meeting transcripts, PDFs, and saved
/// project context should all flow through the same action surface.
enum ActionSurfacePlanner {
    static func shouldAugment(text: String, attachmentNames: [String]) -> Bool {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty || !attachmentNames.isEmpty else { return false }
        if normalized.isEmpty {
            return !attachmentNames.isEmpty
        }

        let actionCues = [
            "action", "actionable", "next step", "next steps", "follow up", "follow-up",
            "todo", "to-do", "task", "tasks", "checklist", "plan", "schedule", "tracker",
            "track", "watch", "monitor", "reminder", "remind", "calendar", "invite",
            "habit", "routine", "surface", "interested", "recommend", "extract",
            "analyze", "analyse", "compare", "prioritize", "prioritise", "research",
            "investigate", "deep search", "deep research", "workflow", "generate",
            "brief", "briefing", "digest", "cron", "recurring", "notify",
            "turn into", "turn this into", "make this useful", "what should i do"
        ]
        guard actionCues.contains(where: { normalized.contains($0) }) else {
            return false
        }

        let explicitActionCues = [
            "action", "actionable", "next step", "next steps", "follow up", "follow-up",
            "todo", "to-do", "task", "tasks", "checklist", "plan", "schedule", "tracker",
            "track", "watch", "monitor", "reminder", "remind", "calendar", "invite",
            "habit", "routine", "surface", "recommend", "extract", "prioritize",
            "prioritise", "workflow", "generate", "briefing", "digest", "cron",
            "recurring", "notify", "turn into", "turn this into", "make this useful",
            "what should i do"
        ]
        if attachmentNames.isEmpty,
           !explicitActionCues.contains(where: { normalized.contains($0) }),
           ["research", "investigate", "compare", "analyze", "analyse"].contains(where: { normalized.contains($0) }) {
            return false
        }

        let nonActionExclusions = [
            "what is", "what are", "define ", "translate ", "summarize in one sentence"
        ]
        if attachmentNames.isEmpty,
           nonActionExclusions.contains(where: { normalized.hasPrefix($0) }) {
            return false
        }
        return true
    }

    static func augmentedPrompt(text: String, attachmentNames: [String], sourceInstruction: String? = nil) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard shouldAugment(text: trimmed, attachmentNames: attachmentNames) else {
            return text
        }

        let trimmedSourceInstruction = sourceInstruction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sourceLine = !trimmedSourceInstruction.isEmpty
            ? trimmedSourceInstruction
            : (attachmentNames.isEmpty
                ? "Use the conversation, selected project context, and any supplied sources."
                : "Use every relevant attached file or sheet: \(attachmentNames.joined(separator: ", ")).")
        let userRequest = trimmed.isEmpty
            ? "Review this context and turn it into useful actions."
            : trimmed

        return """
        \(userRequest)

        Action surface contract:
        - \(sourceLine)
        - Do not narrow this to one workflow. Identify the useful actionable surface in the context: trackers/briefings, reminders, calendar-worthy events, habits/routines, tasks, decisions, open questions, risks, and things I am likely to care about.
        - If structured rows or tables exist, scan all relevant sections/sheets and preserve concrete names, quantities, dates, cadences, timing, and caveats.
        - For every proposed action, include: title, type, why it matters, owner/recipient if known, schedule or trigger if present, missing details if any, and the exact app command that would create or stage it.
        - If you emit a near-widget action_plan, include structured fields where known: source, date, time, duration, recurrence, timezone, location, attendees, missing_fields, and confidence. Do not invent concrete times for fuzzy cues like upon waking or before bed; mark the missing field.
        - Use these app command forms when applicable: "Create a tracker for ... every ...", "Remind me to ... at ...", "Make a briefing about ... every ...", "Ask the agent to ...", or "Save this decision: ...".
        - If the user asked to create actions, show a preview first and call out anything that cannot be safely created yet. Do not claim calendar events or trackers were installed unless the app explicitly confirms them.
        - End with the highest-leverage next action and a compact near-widget action_plan card of the top proposed actions when a card would help.
        """
    }
}

struct TrackerSpec: Equatable {
    var title: String
    var kind: BriefingKind
    var subject: String?            // coin id (price) or account (nearAccount)
    var schedule: BriefingSchedule
    var council: Bool
    var confirmation: String
    var prompt: String?             // cleaned prompt for customPrompt council trackers
    var condition: BriefingCondition?  // threshold gate ("when ETH < $2,000"); nil = plain recurring
}
