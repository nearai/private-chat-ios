import Foundation

/// A tradable commodity/metal the app can price and alert on. `yahooSymbol` is a
/// Yahoo Finance futures symbol (e.g. "GC=F" gold), which resolves on the same
/// `query1.finance.yahoo.com/v8/finance/chart/<symbol>` endpoint the equity path
/// already uses — so commodity conditions reuse the stock-quote evaluation with
/// a "commodity:" coinID prefix, no new live-data plumbing.
struct LiveCommodity: Equatable {
    let label: String       // display name, e.g. "Gold"
    let symbol: String      // display ticker, e.g. "XAU"
    let yahooSymbol: String // Yahoo futures symbol, e.g. "GC=F"
    let keywords: [String]
}

let liveCommodities: [LiveCommodity] = [
    LiveCommodity(label: "Gold", symbol: "XAU", yahooSymbol: "GC=F", keywords: ["gold", "xau"]),
    LiveCommodity(label: "Silver", symbol: "XAG", yahooSymbol: "SI=F", keywords: ["silver", "xag"]),
    LiveCommodity(label: "Platinum", symbol: "XPT", yahooSymbol: "PL=F", keywords: ["platinum", "xpt"]),
    LiveCommodity(label: "Palladium", symbol: "XPD", yahooSymbol: "PA=F", keywords: ["palladium", "xpd"]),
    LiveCommodity(label: "Copper", symbol: "HG", yahooSymbol: "HG=F", keywords: ["copper"]),
    LiveCommodity(label: "Crude Oil", symbol: "WTI", yahooSymbol: "CL=F", keywords: ["wti crude", "wti", "crude oil", "crude", "oil"]),
    LiveCommodity(label: "Brent Crude", symbol: "BRENT", yahooSymbol: "BZ=F", keywords: ["brent crude", "brent"]),
    LiveCommodity(label: "Natural Gas", symbol: "NG", yahooSymbol: "NG=F", keywords: ["natural gas", "natgas", "nat gas"]),
    LiveCommodity(label: "Gasoline", symbol: "RB", yahooSymbol: "RB=F", keywords: ["gasoline", "rbob"]),
    LiveCommodity(label: "Wheat", symbol: "ZW", yahooSymbol: "ZW=F", keywords: ["wheat"]),
    LiveCommodity(label: "Corn", symbol: "ZC", yahooSymbol: "ZC=F", keywords: ["corn"]),
    LiveCommodity(label: "Soybeans", symbol: "ZS", yahooSymbol: "ZS=F", keywords: ["soybeans", "soybean", "soy"]),
    LiveCommodity(label: "Coffee", symbol: "KC", yahooSymbol: "KC=F", keywords: ["coffee"]),
    LiveCommodity(label: "Sugar", symbol: "SB", yahooSymbol: "SB=F", keywords: ["sugar"])
]

extension QuickIntentParser {
    /// Resolves a commodity/metal from free text → its display + Yahoo symbol.
    /// Longest keyword first so "brent crude" beats "crude" and "natural gas"
    /// beats a stray "gas". nil when no commodity keyword is present.
    static func matchedCommodity(in text: String) -> LiveCommodity? {
        let candidates = liveCommodities.flatMap { c in c.keywords.map { (c, $0) } }
            .sorted { $0.1.count > $1.1.count }
        for (commodity, keyword) in candidates where wordPresent(keyword, in: text) {
            return commodity
        }
        return nil
    }
}
