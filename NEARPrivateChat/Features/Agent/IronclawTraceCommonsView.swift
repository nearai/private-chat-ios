import SwiftUI

/// Trace Commons panel — parity with the hosted IronClaw web UI Trace Commons
/// tab. Shows the per-account credit ledger for contributed redacted traces and
/// the manual-review holds the user authorizes before submission.
/// Endpoints: GET /api/webchat/v2/traces/credit, POST .../holds/{id}/authorize.
@MainActor
struct IronclawTraceCommonsView: View {
    @EnvironmentObject private var agentStore: AgentStore
    private let ironclawAPI = IronclawAPI()

    @State private var credits: IronclawTraceCredits?
    @State private var loadState: LoadState = .loading
    @State private var authorizingHoldIDs: Set<String> = []

    private enum LoadState: Equatable {
        case loading
        case failed
        case loaded
    }

    var body: some View {
        List {
            switch loadState {
            case .loading:
                centeredRow { ProgressView() }
            case .failed:
                Section {
                    Text("Could not load Trace Commons credits.")
                        .font(.callout)
                        .foregroundStyle(Color.failedColor)
                        .listRowBackground(Color.appSecondaryBackground)
                }
            case .loaded:
                if let credits, credits.hasActivity {
                    statusSection(credits)
                    submissionsSection(credits)
                    explanationsSection(credits)
                    holdsSection(credits)
                    Section {
                        Text(Self.noteText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.appSecondaryBackground)
                    }
                } else {
                    Section {
                        Text("Not enrolled — ask your agent to onboard with a Trace Commons invite.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.appSecondaryBackground)
                    } footer: {
                        Text(Self.noteText)
                    }
                }
            }
        }
        .navigationTitle("Trace Commons")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Sections

    @ViewBuilder
    private func statusSection(_ credits: IronclawTraceCredits) -> some View {
        Section {
            statRow("Enrollment", value: credits.isEnrolled ? "Enrolled" : "Not enrolled")
            statRow("Pending credit", description: "Earned but not yet finalized",
                    value: Self.formatCredit(credits.pendingCredit))
            statRow("Final credit", description: "Confirmed credit",
                    value: Self.formatCredit(credits.finalCredit))
            statRow("Delayed ledger", description: "Can still change after review",
                    value: Self.formatSignedCredit(credits.delayedCreditDelta))
        } header: {
            Text("Trace Commons credits")
        } footer: {
            Text("Credit earned for contributed redacted traces, scoped to your account.")
        }
    }

    @ViewBuilder
    private func submissionsSection(_ credits: IronclawTraceCredits) -> some View {
        Section {
            statRow("Submissions", value: "\(credits.submissionsSubmitted ?? 0) submitted, "
                    + "\(credits.submissionsAccepted ?? 0) accepted of \(credits.submissionsTotal ?? 0) total")
            statRow("Last submission", value: Self.formatTimestamp(credits.lastSubmissionAt))
            statRow("Last credit sync", description: "Local view as of last sync",
                    value: Self.formatTimestamp(credits.lastCreditSyncAt))
        }
    }

    @ViewBuilder
    private func explanationsSection(_ credits: IronclawTraceCredits) -> some View {
        if !credits.explanations.isEmpty {
            Section("Recent credit explanations") {
                ForEach(Array(credits.explanations.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.appSecondaryBackground)
                }
            }
        }
    }

    @ViewBuilder
    private func holdsSection(_ credits: IronclawTraceCredits) -> some View {
        if !credits.activeHolds.isEmpty {
            Section {
                ForEach(credits.activeHolds) { hold in
                    holdRow(hold)
                }
            } header: {
                Text("Held for review")
            } footer: {
                Text("Held because of higher privacy risk; review and authorize to submit.")
            }
        }
    }

    private func holdRow(_ hold: IronclawTraceHold) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(hold.displayReason)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Text(hold.submissionID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            Button {
                Task { await authorize(hold) }
            } label: {
                if authorizingHoldIDs.contains(hold.submissionID) {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Authorize")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.bordered)
            .tint(Color.brandAccent)
            .disabled(authorizingHoldIDs.contains(hold.submissionID))
        }
        .padding(.vertical, 2)
        .listRowBackground(Color.appSecondaryBackground)
    }

    private func statRow(_ label: String, description: String? = nil, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.primary)
                if let description {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text(value)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .listRowBackground(Color.appSecondaryBackground)
    }

    private func centeredRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Spacer()
            content()
            Spacer()
        }
        .listRowBackground(Color.appSecondaryBackground)
    }

    // MARK: - Actions

    private func load() async {
        if credits == nil { loadState = .loading }
        let token = agentStore.loadIronclawAuthToken() ?? ""
        let result = await ironclawAPI.fetchTraceCredits(
            settings: agentStore.ironclawSettings,
            authToken: token
        )
        // @MainActor view → these @State writes are already main-isolated.
        if let result {
            credits = result
            loadState = .loaded
        } else if credits != nil {
            // Keep the last good view rather than dropping to an error on a
            // transient refresh failure.
            loadState = .loaded
        } else {
            loadState = .failed
        }
    }

    private func authorize(_ hold: IronclawTraceHold) async {
        guard !authorizingHoldIDs.contains(hold.submissionID) else { return }
        authorizingHoldIDs.insert(hold.submissionID)
        let token = agentStore.loadIronclawAuthToken() ?? ""
        let ok = await ironclawAPI.authorizeTraceHold(
            submissionID: hold.submissionID,
            settings: agentStore.ironclawSettings,
            authToken: token
        )
        if ok {
            await load()
        }
        authorizingHoldIDs.remove(hold.submissionID)
    }

    // MARK: - Formatting

    private static let noteText =
        "Local view as of last sync — the authoritative credit ledger is server-side. "
        + "Final credit can change after privacy review, replay/eval, duplicate checks, "
        + "and downstream utility scoring."

    private static func formatCredit(_ value: Double?) -> String {
        String(format: "%.2f", value ?? 0)
    }

    private static func formatSignedCredit(_ value: Double?) -> String {
        let numeric = value ?? 0
        return String(format: "%@%.2f", numeric >= 0 ? "+" : "", numeric)
    }

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoParserNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static func formatTimestamp(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return "never"
        }
        let date = isoParser.date(from: value) ?? isoParserNoFraction.date(from: value)
        guard let date else { return "never" }
        return displayFormatter.string(from: date)
    }
}
