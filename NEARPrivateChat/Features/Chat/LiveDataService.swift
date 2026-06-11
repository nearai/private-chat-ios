import Foundation

// LiveDataService — deterministic public-data helpers retained for parser
// metadata, threshold-alert gates, and demo/debug capture screens. Normal chat
// answers and recurring workflow presentation route through the model.

enum LiveDataService {
    /// ETH price + 24h sparkline (CoinGecko) → chart widget.
    static func ethPriceWidget() async -> MessageWidget? {
        await cryptoPriceWidget(coinID: "ethereum", symbol: "ETH")
    }

    /// Raw USD spot price for any CoinGecko id — the deterministic value a
    /// conditional tracker evaluates its threshold against. nil on fetch failure.
    static func coinUSDPrice(coinID: String) async -> Double? {
        let id = coinID.lowercased()
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(id)&vs_currencies=usd") else {
            return nil
        }
        guard let data = try? await fetchData(from: url),
              let coin = (try? JSONDecoder().decode([String: CoinSimplePrice].self, from: data))?[id] else {
            return nil
        }
        return coin.usd
    }

    /// "$2,000" / "$1.95" — USD price label for alert copy.
    static func usdPriceString(_ value: Double) -> String {
        currencyFormatter(maximumFractionDigits: value < 10 ? 2 : 0).string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    /// Compact USD for big figures: "$2.34T", "$58.1B", "$420.0M".
    static func compactUSD(_ value: Double) -> String {
        let magnitude = Swift.abs(value)
        if magnitude >= 1e12 { return String(format: "$%.2fT", value / 1e12) }
        if magnitude >= 1e9 { return String(format: "$%.1fB", value / 1e9) }
        if magnitude >= 1e6 { return String(format: "$%.1fM", value / 1e6) }
        return usdPriceString(value)
    }

    /// Global crypto market overview (total cap, 24h change, BTC/ETH dominance)
    /// → comparison widget. Auth-free (`/global`).
    static func cryptoMarketWidget() async -> MessageWidget? {
        guard let url = URL(string: "https://api.coingecko.com/api/v3/global") else { return nil }
        guard let data = try? await fetchData(from: url),
              let response = try? JSONDecoder().decode(CoinGeckoGlobalResponse.self, from: data),
              let totalUSD = response.data.totalMarketCap["usd"] else {
            return nil
        }
        let change = response.data.marketCapChangePercentage24HUsd ?? 0
        var rows: [WidgetComparisonRow] = [
            WidgetComparisonRow(label: "Total market cap", cells: [WidgetComparisonCell(text: compactUSD(totalUSD), tone: nil)]),
            WidgetComparisonRow(label: "24h change", cells: [WidgetComparisonCell(text: String(format: "%+.1f%%", change), tone: change >= 0 ? .good : .warn)])
        ]
        if let btc = response.data.marketCapPercentage["btc"] {
            rows.append(WidgetComparisonRow(label: "BTC dominance", cells: [WidgetComparisonCell(text: String(format: "%.1f%%", btc), tone: nil)]))
        }
        if let eth = response.data.marketCapPercentage["eth"] {
            rows.append(WidgetComparisonRow(label: "ETH dominance", cells: [WidgetComparisonCell(text: String(format: "%.1f%%", eth), tone: nil)]))
        }
        return MessageWidget(
            kind: .comparison,
            title: "Crypto market",
            freshness: .fresh,
            time: shortCurrentTimeString(),
            followUp: "What’s trending?",
            note: nil,
            chart: nil,
            metric: nil,
            comparison: WidgetComparison(subtitle: "Global overview", columns: ["Value"], rows: rows),
            newsBrief: nil
        )
    }

    /// Coins trending on CoinGecko right now → a comparison widget (coin ·
    /// symbol · market-cap rank). Auth-free (`/search/trending`).
    static func trendingCryptoWidget() async -> MessageWidget? {
        guard let url = URL(string: "https://api.coingecko.com/api/v3/search/trending") else { return nil }
        guard let data = try? await fetchData(from: url),
              let response = try? JSONDecoder().decode(CoinGeckoTrendingResponse.self, from: data),
              !response.coins.isEmpty else {
            return nil
        }
        let rows = response.coins.prefix(7).map { wrapper -> WidgetComparisonRow in
            let coin = wrapper.item
            let rank = coin.marketCapRank.map { "#\($0)" } ?? "—"
            return WidgetComparisonRow(
                label: coin.name,
                cells: [
                    WidgetComparisonCell(text: coin.symbol.uppercased(), tone: nil),
                    WidgetComparisonCell(text: rank, tone: nil)
                ]
            )
        }
        return MessageWidget(
            kind: .comparison,
            title: "Trending on CoinGecko",
            freshness: .fresh,
            time: shortCurrentTimeString(),
            followUp: "Want a price on any of these?",
            note: nil,
            chart: nil,
            metric: nil,
            comparison: WidgetComparison(subtitle: "Trending now", columns: ["Symbol", "Rank"], rows: Array(rows)),
            newsBrief: nil
        )
    }

    /// Price + 24h sparkline for any CoinGecko coin id → chart widget.
    /// The sparkline is best-effort: CoinGecko rate-limits the heavier chart
    /// endpoint first, so if it fails we still surface the live price as a
    /// metric widget rather than failing the whole answer.
    // MARK: - Stocks (Yahoo Finance, auth-free)

    private struct YahooChartResponse: Decodable {
        struct Chart: Decodable { let result: [Result]? }
        struct Result: Decodable { let meta: Meta; let indicators: Indicators }
        struct Meta: Decodable {
            let symbol: String?
            let currency: String?
            let regularMarketPrice: Double?
            let chartPreviousClose: Double?
            let previousClose: Double?
        }
        struct Indicators: Decodable { let quote: [Quote] }
        struct Quote: Decodable { let close: [Double?]? }
        let chart: Chart
    }

    /// Yahoo's chart endpoint needs a browser UA, and serves both the live price
    /// and the historical close series for any range — so one call powers both
    /// the quote widget and history charts.
    private static func fetchYahooChart(symbol: String, range: String, interval: String) async -> (price: Double, prevClose: Double?, currency: String, closes: [Double])? {
        let sym = symbol.uppercased()
        guard let encoded = sym.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=\(range)&interval=\(interval)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let data = try? await fetchData(for: request),
              let response = try? JSONDecoder().decode(YahooChartResponse.self, from: data),
              let result = response.chart.result?.first else {
            return nil
        }
        let closes = (result.indicators.quote.first?.close ?? []).compactMap { $0 }
        guard let price = result.meta.regularMarketPrice ?? closes.last else { return nil }
        return (price, result.meta.chartPreviousClose ?? result.meta.previousClose, result.meta.currency ?? "USD", closes)
    }

    private static func stockChartWidget(price: Double, prevClose: Double?, closes: [Double], symbol: String, company: String, caption: String, timeframe: String) -> MessageWidget {
        let points = downsample(closes, targetCount: timeframe == "1M" ? 30 : 40)
        let baseline = prevClose ?? closes.first ?? price
        let change = baseline > 0 ? (price - baseline) / baseline * 100 : 0
        let valueString = currencyFormatter(maximumFractionDigits: 2).string(from: NSNumber(value: price)) ?? "$\(price)"
        let deltaString = percentChangeFormatter().string(from: NSNumber(value: change / 100))
        let title = company.isEmpty ? symbol : company
        let trend: WidgetTrend = change >= 0 ? .up : .down
        if points.count >= 2 {
            return MessageWidget(
                kind: .chart, title: "\(title) · \(symbol)", freshness: .fresh,
                time: shortCurrentTimeString(), followUp: "Track \(symbol)", note: nil,
                chart: WidgetChart(label: "\(symbol) · USD", value: valueString, delta: deltaString, trend: trend, points: points, caption: caption, timeframe: timeframe),
                metric: nil, comparison: nil, newsBrief: nil
            )
        }
        return MessageWidget(
            kind: .metric, title: "\(title) · \(symbol)", freshness: .fresh,
            time: shortCurrentTimeString(), followUp: "Track \(symbol)", note: nil, chart: nil,
            metric: WidgetMetric(label: "\(symbol) · USD", value: valueString, delta: deltaString, trend: trend, caption: "stock price"),
            comparison: nil, newsBrief: nil
        )
    }

    /// Spot stock price (USD) for threshold-alert evaluation.
    static func stockUSDPrice(symbol: String) async -> Double? {
        await fetchYahooChart(symbol: symbol, range: "1d", interval: "1d")?.price
    }

    /// Live stock quote + 1-month sparkline (price, day change vs previous close).
    static func stockQuoteWidget(symbol: String, company: String) async -> MessageWidget? {
        guard let q = await fetchYahooChart(symbol: symbol, range: "1mo", interval: "1d") else { return nil }
        return stockChartWidget(price: q.price, prevClose: q.prevClose, closes: q.closes, symbol: symbol.uppercased(), company: company, caption: "past month", timeframe: "1M")
    }

    /// Real historical stock chart for a Yahoo range ("5d"/"1mo"/"3mo"/"6mo"/"1y"/"max").
    static func stockHistoryChartWidget(symbol: String, range: String, label: String) async -> MessageWidget? {
        guard let q = await fetchYahooChart(symbol: symbol, range: range, interval: "1d"), q.closes.count >= 2 else { return nil }
        return stockChartWidget(price: q.price, prevClose: q.closes.first, closes: q.closes, symbol: symbol.uppercased(), company: "", caption: "past \(label)", timeframe: label)
    }

    /// Maps a CoinGecko `days` value (from parseChartTimeframe) to a Yahoo range.
    static func yahooRange(forDays days: String) -> String {
        switch days {
        case "7": return "5d"
        case "30": return "1mo"
        case "90": return "3mo"
        case "180": return "6mo"
        case "365": return "1y"
        default: return "max"
        }
    }

    /// A glanceable multi-asset watchlist (crypto + stocks) → comparison card,
    /// one row per asset with price + 24h change (color-as-data). `serialized`
    /// is "crypto:ethereum|stock:AAPL|crypto:near". Crypto is batched in one
    /// CoinGecko call; stocks fetch in parallel from Yahoo.
    static func watchlistWidget(serialized: String) async -> MessageWidget? {
        let order: [(kind: String, id: String)] = serialized.split(separator: "|").compactMap { entry in
            let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        }
        guard !order.isEmpty else { return nil }
        let cryptoIDs = order.filter { $0.kind == "crypto" }.map { $0.id }
        let stockSymbols = order.filter { $0.kind == "stock" }.map { $0.id }

        var cryptoData: [String: (price: Double, change: Double)] = [:]
        if !cryptoIDs.isEmpty,
           let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(cryptoIDs.joined(separator: ","))&vs_currencies=usd&include_24hr_change=true"),
           let data = try? await fetchData(from: url),
           let decoded = try? JSONDecoder().decode([String: CoinSimplePrice].self, from: data) {
            for (id, coin) in decoded where coin.usd != nil {
                cryptoData[id] = (coin.usd!, coin.usd24HourChange ?? 0)
            }
        }

        var stockData: [String: (price: Double, change: Double)] = [:]
        if !stockSymbols.isEmpty {
            stockData = await withTaskGroup(of: (String, (Double, Double)?).self) { group in
                for sym in stockSymbols {
                    group.addTask {
                        guard let q = await fetchYahooChart(symbol: sym, range: "5d", interval: "1d") else { return (sym, nil) }
                        let prev = q.prevClose ?? q.closes.first ?? q.price
                        let change = prev > 0 ? (q.price - prev) / prev * 100 : 0
                        return (sym, (q.price, change))
                    }
                }
                var result: [String: (price: Double, change: Double)] = [:]
                for await (sym, value) in group { if let value { result[sym] = (value.0, value.1) } }
                return result
            }
        }

        var rows: [WidgetComparisonRow] = []
        for item in order {
            let label = item.kind == "crypto" ? symbol(forCoinID: item.id) : item.id
            let datum = item.kind == "crypto" ? cryptoData[item.id] : stockData[item.id]
            guard let datum else {
                rows.append(WidgetComparisonRow(label: label, cells: [WidgetComparisonCell(text: "—", tone: .off), WidgetComparisonCell(text: "—", tone: .off)]))
                continue
            }
            let digits = datum.price < 100 ? 2 : 0
            let priceStr = currencyFormatter(maximumFractionDigits: digits).string(from: NSNumber(value: datum.price)) ?? "$\(datum.price)"
            let changeStr = percentChangeFormatter().string(from: NSNumber(value: datum.change / 100)) ?? "\(datum.change)%"
            rows.append(WidgetComparisonRow(label: label, cells: [
                WidgetComparisonCell(text: priceStr, tone: .neutral),
                WidgetComparisonCell(text: changeStr, tone: datum.change >= 0 ? .good : .bad)
            ]))
        }
        guard rows.contains(where: { $0.cells.first?.text != "—" }) else { return nil }
        return MessageWidget(
            kind: .comparison, title: "Watchlist", freshness: .fresh,
            time: shortCurrentTimeString(), followUp: "What moved most?", note: nil,
            chart: nil, metric: nil,
            comparison: WidgetComparison(subtitle: "\(rows.count) assets · 24h", columns: ["Price", "24h"], rows: rows),
            newsBrief: nil
        )
    }

    /// A real historical price chart over `days` (CoinGecko `market_chart`,
    /// auth-free). `days` is "7"/"30"/"90"/"180"/"365"/"max". Powers chart-
    /// timeframe follow-ups in a price tracker thread ("show me the 1y chart").
    static func cryptoHistoryChartWidget(coinID: String, symbol: String, days: String, label: String) async -> MessageWidget? {
        let id = coinID.lowercased()
        guard let url = URL(string: "https://api.coingecko.com/api/v3/coins/\(id)/market_chart?vs_currency=usd&days=\(days)") else {
            return nil
        }
        let decoder = JSONDecoder()
        guard let data = try? await fetchData(from: url),
              let response = try? decoder.decode(CoinGeckoMarketChartResponse.self, from: data) else {
            return nil
        }
        let prices = response.prices.compactMap(\.price)
        guard prices.count >= 2, let first = prices.first, let last = prices.last else { return nil }
        let points = downsample(prices, targetCount: 40)
        let change = first > 0 ? (last - first) / first * 100 : 0
        let valueString = currencyFormatter(maximumFractionDigits: last < 10 ? 2 : 0)
            .string(from: NSNumber(value: last)) ?? "$\(last)"
        let deltaString = percentChangeFormatter().string(from: NSNumber(value: change / 100))
        return MessageWidget(
            kind: .chart,
            title: "\(symbol) · \(label)",
            freshness: .fresh,
            time: shortCurrentTimeString(),
            followUp: nil,
            note: nil,
            chart: WidgetChart(
                label: "\(symbol) / USD",
                value: valueString,
                delta: deltaString,
                trend: change >= 0 ? .up : .down,
                points: points,
                caption: "past \(label)",
                timeframe: label
            ),
            metric: nil,
            comparison: nil,
            newsBrief: nil
        )
    }

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
                followUp: "Track \(symbol) price",
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
            followUp: "Track \(symbol) price",
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
    private struct NewsFeed { let name: String; let label: String; let color: String; let domain: String; let url: String }
    private static let newsFeeds: [NewsFeed] = [
        NewsFeed(name: "BBC", label: "B", color: "#990000", domain: "bbc.com", url: "https://feeds.bbci.co.uk/news/world/rss.xml"),
        NewsFeed(name: "NPR", label: "N", color: "#d7322b", domain: "npr.org", url: "https://feeds.npr.org/1001/rss.xml"),
        NewsFeed(name: "Guardian", label: "G", color: "#052962", domain: "theguardian.com", url: "https://www.theguardian.com/world/rss"),
        NewsFeed(name: "Al Jazeera", label: "A", color: "#fa9000", domain: "aljazeera.com", url: "https://www.aljazeera.com/xml/rss/all.xml"),
    ]

    /// Top headlines pulled from SEVERAL reputable feeds (BBC, NPR, Guardian, Al
    /// Jazeera), interleaved round-robin and de-duped — not a single source.
    static func newsBriefWidget() async -> MessageWidget? {
        let perFeed: [[WidgetNewsStory]] = await withTaskGroup(of: (Int, [WidgetNewsStory]).self) { group in
            for (index, feed) in newsFeeds.enumerated() {
                group.addTask {
                    guard let url = URL(string: feed.url), let data = try? await fetchData(from: url) else { return (index, []) }
                    let items = BBCNewsRSSParser().parse(data: data).prefix(3)
                    let source = WidgetNewsSource(label: feed.label, color: feed.color, domain: feed.domain)
                    return (index, items.map { WidgetNewsStory(title: $0.title, tag: feed.name, sources: [source], url: $0.link) })
                }
            }
            var results = Array(repeating: [WidgetNewsStory](), count: newsFeeds.count)
            for await (index, stories) in group { results[index] = stories }
            return results
        }

        // Round-robin across feeds so the brief mixes sources; de-dupe by title.
        var stories: [WidgetNewsStory] = []
        var seen = Set<String>()
        let rounds = perFeed.map(\.count).max() ?? 0
        outer: for round in 0..<rounds {
            for feed in perFeed where round < feed.count {
                let story = feed[round]
                if seen.insert(story.title.lowercased()).inserted { stories.append(story) }
                if stories.count >= 6 { break outer }
            }
        }
        guard !stories.isEmpty else { return nil }
        let sourceCount = Set(stories.compactMap { $0.sources.first?.domain }).count

        return MessageWidget(
            kind: .newsBrief,
            title: "News brief",
            freshness: .fresh,
            time: shortCurrentTimeString(),
            followUp: "What's the biggest story?",
            note: nil,
            chart: nil,
            metric: nil,
            comparison: nil,
            newsBrief: WidgetNewsBrief(
                heading: "Top stories · \(sourceCount) source\(sourceCount == 1 ? "" : "s")",
                stories: stories
            )
        )
    }

    /// Current conditions + today's high/low for a named place (open-meteo
    /// geocoding + forecast, both auth-free) → metric widget.
    static func weatherWidget(query: String) async -> MessageWidget? {
        let place = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
        let usesFahrenheit = Locale.current.measurementSystem == .us
        let temperatureUnit = usesFahrenheit ? "fahrenheit" : "celsius"
        let temperatureSymbol = usesFahrenheit ? "F" : "C"
        func temperatureLabel(_ value: Double) -> String {
            "\(Int(value.rounded()))°\(temperatureSymbol)"
        }
        guard !place.isEmpty,
              let encoded = place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let geoURL = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=\(languageCode)&format=json") else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            let geo = try decoder.decode(GeocodingResponse.self, from: try await fetchData(from: geoURL))
            guard let match = geo.results?.first else { return nil }

            guard let forecastURL = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(match.latitude)&longitude=\(match.longitude)&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&temperature_unit=\(temperatureUnit)&timezone=auto&forecast_days=1") else {
                return nil
            }
            let forecast = try decoder.decode(WeatherForecastResponse.self, from: try await fetchData(from: forecastURL))
            guard let temperature = forecast.current?.temperature2m else { return nil }

            let condition = weatherDescription(forCode: forecast.current?.weatherCode ?? -1)
            var captionParts = [condition]
            if let high = forecast.daily?.temperatureMax?.first, let low = forecast.daily?.temperatureMin?.first {
                captionParts.append("H \(temperatureLabel(high)) · L \(temperatureLabel(low))")
            }
            let region = [match.admin1, match.country].compactMap { $0 }.first

            return MessageWidget(
                kind: .metric,
                title: match.name ?? place.capitalized,
                freshness: .fresh,
                time: shortCurrentTimeString(),
                followUp: "What should I wear?",
                note: nil,
                chart: nil,
                metric: WidgetMetric(
                    label: region ?? "Weather",
                    value: temperatureLabel(temperature),
                    delta: nil,
                    trend: .flat,
                    caption: captionParts.joined(separator: " · ")
                ),
                comparison: nil,
                newsBrief: nil
            )
        } catch {
            return nil
        }
    }

    /// Human label for a WMO weather-interpretation code.
    static func weatherDescription(forCode code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1, 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55, 56, 57: return "Drizzle"
        case 61, 63, 65, 66, 67: return "Rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm + hail"
        default: return "—"
        }
    }

    /// Current local time for a named place (open-meteo geocoding gives the
    /// IANA timezone; the time itself is computed on-device) → metric widget.
    static func worldTimeWidget(query: String) async -> MessageWidget? {
        let place = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
        guard !place.isEmpty,
              let encoded = place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let geoURL = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=\(languageCode)&format=json") else {
            return nil
        }
        do {
            let geo = try JSONDecoder().decode(GeocodingResponse.self, from: try await fetchData(from: geoURL))
            guard let match = geo.results?.first,
                  let timeZoneID = match.timezone,
                  let timeZone = TimeZone(identifier: timeZoneID) else {
                return nil
            }
            let now = Date()
            let timeFormatter = DateFormatter()
            timeFormatter.timeZone = timeZone
            timeFormatter.dateFormat = "h:mm a"
            let dayFormatter = DateFormatter()
            dayFormatter.timeZone = timeZone
            dayFormatter.dateFormat = "EEEE"

            let offsetHours = Double(timeZone.secondsFromGMT(for: now)) / 3600
            let offsetString = String(format: "GMT%+g", offsetHours)
            let region = [match.admin1, match.country].compactMap { $0 }.first

            return MessageWidget(
                kind: .metric,
                title: match.name ?? place.capitalized,
                freshness: .fresh,
                time: shortCurrentTimeString(),
                followUp: "Schedule something there?",
                note: nil,
                chart: nil,
                metric: WidgetMetric(
                    label: region ?? "Local time",
                    value: timeFormatter.string(from: now),
                    delta: nil,
                    trend: .flat,
                    caption: "\(dayFormatter.string(from: now)) · \(offsetString)"
                ),
                comparison: nil,
                newsBrief: nil
            )
        } catch {
            return nil
        }
    }

    /// Dictionary definition (dictionaryapi.dev, auth-free) → generic widget.
    static func defineWidget(word: String) async -> MessageWidget? {
        let term = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty,
              let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)") else {
            return nil
        }
        do {
            let entries = try JSONDecoder().decode([DictionaryEntry].self, from: try await fetchData(from: url))
            guard let meaning = entries.first?.meanings?.first,
                  let definition = meaning.definitions?.first?.definition, !definition.isEmpty else {
                return nil
            }
            let partOfSpeech = meaning.partOfSpeech.map { "\($0) · " } ?? ""
            return MessageWidget(
                kind: .generic,
                title: word.capitalized,
                freshness: .fresh,
                time: shortCurrentTimeString(),
                followUp: "Use it in a sentence?",
                note: "\(partOfSpeech)\(definition)",
                chart: nil,
                metric: nil,
                comparison: nil,
                newsBrief: nil
            )
        } catch {
            return nil
        }
    }

    /// On-device unit conversion → metric widget (no network).
    static func unitConvertWidget(value: Double, from: String, to: String) async -> MessageWidget? {
        guard let converted = UnitConverter.convert(value: value, from: from, to: to) else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        let valueString = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        let resultString = formatter.string(from: NSNumber(value: converted.result)) ?? "\(converted.result)"
        return MessageWidget(
            kind: .metric,
            title: "\(converted.fromSymbol) → \(converted.toSymbol)",
            freshness: .fresh,
            time: shortCurrentTimeString(),
            followUp: nil,
            note: nil,
            chart: nil,
            metric: WidgetMetric(
                label: "\(valueString) \(converted.fromSymbol)",
                value: "\(resultString) \(converted.toSymbol)",
                delta: nil,
                trend: .flat,
                caption: nil
            ),
            comparison: nil,
            newsBrief: nil
        )
    }

    /// Currency conversion via frankfurter.app (ECB rates, auth-free) → metric.
    static func fxWidget(amount: Double, from: String, to: String) async -> MessageWidget? {
        let amountString = amount.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(amount))
            : String(format: "%.2f", amount)
        guard let url = URL(string: "https://api.frankfurter.app/latest?amount=\(amountString)&from=\(from)&to=\(to)") else {
            return nil
        }
        do {
            let response = try JSONDecoder().decode(FrankfurterResponse.self, from: try await fetchData(from: url))
            guard let converted = response.rates?[to] else { return nil }
            let rate = amount != 0 ? converted / amount : converted

            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            let convertedString = formatter.string(from: NSNumber(value: converted)) ?? String(format: "%.2f", converted)
            formatter.maximumFractionDigits = 4
            let rateString = formatter.string(from: NSNumber(value: rate)) ?? String(format: "%.4f", rate)

            return MessageWidget(
                kind: .metric,
                title: "\(from) → \(to)",
                freshness: .fresh,
                time: shortCurrentTimeString(),
                followUp: "Convert a different amount?",
                note: nil,
                chart: nil,
                metric: WidgetMetric(
                    label: "\(amountString) \(from)",
                    value: "\(convertedString) \(to)",
                    delta: nil,
                    trend: .flat,
                    caption: "1 \(from) = \(rateString) \(to)"
                ),
                comparison: nil,
                newsBrief: nil
            )
        } catch {
            return nil
        }
    }
}
