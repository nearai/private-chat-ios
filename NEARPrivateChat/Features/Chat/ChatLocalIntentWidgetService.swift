import Foundation

enum ChatLocalIntentWidgetService {
    static func widget(
        for intent: QuickIntent,
        briefDigestWidget: () async -> MessageWidget?
    ) async -> MessageWidget? {
        switch intent {
        case .briefMe:
            return await briefDigestWidget()
        case .price, .stock, .watchlist, .trendingCrypto, .cryptoMarket,
             .nearAccount, .news, .weather, .worldTime, .fx, .unitConvert,
             .define, .math, .dateMath, .tipSplit, .remember, .recallMemory,
             .forget, .forgetAutoLearned, .setMemoryCapture, .setDocumentPrivacy,
             .activityLog, .listTrackers, .capabilities, .searchHistory,
             .createReminder, .createTracker, .requestNearAccountTracker,
             .trackLast:
            return nil
        }
    }
}
