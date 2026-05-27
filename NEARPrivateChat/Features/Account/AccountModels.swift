import Foundation
import SwiftUI

struct AppDiagnosticCheck: Identifiable, Hashable {
    enum State: String, Hashable {
        case running
        case passed
        case warning
        case failed

        var symbolName: String {
            switch self {
            case .running: "arrow.triangle.2.circlepath"
            case .passed: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .failed: "xmark.circle.fill"
            }
        }
    }

    var id = UUID().uuidString
    var title: String
    var detail: String
    var state: State
}
