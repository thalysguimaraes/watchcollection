import SwiftUI
import Observation

@Observable
@MainActor
final class AppState {
    var selectedTab: Tab = .collection
    var isAddingWatch: Bool = false

    enum Tab: Int, CaseIterable {
        case collection = 0
        case catalog = 1
        case settings = 2

        var title: String {
            switch self {
            case .collection: return "Collection"
            case .catalog: return "Catalog"
            case .settings: return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .collection: return "clock.fill"
            case .catalog: return "books.vertical.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }
}
