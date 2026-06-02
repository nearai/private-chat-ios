import SwiftUI

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
    @State private var monthDay: Int
    @State private var intervalHours: Int
    @State private var isPaused: Bool
    @State private var kind: BriefingKind
    @State private var accountID: String?
    @State private var council: Bool
    @State private var condition: BriefingCondition?
    @State private var builderInput = ""
    @State private var builderMessages: [BriefingBuilderMessage]
    @State private var builderActionCandidates: [WidgetActionItem]
    @State private var approvedBuilderActionIDs: Set<String>

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
        _monthDay = State(initialValue: Self.monthDay(from: briefing?.schedule) ?? 1)
        _intervalHours = State(initialValue: Self.interval(from: briefing?.schedule) ?? 6)
        _isPaused = State(initialValue: briefing?.isPaused ?? false)
        _kind = State(initialValue: briefing?.kind ?? .customPrompt)
        _accountID = State(initialValue: briefing?.accountID)
        _council = State(initialValue: briefing?.council ?? false)
        _condition = State(initialValue: briefing?.condition)
        _builderMessages = State(initialValue: [
            BriefingBuilderMessage(role: .assistant, text: "What should I turn into an action, automation, reminder, or calendar follow-up?")
        ])
        _builderActionCandidates = State(initialValue: [])
        _approvedBuilderActionIDs = State(initialValue: [])
    }

    var body: some View {
        NavigationStack {
            Group {
                if existingBriefing == nil {
                    briefingBuilder
                } else {
                    briefingForm
                }
            }
            .navigationTitle(existingBriefing == nil ? "New Workflow" : "Edit Workflow")
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

    private var briefingForm: some View {
        Form {
            Section("Workflow") {
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

                if frequency == .weekly || frequency == .biweekly {
                    Picker("Day", selection: $weekday) {
                        ForEach(1...7, id: \.self) { value in
                            Text(weekdayName(value)).tag(value)
                        }
                    }
                }

                if frequency == .monthly {
                    Stepper("Day \(monthDay)", value: $monthDay, in: 1...31)
                }

                if frequency == .everyNHours {
                    Stepper("Every \(intervalHours) hours", value: $intervalHours, in: 1...24)
                } else {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                }

                Toggle("Active", isOn: Binding(
                    get: { !isPaused },
                    set: { isPaused = !$0 }
                ))
                    .tint(Color.actionPrimary)
            }

            if let existingBriefing, onDelete != nil {
                Section {
                    Button(role: .destructive) {
                        onDelete?(existingBriefing)
                        dismiss()
                    } label: {
                        Text("Delete Workflow")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
    }

    private var briefingBuilder: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Describe the workflow")
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(Color.textSecondary)
                        ForEach(builderMessages) { message in
                            BriefingBuilderBubble(message: message)
                        }
                    }

                    BriefingBuilderExamples { example in
                        applyBuilderInput(example)
                    }

                    if builderActionCandidates.isEmpty && !hasDraftPreviewContent {
                        BriefingBuilderStartPanel()
                    }

                    if !builderActionCandidates.isEmpty {
                        BriefingBuilderActionCards(
                            actions: builderActionCandidates,
                            approvedIDs: approvedBuilderActionIDs,
                            onApprove: approveBuilderAction,
                            onReject: rejectBuilderAction
                        )
                    }

                    if hasDraftPreviewContent {
                        BriefingDraftPreview(
                            title: $title,
                            prompt: $prompt,
                            frequency: $frequency,
                            time: $time,
                            weekday: $weekday,
                            monthDay: $monthDay,
                            intervalHours: $intervalHours,
                            isPaused: $isPaused,
                            accountID: $accountID,
                            council: $council,
                            kind: kind,
                            canSave: canSave
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }

            Divider().overlay(Color.appHairline)
            briefingBuilderComposer
        }
        .background(Color.appBackground)
    }

    private var briefingBuilderComposer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Paste a row, source, note, or goal…", text: $builderInput, axis: .vertical)
                .lineLimit(1...4)
                .font(.body)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 1)
                }

            Button {
                applyBuilderInput(builderInput)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.actionPrimary)
            }
            .buttonStyle(.plain)
            .disabled(builderInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(builderInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            .accessibilityLabel("Stage workflow")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(Color.appBackground)
    }

    private var canSave: Bool {
        let hasBase =
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasBase else { return false }
        switch kind {
        case .nearAccount, .cryptoPrice, .stockPrice, .watchlist:
            return accountID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .customPrompt, .ethPrice, .dailyNews, .dailyBrief:
            return true
        }
    }

    private var hasDraftPreviewContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            accountID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
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
            latestResult: existingBriefing?.latestResult,
            // Preserve the live kind + account when editing, or the edit would
            // silently revert a live briefing to a custom prompt.
            kind: kind,
            accountID: accountID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            timeZoneIdentifier: existingBriefing?.timeZoneIdentifier ?? TimeZone.current.identifier,
            lastFailureAt: existingBriefing?.lastFailureAt,
            lastFailureMessage: existingBriefing?.lastFailureMessage,
            // Preserve council + condition too — otherwise editing a conditional
            // alert would silently turn it into a plain recurring price briefing
            // that fires every cycle.
            council: council,
            condition: condition
        )
    }

    private func applyBuilderInput(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        builderInput = ""
        builderMessages.append(BriefingBuilderMessage(role: .user, text: text))
        let current = BriefingBuilderDraft(
            title: title,
            prompt: prompt,
            schedule: makeScheduleForCurrentState(),
            kind: kind,
            accountID: accountID,
            council: council,
            condition: condition
        )
        let plan = BriefingBuilderPlanner.plan(from: text, current: current)
        applyBuilderDraft(plan.draft)
        builderActionCandidates = plan.actions
        approvedBuilderActionIDs.removeAll()
        builderMessages.append(BriefingBuilderMessage(role: .assistant, text: plan.reply))
        AppHaptics.selection()
    }

    private func applyBuilderDraft(_ draft: BriefingBuilderDraft) {
        title = draft.title
        prompt = draft.prompt
        kind = draft.kind
        accountID = draft.accountID
        council = draft.council
        condition = draft.condition
        applySchedule(draft.schedule)
    }

    private func approveBuilderAction(_ action: WidgetActionItem) {
        approvedBuilderActionIDs.insert(action.id)
        if let appDraft = action.appActionDraft(), appDraft.isReady {
            title = appDraft.title
            prompt = appDraft.prompt
            kind = .customPrompt
            accountID = nil
            council = council || action.type?.localizedCaseInsensitiveContains("research") == true
            condition = nil
            applySchedule(appDraft.schedule)
        }
        AppHaptics.selection()
    }

    private func rejectBuilderAction(_ action: WidgetActionItem) {
        builderActionCandidates.removeAll { $0.id == action.id }
        approvedBuilderActionIDs.remove(action.id)
        AppHaptics.selection()
    }

    private func applySchedule(_ schedule: BriefingSchedule) {
        frequency = schedule.frequency
        weekday = Self.weekday(from: schedule) ?? weekday
        monthDay = Self.monthDay(from: schedule) ?? monthDay
        intervalHours = Self.interval(from: schedule) ?? intervalHours
        if let timeComponents = schedule.timeComponents {
            time = Self.dateForTime(timeComponents)
        }
    }

    private func makeScheduleForCurrentState() -> BriefingSchedule {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        return makeSchedule(hour: components.hour ?? 8, minute: components.minute ?? 0)
    }

    private func makeSchedule(hour: Int, minute: Int) -> BriefingSchedule {
        switch frequency {
        case .daily:
            return .daily(hour: hour, minute: minute)
        case .weekdays:
            return .weekdays(hour: hour, minute: minute)
        case .weekly:
            return .weekly(weekday: weekday, hour: hour, minute: minute)
        case .biweekly:
            return .biweekly(weekday: weekday, hour: hour, minute: minute)
        case .monthly:
            return .monthly(day: monthDay, hour: hour, minute: minute)
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
        if case let .biweekly(weekday, _, _) = schedule {
            return weekday
        }
        return nil
    }

    private static func monthDay(from schedule: BriefingSchedule?) -> Int? {
        if case let .monthly(day, _, _) = schedule {
            return day
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
