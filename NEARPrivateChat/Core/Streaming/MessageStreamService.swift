import Foundation

struct MessageStreamService {
    static let textDeltaFlushNanoseconds: UInt64 = 100_000_000
    static let councilTextDeltaFlushNanoseconds: UInt64 = 550_000_000

    static func visibleOutputTimeout(for modelID: String) -> TimeInterval? {
        let route = RoutePlanner.routeKind(forModelID: modelID)
        if route == .nearCloud || route.isIronclawRoute {
            return nil
        }
        return 90
    }
}
