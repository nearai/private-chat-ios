import SwiftUI

#if DEBUG
extension ThreadedBriefingView {
    static var demoDeliveries: [BriefingDelivery] {
        [
            BriefingDelivery(
                dayLabel: "Today",
                time: "—",
                title: "Scheduled briefing",
                body: "First brief is queued. It will return a sourced summary and follow-up thread.",
                isPending: true,
                itemKind: .briefing
            ),
            BriefingDelivery(
                dayLabel: "Yesterday",
                time: "8:02",
                title: "Wed 27 May · briefing",
                body: "Markets steady on Fed pause. UN brokers Lebanon talks. SpaceX Starship 14 launches.",
                replyCount: 5,
                collapsed: true
            ),
            BriefingDelivery(
                dayLabel: "Today",
                time: "8:02",
                title: "Thu 28 May · briefing",
                headline: "US–Iran ceasefire under strain",
                summary: "US strikes Iranian drone sites near Hormuz. 60-day extension under discussion.",
                extra: "+ Israel strikes Beirut · ETH down 2.3% · 2 more",
                sources: [
                    BriefingSourceTag(letter: "W", colorHex: "#ff7e1c"),
                    BriefingSourceTag(letter: "N", colorHex: "#0091FD"),
                    BriefingSourceTag(letter: "a", colorHex: "#000000")
                ],
                verifiedModel: "GLM 5.1",
                replyCount: 2,
                unread: true,
                thread: DeliveryThread(
                    label: "US–Iran ceasefire",
                    replies: [
                        ThreadReply(role: .user, text: "what's the impact on oil?"),
                        ThreadReply(
                            role: .assistant,
                            text: "Brent fell 3.1% on talks of reopening Hormuz; futures pricing in a 60% chance of an extension this week.",
                            citations: [
                                BriefingSourceTag(letter: "r", colorHex: "#FF6B35"),
                                BriefingSourceTag(letter: "B", colorHex: "#000000")
                            ],
                            verifiedModel: "NEAR Private",
                            verifiedSources: 2,
                            ago: "just now"
                        )
                    ]
                )
            )
        ]
    }
}

#Preview("Threaded briefing") {
    ThreadedBriefingView(
        title: "Daily briefing",
        schedule: "Every weekday · 8:00am",
        deliveries: ThreadedBriefingView.demoDeliveries
    )
}
#endif
