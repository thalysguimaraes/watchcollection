import GRDB
import Foundation

final class DataService: Sendable {
    private let dbQueue: DatabaseQueue
    private let ftsService: FTSSearchService

    init(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) {
        self.dbQueue = dbQueue
        self.ftsService = FTSSearchService(dbQueue: dbQueue)
    }

    func fetchCollectionItems(sortBy: CollectionSortOption = .dateAdded, ascending: Bool = false) throws -> [CollectionItem] {
        try dbQueue.read { db in
            var query = CollectionItem.all()
            switch sortBy {
            case .dateAdded:
                query = ascending ? query.order(Column("dateAdded")) : query.order(Column("dateAdded").desc)
            case .brand:
                query = ascending ? query.order(Column("manualBrand")) : query.order(Column("manualBrand").desc)
            case .name:
                query = ascending ? query.order(Column("manualModel")) : query.order(Column("manualModel").desc)
            case .condition:
                query = ascending ? query.order(Column("dateAdded")) : query.order(Column("dateAdded").desc)
            case .purchasePrice:
                query = ascending ? query.order(Column("purchasePrice")) : query.order(Column("purchasePrice").desc)
            }
            return try query.fetchAll(db)
        }
    }

    func fetchCollectionItemsWithDetails(sortBy: CollectionSortOption = .dateAdded, ascending: Bool = false) throws -> [CollectionItemWithDetails] {
        try dbQueue.read { db in
            let items = try CollectionItem.order(Column("dateAdded").desc).fetchAll(db)
            return try items.map { item in
                let catalogWatch = try item.catalogWatchId.flatMap { try WatchModel.fetchOne(db, key: $0) }
                let brand = try catalogWatch?.brandId.flatMap { try Brand.fetchOne(db, key: $0) }
                return CollectionItemWithDetails(collectionItem: item, catalogWatch: catalogWatch, brand: brand)
            }
        }
    }

    func fetchPrimaryPhoto(forItem itemId: String) throws -> WatchPhoto? {
        try dbQueue.read { db in
            try WatchPhoto
                .filter(Column("collectionItemId") == itemId)
                .order(Column("sortOrder"))
                .fetchOne(db)
        }
    }

    func searchCollectionItems(query: String) throws -> [CollectionItem] {
        try dbQueue.read { db in
            let pattern = "%\(query)%"
            return try CollectionItem
                .filter(Column("manualBrand").like(pattern) || Column("manualModel").like(pattern) || Column("manualReference").like(pattern))
                .fetchAll(db)
        }
    }

    func fetchWatchModel(byReference ref: String) throws -> WatchModel? {
        try dbQueue.read { db in
            try WatchModel.filter(Column("reference") == ref).fetchOne(db)
        }
    }

    func fetchWatchModel(byID id: String) throws -> WatchModel? {
        try dbQueue.read { db in
            try WatchModel.fetchOne(db, key: id)
        }
    }

    func searchCatalog(query: String) throws -> [WatchModel] {
        try dbQueue.read { db in
            let pattern = "%\(query)%"
            return try WatchModel
                .filter(Column("displayName").like(pattern) || Column("reference").like(pattern))
                .fetchAll(db)
        }
    }

    func searchCatalogFTS(query: String) throws -> [WatchModelWithBrand] {
        let ftsResults = try ftsService.search(query: query)
        guard !ftsResults.isEmpty else { return [] }

        let ids = ftsResults.map(\.id)
        let idToScore = Dictionary(uniqueKeysWithValues: ftsResults.map { ($0.id, $0.relevanceScore) })

        return try dbQueue.read { db in
            let request = WatchModel
                .filter(ids.contains(Column("id")))
                .including(optional: WatchModel.brand)
            let results = try WatchModelWithBrand.fetchAll(db, request)

            return results.sorted { model1, model2 in
                let score1 = idToScore[model1.watchModel.id] ?? 0
                let score2 = idToScore[model2.watchModel.id] ?? 0
                return score1 > score2
            }
        }
    }

    func fetchBrands() throws -> [Brand] {
        try dbQueue.read { db in
            try Brand.order(Column("name")).fetchAll(db)
        }
    }

    func fetchBrand(byName name: String) throws -> Brand? {
        try dbQueue.read { db in
            try Brand.filter(Column("name") == name).fetchOne(db)
        }
    }

    func fetchBrand(byID id: String) throws -> Brand? {
        try dbQueue.read { db in
            try Brand.fetchOne(db, key: id)
        }
    }

    func addCollectionItem(_ item: CollectionItem) throws {
        _ = try dbQueue.write { db in
            var record = item
            try record.insert(db)
        }
    }

    func updateCollectionItem(_ item: CollectionItem) throws {
        _ = try dbQueue.write { db in
            var record = item
            record.lastModified = Date()
            try record.update(db)
        }
    }

    func deleteCollectionItem(_ item: CollectionItem) throws {
        _ = try dbQueue.write { db in
            _ = try item.delete(db)
        }
    }

    func addWatchModel(_ model: WatchModel) throws {
        _ = try dbQueue.write { db in
            var record = model
            try record.insert(db)
            let brandName = try model.brandId.flatMap { try Brand.fetchOne(db, key: $0)?.name }
            try ftsService.updateFTSIndex(db: db, model: model, brandName: brandName)
        }
    }

    func updateWatchModel(_ model: WatchModel) throws {
        _ = try dbQueue.write { db in
            let record = model
            try record.update(db)
            let brandName = try model.brandId.flatMap { try Brand.fetchOne(db, key: $0)?.name }
            try ftsService.updateFTSIndex(db: db, model: model, brandName: brandName)
        }
    }

    func addBrand(_ brand: Brand) throws {
        _ = try dbQueue.write { db in
            var record = brand
            try record.insert(db)
        }
    }

    func upsertBrand(_ brand: Brand) throws {
        _ = try dbQueue.write { db in
            var record = brand
            try record.save(db)
        }
    }

    func addPriceRecord(_ priceRecord: PriceRecord) throws {
        _ = try dbQueue.write { db in
            var record = priceRecord
            try record.insert(db)
        }
    }

    func addPhoto(_ photo: WatchPhoto) throws {
        _ = try dbQueue.write { db in
            var record = photo
            try record.insert(db)
        }
    }

    func deletePhoto(_ photo: WatchPhoto) throws {
        _ = try dbQueue.write { db in
            _ = try photo.delete(db)
        }
    }

    func fetchPhotos(forItem itemId: String) throws -> [WatchPhoto] {
        try dbQueue.read { db in
            try WatchPhoto
                .filter(Column("collectionItemId") == itemId)
                .order(Column("sortOrder"))
                .fetchAll(db)
        }
    }

    func collectionCount() throws -> Int {
        try dbQueue.read { db in
            try CollectionItem.fetchCount(db)
        }
    }

    func totalCollectionValue(currency: String = "USD") throws -> Decimal {
        try dbQueue.read { db in
            let items = try CollectionItem
                .filter(Column("purchaseCurrency") == currency)
                .fetchAll(db)
            return items.compactMap(\.currentEstimatedValueDecimal).reduce(0, +)
        }
    }

    func saveBatch<T: MutablePersistableRecord>(_ records: [T]) throws {
        try dbQueue.write { db in
            for var record in records {
                try record.save(db)
            }
        }
    }

    func insertBatch<T: MutablePersistableRecord>(_ records: [T]) throws {
        try dbQueue.write { db in
            for var record in records {
                try record.insert(db)
            }
        }
    }

    func fetchBrandsWithModelCount() throws -> [(brand: Brand, modelCount: Int)] {
        try dbQueue.read { db in
            let brands = try Brand.order(Column("name")).fetchAll(db)
            return try brands.map { brand in
                let count = try WatchModel.filter(Column("brandId") == brand.id).fetchCount(db)
                return (brand, count)
            }
        }
    }

    func fetchWatchModelsWithBrand(forBrandId brandId: String) throws -> [WatchModelWithBrand] {
        try dbQueue.read { db in
            let request = WatchModel
                .filter(Column("brandId") == brandId)
                .including(optional: WatchModel.brand)
            return try WatchModelWithBrand.fetchAll(db, request)
        }
    }

    func searchCatalogWithBrands(query: String) throws -> [WatchModelWithBrand] {
        try dbQueue.read { db in
            let pattern = "%\(query)%"
            let request = WatchModel
                .filter(Column("displayName").like(pattern) || Column("reference").like(pattern))
                .including(optional: WatchModel.brand)
            return try WatchModelWithBrand.fetchAll(db, request)
        }
    }

    func fetchWishlistItems(sortBy: WishlistSortOption = .dateAdded) throws -> [WishlistItemWithWatch] {
        try dbQueue.read { db in
            let wishlistItems = try WishlistItem.order(Column("dateAdded").desc).fetchAll(db)

            return try wishlistItems.compactMap { item -> WishlistItemWithWatch? in
                guard let watchModel = try WatchModel.fetchOne(db, key: item.watchModelId) else {
                    return nil
                }
                let brand = try watchModel.brandId.flatMap { try Brand.fetchOne(db, key: $0) }
                return WishlistItemWithWatch(wishlistItem: item, watchModel: watchModel, brand: brand)
            }
        }
    }

    func fetchWishlistItem(forWatchModelId id: String) throws -> WishlistItem? {
        try dbQueue.read { db in
            try WishlistItem.filter(Column("watchModelId") == id).fetchOne(db)
        }
    }

    func addToWishlist(_ item: WishlistItem) throws {
        _ = try dbQueue.write { db in
            var record = item
            try record.insert(db)
        }
    }

    func removeFromWishlist(_ item: WishlistItem) throws {
        _ = try dbQueue.write { db in
            _ = try item.delete(db)
        }
    }

    func removeFromWishlist(watchModelId: String) throws {
        _ = try dbQueue.write { db in
            try WishlistItem.filter(Column("watchModelId") == watchModelId).deleteAll(db)
        }
    }

    func updateWishlistItem(_ item: WishlistItem) throws {
        _ = try dbQueue.write { db in
            let record = item
            try record.update(db)
        }
    }

    func isOnWishlist(watchModelId: String) throws -> Bool {
        try dbQueue.read { db in
            try WishlistItem.filter(Column("watchModelId") == watchModelId).fetchCount(db) > 0
        }
    }

    func wishlistCount() throws -> Int {
        try dbQueue.read { db in
            try WishlistItem.fetchCount(db)
        }
    }

    func collectionStats() throws -> CollectionStats {
        try dbQueue.read { db in
            let items = try CollectionItem.fetchAll(db)
            let totalCount = items.count
            let fullSetCount = items.filter { $0.hasBox && $0.hasPapers }.count
            let withBoxCount = items.filter(\.hasBox).count
            let withPapersCount = items.filter(\.hasPapers).count

            var totalMarketValueUSD: Decimal = 0
            var itemsWithMarketValue = 0

            for item in items {
                if let catalogWatchId = item.catalogWatchId,
                   let watchModel = try WatchModel.fetchOne(db, key: catalogWatchId),
                   let marketPrice = watchModel.marketPriceMedian {
                    totalMarketValueUSD += Decimal(marketPrice)
                    itemsWithMarketValue += 1
                } else if let estimatedValue = item.currentEstimatedValueDecimal {
                    totalMarketValueUSD += estimatedValue
                    itemsWithMarketValue += 1
                }
            }

            return CollectionStats(
                totalCount: totalCount,
                fullSetCount: fullSetCount,
                withBoxCount: withBoxCount,
                withPapersCount: withPapersCount,
                totalMarketValueUSD: totalMarketValueUSD,
                itemsWithMarketValue: itemsWithMarketValue
            )
        }
    }
}

enum CollectionSortOption: String, CaseIterable, Sendable {
    case dateAdded = "Date Added"
    case brand = "Brand"
    case name = "Name"
    case condition = "Condition"
    case purchasePrice = "Value"

    var icon: String {
        switch self {
        case .dateAdded: return "calendar"
        case .brand: return "tag"
        case .name: return "textformat"
        case .condition: return "star"
        case .purchasePrice: return "dollarsign.circle"
        }
    }
}

enum WishlistSortOption: String, CaseIterable, Sendable {
    case dateAdded = "Date Added"
    case priority = "Priority"
    case price = "Price"
    case name = "Name"

    var icon: String {
        switch self {
        case .dateAdded: return "calendar"
        case .priority: return "flame"
        case .price: return "dollarsign.circle"
        case .name: return "textformat"
        }
    }
}
