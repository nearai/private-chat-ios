import SwiftUI

struct IronclawAutomationsView: View {
    @EnvironmentObject private var agentStore: AgentStore

    @State private var automations: [IronclawAutomation] = []
    @State private var isLoading = false

    private let api = IronclawAPI()

    var body: some View {
        Group {
            if isLoading && automations.isEmpty {
                ProgressView()
                    .tint(Color(hex: "#0091FD"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if automations.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Automations")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(hex: "#0A0E1A"))
        .task { await load() }
    }

    // MARK: - Subviews

    private var list: some View {
        List(automations) { automation in
            AutomationRow(automation: automation)
                .listRowBackground(Color(hex: "#111827"))
                .listRowSeparatorTint(Color.white.opacity(0.08))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 44))
                .foregroundStyle(Color(hex: "#0091FD").opacity(0.6))
            Text("No automations configured.")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Ask the agent to set up a recurring task.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let settings = agentStore.ironclawSettings
        guard let token = agentStore.loadIronclawAuthToken(), !token.isEmpty else { return }
        automations = await api.fetchAutomations(settings: settings, authToken: token)
    }
}

// MARK: - Automation Row

private struct AutomationRow: View {
    let automation: IronclawAutomation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(automation.statusColor)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(automation.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                if let schedule = automation.schedule ?? automation.trigger, !schedule.isEmpty {
                    Text(schedule)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.55))
                }

                if let lastRun = automation.lastRunAt {
                    Text("Last run \(lastRun.relativeDescription)")
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.38))
                }
            }

            Spacer()

            if let nextRun = automation.nextRunAt {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Next")
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.38))
                    Text(nextRun.relativeDescription)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color(hex: "#0091FD").opacity(0.85))
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Helpers

private extension Date {
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 1; g = 1; b = 1
        }
        self.init(red: r, green: g, blue: b)
    }
}
