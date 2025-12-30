import SwiftUI
import Observation

@Observable
@MainActor
final class NavigationRouter {
    var selectedTab: Int = 0
    var collectionPath: [CollectionDestination] = []
    var wishlistPath: [WishlistDestination] = []
    var catalogPath: [CatalogDestination] = []
    var presentedSheet: AppSheet?

    func navigateToWatch(_ item: CollectionItem) {
        collectionPath.append(.watchDetail(item))
    }

    func navigateToCatalogWatch(_ model: WatchModel) {
        catalogPath.append(.watchModel(model))
    }

    func navigateToWishlistDetail(_ item: WishlistItemWithWatch) {
        wishlistPath.append(.wishlistDetail(item))
    }

    func presentAddWatch() {
        presentedSheet = .addWatch
    }

    func presentEditWatch(_ item: CollectionItem) {
        presentedSheet = .editWatch(item)
    }

    func presentQuickAddToCollection(_ model: WatchModel, brand: Brand?) {
        presentedSheet = .quickAddToCollection(model, brand)
    }

    func presentAddToWishlist(_ model: WatchModel, brand: Brand?) {
        presentedSheet = .addToWishlist(model, brand)
    }

    func presentEditWishlistItem(_ item: WishlistItem) {
        presentedSheet = .editWishlistItem(item)
    }

    func presentWatchIdentification() {
        presentedSheet = .watchIdentification
    }

    func dismiss() {
        presentedSheet = nil
    }

    func popToRoot() {
        collectionPath.removeAll()
    }

    func popWishlistToRoot() {
        wishlistPath.removeAll()
    }

    func popCatalogToRoot() {
        catalogPath.removeAll()
    }
}

enum CollectionDestination: Hashable {
    case watchDetail(CollectionItem)
    case editWatch(CollectionItem)

    func hash(into hasher: inout Hasher) {
        switch self {
        case .watchDetail(let item):
            hasher.combine("detail")
            hasher.combine(item.id)
        case .editWatch(let item):
            hasher.combine("edit")
            hasher.combine(item.id)
        }
    }

    static func == (lhs: CollectionDestination, rhs: CollectionDestination) -> Bool {
        switch (lhs, rhs) {
        case (.watchDetail(let a), .watchDetail(let b)):
            return a.id == b.id
        case (.editWatch(let a), .editWatch(let b)):
            return a.id == b.id
        default:
            return false
        }
    }
}

enum CatalogDestination: Hashable {
    case watchModel(WatchModel)
    case brand(Brand)

    func hash(into hasher: inout Hasher) {
        switch self {
        case .watchModel(let model):
            hasher.combine("model")
            hasher.combine(model.id)
        case .brand(let brand):
            hasher.combine("brand")
            hasher.combine(brand.id)
        }
    }

    static func == (lhs: CatalogDestination, rhs: CatalogDestination) -> Bool {
        switch (lhs, rhs) {
        case (.watchModel(let a), .watchModel(let b)):
            return a.id == b.id
        case (.brand(let a), .brand(let b)):
            return a.id == b.id
        default:
            return false
        }
    }
}

enum WishlistDestination: Hashable {
    case wishlistDetail(WishlistItemWithWatch)
    case catalogWatch(WatchModel)

    func hash(into hasher: inout Hasher) {
        switch self {
        case .wishlistDetail(let item):
            hasher.combine("wishlist")
            hasher.combine(item.wishlistItem.id)
        case .catalogWatch(let model):
            hasher.combine("catalog")
            hasher.combine(model.id)
        }
    }

    static func == (lhs: WishlistDestination, rhs: WishlistDestination) -> Bool {
        switch (lhs, rhs) {
        case (.wishlistDetail(let a), .wishlistDetail(let b)):
            return a.wishlistItem.id == b.wishlistItem.id
        case (.catalogWatch(let a), .catalogWatch(let b)):
            return a.id == b.id
        default:
            return false
        }
    }
}

enum AppSheet: Identifiable {
    case addWatch
    case editWatch(CollectionItem)
    case photoViewer(WatchPhoto)
    case quickAddToCollection(WatchModel, Brand?)
    case addToWishlist(WatchModel, Brand?)
    case editWishlistItem(WishlistItem)
    case watchIdentification

    var id: String {
        switch self {
        case .addWatch: return "addWatch"
        case .editWatch(let item): return "editWatch-\(item.id)"
        case .photoViewer(let photo): return "photo-\(photo.id)"
        case .quickAddToCollection(let model, _): return "quickAdd-\(model.id)"
        case .addToWishlist(let model, _): return "wishlist-\(model.id)"
        case .editWishlistItem(let item): return "editWishlist-\(item.id)"
        case .watchIdentification: return "watchIdentification"
        }
    }
}
