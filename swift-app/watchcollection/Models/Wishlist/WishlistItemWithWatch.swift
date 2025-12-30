import Foundation

struct WishlistItemWithWatch: Hashable, Sendable {
    var wishlistItem: WishlistItem
    var watchModel: WatchModel
    var brand: Brand?

    var displayName: String {
        if let brandName = brand?.name {
            return "\(brandName) \(watchModel.displayName)"
        }
        return watchModel.displayName
    }

    var reference: String {
        watchModel.reference
    }

    var brandName: String? {
        brand?.name
    }
}
