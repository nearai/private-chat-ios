import Foundation

struct ChatLocalIntentExecutionResult {
    var assistantText: String
    var pendingNearAccountTrackerSchedule: BriefingSchedule?
    var shouldHaptic: Bool = false
}

@MainActor
enum ChatLocalIntentExecutor {
    struct Environment {
        var memoryStore: MemoryStore
        var activityLog: AgentActivityLog
        var trackers: () -> [Briefing]
        var createTracker: (Briefing) -> Void
        var setPassiveMemoryEnabled: (Bool) -> Void
        var setKeepDocumentsOnDevice: (Bool) -> Void
        var searchHistory: (String) -> [ConversationSearchHit]
        var scheduleReminder: (PersonalReminder) -> Void
    }

    static func execute(
        intent: QuickIntent,
        prompt: String,
        priorUserText: String?,
        environment: Environment
    ) -> ChatLocalIntentExecutionResult? {
        switch intent {
        case let .createTracker(spec):
            let briefing = ChatLocalIntentBriefingFactory.trackerBriefing(for: spec, fallbackPrompt: prompt)
            environment.createTracker(briefing)
            environment.activityLog.record(ChatLocalIntentBriefingFactory.trackerActivitySummary(for: spec))
            return ChatLocalIntentExecutionResult(
                assistantText: ChatLocalIntentResponseFormatter.trackerCreated(spec: spec),
                shouldHaptic: true
            )
        case let .trackLast(schedule):
            let priorText = priorUserText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let draft = ChatLocalIntentBriefingFactory.trackLastDraft(priorUserText: priorText, schedule: schedule) {
                environment.createTracker(draft.briefing)
                environment.activityLog.record(ChatLocalIntentBriefingFactory.trackLastActivitySummary(title: draft.title))
                return ChatLocalIntentExecutionResult(
                    assistantText: ChatLocalIntentResponseFormatter.trackLastCreated(title: draft.title, schedule: schedule),
                    shouldHaptic: true
                )
            }
            return ChatLocalIntentExecutionResult(assistantText: ChatLocalIntentResponseFormatter.trackLastNeedsSubject)
        case .nearAccount(nil):
            return ChatLocalIntentExecutionResult(assistantText: ChatLocalIntentResponseFormatter.nearAccountPrompt)
        case let .requestNearAccountTracker(schedule):
            return ChatLocalIntentExecutionResult(
                assistantText: ChatLocalIntentResponseFormatter.nearAccountTrackerPrompt(schedule: schedule),
                pendingNearAccountTrackerSchedule: schedule
            )
        case let .remember(text):
            let assistantText = environment.memoryStore.add(text) != nil
                ? ChatLocalIntentResponseFormatter.remembered(text)
                : ChatLocalIntentResponseFormatter.alreadyRemembered
            return ChatLocalIntentExecutionResult(assistantText: assistantText, shouldHaptic: true)
        case .recallMemory:
            return ChatLocalIntentExecutionResult(
                assistantText: ChatLocalIntentResponseFormatter.memoryRecall(environment.memoryStore.items)
            )
        case let .forget(text):
            if let text {
                let removed = environment.memoryStore.remove(matching: text)
                return ChatLocalIntentExecutionResult(
                    assistantText: ChatLocalIntentResponseFormatter.forgot(matching: text, removed: removed),
                    shouldHaptic: true
                )
            }
            environment.memoryStore.clear()
            environment.activityLog.clear()
            return ChatLocalIntentExecutionResult(
                assistantText: ChatLocalIntentResponseFormatter.forgotAll,
                shouldHaptic: true
            )
        case .forgetAutoLearned:
            let removed = environment.memoryStore.removeInferred()
            return ChatLocalIntentExecutionResult(
                assistantText: ChatLocalIntentResponseFormatter.forgotAutoLearned(removed: removed),
                shouldHaptic: true
            )
        case let .setMemoryCapture(enabled):
            environment.setPassiveMemoryEnabled(enabled)
            return ChatLocalIntentExecutionResult(
                assistantText: ChatLocalIntentResponseFormatter.memoryCapture(enabled: enabled),
                shouldHaptic: true
            )
        case let .setDocumentPrivacy(onDevice):
            environment.setKeepDocumentsOnDevice(onDevice)
            return ChatLocalIntentExecutionResult(
                assistantText: ChatLocalIntentResponseFormatter.documentPrivacy(onDevice: onDevice),
                shouldHaptic: true
            )
        case .activityLog:
            return ChatLocalIntentExecutionResult(
                assistantText: ChatLocalIntentResponseFormatter.activityLog(environment.activityLog.entries)
            )
        case .listTrackers:
            return ChatLocalIntentExecutionResult(
                assistantText: TrackerListFormatter.summary(for: environment.trackers())
            )
        case .capabilities:
            return ChatLocalIntentExecutionResult(assistantText: QuickIntentParser.capabilitiesText())
        case let .math(expression, result):
            return ChatLocalIntentExecutionResult(assistantText: "\(expression) = **\(result)**", shouldHaptic: true)
        case let .dateMath(_, answer):
            return ChatLocalIntentExecutionResult(assistantText: answer, shouldHaptic: true)
        case let .tipSplit(summary):
            return ChatLocalIntentExecutionResult(assistantText: summary, shouldHaptic: true)
        case let .searchHistory(query):
            return ChatLocalIntentExecutionResult(
                assistantText: ChatLocalIntentResponseFormatter.searchHistory(
                    query: query,
                    hits: environment.searchHistory(query)
                )
            )
        case let .createReminder(reminder):
            environment.scheduleReminder(reminder)
            environment.activityLog.record("Set reminder: \(reminder.title)")
            return ChatLocalIntentExecutionResult(
                assistantText: ChatLocalIntentResponseFormatter.reminderCreated(reminder),
                shouldHaptic: true
            )
        default:
            return nil
        }
    }

    static func completePendingNearAccountTracker(
        account: String,
        schedule: BriefingSchedule,
        environment: Environment
    ) -> ChatLocalIntentExecutionResult {
        let briefing = ChatLocalIntentBriefingFactory.nearAccountBriefing(account: account, schedule: schedule)
        environment.createTracker(briefing)
        environment.activityLog.record(ChatLocalIntentBriefingFactory.nearAccountActivitySummary(account: account, schedule: schedule))
        return ChatLocalIntentExecutionResult(
            assistantText: ChatLocalIntentResponseFormatter.nearAccountTrackerCreated(account: account, schedule: schedule),
            shouldHaptic: true
        )
    }

    static func captureInferredMemory(
        from text: String,
        memoryStore: MemoryStore,
        activityLog: AgentActivityLog,
        isEnabled: Bool
    ) {
        guard isEnabled else { return }
        let learned = QuickIntentParser.inferredFacts(from: text)
        guard !learned.isEmpty else { return }
        var stored: [String] = []
        for fact in learned {
            let isNew = !memoryStore.items.contains { $0.text.caseInsensitiveCompare(fact) == .orderedSame }
            if memoryStore.add(fact, source: .inferred) != nil, isNew {
                stored.append(fact)
            }
        }
        guard !stored.isEmpty else { return }
        activityLog.record("Noted from chat: \(stored.joined(separator: "; "))")
    }
}
