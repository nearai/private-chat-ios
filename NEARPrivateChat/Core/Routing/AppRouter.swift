import Foundation

@MainActor
final class AppRouter: ObservableObject {
    @Published var path: [AppRoute] = []
    @Published var activeSheet: AppSheet?
    @Published private(set) var currentAccountID: String?

    func navigate(to route: AppRoute) {
        path.append(route)
    }

    func replace(with route: AppRoute) {
        path = [route]
    }

    func popToRoot() {
        path.removeAll()
    }

    func present(_ sheet: AppSheet) {
        activeSheet = sheet
    }

    func dismissSheet() {
        activeSheet = nil
    }

    func resetForSignOut() {
        currentAccountID = nil
        path.removeAll()
        activeSheet = nil
    }

    func resetForAccountSwitch(_ accountID: String?) {
        guard currentAccountID != accountID else { return }
        currentAccountID = accountID
        path.removeAll()
        activeSheet = nil
    }
}
