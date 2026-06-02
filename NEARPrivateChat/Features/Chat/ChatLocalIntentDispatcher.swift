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

        if let intents = QuickIntentParser.parseCompound(text),
           intents.allSatisfy(shouldHandleLocally) {
            return ChatLocalIntentDispatch(
                clearsPendingNearAccountTracker: clearsPendingNearAccountTracker,
                action: .compound(intents)
            )
        }
        if let intent = QuickIntentParser.parse(text),
           shouldHandleLocally(intent) {
            return ChatLocalIntentDispatch(
                clearsPendingNearAccountTracker: clearsPendingNearAccountTracker,
                action: .single(intent)
            )
        }

        guard clearsPendingNearAccountTracker else { return nil }
        return ChatLocalIntentDispatch(clearsPendingNearAccountTracker: true, action: nil)
    }

    private static func shouldHandleLocally(_ intent: QuickIntent) -> Bool {
        switch intent {
        case .price, .stock, .watchlist, .trendingCrypto, .cryptoMarket, .news,
             .weather, .worldTime, .fx, .unitConvert, .define, .math, .dateMath,
             .tipSplit:
            return false
        case .nearAccount(let account):
            return account == nil
        case .briefMe, .remember, .recallMemory, .forget, .forgetAutoLearned,
             .setMemoryCapture, .setDocumentPrivacy, .activityLog, .listTrackers,
             .capabilities, .searchHistory, .createReminder, .createTracker,
             .requestNearAccountTracker, .trackLast:
            return true
        }
    }
}
