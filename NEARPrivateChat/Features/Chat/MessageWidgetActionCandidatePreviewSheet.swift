import EventKit
import SwiftUI

struct WidgetActionCandidatePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let action: WidgetActionItem
    let canStageCommand: Bool
    let onStageCommand: (String) -> Void
    let onCreateAppAction: ((WidgetActionItem) -> Void)?
    @State private var isSavingSystemAction = false
    @State private var systemActionStatus: String?

    var body: some View {
        let systemDraft = action.systemActionDraft()
        let appDraft = action.appActionDraft()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(action.title.isEmpty ? "Action" : action.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = widgetNonBlank(action.detail) {
                            Text(detail)
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    WidgetActionCandidateFieldList(action: action)

                    WidgetAppActionSection(
                        draft: appDraft,
                        canCreate: onCreateAppAction != nil,
                        onCreate: {
                            onCreateAppAction?(action)
                            dismiss()
                        }
                    )

                    WidgetSystemActionSection(
                        action: action,
                        draft: systemDraft,
                        isSaving: isSavingSystemAction,
                        status: systemActionStatus,
                        onSave: { draft in
                            saveSystemAction(draft)
                        }
                    )

                    if let command = widgetNonBlank(action.command) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Stage in Chat")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                            Text(command)
                                .font(.footnote)
                                .foregroundStyle(Color.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.appBorder, lineWidth: 0.5)
                                }
                        }
                    }
                }
                .padding(18)
            }
            .background(Color.appBackground)
            .navigationTitle("Review Before Creating")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if canStageCommand, let command = widgetNonBlank(action.command) {
                        Button("Stage") {
                            onStageCommand(command)
                        }
                    }
                }
            }
        }
        .platformMediumDetent()
    }

    private func saveSystemAction(_ draft: WidgetSystemActionDraft) {
        guard !isSavingSystemAction else { return }
        isSavingSystemAction = true
        systemActionStatus = nil
        Task {
            do {
                let message = try await WidgetSystemActionWriter.shared.save(draft)
                await MainActor.run {
                    systemActionStatus = message
                    isSavingSystemAction = false
                }
            } catch {
                await MainActor.run {
                    systemActionStatus = error.localizedDescription
                    isSavingSystemAction = false
                }
            }
        }
    }
}

struct WidgetAppActionSection: View {
    let draft: WidgetAppActionDraft?
    let canCreate: Bool
    let onCreate: () -> Void

    var body: some View {
        guard let draft else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text("Create in App")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)

                if draft.isReady {
                    Button {
                        onCreate()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.subheadline.weight(.semibold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Create Tracker")
                                    .font(.subheadline.weight(.semibold))
                                Text(draft.schedule.scheduleLabel)
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.actionPrimary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.actionPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCreate)
                    .accessibilityLabel("Create tracker")
                } else {
                    Label("Needs \(draft.missingFields.prefix(3).joined(separator: ", ")) before it can be saved as a tracker.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        )
    }
}

struct WidgetSystemActionSection: View {
    let action: WidgetActionItem
    let draft: WidgetSystemActionDraft?
    let isSaving: Bool
    let status: String?
    let onSave: (WidgetSystemActionDraft) -> Void

    var body: some View {
        guard action.systemActionKind != nil else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text("Add to Phone")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)

                if let draft {
                    Button {
                        onSave(draft)
                    } label: {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: draft.kind == .calendarEvent ? "calendar.badge.plus" : "bell.badge")
                                    .font(.subheadline.weight(.semibold))
                            }
                            Text(draft.kind == .calendarEvent ? "Add to Calendar" : "Add Reminder")
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                            Text(draft.startDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.actionPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                } else {
                    Label("Needs an exact date and time before adding to iOS.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if let status = widgetNonBlank(status) {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        )
    }
}

@MainActor
private final class WidgetSystemActionWriter {
    static let shared = WidgetSystemActionWriter()
    private let eventStore = EKEventStore()

    func save(_ draft: WidgetSystemActionDraft) async throws -> String {
        switch draft.kind {
        case .calendarEvent:
            try await requestCalendarAccess()
            guard let calendar = eventStore.defaultCalendarForNewEvents else {
                throw WidgetSystemActionWriterError.noDefaultCalendar
            }
            let event = EKEvent(eventStore: eventStore)
            event.calendar = calendar
            event.title = draft.title
            event.startDate = draft.startDate
            event.endDate = draft.endDate ?? draft.startDate.addingTimeInterval(30 * 60)
            event.notes = draft.notes
            event.location = draft.location
            if let rule = recurrenceRule(from: draft.recurrence) {
                event.addRecurrenceRule(rule)
            }
            try eventStore.save(event, span: .futureEvents, commit: true)
            return "Added to Calendar."
        case .reminder:
            try await requestReminderAccess()
            guard let calendar = eventStore.defaultCalendarForNewReminders() else {
                throw WidgetSystemActionWriterError.noDefaultReminderList
            }
            let reminder = EKReminder(eventStore: eventStore)
            reminder.calendar = calendar
            reminder.title = draft.title
            reminder.notes = draft.notes
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: draft.startDate
            )
            if let rule = recurrenceRule(from: draft.recurrence) {
                reminder.addRecurrenceRule(rule)
            }
            try eventStore.save(reminder, commit: true)
            return "Added to Reminders."
        }
    }

    private func requestCalendarAccess() async throws {
        let granted: Bool = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            eventStore.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
        guard granted else { throw WidgetSystemActionWriterError.accessDenied("Calendar") }
    }

    private func requestReminderAccess() async throws {
        let granted: Bool = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            eventStore.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
        guard granted else { throw WidgetSystemActionWriterError.accessDenied("Reminders") }
    }

    private func recurrenceRule(from value: String?) -> EKRecurrenceRule? {
        guard let value = widgetNonBlank(value)?.lowercased() else { return nil }
        if value.contains("weekday") || value.contains("weekdays") || value.contains("mon-fri") || value.contains("monday to friday") {
            let weekdays = [
                EKRecurrenceDayOfWeek(.monday),
                EKRecurrenceDayOfWeek(.tuesday),
                EKRecurrenceDayOfWeek(.wednesday),
                EKRecurrenceDayOfWeek(.thursday),
                EKRecurrenceDayOfWeek(.friday)
            ]
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                daysOfTheWeek: weekdays,
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: nil
            )
        }
        let frequency: EKRecurrenceFrequency
        if value.contains("month") {
            frequency = .monthly
        } else if value.contains("week") {
            frequency = .weekly
        } else if value.contains("year") || value.contains("annual") {
            frequency = .yearly
        } else if value.contains("daily") || value.contains("day") {
            frequency = .daily
        } else {
            return nil
        }
        return EKRecurrenceRule(recurrenceWith: frequency, interval: 1, end: nil)
    }
}

private enum WidgetSystemActionWriterError: LocalizedError {
    case accessDenied(String)
    case noDefaultCalendar
    case noDefaultReminderList

    var errorDescription: String? {
        switch self {
        case let .accessDenied(scope):
            return "\(scope) access was not granted."
        case .noDefaultCalendar:
            return "No writable default calendar is available."
        case .noDefaultReminderList:
            return "No writable default reminders list is available."
        }
    }
}

