import SwiftUI
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

@main
struct BriefingWidgetBundle: WidgetBundle {
    var body: some Widget {
        BriefingWidget()
        #if canImport(ActivityKit)
        // Live Activity for in-progress council/compound agent runs. Available
        // only where ActivityKit is present (iOS 16.1+).
        if #available(iOS 16.1, *) {
            AgentLiveActivity()
        }
        #endif
    }
}
