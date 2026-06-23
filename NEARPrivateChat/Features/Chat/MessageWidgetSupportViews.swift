import SwiftUI

struct WidgetActionCandidateFieldList: View {
    let action: WidgetActionItem

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                if index > 0 {
                    Divider().overlay(Color.appHairline)
                        .padding(.leading, 40)
                }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: field.symbolName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.actionPrimary)
                        .frame(width: 28, height: 28)
                        .background(Color.actionTint, in: RoundedRectangle.app(AppRadius.pill))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(field.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                        Text(field.value)
                            .font(.subheadline)
                            .foregroundStyle(Color.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 0.5)
        }
    }

    private var fields: [WidgetActionCandidateField] {
        var result: [WidgetActionCandidateField] = []
        func append(_ title: String, _ value: String?, _ symbolName: String) {
            guard let value = widgetNonBlank(value) else { return }
            result.append(WidgetActionCandidateField(title: title, value: value, symbolName: symbolName))
        }
        append("Type", action.type, "tag")
        append("Schedule", action.schedule, "calendar")
        append("Date", action.date, "calendar.badge.clock")
        append("Time", action.time, "clock")
        append("Duration", action.duration, "timer")
        append("Recurrence", action.recurrence, "repeat")
        append("Timezone", action.timezone, "globe")
        append("Source", action.source, "doc.text.magnifyingglass")
        append("Location", action.location, "mappin.and.ellipse")
        if !action.attendees.isEmpty {
            result.append(WidgetActionCandidateField(
                title: "Attendees",
                value: action.attendees.joined(separator: ", "),
                symbolName: "person.2"
            ))
        }
        let missingFields = action.reviewMissingFields
        if !missingFields.isEmpty {
            result.append(WidgetActionCandidateField(
                title: "Needs",
                value: missingFields.joined(separator: ", "),
                symbolName: "exclamationmark.triangle"
            ))
        }
        if let confidence = action.confidence {
            result.append(WidgetActionCandidateField(
                title: "Confidence",
                value: "\(Int((confidence * 100).rounded()))%",
                symbolName: "gauge"
            ))
        }
        if result.isEmpty {
            result.append(WidgetActionCandidateField(
                title: "Status",
                value: "Preview only",
                symbolName: "eye"
            ))
        }
        return result
    }
}

struct WidgetActionCandidateField {
    let title: String
    let value: String
    let symbolName: String
}

struct WidgetGenericBody: View {
    let note: String

    var body: some View {
        // Generic widgets are compact presentation cards. Strip inline markdown
        // markers before rendering so generated briefing notes never show raw
        // **bold** or *italic* punctuation inside the card.
        MarkdownMessageText(text: Self.displayNote(note))
            .fixedSize(horizontal: false, vertical: true)
    }

    static func displayNote(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"__([^_]+)__"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(?<!_)_([^_\n]+)_(?!_)"#, with: "$1", options: .regularExpression)
    }
}

struct WidgetSourceDot: View {
    let source: WidgetNewsSource
    var size: CGFloat = 14

    var body: some View {
        // Widget sources are model-emitted JSON. Known publisher domains/labels
        // can still resolve network favicons; unknown sources always stay local.
        SourceFaviconView(
            domain: source.faviconIdentity,
            size: size,
            fallbackText: source.fallbackMark,
            fallbackColor: dotColor,
            cornerRadius: max(4, size * 0.26),
            borderColor: Color.white.opacity(0.72),
            borderWidth: 0.7,
            allowsNetworkFavicon: allowsNetworkFavicon
        )
    }

    private var dotColor: Color {
        if let hex = source.color, let c = widgetColor(fromHex: hex) { return c }
        return SourceFaviconResolver.fallbackTint(for: source.faviconIdentity)
    }

    private var allowsNetworkFavicon: Bool {
        source.allowsNetworkFavicon && size >= 18
    }
}

// MARK: Sparkline shapes

struct WidgetSparkline: Shape {
    let points: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        let minV = points.min() ?? 0
        let maxV = points.max() ?? 1
        let range = maxV - minV
        let stepX = rect.width / CGFloat(points.count - 1)
        for (i, v) in points.enumerated() {
            let x = rect.minX + CGFloat(i) * stepX
            let norm = range == 0 ? 0.5 : CGFloat((v - minV) / range)
            let y = rect.maxY - norm * rect.height
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

struct WidgetSparklineFill: Shape {
    let points: [Double]

    func path(in rect: CGRect) -> Path {
        var path = WidgetSparkline(points: points).path(in: rect)
        guard !path.isEmpty else { return path }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: Widget helpers

func widgetTrendColor(_ trend: WidgetTrend?) -> Color {
    switch trend {
    case .up: return .proofVerified
    case .down: return .proofMismatch
    default: return .textSecondary
    }
}

func widgetToneColor(_ tone: WidgetTone?) -> Color {
    switch tone {
    case .good: return .proofVerified
    case .warn: return .proofStale
    case .bad: return .proofMismatch // red — matches the chart card's down-delta
    case .off: return .secondary
    default: return .primary
    }
}

func widgetNonBlank(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

func widgetColor(fromHex hex: String) -> Color? {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
    return Color(
        red: Double((value >> 16) & 0xFF) / 255,
        green: Double((value >> 8) & 0xFF) / 255,
        blue: Double(value & 0xFF) / 255
    )
}
