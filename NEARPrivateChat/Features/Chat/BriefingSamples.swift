import SwiftUI

enum BriefingSamples {
    @MainActor
    static let store = BriefingStore(briefings: sampleBriefings)

    // Sample briefings — no canned results. Production injects the real
    // model-routed runner; preview-only stores can still fall back to sample
    // widgets when no runner is available.
    static let sampleBriefings: [Briefing] = [
        Briefing(
            title: "Daily news brief",
            prompt: "Today's top news",
            schedule: .weekdays(hour: 8, minute: 0),
            createdAt: Date().addingTimeInterval(-86_400 * 3),
            kind: .dailyNews
        ),
        Briefing(
            title: "Project digest",
            prompt: "Review my active project context and summarize open questions, risks, and next steps.",
            schedule: .daily(hour: 9, minute: 0),
            createdAt: Date().addingTimeInterval(-86_400 * 2),
            kind: .customPrompt
        ),
        Briefing(
            title: "Research brief",
            prompt: "Research the latest credible developments on my saved topic and turn them into a short briefing with sources and follow-ups.",
            schedule: .daily(hour: 8, minute: 0),
            createdAt: Date().addingTimeInterval(-86_400),
            kind: .customPrompt
        ),
        Briefing(
            title: "ETH price watcher",
            prompt: "Alert me when ETH drops below $3,180 and summarize why it moved.",
            schedule: .daily(hour: 8, minute: 0),
            createdAt: Date().addingTimeInterval(-86_400 * 2),
            lastRunAt: Date().addingTimeInterval(-3_600),
            latestResult: MessageWidget(
                kind: .metric,
                title: "ETH watcher",
                freshness: .fresh,
                time: "1h ago",
                followUp: "Why did it move?",
                metric: WidgetMetric(
                    label: "ETH · USD",
                    value: "$3,124",
                    delta: "−2.3% (1h)",
                    trend: .down,
                    caption: "threshold $3,180 breached"
                )
            ),
            kind: .customPrompt,
            condition: BriefingCondition(
                coinID: "ethereum",
                symbol: "ETH",
                comparator: .below,
                threshold: 3180
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
