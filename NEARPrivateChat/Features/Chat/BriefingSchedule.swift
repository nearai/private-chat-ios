import Foundation
@preconcurrency import UserNotifications

enum BriefingSchedule: Codable, Hashable {
    case daily(hour: Int, minute: Int)
    case weekdays(hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int)
    case biweekly(weekday: Int, hour: Int, minute: Int)
    case monthly(day: Int, hour: Int, minute: Int)
    case everyNHours(Int)

    private enum Kind: String, Codable {
        case daily
        case weekdays
        case weekly
        case biweekly
        case monthly
        case everyNHours
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case weekday
        case day
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
        case .biweekly:
            self = .biweekly(
                weekday: (try? container.decode(Int.self, forKey: .weekday)) ?? 2,
                hour: hour,
                minute: minute
            )
        case .monthly:
            self = .monthly(
                day: Self.clampedMonthDay((try? container.decode(Int.self, forKey: .day)) ?? 1),
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
        case let .biweekly(weekday, hour, minute):
            try container.encode(Kind.biweekly, forKey: .kind)
            try container.encode(clampedWeekday(weekday), forKey: .weekday)
            try container.encode(clampedHour(hour), forKey: .hour)
            try container.encode(clampedMinute(minute), forKey: .minute)
        case let .monthly(day, hour, minute):
            try container.encode(Kind.monthly, forKey: .kind)
            try container.encode(Self.clampedMonthDay(day), forKey: .day)
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
        case let .biweekly(weekday, hour, minute):
            let targetWeekday = clampedWeekday(weekday)
            if calendar.component(.weekday, from: date) == targetWeekday,
               let twoWeeks = calendar.date(byAdding: .day, value: 14, to: date) {
                var components = calendar.dateComponents([.year, .month, .day], from: twoWeeks)
                components.hour = clampedHour(hour)
                components.minute = clampedMinute(minute)
                components.second = 0
                if let candidate = calendar.date(from: components), candidate > date {
                    return candidate
                }
            }
            return nextMatchingDate(after: date, hour: hour, minute: minute, calendar: calendar) { candidate in
                calendar.component(.weekday, from: candidate) == targetWeekday
            }
        case let .monthly(day, hour, minute):
            return nextMonthlyDate(after: date, day: day, hour: hour, minute: minute, calendar: calendar)
        case let .everyNHours(interval):
            guard interval > 0 else { return nil }
            return calendar.date(byAdding: .hour, value: interval, to: date)
        }
    }

    /// Repeating local-notification triggers so a scheduled briefing pings the
    /// user at its time even if background refresh is throttled. Weekday
    /// schedules expand to one weekly trigger per business day.
    func notificationTriggers() -> [UNNotificationTrigger] {
        switch self {
        case let .daily(hour, minute):
            var components = DateComponents()
            components.hour = clampedHour(hour)
            components.minute = clampedMinute(minute)
            return [UNCalendarNotificationTrigger(dateMatching: components, repeats: true)]
        case let .weekdays(hour, minute):
            return (2...6).map { weekday in
                var components = DateComponents()
                components.weekday = weekday
                components.hour = clampedHour(hour)
                components.minute = clampedMinute(minute)
                return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            }
        case let .weekly(weekday, hour, minute):
            var components = DateComponents()
            components.weekday = clampedWeekday(weekday)
            components.hour = clampedHour(hour)
            components.minute = clampedMinute(minute)
            return [UNCalendarNotificationTrigger(dateMatching: components, repeats: true)]
        case .biweekly:
            return [UNTimeIntervalNotificationTrigger(timeInterval: 14 * 24 * 3600, repeats: true)]
        case let .monthly(day, hour, minute):
            var components = DateComponents()
            components.day = Self.clampedMonthDay(day)
            components.hour = clampedHour(hour)
            components.minute = clampedMinute(minute)
            return [UNCalendarNotificationTrigger(dateMatching: components, repeats: true)]
        case let .everyNHours(interval):
            let seconds = TimeInterval(max(1, interval) * 3600)
            return [UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: true)]
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
        case let .biweekly(weekday, hour, minute):
            return "Every other \(Self.weekdayLabel(weekday)) · \(Self.timeLabel(hour: hour, minute: minute))"
        case let .monthly(day, hour, minute):
            return "Monthly on day \(Self.clampedMonthDay(day)) · \(Self.timeLabel(hour: hour, minute: minute))"
        case let .everyNHours(interval):
            return "Every \(max(1, interval))h"
        }
    }

    var timeComponents: (hour: Int, minute: Int)? {
        switch self {
        case let .daily(hour, minute),
             let .weekdays(hour, minute),
             let .weekly(_, hour, minute),
             let .biweekly(_, hour, minute),
             let .monthly(_, hour, minute):
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
        case .biweekly: return .biweekly
        case .monthly: return .monthly
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

    private func nextMonthlyDate(
        after date: Date,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date? {
        let targetDay = Self.clampedMonthDay(day)
        let current = calendar.dateComponents([.year, .month], from: date)
        guard let year = current.year, let month = current.month else { return nil }
        for offset in 0...24 {
            guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month + offset, day: 1)),
                  let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
                continue
            }
            var components = calendar.dateComponents([.year, .month], from: firstOfMonth)
            components.day = min(targetDay, range.count)
            components.hour = clampedHour(hour)
            components.minute = clampedMinute(minute)
            components.second = 0
            if let candidate = calendar.date(from: components), candidate > date {
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

    private static func clampedMonthDay(_ day: Int) -> Int {
        min(31, max(1, day))
    }
}

enum BriefingScheduleFrequency: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekdays = "Weekdays"
    case weekly = "Weekly"
    case biweekly = "Biweekly"
    case monthly = "Monthly"
    case everyNHours = "Every N hours"

    var id: String { rawValue }
}
