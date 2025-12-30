import Foundation
import Observation

@Observable
@MainActor
final class DataRefreshStore {
    var collectionRefreshToken: UUID = UUID()
    var wishlistRefreshToken: UUID = UUID()

    func notifyCollectionChanged() {
        collectionRefreshToken = UUID()
    }

    func notifyWishlistChanged() {
        wishlistRefreshToken = UUID()
    }
}
