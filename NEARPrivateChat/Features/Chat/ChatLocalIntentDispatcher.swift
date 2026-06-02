import Foundation

struct ChatLocalIntentDispatch: Equatable {
    var clearsPendingNearAccountTracker: Bool
    var action: ChatLocalIntentAction?
}

enum ChatLocalIntentAction: Equatable {
    case completePendingNearAccountTracker(account: String, schedule: BriefingSchedule)
    case compound([QuickIntent])
    case single(QuickIntent)
}

enum ChatLocalIntentDispatcher {
    static func dispatch(
        text: String,
        pendingNearAccountTrackerSchedule: BriefingSchedule?
    ) -> ChatLocalIntentDispatch? {
        var clearsPendingNearAccountTracker = false
        if let schedule = pendingNearAccountTrackerSchedule {
            if let account = QuickIntentParser.extractAccount(from: text.lowercased()) {
                return ChatLocalIntentDispatch(
                    clearsPendingNearAccountTracker: true,
                    action: .completePendingNearAccountTracker(account: account, schedule: schedule)
                )
            }
            clearsPendingNearAccountTracker = true
        }

        if let intents = QuickIntentParser.parseCompound(text) {
            return ChatLocalIntentDispatch(
                clearsPendingNearAccountTracker: clearsPendingNearAccountTracker,
                action: .compound(intents)
            )
        }
        if let intent = QuickIntentParser.parse(text) {
            return ChatLocalIntentDispatch(
                clearsPendingNearAccountTracker: clearsPendingNearAccountTracker,
                action: .single(intent)
            )
        }

        guard clearsPendingNearAccountTracker else { return nil }
        return ChatLocalIntentDispatch(clearsPendingNearAccountTracker: true, action: nil)
    }
}
