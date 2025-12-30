import GRDB
import Foundation

extension WatchPhoto: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "watchPhoto" }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["imageData"] = imageData
        container["thumbnailData"] = thumbnailData
        container["caption"] = caption
        container["photoType"] = photoType.rawValue
        container["sortOrder"] = sortOrder
        container["dateAdded"] = dateAdded
        container["collectionItemId"] = collectionItemId
    }
}

extension PriceRecord: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "priceRecord" }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["price"] = price
        container["currency"] = currency
        container["source"] = source.rawValue
        container["condition"] = condition?.rawValue
        container["hasBox"] = hasBox
        container["hasPapers"] = hasPapers
        container["recordDate"] = recordDate
        container["sourceURL"] = sourceURL
        container["watchModelId"] = watchModelId
    }
}

extension CollectionItem: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "collectionItem" }

    static let catalogWatch = belongsTo(WatchModel.self, using: ForeignKey(["catalogWatchId"]))

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["catalogWatchId"] = catalogWatchId
        container["manualBrand"] = manualBrand
        container["manualModel"] = manualModel
        container["manualReference"] = manualReference
        container["serialNumber"] = serialNumber
        container["condition"] = condition.rawValue
        container["hasBox"] = hasBox
        container["hasPapers"] = hasPapers
        container["hasWarrantyCard"] = hasWarrantyCard
        container["purchasePrice"] = purchasePrice
        container["purchaseCurrency"] = purchaseCurrency
        container["purchaseDate"] = purchaseDate
        container["purchaseSource"] = purchaseSource
        container["currentEstimatedValue"] = currentEstimatedValue
        container["lastValuationDate"] = lastValuationDate
        container["notes"] = notes
        container["dateAdded"] = dateAdded
        container["lastModified"] = lastModified
    }
}

extension Brand: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "brand" }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["name"] = name
        container["country"] = country
        container["logoURL"] = logoURL
    }
}

extension WatchModel: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "watchModel" }

    static let brand = belongsTo(Brand.self)

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["reference"] = reference
        container["displayName"] = displayName
        container["collection"] = collection
        container["productionYearStart"] = productionYearStart
        container["productionYearEnd"] = productionYearEnd
        container["specsJSON"] = specsJSON
        container["catalogImageURL"] = catalogImageURL
        container["wikidataID"] = wikidataID
        container["watchbaseID"] = watchbaseID
        container["lastUpdated"] = lastUpdated
        container["marketPriceMin"] = marketPriceMin
        container["marketPriceMax"] = marketPriceMax
        container["marketPriceMedian"] = marketPriceMedian
        container["marketPriceListings"] = marketPriceListings
        container["marketPriceUpdatedAt"] = marketPriceUpdatedAt
        container["brandId"] = brandId
        container["watchchartsId"] = watchchartsId
        container["watchchartsUrl"] = watchchartsUrl
        container["isCurrent"] = isCurrent
        container["retailPriceUSD"] = retailPriceUSD
        container["priceHistoryJSON"] = priceHistoryJSON
        container["priceHistorySource"] = priceHistorySource
    }
}

extension WatchModelWithBrand: FetchableRecord {}
extension CollectionItemWithDetails: FetchableRecord {}

extension WishlistItem: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "wishlistItem" }

    static let watchModel = belongsTo(WatchModel.self, using: ForeignKey(["watchModelId"]))

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["watchModelId"] = watchModelId
        container["priority"] = priority.rawValue
        container["targetPrice"] = targetPrice
        container["targetCurrency"] = targetCurrency
        container["notes"] = notes
        container["dateAdded"] = dateAdded
        container["notifyOnPriceDrop"] = notifyOnPriceDrop
    }
}
