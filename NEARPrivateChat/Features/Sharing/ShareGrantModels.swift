import Foundation

enum ShareGrantMode: String, CaseIterable, Identifiable {
    case people = "People"
    case group = "Group"
    case organization = "Organization"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .people: "person.badge.plus"
        case .group: "person.3"
        case .organization: "building.2"
        }
    }
}

enum ShareGrantPermission: String, CaseIterable, Identifiable {
    case read = "Read-only"
    case write = "Can reply"

    var id: String { rawValue }
    var apiValue: String {
        switch self {
        case .read:
            return "read"
        case .write:
            return "write"
        }
    }
}

enum SensitiveShareGrant {
    case people
    case group
    case organization

    var label: String {
        switch self {
        case .people: "people"
        case .group: "this group"
        case .organization: "the organization"
        }
    }
}
