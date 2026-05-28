import Foundation

// LiveDataService — turns auth-free public APIs into MessageWidgets so the named
// use cases ("what is ETH price", "how is my NEAR account doing", "pull daily
// news") produce real answers through the widget/briefing UX without the chat
// backend. Filled in by a ring-fenced workstream.

enum LiveDataService {
    /// ETH price + 24h sparkline (CoinGecko) → chart widget.
    static func ethPriceWidget() async -> MessageWidget? {
        guard let priceURL = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd&include_24hr_change=true"),
              let chartURL = URL(string: "https://api.coingecko.com/api/v3/coins/ethereum/market_chart?vs_currency=usd&days=1") else {
            return nil
        }

        do {
            async let priceData = fetchData(from: priceURL)
            async let chartData = fetchData(from: chartURL)

            let decoder = JSONDecoder()
            let priceResponse = try decoder.decode(EthereumPriceResponse.self, from: try await priceData)
            let chartResponse = try decoder.decode(CoinGeckoMarketChartResponse.self, from: try await chartData)

            guard let price = priceResponse.ethereum.usd,
                  let change = priceResponse.ethereum.usd24HourChange else {
                return nil
            }

            let points = downsample(chartResponse.prices.compactMap(\.price), targetCount: 30)
            guard !points.isEmpty else { return nil }

            return MessageWidget(
                kind: .chart,
                title: "ETH watcher",
                freshness: .fresh,
                time: shortCurrentTimeString(),
                followUp: "Why is it moving?",
                note: nil,
                chart: WidgetChart(
                    label: "ETH / USD",
                    value: currencyFormatter(maximumFractionDigits: 0).string(from: NSNumber(value: price)),
                    delta: percentChangeFormatter().string(from: NSNumber(value: change / 100)),
                    trend: change >= 0 ? .up : .down,
                    points: points,
                    caption: "past 24h",
                    timeframe: "24h"
                ),
                metric: nil,
                comparison: nil,
                newsBrief: nil
            )
        } catch {
            return nil
        }
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
    struct EthereumPriceResponse: Decodable {
        let ethereum: EthereumPrice
    }

    struct EthereumPrice: Decodable {
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
