import Foundation

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
    LiveCoin(id: "dogecoin", symbol: "DOGE", keywords: ["dogecoin", "doge"]),
    LiveCoin(id: "binancecoin", symbol: "BNB", keywords: ["binance coin", "binancecoin", "bnb"]),
    LiveCoin(id: "ripple", symbol: "XRP", keywords: ["xrp", "ripple"]),
    LiveCoin(id: "cardano", symbol: "ADA", keywords: ["cardano", "ada"]),
    LiveCoin(id: "avalanche-2", symbol: "AVAX", keywords: ["avalanche", "avax"]),
    LiveCoin(id: "polkadot", symbol: "DOT", keywords: ["polkadot", "dot"]),
    LiveCoin(id: "chainlink", symbol: "LINK", keywords: ["chainlink", "link token"]),
    LiveCoin(id: "litecoin", symbol: "LTC", keywords: ["litecoin", "ltc"]),
    LiveCoin(id: "bitcoin-cash", symbol: "BCH", keywords: ["bitcoin cash", "bch"]),
    LiveCoin(id: "usd-coin", symbol: "USDC", keywords: ["usd coin", "usdc"]),
    LiveCoin(id: "tether", symbol: "USDT", keywords: ["tether", "usdt"])
]

func liveCoin(forID id: String) -> LiveCoin? {
    liveCoins.first { $0.id == id.lowercased() }
}

extension LiveDataService {
    /// Symbol for a CoinGecko id (for cryptoPrice briefings).
    static func symbol(forCoinID id: String) -> String {
        liveCoin(forID: id)?.symbol ?? id.uppercased()
    }
}
