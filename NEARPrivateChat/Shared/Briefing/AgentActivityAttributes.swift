import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Shared description of the "agent run" Live Activity. Both the app target
/// (which starts/updates/ends the Activity) and the widget extension (which
/// renders it on the Lock Screen and in the Dynamic Island) compile this file,
/// mirroring how `BriefingSnapshot.swift` is shared across both targets.
///
/// The type is declared unconditionally so it is always available to plain Swift
/// code; only the `ActivityAttributes` conformance is gated behind ActivityKit,
/// which is present on iOS but not on every platform the package may compile for.
#if canImport(ActivityKit)
struct AgentActivityAttributes: ActivityAttributes {
    /// Per-update state: which stage the run is in, plus how many sub-steps have
    /// completed out of the total. Kept tiny and `Codable` so ActivityKit can
    /// ship it to the widget process.
    public struct ContentState: Codable, Hashable {
        /// Human-readable label for the current step, e.g. "Synthesizing" or the
        /// model name currently answering. Shown verbatim in the Live Activity.
        public var stage: String
        /// Number of sub-steps finished so far (0...total).
        public var completed: Int
        /// Total number of sub-steps in this run (model count, intent count, …).
        public var total: Int

        public init(stage: String, completed: Int, total: Int) {
            self.stage = stage
            self.completed = completed
            self.total = total
        }
    }

    /// Static, set once when the Activity starts: the run's headline (e.g. the
    /// briefing title, or "Working on N lookups").
    public var title: String

    public init(title: String) {
        self.title = title
    }
}
#endif
