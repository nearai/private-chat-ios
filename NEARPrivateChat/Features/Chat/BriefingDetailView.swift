import SwiftUI

struct BriefingDetailView: View {
    @ObservedObject var store: BriefingStore
    let briefing: Briefing
    var onFollowUp: (String) -> Void = { _ in }

    @State private var isRunning = false

    private var currentBriefing: Briefing {
        store.briefings.first(where: { $0.id == briefing.id }) ?? briefing
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if currentBriefing.status == .failed {
                    failedRunCard
                } else if let widget = currentBriefing.latestResult {
                    MessageWidgetCard(widget: widget, onFollowUp: onFollowUp)
                } else {
                    readyCard
                }

                briefingAboutSection

                scheduleSection

                runButton

                pauseButton
            }
            .padding(16)
        }
        .background(Color.appBackground)
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                briefingNavigationTitle
            }
        }
    }

    private var briefingNavigationTitle: some View {
        VStack(spacing: 1) {
            Text(displayTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .accessibilityIdentifier("briefing.detail.title")
            Text(currentBriefing.schedule.scheduleLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .accessibilityIdentifier("briefing.detail.subtitle")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayTitle), \(currentBriefing.schedule.scheduleLabel)")
    }

    private var failedRunCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.proofStaleText)
                .frame(width: 32, height: 32)
                .background(Color.proofStale.opacity(0.14), in: RoundedRectangle.app(AppRadius.control))

            VStack(alignment: .leading, spacing: 5) {
                Text("The \(scheduledRunTimeText) run didn't start")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(failureDetailText)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.control))
        .overlay {
            RoundedRectangle.app(AppRadius.control)
                .stroke(Color.proofStale.opacity(0.22), lineWidth: 1)
        }
    }

    private var readyCard: some View {
        HStack(alignment: .top, spacing: 12) {
            BriefingIconChip(briefing: currentBriefing, widget: currentBriefing.latestResult)
            VStack(alignment: .leading, spacing: 5) {
                Text(displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(lastRunText)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.control))
        .overlay {
            RoundedRectangle.app(AppRadius.control)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var briefingAboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(Color.textTertiary)
            Text(aboutText)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schedule")
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(Color.textTertiary)

            VStack(spacing: 0) {
                BriefingDetailScheduleRow(symbolName: "calendar", title: "Frequency", value: currentBriefing.schedule.scheduleLabel)
                Divider().overlay(Color.appHairline)
                BriefingDetailScheduleRow(symbolName: "folder", title: "Plan", value: planText)
                Divider().overlay(Color.appHairline)
                BriefingDetailScheduleRow(symbolName: "clock", title: "Last delivered", value: lastDeliveredText)
            }
            .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.control))
            .overlay {
                RoundedRectangle.app(AppRadius.control)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
        }
    }

    private var runButton: some View {
        Button {
            Task {
                isRunning = true
                await store.run(currentBriefing)
                isRunning = false
            }
        } label: {
            HStack(spacing: 8) {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                Text(isRunning ? "Running" : runButtonTitle)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.actionPrimary, in: RoundedRectangle.app(AppRadius.pill))
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .accessibilityLabel(isRunning ? "Running briefing" : "\(runButtonTitle) briefing")
    }

    private var pauseButton: some View {
        Button {
            store.setPaused(currentBriefing, !currentBriefing.isPaused)
        } label: {
            Text(currentBriefing.isPaused ? "Resume briefing" : "Pause briefing")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(currentBriefing.isPaused ? "Resume briefing" : "Pause briefing")
    }

    private var aboutText: String {
        BriefingPresentationText.conciseAboutText(for: currentBriefing)
    }

    private var displayTitle: String {
        BriefingPresentationText.displayTitle(currentBriefing.title)
    }

    private var planText: String {
        if currentBriefing.council { return "Council" }
        if let accountID = currentBriefing.accountID?.nilIfBlank { return accountID }
        switch currentBriefing.kind {
        case .customPrompt:
            return "Private plan"
        case .dailyNews:
            return "News sources"
        case .dailyBrief:
            return "Your trackers"
        case .ethPrice, .cryptoPrice, .stockPrice, .watchlist:
            return "Market data"
        case .nearAccount:
            return "NEAR account"
        }
    }

    private var runButtonTitle: String {
        currentBriefing.lastRunAt == nil &&
            currentBriefing.latestResult == nil &&
            currentBriefing.lastFailureAt == nil
            ? "Run now"
            : "Re-run now"
    }

    private var scheduledRunTimeText: String {
        guard let time = currentBriefing.schedule.timeComponents else { return "scheduled" }
        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute
        guard let date = Calendar.current.date(from: components) else { return "scheduled" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: date).lowercased()
    }

    private var failureDetailText: String {
        let failure = currentBriefing.lastFailureMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if looksLikeSignInFailure(failure) {
            return "The plan wasn't signed in when the brief was due. Re-run now, or check the plan's sign-in to resume the schedule."
        }
        if !failure.isEmpty {
            return failure
        }
        return "The last scheduled run didn't produce a result. Re-run now, or check the plan's route and sign-in."
    }

    private func looksLikeSignInFailure(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("sign-in") ||
            lower.contains("sign in") ||
            lower.contains("signed in") ||
            lower.contains("not signed") ||
            lower.contains("login") ||
            lower.contains("not logged in") ||
            lower.contains("unauthorized") ||
            lower.contains("authorization")
    }

    private var lastRunText: String {
        guard let lastRunAt = currentBriefing.lastRunAt else {
            return "Ready for first run"
        }
        return "Last run: \(lastRunAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private var lastDeliveredText: String {
        guard let lastRunAt = currentBriefing.lastRunAt else {
            return "Never"
        }
        return lastRunAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

private struct BriefingDetailScheduleRow: View {
    let symbolName: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 20)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }
}
