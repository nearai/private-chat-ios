import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Best-effort wrapper around an `Activity<AgentActivityAttributes>` for showing
/// progress of a running council briefing or compound multi-lookup on the Lock
/// Screen and in the Dynamic Island.
///
/// Every method is a pure side-effect: it never throws, never blocks the
/// caller's control flow, and silently no-ops when Live Activities are
/// unavailable, unauthorized, or fail to start. The caller's behavior and
/// results are identical whether or not an Activity ever appears.
@MainActor
final class AgentActivityController {
    #if canImport(ActivityKit)
    private var activity: Any?
    #endif

    init() {}

    deinit {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *),
           let activity = activity as? Activity<AgentActivityAttributes> {
            let finalState = activity.content.state
            Task {
                await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
            }
        }
        #endif
    }

    /// Starts a Live Activity for a run with `total` steps. Returns an opaque
    /// identifier on success, or `nil` if Live Activities are off/unavailable or
    /// the start failed. Safe to call unconditionally.
    @discardableResult
    func start(title: String, total: Int) -> String? {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return nil }
        // Never run two at once for the same controller.
        guard activity == nil else { return nil }
        // Respect the user's setting / OS availability.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }

        let safeTotal = max(total, 0)
        let attributes = AgentActivityAttributes(title: title)
        let initialState = AgentActivityAttributes.ContentState(
            stage: "Starting…",
            completed: 0,
            total: safeTotal
        )
        do {
            let started = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil)
            )
            activity = started
            return started.id
        } catch {
            // Authorization races, budget exhaustion, etc. — drop silently.
            activity = nil
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Updates the running Activity's stage and progress. No-op if none is live.
    func update(stage: String, completed: Int) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *),
              let activity = activity as? Activity<AgentActivityAttributes> else { return }
        let total = activity.content.state.total
        let safeCompleted = max(0, min(completed, total))
        let newState = AgentActivityAttributes.ContentState(
            stage: stage,
            completed: safeCompleted,
            total: total
        )
        Task {
            await activity.update(.init(state: newState, staleDate: nil))
        }
        #endif
    }

    /// Ends the running Activity immediately and clears local state. No-op if
    /// none is live. Safe to call multiple times.
    func end() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *),
              let activity = activity as? Activity<AgentActivityAttributes> else { return }
        self.activity = nil
        let finalState = activity.content.state
        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        }
        #endif
    }
}
