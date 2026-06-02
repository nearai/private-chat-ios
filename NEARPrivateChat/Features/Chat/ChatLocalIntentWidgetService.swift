import Foundation

enum ChatLocalIntentWidgetService {
    static func widget(
        for intent: QuickIntent,
        briefDigestWidget: () async -> MessageWidget?
    ) async -> MessageWidget? {
        switch intent {
        case let .price(coinID, symbol):
            return await LiveDataService.cryptoPriceWidget(coinID: coinID, symbol: symbol)
        case let .stock(symbol, company):
            return await LiveDataService.stockQuoteWidget(symbol: symbol, company: company)
        case let .watchlist(serialized):
            return await LiveDataService.watchlistWidget(serialized: serialized)
        case .trendingCrypto:
            return await LiveDataService.trendingCryptoWidget()
        case .cryptoMarket:
            return await LiveDataService.cryptoMarketWidget()
        case .briefMe:
            return await briefDigestWidget()
        case let .nearAccount(account):
            return await LiveDataService.nearAccountWidget(account: account ?? "")
        case .news:
            return await LiveDataService.newsBriefWidget()
        case let .weather(query):
            return await LiveDataService.weatherWidget(query: query)
        case let .worldTime(query):
            return await LiveDataService.worldTimeWidget(query: query)
        case let .fx(amount, from, to):
            return await LiveDataService.fxWidget(amount: amount, from: from, to: to)
        case let .unitConvert(value, from, to):
            return await LiveDataService.unitConvertWidget(value: value, from: from, to: to)
        case let .define(word):
            return await LiveDataService.defineWidget(word: word)
        case .math, .dateMath, .tipSplit, .remember, .recallMemory, .forget, .forgetAutoLearned, .setMemoryCapture, .setDocumentPrivacy, .activityLog, .listTrackers, .capabilities, .searchHistory, .createReminder, .createTracker, .requestNearAccountTracker, .trackLast:
            return nil
        }
    }
}
