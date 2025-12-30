import Foundation

struct CollectionItem: Codable, Hashable, Identifiable {
    var id: String
    var catalogWatchId: String?
    var manualBrand: String?
    var manualModel: String?
    var manualReference: String?
    var serialNumber: String?
    var condition: WatchCondition
    var hasBox: Bool
    var hasPapers: Bool
    var hasWarrantyCard: Bool
    var purchasePrice: String?
    var purchaseCurrency: String
    var purchaseDate: Date?
    var purchaseSource: String?
    var currentEstimatedValue: String?
    var lastValuationDate: Date?
    var notes: String?
    var dateAdded: Date
    var lastModified: Date

    var purchasePriceDecimal: Decimal? {
        get { purchasePrice.flatMap { Decimal(string: $0) } }
        set { purchasePrice = newValue.map { "\($0)" } }
    }

    var currentEstimatedValueDecimal: Decimal? {
        get { currentEstimatedValue.flatMap { Decimal(string: $0) } }
        set { currentEstimatedValue = newValue.map { "\($0)" } }
    }

    var completenessSet: String {
        var parts: [String] = []
        if hasBox { parts.append("Box") }
        if hasPapers { parts.append("Papers") }
        if hasWarrantyCard { parts.append("Warranty") }
        return parts.isEmpty ? "Watch only" : parts.joined(separator: " + ")
    }

    var valueChange: Decimal? {
        guard let purchase = purchasePriceDecimal,
              let current = currentEstimatedValueDecimal else { return nil }
        return current - purchase
    }

    var valueChangePercentage: Decimal? {
        guard let purchase = purchasePriceDecimal,
              let change = valueChange,
              purchase > 0 else { return nil }
        return (change / purchase) * 100
    }

    var displayName: String {
        if let model = manualModel, !model.isEmpty {
            if let brand = manualBrand, !brand.isEmpty {
                return "\(brand) \(model)"
            }
            return model
        }
        return manualBrand ?? "Unknown Watch"
    }

    var reference: String? {
        manualReference
    }

    var brandName: String? {
        manualBrand
    }

    init(
        id: String = UUID().uuidString,
        catalogWatchId: String? = nil,
        condition: WatchCondition = .excellent,
        purchaseCurrency: String = "USD"
    ) {
        self.id = id
        self.catalogWatchId = catalogWatchId
        self.condition = condition
        self.hasBox = false
        self.hasPapers = false
        self.hasWarrantyCard = false
        self.purchaseCurrency = purchaseCurrency
        self.dateAdded = Date()
        self.lastModified = Date()
    }
}


struct CollectionItemWithDetails: Decodable, Hashable, Sendable {
    var collectionItem: CollectionItem
    var catalogWatch: WatchModel?
    var brand: Brand?

    var displayName: String {
        if let watch = catalogWatch {
            var name = watch.displayName
            if let brandName = brand?.name {
                let prefixes = [brandName + " ", brandName.uppercased() + " ", brandName.lowercased() + " "]
                for prefix in prefixes {
                    if name.hasPrefix(prefix) {
                        name = String(name.dropFirst(prefix.count))
                        break
                    }
                }
            }
            return name
        }
        return collectionItem.manualModel ?? "Unknown Watch"
    }

    var reference: String? {
        catalogWatch?.reference ?? collectionItem.manualReference
    }

    var brandName: String? {
        brand?.name ?? collectionItem.manualBrand
    }
}
