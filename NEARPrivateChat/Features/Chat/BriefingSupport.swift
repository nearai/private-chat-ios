import Foundation

extension JSONEncoder {
    static var briefing: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var briefing: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

func briefingSort(_ lhs: Briefing, _ rhs: Briefing) -> Bool {
    if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
    if lhs.isPaused != rhs.isPaused { return !lhs.isPaused }
    let now = Date()
    let lhsNext = lhs.schedule.nextRun(after: lhs.lastRunAt ?? now) ?? .distantFuture
    let rhsNext = rhs.schedule.nextRun(after: rhs.lastRunAt ?? now) ?? .distantFuture
    if lhsNext != rhsNext { return lhsNext < rhsNext }
    return lhs.createdAt > rhs.createdAt
}

func relativeNextRun(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
}

var briefingTimeFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateFormat = "h:mma"
    return formatter
}

func clampedHour(_ hour: Int) -> Int {
    min(max(hour, 0), 23)
}

func clampedMinute(_ minute: Int) -> Int {
    min(max(minute, 0), 59)
}

func clampedWeekday(_ weekday: Int) -> Int {
    min(max(weekday, 1), 7)
}
