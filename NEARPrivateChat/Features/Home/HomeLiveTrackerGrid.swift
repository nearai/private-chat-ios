import SwiftUI

struct HomeLiveTrackerCard: View {
    let symbol: String
    let name: String
    let price: String?
    let change: Double?
    let isLoading: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.appSecondaryBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 1)
            )
            .frame(height: 96)
            .overlay(
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center) {
                        Text(symbol)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                        Spacer()
                        if let change {
                            changeBadge(change: change)
                        }
                    }

                    Text(price ?? "—")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .redacted(reason: isLoading ? .placeholder : [])
            )
    }

    @ViewBuilder
    private func changeBadge(change: Double) -> some View {
        let isPositive = change >= 0
        let label = String(format: "%@%.2f%%", isPositive ? "+" : "", change)
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isPositive ? Color.green : Color.red)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(isPositive ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
            )
    }
}

struct HomeLiveTrackerGrid: View {
    private struct CoinEntry: Identifiable {
        let id = UUID()
        let symbol: String
        let name: String
        let coinID: String
    }

    private let coins: [CoinEntry] = [
        CoinEntry(symbol: "NEAR", name: "NEAR Protocol", coinID: "near"),
        CoinEntry(symbol: "ETH",  name: "Ethereum",      coinID: "ethereum"),
        CoinEntry(symbol: "BTC",  name: "Bitcoin",       coinID: "bitcoin"),
        CoinEntry(symbol: "SOL",  name: "Solana",        coinID: "solana"),
    ]

    @State private var prices: [String: (price: String, change: Double)] = [:]
    @State private var isLoading: Bool = true
    @State private var refreshTrigger: Int = 0

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LIVE")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    refreshTrigger += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(coins) { coin in
                    HomeLiveTrackerCard(
                        symbol: coin.symbol,
                        name: coin.name,
                        price: prices[coin.symbol]?.price,
                        change: prices[coin.symbol]?.change,
                        isLoading: isLoading
                    )
                }
            }
        }
        .task { await fetchPrices() }
        .task(id: refreshTrigger) { await fetchPrices() }
    }

    private func fetchPrices() async {
        await MainActor.run { isLoading = prices.isEmpty }
        await withTaskGroup(of: Void.self) { group in
            for coin in coins {
                let coinID = coin.coinID
                let symbol = coin.symbol
                group.addTask {
                    let urlString = "https://api.coingecko.com/api/v3/simple/price?ids=\(coinID)&vs_currencies=usd&include_24hr_change=true"
                    guard let url = URL(string: urlString),
                          let data = try? await URLSession.shared.data(from: url).0,
                          let decoded = try? JSONDecoder().decode([String: [String: Double]].self, from: data),
                          let coinData = decoded[coinID],
                          let price = coinData["usd"],
                          let change = coinData["usd_24h_change"]
                    else { return }
                    let priceStr: String
                    if price < 1 {
                        priceStr = String(format: "$%.4f", price)
                    } else if price < 100 {
                        priceStr = String(format: "$%.2f", price)
                    } else {
                        priceStr = String(format: "$%.0f", price)
                    }
                    await MainActor.run { prices[symbol] = (priceStr, change) }
                }
            }
        }
        await MainActor.run { isLoading = false }
    }
}
