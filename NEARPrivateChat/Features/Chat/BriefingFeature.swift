/**
 INTEGRATION

 The integrator must wire these points elsewhere:
 1. Own one `BriefingStore` and inject the real `runner` that sends `briefing.prompt` through the chat send path, then uses `MessageWidget.extract` on the answer.
 2. Insert `TodaySection(...)` at the top of `ConversationListView`'s main `LazyVStack` around line 252, gated to the default filter plus empty search.
 3. Register `BGTaskScheduler` and `UNUserNotificationCenter`, and call `store.runDue` on foreground.
 4. Add Info.plist keys: `UIBackgroundModes` with processing/fetch, and `BGTaskSchedulerPermittedIdentifiers`.
 */

import Foundation
import SwiftUI
@preconcurrency import UserNotifications

struct Briefing: Codable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var prompt: String
    var schedule: BriefingSchedule
    var isPaused: Bool
    var createdAt: Date
    var lastRunAt: Date?
    var latestResult: MessageWidget?

    init(
        id: UUID = UUID(),
        title: String,
        prompt: String,
        schedule: BriefingSchedule,
        isPaused: Bool = false,
        createdAt: Date = Date(),
        lastRunAt: Date? = nil,
        latestResult: MessageWidget? = nil
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.schedule = schedule
        self.isPaused = isPaused
        self.createdAt = createdAt
        self.lastRunAt = lastRunAt
        self.latestResult = latestResult
    }

    var status: BriefingStatus {
        if isPaused { return .paused }
        if latestResult != nil { return .live }
        return .scheduled
    }
}

enum BriefingStatus: String, Codable, Hashable {
    case live
    case scheduled
    case paused
}

enum BriefingSchedule: Codable, Hashable {
    case daily(hour: Int, minute: Int)
    case weekdays(hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int)
    case everyNHours(Int)

    private enum Kind: String, Codable {
        case daily
        case weekdays
        case weekly
        case everyNHours
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case weekday
        case hour
        case minute
        case intervalHours
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let hour = (try? container.decode(Int.self, forKey: .hour)) ?? 9
        let minute = (try? container.decode(Int.self, forKey: .minute)) ?? 0
        switch kind {
        case .daily:
            self = .daily(hour: hour, minute: minute)
        case .weekdays:
            self = .weekdays(hour: hour, minute: minute)
        case .weekly:
            self = .weekly(
                weekday: (try? container.decode(Int.self, forKey: .weekday)) ?? 2,
                hour: hour,
                minute: minute
            )
        case .everyNHours:
            self = .everyNHours(max(1, (try? container.decode(Int.self, forKey: .intervalHours)) ?? 6))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .daily(hour, minute):
            try container.encode(Kind.daily, forKey: .kind)
            try container.encode(clampedHour(hour), forKey: .hour)
            try container.encode(clampedMinute(minute), forKey: .minute)
        case let .weekdays(hour, minute):
            try container.encode(Kind.weekdays, forKey: .kind)
            try container.encode(clampedHour(hour), forKey: .hour)
            try container.encode(clampedMinute(minute), forKey: .minute)
        case let .weekly(weekday, hour, minute):
            try container.encode(Kind.weekly, forKey: .kind)
            try container.encode(clampedWeekday(weekday), forKey: .weekday)
            try container.encode(clampedHour(hour), forKey: .hour)
            try container.encode(clampedMinute(minute), forKey: .minute)
        case let .everyNHours(interval):
            try container.encode(Kind.everyNHours, forKey: .kind)
            try container.encode(max(1, interval), forKey: .intervalHours)
        }
    }

    func nextRun(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case let .daily(hour, minute):
            return nextMatchingDate(after: date, hour: hour, minute: minute, calendar: calendar) { _ in true }
        case let .weekdays(hour, minute):
            return nextMatchingDate(after: date, hour: hour, minute: minute, calendar: calendar) { candidate in
                let weekday = calendar.component(.weekday, from: candidate)
                return (2...6).contains(weekday)
            }
        case let .weekly(weekday, hour, minute):
            let targetWeekday = clampedWeekday(weekday)
            return nextMatchingDate(after: date, hour: hour, minute: minute, calendar: calendar) { candidate in
                calendar.component(.weekday, from: candidate) == targetWeekday
            }
        case let .everyNHours(interval):
            guard interval > 0 else { return nil }
            return calendar.date(byAdding: .hour, value: interval, to: date)
        }
    }

    var scheduleLabel: String {
        switch self {
        case let .daily(hour, minute):
            return "Daily · \(Self.timeLabel(hour: hour, minute: minute))"
        case let .weekdays(hour, minute):
            return "Weekdays · \(Self.timeLabel(hour: hour, minute: minute))"
        case let .weekly(weekday, hour, minute):
            return "\(Self.weekdayLabel(weekday)) · \(Self.timeLabel(hour: hour, minute: minute))"
        case let .everyNHours(interval):
            return "Every \(max(1, interval))h"
        }
    }

    var timeComponents: (hour: Int, minute: Int)? {
        switch self {
        case let .daily(hour, minute),
             let .weekdays(hour, minute),
             let .weekly(_, hour, minute):
            return (clampedHour(hour), clampedMinute(minute))
        case .everyNHours:
            return nil
        }
    }

    var frequency: BriefingScheduleFrequency {
        switch self {
        case .daily: return .daily
        case .weekdays: return .weekdays
        case .weekly: return .weekly
        case .everyNHours: return .everyNHours
        }
    }

    private func nextMatchingDate(
        after date: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar,
        matches: (Date) -> Bool
    ) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = clampedHour(hour)
        components.minute = clampedMinute(minute)
        components.second = 0

        guard let startOfCandidateDay = calendar.date(from: components) else {
            return nil
        }

        for dayOffset in 0...14 {
            guard let candidate = calendar.date(byAdding: .day, value: dayOffset, to: startOfCandidateDay) else {
                continue
            }
            if candidate > date, matches(candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func timeLabel(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.hour = clampedHour(hour)
        components.minute = clampedMinute(minute)
        let date = Calendar.current.date(from: components) ?? Date()
        return briefingTimeFormatter.string(from: date)
    }

    private static func weekdayLabel(_ weekday: Int) -> String {
        let labels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return labels[clampedWeekday(weekday) - 1]
    }
}

enum BriefingScheduleFrequency: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekdays = "Weekdays"
    case weekly = "Weekly"
    case everyNHours = "Every N hours"

    var id: String { rawValue }
}

@MainActor
final class BriefingStore: ObservableObject {
    @Published private(set) var briefings: [Briefing]
    var runner: (Briefing) async -> MessageWidget?

    private let fileURL: URL

    init(
        briefings: [Briefing] = [],
        fileURL: URL? = nil,
        runner: @escaping (Briefing) async -> MessageWidget? = { briefing in
            BriefingSamples.sampleWidget(title: briefing.title)
        }
    ) {
        self.briefings = briefings
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.runner = runner
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
    }

    func update(_ briefing: Briefing) {
        guard let index = briefings.firstIndex(where: { $0.id == briefing.id }) else {
            add(briefing)
            return
        }
        briefings[index] = briefing
        briefings.sort(by: briefingSort)
        save()
    }

    func remove(_ briefing: Briefing) {
        briefings.removeAll { $0.id == briefing.id }
        save()
    }

    func setPaused(_ briefing: Briefing, _ isPaused: Bool) {
        guard let index = briefings.firstIndex(where: { $0.id == briefing.id }) else { return }
        briefings[index].isPaused = isPaused
        save()
    }

    func run(_ briefing: Briefing) async {
        guard let snapshot = briefings.first(where: { $0.id == briefing.id }) else { return }
        let result = await runner(snapshot)
        // Re-resolve after the await; the list may have changed during the call.
        guard let index = briefings.firstIndex(where: { $0.id == briefing.id }) else { return }
        // On failure (e.g. signed out), leave lastRunAt untouched so the briefing
        // stays due and retries, rather than silently skipping its next run.
        guard let result else { return }
        briefings[index].latestResult = result
        briefings[index].lastRunAt = Date()
        save()
        Self.postBriefingReadyNotification(title: briefings[index].title)
    }

    /// Requested contextually when the user creates their first briefing.
    nonisolated static func requestNotificationAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// Posts when a briefing produces a fresh result. iOS suppresses foreground
    /// banners by default, so app-open runs don't spam; background runs surface.
    nonisolated static func postBriefingReadyNotification(title: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = "Your briefing is ready."
            center.add(UNNotificationRequest(identifier: "briefing-\(UUID().uuidString)", content: content, trigger: nil))
        }
    }

    func runDue(now: Date = Date()) async {
        let dueIDs = Set(dueBriefings(now: now).map(\.id))
        for briefing in briefings where dueIDs.contains(briefing.id) {
            await run(briefing)
        }
    }

    func dueBriefings(now: Date = Date()) -> [Briefing] {
        briefings.filter { briefing in
            guard !briefing.isPaused else { return false }
            let baseline = briefing.lastRunAt ?? briefing.createdAt
            guard let nextRun = briefing.schedule.nextRun(after: baseline) else { return false }
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
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("NEARPrivateChat", isDirectory: true)
            .appendingPathComponent("briefings.json")
    }
}

struct TodaySection: View {
    @ObservedObject var store: BriefingStore
    var onOpenBriefing: (Briefing) -> Void
    var onNewBriefing: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if store.briefings.isEmpty {
                TodayEmptyState(onNewBriefing: onNewBriefing)
            } else {
                let liveBriefings = store.briefings.filter { $0.latestResult != nil }
                if !liveBriefings.isEmpty {
                    labeledSection("Live")
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(liveBriefings) { briefing in
                            BriefingTile(briefing: briefing) {
                                onOpenBriefing(briefing)
                            }
                        }
                    }
                }

                labeledSection("Scheduled")
                    .padding(.top, liveBriefings.isEmpty ? 0 : 2)
                VStack(spacing: 0) {
                    ForEach(store.briefings) { briefing in
                        ScheduleRow(briefing: briefing) {
                            onOpenBriefing(briefing)
                        }
                        if briefing.id != store.briefings.last?.id {
                            Divider()
                                .overlay(Color.appHairline)
                                .padding(.leading, 52)
                        }
                    }
                }
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Today")
                    .font(.title3.weight(.semibold))
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 12)
            Button(action: onNewBriefing) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appPanelBackground)
                    .frame(width: 32, height: 32)
                    .background(Color.actionPrimary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New briefing")
        }
    }

    private func labeledSection(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(Color.textSecondary)
    }
}

struct BriefingTile: View {
    let briefing: Briefing
    var action: () -> Void = {}

    private var widget: MessageWidget? { briefing.latestResult }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    BriefingIconChip(briefing: briefing, widget: widget)
                    Spacer(minLength: 8)
                    if widget != nil {
                        Circle()
                            .fill(Color.actionPrimary)
                            .frame(width: 7, height: 7)
                            .padding(.top, 2)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(briefing.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    tileBody
                }

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(footerText)
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(deliveredTime)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tileBody: some View {
        switch widget?.kind {
        case .metric:
            if let metric = widget?.metric {
                VStack(alignment: .leading, spacing: 3) {
                    Text(metric.value)
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let delta = metric.delta {
                        Text(delta)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(trendColor(metric.trend))
                            .lineLimit(1)
                    }
                }
            }
        case .chart:
            VStack(alignment: .leading, spacing: 3) {
                Text(widget?.chart?.value ?? widget?.chart?.label ?? "Updated")
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let delta = widget?.chart?.delta {
                    Text(delta)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(trendColor(widget?.chart?.trend))
                        .lineLimit(1)
                }
            }
        case .comparison:
            Text(widget?.comparison?.subtitle ?? widget?.note ?? "Comparison ready")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        case .newsBrief:
            Text(widget?.newsBrief?.stories.first?.title ?? widget?.newsBrief?.heading ?? "News brief ready")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        case .generic, .none:
            Text(widget?.note ?? "No result yet")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footerText: String {
        guard let widget else { return "Scheduled" }
        switch widget.kind {
        case .newsBrief:
            let stories = widget.newsBrief?.stories.count ?? 0
            let sources = widget.newsBrief?.stories.reduce(0) { $0 + $1.sources.count } ?? 0
            if stories > 0, sources > 0 { return "\(stories) stories · \(sources) sources" }
            if stories > 0 { return "\(stories) stories" }
            return "News brief"
        case .comparison:
            let rows = widget.comparison?.rows.count ?? 0
            return rows == 1 ? "1 row" : "\(rows) rows"
        case .chart:
            return widget.chart?.timeframe ?? widget.chart?.caption ?? "Chart"
        case .metric:
            return widget.metric?.caption ?? widget.metric?.label ?? "Metric"
        case .generic:
            return "Brief"
        }
    }

    private var deliveredTime: String {
        if let time = widget?.time, !time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return time
        }
        if let lastRunAt = briefing.lastRunAt {
            return briefingTimeFormatter.string(from: lastRunAt)
        }
        return "pending"
    }

    private func trendColor(_ trend: WidgetTrend?) -> Color {
        switch trend {
        case .up: return Color.proofVerified
        case .down: return Color.proofMismatch
        case .flat, .none: return Color.textSecondary
        }
    }
}

struct ScheduleRow: View {
    let briefing: Briefing
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                BriefingIconChip(briefing: briefing, widget: briefing.latestResult)

                VStack(alignment: .leading, spacing: 3) {
                    Text(briefing.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(briefing.schedule.scheduleLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .opacity(briefing.isPaused ? 0.48 : 1)
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        if briefing.isPaused { return "paused" }
        guard let next = briefing.schedule.nextRun(after: briefing.lastRunAt ?? Date()) else {
            return "not scheduled"
        }
        return "next run \(relativeNextRun(next))"
    }
}

struct BriefingEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let existingBriefing: Briefing?
    private let onSave: (Briefing) -> Void
    private let onDelete: ((Briefing) -> Void)?

    @State private var title: String
    @State private var prompt: String
    @State private var frequency: BriefingScheduleFrequency
    @State private var time: Date
    @State private var weekday: Int
    @State private var intervalHours: Int
    @State private var isPaused: Bool

    init(
        briefing: Briefing? = nil,
        onSave: @escaping (Briefing) -> Void = { _ in },
        onDelete: ((Briefing) -> Void)? = nil
    ) {
        self.existingBriefing = briefing
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: briefing?.title ?? "")
        _prompt = State(initialValue: briefing?.prompt ?? "")
        _frequency = State(initialValue: briefing?.schedule.frequency ?? .weekdays)
        _time = State(initialValue: Self.dateForTime(briefing?.schedule.timeComponents ?? (8, 0)))
        _weekday = State(initialValue: Self.weekday(from: briefing?.schedule) ?? 2)
        _intervalHours = State(initialValue: Self.interval(from: briefing?.schedule) ?? 6)
        _isPaused = State(initialValue: briefing?.isPaused ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Briefing") {
                    TextField("Title", text: $title)
                    TextField("Prompt", text: $prompt, axis: .vertical)
                        .lineLimit(4...8)
                }

                Section("Schedule") {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(BriefingScheduleFrequency.allCases) { frequency in
                            Text(frequency.rawValue).tag(frequency)
                        }
                    }

                    if frequency == .weekly {
                        Picker("Day", selection: $weekday) {
                            ForEach(1...7, id: \.self) { value in
                                Text(weekdayName(value)).tag(value)
                            }
                        }
                    }

                    if frequency == .everyNHours {
                        Stepper("Every \(intervalHours) hours", value: $intervalHours, in: 1...24)
                    } else {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    }

                    Toggle("Paused", isOn: $isPaused)
                        .tint(Color.actionPrimary)
                }

                if let existingBriefing, onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            onDelete?(existingBriefing)
                            dismiss()
                        } label: {
                            Text("Delete Briefing")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle(existingBriefing == nil ? "New Briefing" : "Edit Briefing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(makeBriefing())
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func makeBriefing() -> Briefing {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hour = components.hour ?? 8
        let minute = components.minute ?? 0
        return Briefing(
            id: existingBriefing?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            schedule: makeSchedule(hour: hour, minute: minute),
            isPaused: isPaused,
            createdAt: existingBriefing?.createdAt ?? Date(),
            lastRunAt: existingBriefing?.lastRunAt,
            latestResult: existingBriefing?.latestResult
        )
    }

    private func makeSchedule(hour: Int, minute: Int) -> BriefingSchedule {
        switch frequency {
        case .daily:
            return .daily(hour: hour, minute: minute)
        case .weekdays:
            return .weekdays(hour: hour, minute: minute)
        case .weekly:
            return .weekly(weekday: weekday, hour: hour, minute: minute)
        case .everyNHours:
            return .everyNHours(intervalHours)
        }
    }

    private func weekdayName(_ value: Int) -> String {
        let labels = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return labels[clampedWeekday(value) - 1]
    }

    private static func dateForTime(_ time: (hour: Int, minute: Int)) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = clampedHour(time.hour)
        components.minute = clampedMinute(time.minute)
        return Calendar.current.date(from: components) ?? Date()
    }

    private static func weekday(from schedule: BriefingSchedule?) -> Int? {
        if case let .weekly(weekday, _, _) = schedule {
            return weekday
        }
        return nil
    }

    private static func interval(from schedule: BriefingSchedule?) -> Int? {
        if case let .everyNHours(interval) = schedule {
            return interval
        }
        return nil
    }
}

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
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        BriefingIconChip(briefing: currentBriefing, widget: currentBriefing.latestResult)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(currentBriefing.title)
                                .font(.title3.weight(.semibold))
                            Text(currentBriefing.schedule.scheduleLabel)
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }

                    Text(lastRunText)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(14)
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 1)
                }

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
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(isRunning ? "Running" : "Run now")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Color.appPanelBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.actionPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isRunning)

                if let widget = currentBriefing.latestResult {
                    MessageWidgetCard(widget: widget, onFollowUp: onFollowUp)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No result yet")
                            .font(.headline)
                        Text("Run this briefing to generate its first Today card.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.appBorder, lineWidth: 1)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.appBackground)
        .navigationTitle("Briefing")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lastRunText: String {
        guard let lastRunAt = currentBriefing.lastRunAt else {
            return "Last run: never"
        }
        return "Last run: \(lastRunAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct TodayEmptyState: View {
    var onNewBriefing: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BriefingIconChip(symbolName: "calendar.badge.plus", tint: Color.actionPrimary)
            Text("No briefings yet")
                .font(.headline)
            Text("Create a recurring prompt and its latest result will appear here.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onNewBriefing) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("New briefing")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Color.appPanelBackground)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.actionPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }
}

private struct BriefingIconChip: View {
    let symbolName: String
    let tint: Color

    init(briefing: Briefing, widget: MessageWidget?) {
        let palette = Self.palette(for: briefing.id)
        self.symbolName = Self.symbolName(for: widget?.kind)
        self.tint = briefing.isPaused ? Color.textSecondary : palette
    }

    init(symbolName: String, tint: Color) {
        self.symbolName = symbolName
        self.tint = tint
    }

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            }
    }

    private static func symbolName(for kind: WidgetKind?) -> String {
        switch kind {
        case .chart: return "chart.xyaxis.line"
        case .metric: return "number"
        case .comparison: return "tablecells"
        case .newsBrief: return "newspaper"
        case .generic, .none: return "sparkles"
        }
    }

    private static func palette(for id: UUID) -> Color {
        let colors: [Color] = [
            Color.actionPrimary,
            Color.brandBlue,
            Color.proofVerified,
            Color.proofStale,
            Color.proofMismatch,
            Color.textSecondary
        ]
        let index = abs(id.uuidString.hashValue) % colors.count
        return colors[index]
    }
}

private enum BriefingSamples {
    @MainActor
    static let store = BriefingStore(briefings: sampleBriefings)

    static let sampleBriefings: [Briefing] = [
        Briefing(
            title: "Daily news brief",
            prompt: "Give me a concise private daily news brief.",
            schedule: .weekdays(hour: 8, minute: 0),
            createdAt: Date().addingTimeInterval(-86_400 * 5),
            lastRunAt: Date().addingTimeInterval(-2_100),
            latestResult: MessageWidget(
                kind: .newsBrief,
                title: "Daily news brief",
                freshness: .fresh,
                time: "8:02am",
                followUp: "Open the lead story",
                newsBrief: WidgetNewsBrief(
                    heading: "Today · 3 stories",
                    stories: [
                        WidgetNewsStory(
                            title: "Markets steady as chip guidance offsets rate worries",
                            tag: "Markets",
                            sources: [
                                WidgetNewsSource(label: "R", color: nil, domain: "reuters.com"),
                                WidgetNewsSource(label: "B", color: nil, domain: "bloomberg.com")
                            ],
                            url: nil
                        ),
                        WidgetNewsStory(
                            title: "New private AI deployment rules move through committee",
                            tag: "Policy",
                            sources: [WidgetNewsSource(label: "A", color: nil, domain: "apnews.com")],
                            url: nil
                        ),
                        WidgetNewsStory(
                            title: "Energy grid battery installs reach a quarterly high",
                            tag: "Energy",
                            sources: [
                                WidgetNewsSource(label: "F", color: nil, domain: "ft.com"),
                                WidgetNewsSource(label: "V", color: nil, domain: "verge.com"),
                                WidgetNewsSource(label: "N", color: nil, domain: "nature.com")
                            ],
                            url: nil
                        )
                    ]
                )
            )
        ),
        Briefing(
            title: "Weekly market summary",
            prompt: "Summarize the week in public markets with key risk signals.",
            schedule: .weekly(weekday: 2, hour: 7, minute: 0),
            createdAt: Date().addingTimeInterval(-86_400 * 14),
            lastRunAt: Date().addingTimeInterval(-7_200),
            latestResult: MessageWidget(
                kind: .metric,
                title: "Weekly market summary",
                freshness: .fresh,
                time: "7:03am",
                followUp: "Explain the move",
                metric: WidgetMetric(
                    label: "S&P 500 weekly move",
                    value: "+1.8%",
                    delta: "+0.6% vs prior week",
                    trend: .up,
                    caption: "Breadth improved across 8 of 11 sectors."
                )
            )
        ),
        Briefing(
            title: "Crypto liquidity watch",
            prompt: "Check BTC and ETH liquidity, volatility, and risk levels.",
            schedule: .daily(hour: 21, minute: 0),
            isPaused: true,
            createdAt: Date().addingTimeInterval(-86_400 * 20),
            lastRunAt: Date().addingTimeInterval(-86_400 * 2),
            latestResult: MessageWidget(
                kind: .chart,
                title: "Crypto liquidity watch",
                freshness: .stale,
                time: "9:01pm",
                chart: WidgetChart(
                    label: "BTC / USD",
                    value: "$68,420",
                    delta: "-1.2%",
                    trend: .down,
                    points: [52, 55, 54, 59, 57, 56, 53],
                    caption: "Spot depth thinned after the US close.",
                    timeframe: "past 24h"
                )
            )
        )
    ]

    static func sampleWidget(title: String) -> MessageWidget {
        MessageWidget(
            kind: .generic,
            title: title,
            freshness: .fresh,
            time: briefingTimeFormatter.string(from: Date()),
            followUp: "Tell me more",
            note: "Sample briefing result generated locally. Wire a real runner to replace this with a private chat answer."
        )
    }
}

private extension JSONEncoder {
    static var briefing: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var briefing: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private func briefingSort(_ lhs: Briefing, _ rhs: Briefing) -> Bool {
    if lhs.isPaused != rhs.isPaused { return !lhs.isPaused }
    let now = Date()
    let lhsNext = lhs.schedule.nextRun(after: lhs.lastRunAt ?? now) ?? .distantFuture
    let rhsNext = rhs.schedule.nextRun(after: rhs.lastRunAt ?? now) ?? .distantFuture
    if lhsNext != rhsNext { return lhsNext < rhsNext }
    return lhs.createdAt > rhs.createdAt
}

private func relativeNextRun(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
}

private var briefingTimeFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateFormat = "h:mma"
    return formatter
}

private func clampedHour(_ hour: Int) -> Int {
    min(max(hour, 0), 23)
}

private func clampedMinute(_ minute: Int) -> Int {
    min(max(minute, 0), 59)
}

private func clampedWeekday(_ weekday: Int) -> Int {
    min(max(weekday, 1), 7)
}

#Preview("Today Section") {
    ScrollView {
        TodaySection(
            store: BriefingSamples.store,
            onOpenBriefing: { _ in },
            onNewBriefing: {}
        )
    }
    .background(Color.appBackground)
}

#Preview("Briefing Editor") {
    BriefingEditorSheet(
        briefing: BriefingSamples.sampleBriefings.first,
        onSave: { _ in },
        onDelete: { _ in }
    )
}
