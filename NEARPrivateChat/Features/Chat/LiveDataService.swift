import Foundation

// LiveDataService — turns auth-free public APIs into MessageWidgets so the named
// use cases ("what is ETH price", "how is my NEAR account doing", "pull daily
// news") produce real answers through the widget/briefing UX without the chat
// backend. Filled in by a ring-fenced workstream.

// Coins recognized in prompts ("eth price", "track near every morning").
struct LiveCoin: Equatable {
    let id: String      // CoinGecko id
    let symbol: String  // display symbol
    let keywords: [String]
}

let liveCoins: [LiveCoin] = [
    LiveCoin(id: "ethereum", symbol: "ETH", keywords: ["ethereum", "eth", "ether"]),
    LiveCoin(id: "near", symbol: "NEAR", keywords: ["near protocol", "near"]),
    LiveCoin(id: "bitcoin", symbol: "BTC", keywords: ["bitcoin", "btc"]),
    LiveCoin(id: "solana", symbol: "SOL", keywords: ["solana", "sol"]),
    LiveCoin(id: "dogecoin", symbol: "DOGE", keywords: ["dogecoin", "doge"])
]

func liveCoin(forID id: String) -> LiveCoin? {
    liveCoins.first { $0.id == id.lowercased() }
}

/// What a typed prompt should do, parsed locally so common data questions and
/// "create a tracker…" commands work without the chat backend.
enum QuickIntent: Equatable {
    case price(coinID: String, symbol: String)
    case nearAccount(account: String?)
    case news
    case createTracker(TrackerSpec)
}

struct TrackerSpec: Equatable {
    var title: String
    var kind: BriefingKind
    var subject: String?            // coin id (price) or account (nearAccount)
    var schedule: BriefingSchedule
    var council: Bool
    var confirmation: String
}

enum QuickIntentParser {
    static func parse(_ raw: String) -> QuickIntent? {
        let text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // 1) "create a tracker / watch / every morning …" — only when the
        // prompt names a subject we can actually track. Otherwise fall through
        // so "remind me to stretch daily" goes to the model, not an ETH tracker.
        let createVerb = contains(text, ["create", "make", "set up", "set-up", "setup", "build", "schedule", "start", "add", "track", "watch", "remind"])
        let trackerNoun = contains(text, ["tracker", "watcher", "alert", "briefing", "brief", "digest", "every day", "every morning", "each morning", "each day", "every weekday", "daily", "weekly"])
        if createVerb && trackerNoun, let spec = makeTracker(from: text) {
            return .createTracker(spec)
        }

        // 2) news
        if contains(text, ["news", "headlines", "what's happening", "whats happening", "top stories", "current events"]) {
            return .news
        }

        // 3) NEAR account — named phrases, or a .near token plus a status word.
        let account = extractAccount(from: text)
        if contains(text, ["my near account", "near account", "near.com account", "account doing", "account balance", "wallet balance", "my wallet", "my balance"]) ||
            (account != nil && contains(text, ["doing", "balance", "holdings", "how is", "status", "account", "wallet", "worth"])) {
            return .nearAccount(account: account)
        }

        // 4) price of a coin (a bare "?" is not enough — it swallows
        // "can you explain ethereum?" — so require an explicit price word).
        if let coin = matchedCoin(in: text),
           contains(text, ["price", "worth", "trading", "how much", "value", "cost"]) {
            return .price(coinID: coin.id, symbol: coin.symbol)
        }

        return nil
    }

    /// Builds a tracker only when a real subject is present. Returns nil for
    /// generic "remind me …" prompts and account trackers with no id so the
    /// caller can fall through to the model instead of scheduling a dead fetch.
    private static func makeTracker(from text: String) -> TrackerSpec? {
        // `council` is recorded for a future scheduled-council runner; today the
        // briefing runner fetches live data, so we don't promise it in the label.
        let council = contains(text, ["council", "panel", "multiple models", "models debate", "debate"])
        let schedule = extractSchedule(from: text)
        let label = schedule.scheduleLabel
        let account = extractAccount(from: text)
        let mentionsAccount = contains(text, ["account", "wallet", "near.com"]) || account != nil

        if mentionsAccount, !contains(text, ["price"]) {
            // An account tracker with no id would schedule an empty fetch.
            guard let account else { return nil }
            return TrackerSpec(
                title: "NEAR account",
                kind: .nearAccount,
                subject: account,
                schedule: schedule,
                council: council,
                confirmation: "NEAR account · \(account) · \(label)"
            )
        }
        if contains(text, ["news", "headlines", "stories"]) {
            return TrackerSpec(title: "Daily news", kind: .dailyNews, subject: nil, schedule: schedule, council: council, confirmation: "Daily news · \(label)")
        }
        // Price tracker only for a supported coin — no silent ETH default.
        guard let coin = matchedCoin(in: text) else { return nil }
        return TrackerSpec(
            title: "\(coin.symbol) price",
            kind: .cryptoPrice,
            subject: coin.id,
            schedule: schedule,
            council: council,
            confirmation: "\(coin.symbol) price · \(label)"
        )
    }

    static func matchedCoin(in text: String) -> LiveCoin? {
        // Longest keyword first so "near protocol" beats "near".
        let candidates = liveCoins.flatMap { coin in coin.keywords.map { (coin, $0) } }
            .sorted { $0.1.count > $1.1.count }
        for (coin, keyword) in candidates where wordPresent(keyword, in: text) {
            return coin
        }
        return nil
    }

    static func extractAccount(from text: String) -> String? {
        // A token ending in .near / .testnet, e.g. "abhishek.near".
        let words = text.replacingOccurrences(of: "?", with: " ").split(separator: " ")
        for word in words {
            let w = word.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            if w.hasSuffix(".near") || w.hasSuffix(".testnet"), w.count > 5 {
                return w
            }
        }
        return nil
    }

    private static func extractSchedule(from text: String) -> BriefingSchedule {
        var hour = 8
        var minute = 0
        if contains(text, ["evening", "night", "9pm", "9 pm"]) { hour = 21 }
        if contains(text, ["noon", "midday"]) { hour = 12 }
        // explicit "8am", "7:30 am", "at 9 pm"
        if let r = text.range(of: #"(\d{1,2})(:(\d{2}))?\s*(am|pm)"#, options: .regularExpression) {
            let token = String(text[r])
            let digits = token.components(separatedBy: CharacterSet(charactersIn: "0123456789").inverted).filter { !$0.isEmpty }
            if let h = digits.first.flatMap({ Int($0) }) {
                hour = h % 12
                if token.contains("pm") { hour += 12 }
                if token.contains("am") && h == 12 { hour = 0 }
            }
            if digits.count > 1, let m = Int(digits[1]) { minute = m }
        }
        if contains(text, ["weekday", "weekdays", "every weekday"]) {
            return .weekdays(hour: hour, minute: minute)
        }
        if contains(text, ["weekly", "every week", "every monday"]) {
            return .weekly(weekday: 2, hour: hour, minute: minute)
        }
        return .daily(hour: hour, minute: minute)
    }

    private static func contains(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func wordPresent(_ word: String, in text: String) -> Bool {
        if word.contains(" ") { return text.contains(word) }
        // whole-word match for short symbols like "eth"/"sol"
        let padded = " \(text.replacingOccurrences(of: "?", with: " ").replacingOccurrences(of: ",", with: " ")) "
        return padded.contains(" \(word) ") || padded.contains(" \(word)'") || text == word
    }
}

extension LiveDataService {
    /// Symbol for a CoinGecko id (for cryptoPrice briefings).
    static func symbol(forCoinID id: String) -> String {
        liveCoin(forID: id)?.symbol ?? id.uppercased()
    }
}

enum LiveDataService {
    /// ETH price + 24h sparkline (CoinGecko) → chart widget.
    static func ethPriceWidget() async -> MessageWidget? {
        await cryptoPriceWidget(coinID: "ethereum", symbol: "ETH")
    }

    /// Price + 24h sparkline for any CoinGecko coin id → chart widget.
    /// The sparkline is best-effort: CoinGecko rate-limits the heavier chart
    /// endpoint first, so if it fails we still surface the live price as a
    /// metric widget rather than failing the whole answer.
    static func cryptoPriceWidget(coinID: String, symbol: String) async -> MessageWidget? {
        let id = coinID.lowercased()
        guard let priceURL = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(id)&vs_currencies=usd&include_24hr_change=true") else {
            return nil
        }

        let decoder = JSONDecoder()
        guard let priceData = try? await fetchData(from: priceURL),
              let coin = (try? decoder.decode([String: CoinSimplePrice].self, from: priceData))?[id],
              let price = coin.usd, let change = coin.usd24HourChange else {
            return nil
        }

        let valueString = currencyFormatter(maximumFractionDigits: price < 10 ? 2 : 0)
            .string(from: NSNumber(value: price)) ?? "$\(price)"
        let deltaString = percentChangeFormatter().string(from: NSNumber(value: change / 100))
        let trend: WidgetTrend = change >= 0 ? .up : .down

        // Sparkline is best-effort; a rate-limited chart call still yields a price.
        var points: [Double] = []
        if let chartURL = URL(string: "https://api.coingecko.com/api/v3/coins/\(id)/market_chart?vs_currency=usd&days=1"),
           let chartData = try? await fetchData(from: chartURL),
           let chartResponse = try? decoder.decode(CoinGeckoMarketChartResponse.self, from: chartData) {
            points = downsample(chartResponse.prices.compactMap(\.price), targetCount: 30)
        }

        if !points.isEmpty {
            return MessageWidget(
                kind: .chart,
                title: "\(symbol) watcher",
                freshness: .fresh,
                time: shortCurrentTimeString(),
                followUp: "Why is it moving?",
                note: nil,
                chart: WidgetChart(
                    label: "\(symbol) / USD",
                    value: valueString,
                    delta: deltaString,
                    trend: trend,
                    points: points,
                    caption: "past 24h",
                    timeframe: "24h"
                ),
                metric: nil,
                comparison: nil,
                newsBrief: nil
            )
        }

        // No sparkline available — still show the live price as a metric.
        return MessageWidget(
            kind: .metric,
            title: "\(symbol) price",
            freshness: .fresh,
            time: shortCurrentTimeString(),
            followUp: "Why is it moving?",
            note: nil,
            chart: nil,
            metric: WidgetMetric(
                label: "\(symbol) / USD",
                value: valueString,
                delta: deltaString,
                trend: trend,
                caption: "24h change"
            ),
            comparison: nil,
            newsBrief: nil
        )
    }

    /// NEAR account balance / holdings (NEAR RPC + FastNEAR) → metric widget.
    static func nearAccountWidget(account: String) async -> MessageWidget? {
        let accountID = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountID.isEmpty,
              let rpcURL = URL(string: "https://rpc.mainnet.near.org") else {
            return nil
        }

        do {
            var request = URLRequest(url: rpcURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(NEARAccountRPCRequest(accountID: accountID))

            let response = try JSONDecoder().decode(NEARAccountRPCResponse.self, from: try await fetchData(for: request))
            guard response.error == nil,
                  response.result?.error == nil,
                  let amount = response.result?.amount,
                  let balance = nearBalance(fromYoctoNEAR: amount) else {
                return accountNotFoundWidget(accountID: accountID)
            }

            async let holdings = fetchFastNEARHoldings(accountID: accountID)
            async let nearUSDPrice = fetchNEARUSDPrice()

            let caption = await nearCaption(balance: balance, holdings: holdings, usdPrice: nearUSDPrice)

            return MessageWidget(
                kind: .metric,
                title: accountID,
                freshness: .fresh,
                time: shortCurrentTimeString(),
                followUp: "Show recent activity",
                note: nil,
                chart: nil,
                metric: WidgetMetric(
                    label: "NEAR balance",
                    value: nearBalanceFormatter().string(from: balance as NSDecimalNumber) ?? "\(balance) NEAR",
                    delta: nil,
                    trend: .flat,
                    caption: caption
                ),
                comparison: nil,
                newsBrief: nil
            )
        } catch {
            return nil
        }
    }

    /// Top headlines (public RSS) → news-brief widget.
    static func newsBriefWidget() async -> MessageWidget? {
        guard let url = URL(string: "https://feeds.bbci.co.uk/news/rss.xml") else {
            return nil
        }

        do {
            let parser = BBCNewsRSSParser()
            let items = parser.parse(data: try await fetchData(from: url)).prefix(4)
            guard !items.isEmpty else { return nil }

            let source = WidgetNewsSource(label: "B", color: "#990000", domain: "bbc.com")
            let stories = items.map { item in
                WidgetNewsStory(title: item.title, tag: nil, sources: [source], url: item.link)
            }

            return MessageWidget(
                kind: .newsBrief,
                title: "Daily news brief",
                freshness: .fresh,
                time: shortCurrentTimeString(),
                followUp: "What's the biggest story?",
                note: nil,
                chart: nil,
                metric: nil,
                comparison: nil,
                newsBrief: WidgetNewsBrief(
                    heading: "Today · \(stories.count) stories",
                    stories: stories
                )
            )
        } catch {
            return nil
        }
    }
}

private extension LiveDataService {
    struct CoinSimplePrice: Decodable {
        let usd: Double?
        let usd24HourChange: Double?

        enum CodingKeys: String, CodingKey {
            case usd
            case usd24HourChange = "usd_24h_change"
        }
    }

    struct CoinGeckoMarketChartResponse: Decodable {
        let prices: [CoinGeckoPricePoint]
    }

    struct CoinGeckoPricePoint: Decodable {
        let price: Double?

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            _ = try? container.decode(Double.self)
            price = try? container.decode(Double.self)
        }
    }

    struct NEARAccountRPCRequest: Encodable {
        let jsonrpc = "2.0"
        let id = "1"
        let method = "query"
        let params: Params

        init(accountID: String) {
            params = Params(accountID: accountID)
        }

        enum CodingKeys: String, CodingKey {
            case jsonrpc, id, method, params
        }

        struct Params: Encodable {
            let requestType = "view_account"
            let finality = "final"
            let accountID: String

            enum CodingKeys: String, CodingKey {
                case requestType = "request_type"
                case finality
                case accountID = "account_id"
            }
        }
    }

    struct NEARAccountRPCResponse: Decodable {
        let result: NEARAccountResult?
        let error: NEARRPCError?
    }

    struct NEARAccountResult: Decodable {
        let amount: String?
        let storageUsage: Int?
        let error: NEARRPCError?

        enum CodingKeys: String, CodingKey {
            case amount
            case storageUsage = "storage_usage"
            case error
        }
    }

    struct NEARRPCError: Decodable {
        let message: String?
    }

    struct FastNEARAccountResponse: Decodable {
        let tokens: [FastNEARToken]?
        let nfts: [FastNEARNFT]?
    }

    struct FastNEARToken: Decodable {}

    struct FastNEARNFT: Decodable {}

    struct NEARPriceResponse: Decodable {
        let near: NEARPrice
    }

    struct NEARPrice: Decodable {
        let usd: Double?
    }

    struct FastNEARHoldings {
        let tokenCount: Int
        let nftCount: Int
    }

    static func fetchData(from url: URL) async throws -> Data {
        try await fetchData(for: URLRequest(url: url))
    }

    static func fetchData(for request: URLRequest) async throws -> Data {
        // Clamp every live fetch to a short timeout so a stalled endpoint can't
        // tie up a manual or background briefing run.
        var timedRequest = request
        timedRequest.timeoutInterval = min(timedRequest.timeoutInterval, 12)
        let (data, response) = try await URLSession.shared.data(for: timedRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    static func downsample(_ values: [Double], targetCount: Int) -> [Double] {
        guard values.count > targetCount, targetCount > 1 else {
            return values
        }

        let maxIndex = values.count - 1
        let denominator = targetCount - 1
        var points: [Double] = []
        points.reserveCapacity(targetCount)

        for index in 0..<targetCount {
            let sourceIndex = (index * maxIndex + denominator / 2) / denominator
            points.append(values[sourceIndex])
        }

        return points
    }

    static func nearBalance(fromYoctoNEAR amount: String) -> Decimal? {
        guard let yocto = Decimal(string: amount),
              let divisor = Decimal(string: "1000000000000000000000000") else {
            return nil
        }
        return yocto / divisor
    }

    static func fetchFastNEARHoldings(accountID: String) async -> FastNEARHoldings? {
        guard let encodedAccount = accountID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.fastnear.com/v1/account/\(encodedAccount)/full") else {
            return nil
        }

        do {
            let response = try JSONDecoder().decode(FastNEARAccountResponse.self, from: try await fetchData(from: url))
            return FastNEARHoldings(
                tokenCount: response.tokens?.count ?? 0,
                nftCount: response.nfts?.count ?? 0
            )
        } catch {
            return nil
        }
    }

    static func fetchNEARUSDPrice() async -> Double? {
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=near&vs_currencies=usd") else {
            return nil
        }

        do {
            return try JSONDecoder().decode(NEARPriceResponse.self, from: try await fetchData(from: url)).near.usd
        } catch {
            return nil
        }
    }

    static func nearCaption(balance: Decimal, holdings: FastNEARHoldings?, usdPrice: Double?) -> String? {
        var parts: [String] = []

        if let usdPrice {
            let balanceNumber = balance as NSDecimalNumber
            let usdValue = balanceNumber.doubleValue * usdPrice
            if let formattedUSD = currencyFormatter(maximumFractionDigits: 2).string(from: NSNumber(value: usdValue)) {
                parts.append(formattedUSD)
            }
        }

        if let holdings {
            parts.append("\(holdings.tokenCount) tokens · \(holdings.nftCount) NFTs")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func accountNotFoundWidget(accountID: String) -> MessageWidget {
        MessageWidget(
            kind: .generic,
            title: accountID,
            freshness: .fresh,
            time: shortCurrentTimeString(),
            followUp: nil,
            note: "Account \(accountID) wasn’t found on NEAR mainnet.",
            chart: nil,
            metric: nil,
            comparison: nil,
            newsBrief: nil
        )
    }

    static func currencyFormatter(maximumFractionDigits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minimumFractionDigits = 0
        return formatter
    }

    static func nearBalanceFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 2
        formatter.positiveSuffix = " NEAR"
        formatter.negativeSuffix = " NEAR"
        return formatter
    }

    static func percentChangeFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        formatter.plusSign = "+"
        formatter.minusSign = "−"
        formatter.positivePrefix = "+"
        return formatter
    }

    static func shortCurrentTimeString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: Date())
    }
}

private final class BBCNewsRSSParser: NSObject, XMLParserDelegate {
    private(set) var items: [Item] = []

    private var isInsideItem = false
    private var currentElement: String?
    private var currentTitle = ""
    private var currentLink = ""

    struct Item {
        let title: String
        let link: String
    }

    func parse(data: Data) -> [Item] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse() ? items : []
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()
        if name == "item" {
            isInsideItem = true
            currentTitle = ""
            currentLink = ""
        }
        currentElement = isInsideItem ? name : nil
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        append(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else { return }
        append(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        if name == "item" {
            let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let link = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, !link.isEmpty {
                items.append(Item(title: title, link: link))
            }
            isInsideItem = false
            currentElement = nil
            return
        }

        if currentElement == name {
            currentElement = nil
        }
    }

    private func append(_ string: String) {
        guard isInsideItem else { return }
        switch currentElement {
        case "title":
            currentTitle += string
        case "link":
            currentLink += string
        default:
            break
        }
    }
}
