import Foundation

enum ChatLocalIntentResponseFormatter {
    static func trackerCreated(spec: TrackerSpec) -> String {
        if spec.condition != nil {
            return "Set up an alert — **\(spec.confirmation)**. I’ll check on that cadence and notify you the first time it triggers, then pause it so I don’t repeat. It lives in Trackers; reopen it any time to re-arm, change, or delete it."
        }
        return "Created a tracker — **\(spec.confirmation)**. It runs on schedule and lands in Trackers; open it any time to Run now, change it, or delete it."
    }

    static func trackLastCreated(title: String, schedule: BriefingSchedule) -> String {
        "On it — I’ll track **\(title)** (\(schedule.scheduleLabel)) and surface it in Trackers. It builds a chart as it runs; reopen it any time to Run now, change, or delete."
    }

    static var trackLastNeedsSubject: String {
        "I’m not sure what to track yet — ask me something first (a price, a stat, a topic), then say “track that.”"
    }

    static var nearAccountPrompt: String {
        "Sure — what’s your NEAR account? Tell me the id (e.g. **yourname.near**) and I’ll pull its balance and holdings."
    }

    static func nearAccountTrackerPrompt(schedule: BriefingSchedule) -> String {
        "Sure — which NEAR account should I track? Send the account id (for example **yourname.near**) and I’ll create the recurring tracker for \(schedule.scheduleLabel.lowercased())."
    }

    static func nearAccountTrackerCreated(account: String, schedule: BriefingSchedule) -> String {
        "Created a tracker — **NEAR account · \(account) · \(schedule.scheduleLabel)**. It runs on schedule and lands in Trackers; open it any time to Run now, change it, or delete it."
    }

    static func remembered(_ text: String) -> String {
        "Got it — I’ll remember that:\n\n> \(text)\n\nIt stays on your device and I’ll use it when it’s relevant. Ask “what do you remember” any time."
    }

    static var alreadyRemembered: String {
        "I’ve already got that noted."
    }

    static func memoryRecall(_ memories: [MemoryItem]) -> String {
        guard !memories.isEmpty else {
            return "I’m not remembering anything yet. Tell me something like **“remember that I prefer concise answers”** and I’ll keep it on your device."
        }

        let lines = memories.prefix(20).map { item -> String in
            item.source == .inferred ? "• \(item.text)  _(noted automatically)_" : "• \(item.text)"
        }.joined(separator: "\n")
        let footer = memories.contains { $0.source == .inferred }
            ? "\n\nItems marked _noted automatically_ were picked up from our chats — say “forget …” to drop any of them."
            : ""
        return "Here’s what I’m keeping on your device:\n\n\(lines)\(footer)"
    }

    static func forgot(matching text: String, removed: Int) -> String {
        removed > 0 ? "Done — I’ve forgotten that." : "I didn’t have anything matching “\(text)” saved."
    }

    static var forgotAll: String {
        "Cleared — I’ve wiped everything stored on this device: all remembered facts and my activity log."
    }

    static func forgotAutoLearned(removed: Int) -> String {
        removed > 0
            ? "Done — dropped \(removed) thing\(removed == 1 ? "" : "s") I’d picked up from our chats. Anything you explicitly asked me to remember is still here."
            : "There was nothing auto-learned to forget. Everything I have, you told me directly."
    }

    static func memoryCapture(enabled: Bool) -> String {
        enabled
            ? "Passive memory is on — I’ll quietly note durable details you mention (like where you live or what you prefer) so answers stay personal. Say “what do you remember” to review, or “stop learning about me” to turn it off."
            : "Passive memory is off — I’ll stop noting things on my own. I’ll still remember anything you explicitly ask me to. Say “start learning about me” to turn it back on."
    }

    static func documentPrivacy(onDevice: Bool) -> String {
        onDevice
            ? "Private document mode is on — attach a PDF and it stays on your device. I only send the passages relevant to your question (over the private route); the file itself is never uploaded. Say “upload documents normally” to turn it off."
            : "Private document mode is off — attached PDFs upload as usual so the model can read the whole file. Say “keep documents on device” to turn privacy mode back on."
    }

    static func activityLog(_ entries: [AgentActivityRecord], now: Date = Date()) -> String {
        guard !entries.isEmpty else {
            return "Nothing yet — once briefings run or you create a tracker, I’ll log it here (on your device)."
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let lines = entries.prefix(20).map {
            "• \($0.summary) — \(formatter.localizedString(for: $0.date, relativeTo: now))"
        }.joined(separator: "\n")
        return "Here’s what I’ve done recently (kept on your device):\n\n\(lines)"
    }

    static func searchHistory(query: String, hits: [ConversationSearchHit], now: Date = Date()) -> String {
        guard !hits.isEmpty else {
            return "I couldn’t find anything about “\(query)” in your saved chats. I only search conversations cached on this device, so a chat that hasn’t synced here won’t show up."
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let lines = hits.map { hit -> String in
            let who = hit.isUser ? "You" : "Assistant"
            let when = hit.date.map { " · \(formatter.localizedString(for: $0, relativeTo: now))" } ?? ""
            return "• **\(hit.conversationTitle)** — \(who): \(hit.snippet)\(when)"
        }.joined(separator: "\n")
        return "Found \(hits.count) match\(hits.count == 1 ? "" : "es") for “\(query)” in your chats:\n\n\(lines)"
    }

    static func reminderCreated(_ reminder: PersonalReminder, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Reminder set — I’ll nudge you to **\(reminder.title)** \(formatter.localizedString(for: reminder.date, relativeTo: now)). You’ll get a notification even if the app is closed."
    }

    static var fetchFailed: String {
        "I couldn’t fetch that just now — try again in a moment."
    }

    static var compoundFetchFailed: String {
        "I couldn’t fetch those just now — try again in a moment."
    }
}
