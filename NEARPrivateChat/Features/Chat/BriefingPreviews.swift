import SwiftUI

#if DEBUG
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
#endif
