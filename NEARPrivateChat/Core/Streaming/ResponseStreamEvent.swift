import Foundation
import SwiftUI

enum ResponseStreamEvent: Equatable {
    case created(responseID: String)
    case reasoningStarted
    case approvalNeeded(IronclawPendingGate)
    case webSearchStarted(query: String?)
    case webSearchCompleted(query: String?, sources: [WebSearchSource])
    case textDelta(String)
    case itemDone(text: String?)
    case titleUpdated(String)
    case completed(responseID: String?)
    case failed(String)
    case failedWithStatus(message: String, statusCode: Int)

    var hasVisibleOutput: Bool {
        switch self {
        case let .textDelta(delta):
            return !delta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .itemDone(text):
            return text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        default:
            return false
        }
    }
}
