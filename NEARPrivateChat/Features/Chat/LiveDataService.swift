import Foundation

// LiveDataService — turns auth-free public APIs into MessageWidgets so the named
// use cases ("what is ETH price", "how is my NEAR account doing", "pull daily
// news") produce real answers through the widget/briefing UX without the chat
// backend. Filled in by a ring-fenced workstream.

enum LiveDataService {
    /// ETH price + 24h sparkline (CoinGecko) → chart widget.
    static func ethPriceWidget() async -> MessageWidget? { nil }

    /// NEAR account balance / holdings (NEAR RPC + FastNEAR) → metric widget.
    static func nearAccountWidget(account: String) async -> MessageWidget? { nil }

    /// Top headlines (public RSS) → news-brief widget.
    static func newsBriefWidget() async -> MessageWidget? { nil }
}
