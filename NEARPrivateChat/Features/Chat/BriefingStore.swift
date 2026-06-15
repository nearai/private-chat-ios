import Foundation
import SwiftUI
@preconcurrency import UserNotifications

@MainActor
final class BriefingStore: ObservableObject {
    @Published private(set) var briefings: [Briefing]
    /// Briefings with a run in flight (manual or scheduled), so every surface —
    /// the Home card, the detail screen, the thread — can show a loading state
    /// instead of the stale "ready"/"no delivery yet" copy while it runs.
    @Published private(set) var runningBriefingIDs: Set<UUID> = []

    func isRunning(_ id: UUID) -> Bool { runningBriefingIDs.contains(id) }
    var runner: (Briefing) async -> BriefingRunOutcome

    private nonisolated static let notificationAuthorizationGateKey = "briefingNotificationAuthorizationRequestsEnabled"

    private let fileURL: URL

    init(
        briefings: [Briefing] = [],
        fileURL: URL? = nil,
        runner: @escaping (Briefing) async -> BriefingRunOutcome = { briefing in
            .delivered(BriefingSamples.sampleWidget(title: briefing.title))
        }
    ) {
        self.briefings = briefings
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.runner = runner
    }

    func setNotificationAuthorizationRequestsEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.notificationAuthorizationGateKey)
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.briefing.decode([Briefing].self, from: data) else {
            return
        }
        briefings = decoded.sorted(by: briefingSort)
    }

    func add(_ briefing: Briefing) {
        briefings.append(briefing)
        briefings.sort(by: briefingSort)
        save()
        Self.requestNotificationAuthorizationIfNeeded()
        Self.scheduleReminderNotifications(for: briefing)
    }

    func update(_ briefing: Briefing) {
        guard let index = briefings.firstIndex(where: { $0.id == briefing.id }) else {
            add(briefing)
            return
        }
        briefings[index] = briefing
        briefings.sort(by: briefingSort)
        save()
        Self.scheduleReminderNotifications(for: briefing)
    }

    func remove(_ briefing: Briefing) {
        briefings.removeAll { $0.id == briefing.id }
        save()
        Self.cancelReminderNotifications(for: briefing.id)
    }

    func setPaused(_ briefing: Briefing, _ isPaused: Bool) {
        guard let index = briefings.firstIndex(where: { $0.id == briefing.id }) else { return }
        briefings[index].isPaused = isPaused
        briefings.sort(by: briefingSort) // muted trackers drop down the list
        save()
        if let updated = briefings.first(where: { $0.id == briefing.id }) {
            Self.scheduleReminderNotifications(for: updated)
        }
    }

    /// Agent-inbox steering: pin a tracker to the top of Next actions.
    func setPinned(_ briefing: Briefing, _ isPinned: Bool) {
        guard let index = briefings.firstIndex(where: { $0.id == briefing.id }) else { return }
        briefings[index].isPinned = isPinned
        briefings.sort(by: briefingSort)
        save()
    }

    /// Agent-inbox steering: skip scheduled runs for `days` days, then resume.
    func snooze(_ briefing: Briefing, days: Int = 1) {
        guard let index = briefings.firstIndex(where: { $0.id == briefing.id }) else { return }
        briefings[index].snoozedUntil = Calendar.current.date(byAdding: .day, value: max(1, days), to: Date())
        save()
        // Cancel any pending local notifications so a snoozed tracker stays quiet.
        Self.cancelReminderNotifications(for: briefing.id)
    }

    /// End a snooze early.
    func unsnooze(_ briefing: Briefing) {
        guard let index = briefings.firstIndex(where: { $0.id == briefing.id }) else { return }
        briefings[index].snoozedUntil = nil
        save()
        Self.scheduleReminderNotifications(for: briefings[index])
    }

    /// Exponential retry backoff after consecutive failed runs: 15m, 30m, 1h,
    /// 2h, 4h, capped at 6h. Keeps a broken route from being hammered on every
    /// app foreground while still retrying on its own.
    static func retryBackoff(afterConsecutiveFailures count: Int) -> TimeInterval {
        let base: TimeInterval = 15 * 60
        let capped = min(max(count, 1), 6)
        return min(base * pow(2, Double(capped - 1)), 6 * 3600)
    }

    func run(_ briefing: Briefing, now: Date = Date()) async {
        guard let snapshot = briefings.first(where: { $0.id == briefing.id }) else { return }
        runningBriefingIDs.insert(briefing.id)
        defer { runningBriefingIDs.remove(briefing.id) }
        let outcome = await runner(snapshot)
        // Re-resolve after the await; the list may have changed during the call.
        guard let index = briefings.firstIndex(where: { $0.id == briefing.id }) else { return }
        let result: MessageWidget
        switch outcome {
        case .quiet:
            // A clean check with nothing to deliver (e.g. a threshold alert that
            // didn't fire). Not a failure: keep the last delivery, clear any
            // stale failure record, and leave lastRunAt untouched so the
            // briefing stays due on its normal cadence.
            briefings[index].lastFailureAt = nil
            briefings[index].lastFailureMessage = nil
            briefings[index].consecutiveFailureCount = 0
            briefings[index].nextRetryAt = nil
            save()
            return
        case let .failed(message):
            // On failure (e.g. signed out), leave lastRunAt untouched so the
            // briefing stays due — but gate the retry behind exponential
            // backoff instead of refiring on every foreground.
            let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            briefings[index].latestResult = nil
            briefings[index].lastFailureAt = now
            briefings[index].lastFailureMessage = trimmed.isEmpty ? "Run failed before producing a result." : trimmed
            briefings[index].consecutiveFailureCount += 1
            briefings[index].nextRetryAt = now.addingTimeInterval(
                Self.retryBackoff(afterConsecutiveFailures: briefings[index].consecutiveFailureCount)
            )
            save()
            return
        case let .delivered(widget):
            result = widget
        }
        // Accumulate a numeric value from this run, then — once there are ≥2
        // points — surface the trend over time as a chart ("watch chart"). Runs
        // that yield no number just deliver the result as-is.
        var delivered = result
        // Only for open-ended (customPrompt) trackers — live-data kinds already
        // return purpose-built widgets (e.g. crypto's 24h sparkline) we shouldn't
        // overwrite with a few run-points.
        if briefings[index].kind == .customPrompt,
           let display = TrackerHistory.sampleDisplay(from: result),
           let value = TrackerHistory.numericValue(from: display) {
            briefings[index].history.append(TrackerSample(date: Date(), value: value, display: display))
            if briefings[index].history.count > TrackerHistory.maxSamples {
                briefings[index].history.removeFirst(briefings[index].history.count - TrackerHistory.maxSamples)
            }
            if let chart = TrackerHistory.chartWidget(title: briefings[index].title, history: briefings[index].history) {
                delivered = chart
            }
        }
        briefings[index].latestResult = delivered
        briefings[index].lastRunAt = now
        briefings[index].lastFailureAt = nil
        briefings[index].lastFailureMessage = nil
        briefings[index].consecutiveFailureCount = 0
        briefings[index].nextRetryAt = nil
        // A conditional alert is one-shot: it only delivers when its threshold is
        // crossed, so once it fires we pause it rather than re-notifying every
        // cycle while the condition still holds. It stays on Today as a record the
        // user can re-enable.
        if briefings[index].isConditional {
            briefings[index].isPaused = true
        }
        save()
        // Signal, not noise: a numeric tracker pings only on its first reading or
        // a meaningful move; quiet checks update Today silently. Non-numeric
        // trackers (news digests, the daily brief) notify each run as before.
        let history = briefings[index].history
        let isNumericTracker = briefings[index].kind == .customPrompt && !history.isEmpty
        let shouldNotify = !isNumericTracker || history.count == 1 || TrackerHistory.significantMove(in: history) != nil
        if shouldNotify {
            Self.postBriefingReadyNotification(
                title: briefings[index].title,
                body: TrackerHistory.notificationBody(history: history, fallback: delivered)
            )
        }
    }

    /// Schedules a one-off personal reminder ("remind me to call mom at 5pm") as
    /// a local notification. Best-effort: requests authorization if undetermined,
    /// then adds the request (the system drops it if access is denied).
    nonisolated static func schedulePersonalReminder(title: String, date: Date, id: String = UUID().uuidString) {
        requestNotificationAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = "Reminder"
        content.body = title
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "reminder-\(id)", content: content, trigger: trigger)
        )
    }

    /// Requested contextually when the user creates their first briefing.
    nonisolated static func requestNotificationAuthorizationIfNeeded() {
        guard UserDefaults.standard.bool(forKey: notificationAuthorizationGateKey) else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// Schedules repeating local notifications at the briefing's time so it
    /// surfaces proactively even when background refresh doesn't fire. Replaces
    /// any previously scheduled reminders for this briefing; paused briefings
    /// just get their reminders cleared.
    /// Deterministic reminder identifiers for a briefing. A fixed upper bound
    /// (≥ any schedule's trigger count, e.g. 5 weekday triggers) lets us clear
    /// them synchronously without an async getPending round-trip.
    private nonisolated static func reminderIdentifiers(for id: UUID) -> [String] {
        (0..<8).map { "briefing-scheduled-\(id.uuidString)-\($0)" }
    }

    nonisolated static func scheduleReminderNotifications(for briefing: Briefing) {
        let center = UNUserNotificationCenter.current()
        // Remove this briefing's existing reminders SYNCHRONOUSLY (deterministic
        // ids) before adding new ones — an async getPending-based cancel could
        // otherwise fire late and delete the reminders we add just below.
        center.removePendingNotificationRequests(withIdentifiers: reminderIdentifiers(for: briefing.id))
        guard !briefing.isPaused else { return }
        // Conditional trackers must NOT pre-schedule guaranteed pings — that would
        // fire even when the threshold isn't met. They notify only on a met run,
        // via postBriefingReadyNotification when runBriefing returns a result.
        guard briefing.condition == nil else { return }
        let triggers = briefing.schedule.notificationTriggers()
        let title = briefing.title
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            for (index, trigger) in triggers.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = "Your scheduled briefing is ready — tap to open."
                content.sound = .default
                let identifier = "briefing-scheduled-\(briefing.id.uuidString)-\(index)"
                center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            }
        }
    }

    nonisolated static func cancelReminderNotifications(for id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: reminderIdentifiers(for: id))
    }

    /// Posts when a briefing produces a fresh result. iOS suppresses foreground
    /// banners by default, so app-open runs don't spam; background runs surface.
    nonisolated static func postBriefingReadyNotification(title: String, body: String = "Your briefing is ready.") {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: "briefing-\(UUID().uuidString)", content: content, trigger: nil))
        }
    }

    private var isRunningDue = false

    func runDue(now: Date = Date()) async {
        // Launch fires this from multiple lifecycle hooks; re-entrancy would
        // double-run every due briefing.
        guard !isRunningDue else { return }
        isRunningDue = true
        defer { isRunningDue = false }
        let dueIDs = Set(dueBriefings(now: now).map(\.id))
        for briefing in briefings where dueIDs.contains(briefing.id) {
            await run(briefing, now: now)
        }
    }

    func dueBriefings(now: Date = Date()) -> [Briefing] {
        briefings.filter { briefing in
            guard !briefing.isPaused else { return false }
            // Snoozed trackers skip runs until the snooze elapses, then resume.
            if let snoozedUntil = briefing.snoozedUntil, snoozedUntil > now { return false }
            // Failed runs retry on an exponential backoff, not every foreground.
            // Manual Run-now calls run() directly and bypasses this gate.
            if let nextRetryAt = briefing.nextRetryAt, nextRetryAt > now { return false }
            let baseline = briefing.lastRunAt ?? briefing.createdAt
            guard let nextRun = briefing.schedule.nextRun(after: baseline, calendar: briefing.scheduleCalendar) else { return false }
            return nextRun <= now
        }
    }

    #if DEBUG
    func seedDemoSamples() {
        briefings = BriefingSamples.sampleBriefings
    }
    #endif

    private func save() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder.briefing.encode(briefings)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            return
        }
        writeWidgetSnapshot()
    }

    /// Mirror the current briefings into the App Group as a flattened snapshot
    /// the widget can decode without compiling any app view code. Best-effort:
    /// failures (e.g. missing entitlement) just leave the widget on its last
    /// snapshot.
    private func writeWidgetSnapshot() {
        #if DEBUG
        // A demo-capture run uses seeded sample trackers; don't let them
        // overwrite the real home-screen widget snapshot.
        if DemoCapture.isEnabled { return }
        #endif
        guard let snapshotURL = BriefingSharedStore.sharedFileURL(BriefingSharedStore.snapshotFileName) else {
            return
        }
        let snapshots = briefings.map { briefing in
            BriefingSnapshot(
                id: briefing.id.uuidString,
                title: briefing.title,
                summary: Self.widgetSummary(for: briefing),
                lastRunAt: briefing.lastRunAt
            )
        }
        do {
            try FileManager.default.createDirectory(
                at: snapshotURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.briefingSnapshot.encode(snapshots)
            try data.write(to: snapshotURL, options: [.atomic])
            BriefingWidgetRefresher.reload()
        } catch {
            return
        }
    }

    /// One-line summary for the widget, derived from the briefing's latest
    /// result. Prefers a concrete metric/chart value, then a news headline,
    /// then the generic note, then a scheduled-state fallback.
    static func widgetSummary(for briefing: Briefing) -> String {
        if briefing.status == .failed {
            return briefing.lastFailureMessage ?? "Last run failed"
        }
        guard let widget = briefing.latestResult else {
            return briefing.isPaused ? "Paused" : "Scheduled — \(briefing.schedule.scheduleLabel)"
        }
        switch widget.kind {
        case .metric:
            if let metric = widget.metric, !metric.value.isEmpty {
                if let delta = metric.delta, !delta.isEmpty { return "\(metric.value) · \(delta)" }
                return metric.value
            }
        case .chart:
            if let value = widget.chart?.value ?? widget.chart?.label, !value.isEmpty {
                if let delta = widget.chart?.delta, !delta.isEmpty { return "\(value) · \(delta)" }
                return value
            }
        case .newsBrief:
            if let headline = widget.newsBrief?.stories.first?.title ?? widget.newsBrief?.heading,
               !headline.isEmpty {
                return headline
            }
        case .comparison:
            if let subtitle = widget.comparison?.subtitle, !subtitle.isEmpty { return subtitle }
        case .actionPlan:
            if let heading = widget.actionPlan?.heading, !heading.isEmpty { return heading }
            if let first = widget.actionPlan?.actions.first?.title, !first.isEmpty { return first }
        case .generic:
            break
        }
        if let note = widget.note, !note.isEmpty { return note }
        return "Updated"
    }

    private static func defaultFileURL() -> URL {
        // Prefer the App Group container so the home-screen widget can read the
        // same briefings file. Fall back to Application Support if the
        // entitlement is unavailable (e.g. a stripped build).
        if let shared = BriefingSharedStore.sharedFileURL(BriefingSharedStore.briefingsFileName) {
            migrateLegacyFileIfNeeded(to: shared)
            return shared
        }
        return legacyFileURL()
    }

    private static func legacyFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(BriefingSharedStore.directoryName, isDirectory: true)
            .appendingPathComponent(BriefingSharedStore.briefingsFileName)
    }

    #if DEBUG
    /// Demo-capture briefings live in their own file so seeded samples (and the
    /// saves their scheduled runs trigger) never leak into the real
    /// `briefings.json` that an interactive/real session loads. Without this,
    /// a screenshot run's sample trackers ("Daily news @ 9am") would reappear
    /// on Today the next time the app opened for real.
    static func demoFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(BriefingSharedStore.directoryName, isDirectory: true)
            .appendingPathComponent("briefings-demo.json")
    }
    #endif

    /// One-time move of a pre-App-Group briefings.json into the shared
    /// container so upgrading users keep their briefings and the widget sees
    /// them. No-op once the shared file exists.
    private static func migrateLegacyFileIfNeeded(to shared: URL) {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: shared.path) else { return }
        let legacy = legacyFileURL()
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        do {
            try fileManager.createDirectory(
                at: shared.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: legacy, to: shared)
        } catch {
            return
        }
    }
}
