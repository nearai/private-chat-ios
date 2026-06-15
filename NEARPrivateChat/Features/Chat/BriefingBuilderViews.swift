import SwiftUI

struct BriefingBuilderBubble: View {
    let message: BriefingBuilderMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 44)
            }
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(message.role == .user ? Color.appPanelBackground : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(message.role == .assistant ? Color.appBorder : Color.clear, lineWidth: 1)
                }
            if message.role == .assistant {
                Spacer(minLength: 44)
            }
        }
    }

    private var background: Color {
        message.role == .user ? Color.actionPrimary : Color.appPanelBackground
    }
}

struct BriefingBuilderActionCards: View {
    let actions: [WidgetActionItem]
    let approvedIDs: Set<String>
    let onApprove: (WidgetActionItem) -> Void
    let onReject: (WidgetActionItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.actionPrimary)
                Text("Review before anything is created")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.textSecondary)
            }

            VStack(spacing: 8) {
                ForEach(actions) { action in
                    actionCard(action)
                }
            }
        }
    }

    private func actionCard(_ action: WidgetActionItem) -> some View {
        let approved = approvedIDs.contains(action.id)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbolName(for: action))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint(for: action, approved: approved))
                    .frame(width: 28, height: 28)
                    .background(tint(for: action, approved: approved).opacity(0.12), in: RoundedRectangle.app(AppRadius.pill))

                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title.isEmpty ? "Action" : action.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(metadata(for: action, approved: approved))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(tint(for: action, approved: approved))
                        .lineLimit(2)

                    if let detail = nonBlank(action.detail) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    let missingFields = action.reviewMissingFields
                    if !missingFields.isEmpty {
                        Text("Needs: \(missingFields.prefix(3).joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(Color.proofStaleText)
                            .lineLimit(2)
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    onApprove(action)
                } label: {
                    Label(approved ? "Approved" : "Approve", systemImage: approved ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(approved ? Color.proofVerified : Color.actionPrimary)

                Button {
                    onReject(action)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 34)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Remove action")
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(approved ? Color.proofVerified.opacity(0.45) : Color.appBorder, lineWidth: 1)
        }
    }

    private func metadata(for action: WidgetActionItem, approved: Bool) -> String {
        let parts = [
            approved ? "approved" : nil,
            nonBlank(action.type),
            nonBlank(action.schedule),
            nonBlank(action.recurrence),
            nonBlank(action.time),
            nonBlank(action.source)
        ].compactMap { $0 }
        return parts.prefix(4).joined(separator: " · ")
    }

    private func symbolName(for action: WidgetActionItem) -> String {
        let normalized = (action.type ?? "").lowercased()
        if normalized.contains("calendar") { return "calendar.badge.plus" }
        if normalized.contains("reminder") { return "bell.badge" }
        if normalized.contains("workflow") || normalized.contains("automation") || normalized.contains("tracker") || normalized.contains("brief") || normalized.contains("watch") {
            return "dot.radiowaves.left.and.right"
        }
        if normalized.contains("decision") { return "checkmark.seal" }
        return "checklist"
    }

    private func tint(for action: WidgetActionItem, approved: Bool) -> Color {
        if approved { return Color.proofVerified }
        switch action.tone ?? .neutral {
        case .warn: return Color.proofStale
        case .bad: return Color.proofMismatch
        case .good: return Color.proofVerified
        case .neutral, .off: return Color.actionPrimary
        }
    }

    private func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct BriefingBuilderExamples: View {
    let onSelect: (String) -> Void

    private let examples = [
        "Turn this table into reminders",
        "Check new project sources every weekday at 8am",
        "Brief me on client follow-ups every morning",
        "Create a daily digest of what changed"
    ]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(examples, id: \.self) { example in
                Button {
                    onSelect(example)
                } label: {
                    Text(example)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.appBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct BriefingBuilderStartPanel: View {
    private let rows: [(String, String, String)] = [
        ("1", "Drop in any source", "Paste a table row, screenshot text, note, URL, or goal."),
        ("2", "Review candidates", "The app drafts automations, reminders, calendar items, and missing fields."),
        ("3", "Approve creation", "Nothing is saved or sent to the phone calendar until you approve it.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How this should work")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color.textSecondary)

            VStack(spacing: 8) {
                ForEach(rows, id: \.0) { row in
                    HStack(alignment: .top, spacing: 10) {
                        Text(row.0)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.actionPrimary)
                            .frame(width: 26, height: 26)
                            .background(Color.actionPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.1)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Text(row.2)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(12)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
        }
    }
}

struct BriefingDraftPreview: View {
    @Binding var title: String
    @Binding var prompt: String
    @Binding var frequency: BriefingScheduleFrequency
    @Binding var time: Date
    @Binding var weekday: Int
    @Binding var monthDay: Int
    @Binding var intervalHours: Int
    @Binding var isPaused: Bool
    @Binding var accountID: String?
    @Binding var council: Bool
    let kind: BriefingKind
    let canSave: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                BriefingIconChip(symbolName: canSave ? "checkmark.seal.fill" : "sparkles", tint: canSave ? Color.proofVerified : Color.actionPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(canSave ? "Ready to save" : "Draft")
                        .font(.headline)
                    Text(canSave ? scheduleSummary : "Schedule suggested: \(scheduleSummary)")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 10) {
                TextField("Title", text: $title)
                    .font(.subheadline.weight(.semibold))
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                TextField("What should run on schedule?", text: $prompt, axis: .vertical)
                    .font(.subheadline)
                    .textFieldStyle(.plain)
                    .lineLimit(3...7)
                    .padding(12)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                if requiresAccount {
                    TextField(accountPlaceholder, text: Binding(
                        get: { accountID ?? "" },
                        set: { accountID = $0 }
                    ))
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            scheduleControls

            if !canSave {
                Label("Add a title and what to check before saving.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                if kind == .customPrompt {
                    Toggle(isOn: $council) {
                        Label("Council", systemImage: "person.3.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .toggleStyle(.switch)
                    .tint(Color.actionPrimary)
                }
                Toggle(isOn: Binding(
                    get: { !isPaused },
                    set: { isPaused = !$0 }
                )) {
                    Label("Active", systemImage: "bell.badge")
                        .font(.caption.weight(.semibold))
                }
                .toggleStyle(.switch)
                .tint(Color.actionPrimary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var scheduleControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BriefingScheduleFrequency.allCases) { item in
                        Button {
                            frequency = item
                        } label: {
                            Text(shortLabel(for: item))
                                .font(.caption.weight(.semibold))
                            .foregroundStyle(frequency == item ? Color.actionPrimary : Color.textSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 44)
                            .background(
                                frequency == item ? Color.actionTint : Color.appSecondaryBackground,
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                        .minimumTouchTarget()
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollClipDisabled()

            if frequency == .weekly || frequency == .biweekly {
                Picker("Day", selection: $weekday) {
                    ForEach(1...7, id: \.self) { value in
                        Text(weekdayName(value)).tag(value)
                    }
                }
                .pickerStyle(.menu)
            }

            if frequency == .monthly {
                Stepper("Day \(monthDay)", value: $monthDay, in: 1...31)
                    .font(.subheadline)
            }

            if frequency == .everyNHours {
                Stepper("Every \(intervalHours) hours", value: $intervalHours, in: 1...24)
                    .font(.subheadline)
            } else {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .font(.subheadline)
            }
        }
    }

    private var scheduleSummary: String {
        switch frequency {
        case .daily, .weekdays, .weekly, .biweekly, .monthly:
            let components = Calendar.current.dateComponents([.hour, .minute], from: time)
            let schedule: BriefingSchedule
            if frequency == .daily {
                schedule = .daily(hour: components.hour ?? 8, minute: components.minute ?? 0)
            } else if frequency == .weekdays {
                schedule = .weekdays(hour: components.hour ?? 8, minute: components.minute ?? 0)
            } else if frequency == .weekly {
                schedule = .weekly(weekday: weekday, hour: components.hour ?? 8, minute: components.minute ?? 0)
            } else if frequency == .biweekly {
                schedule = .biweekly(weekday: weekday, hour: components.hour ?? 8, minute: components.minute ?? 0)
            } else {
                schedule = .monthly(day: monthDay, hour: components.hour ?? 8, minute: components.minute ?? 0)
            }
            return schedule.scheduleLabel
        case .everyNHours:
            return BriefingSchedule.everyNHours(intervalHours).scheduleLabel
        }
    }

    private var requiresAccount: Bool {
        switch kind {
        case .nearAccount, .cryptoPrice, .stockPrice, .commodityPrice, .watchlist:
            return true
        case .customPrompt, .ethPrice, .dailyNews, .dailyBrief:
            return false
        }
    }

    private var accountPlaceholder: String {
        switch kind {
        case .nearAccount:
            return "NEAR account, e.g. yourname.near"
        case .cryptoPrice:
            return "Coin id"
        case .stockPrice:
            return "Ticker"
        case .commodityPrice:
            return "Commodity"
        case .watchlist:
            return "Watchlist"
        case .customPrompt, .ethPrice, .dailyNews, .dailyBrief:
            return "Subject"
        }
    }

    private func shortLabel(for item: BriefingScheduleFrequency) -> String {
        switch item {
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly"
        case .biweekly: return "Biweekly"
        case .monthly: return "Monthly"
        case .everyNHours: return "Hourly"
        }
    }

    private func weekdayName(_ value: Int) -> String {
        let labels = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return labels[clampedWeekday(value) - 1]
    }
}
