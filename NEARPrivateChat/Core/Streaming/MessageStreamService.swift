import Foundation

struct MessageStreamService {
    static func visibleOutputTimeout(for modelID: String) -> TimeInterval? {
        let route = RoutePlanner.routeKind(forModelID: modelID)
        if route == .nearCloud || route.isIronclawRoute {
            return nil
        }
        return 90
    }
}
