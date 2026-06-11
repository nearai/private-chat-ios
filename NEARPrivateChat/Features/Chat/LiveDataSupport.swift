import Foundation

extension LiveDataService {
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

    struct CoinGeckoGlobalResponse: Decodable {
        let data: GlobalData

        struct GlobalData: Decodable {
            let totalMarketCap: [String: Double]
            let marketCapChangePercentage24HUsd: Double?
            let marketCapPercentage: [String: Double]

            enum CodingKeys: String, CodingKey {
                case totalMarketCap = "total_market_cap"
                case marketCapChangePercentage24HUsd = "market_cap_change_percentage_24h_usd"
                case marketCapPercentage = "market_cap_percentage"
            }
        }
    }

    struct CoinGeckoTrendingResponse: Decodable {
        let coins: [TrendingWrapper]

        struct TrendingWrapper: Decodable { let item: TrendingCoin }

        struct TrendingCoin: Decodable {
            let name: String
            let symbol: String
            let marketCapRank: Int?

            enum CodingKeys: String, CodingKey {
                case name, symbol
                case marketCapRank = "market_cap_rank"
            }
        }
    }

    struct GeocodingResponse: Decodable {
        let results: [GeocodingPlace]?
    }

    struct GeocodingPlace: Decodable {
        let name: String?
        let latitude: Double
        let longitude: Double
        let country: String?
        let admin1: String?
        let timezone: String?
    }

    struct WeatherForecastResponse: Decodable {
        let current: WeatherCurrent?
        let daily: WeatherDaily?
    }

    struct WeatherCurrent: Decodable {
        let temperature2m: Double?
        let weatherCode: Int?

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
        }
    }

    struct WeatherDaily: Decodable {
        let temperatureMax: [Double]?
        let temperatureMin: [Double]?

        enum CodingKeys: String, CodingKey {
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
        }
    }

    struct FrankfurterResponse: Decodable {
        let amount: Double?
        let base: String?
        let rates: [String: Double]?
    }

    struct DictionaryEntry: Decodable {
        let word: String?
        let meanings: [DictionaryMeaning]?
    }

    struct DictionaryMeaning: Decodable {
        let partOfSpeech: String?
        let definitions: [DictionaryDefinition]?
    }

    struct DictionaryDefinition: Decodable {
        let definition: String?
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
