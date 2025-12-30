import Foundation

private let currencyFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.maximumFractionDigits = 0
    return formatter
}()

struct PriceHistoryPoint: Codable, Hashable, Sendable {
    let date: Date
    let price: Double
}

struct WatchModel: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var reference: String
    var referenceAliasesJSON: String?
    var displayName: String
    var collection: String?
    var productionYearStart: Int?
    var productionYearEnd: Int?
    var specsJSON: String?
    var catalogImageURL: String?
    var wikidataID: String?
    var watchbaseID: String?
    var lastUpdated: Date
    var marketPriceMin: Int?
    var marketPriceMax: Int?
    var marketPriceMedian: Int?
    var marketPriceListings: Int?
    var marketPriceUpdatedAt: Date?
    var brandId: String?
    var watchchartsId: String?
    var watchchartsUrl: String?
    var isCurrent: Bool?
    var retailPriceUSD: Int?
    var priceHistoryJSON: String?
    var priceHistorySource: String?

    var specs: WatchSpecs? {
        get {
            guard let json = specsJSON, let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(WatchSpecs.self, from: data)
        }
        set {
            guard let newValue else { specsJSON = nil; return }
            if let data = try? JSONEncoder().encode(newValue) {
                specsJSON = String(data: data, encoding: .utf8)
            }
        }
    }

    var referenceAliases: [String]? {
        get {
            guard let json = referenceAliasesJSON, let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([String].self, from: data)
        }
        set {
            guard let newValue, !newValue.isEmpty else { referenceAliasesJSON = nil; return }
            if let data = try? JSONEncoder().encode(newValue) {
                referenceAliasesJSON = String(data: data, encoding: .utf8)
            }
        }
    }

    var priceHistory: [PriceHistoryPoint]? {
        get {
            guard let json = priceHistoryJSON,
                  let data = json.data(using: .utf8),
                  let points = try? JSONDecoder().decode([[Double]].self, from: data) else {
                return nil
            }
            return points.compactMap { arr -> PriceHistoryPoint? in
                guard arr.count >= 2 else { return nil }
                let date = Date(timeIntervalSince1970: arr[0])
                return PriceHistoryPoint(date: date, price: arr[1])
            }.sorted { $0.date < $1.date }
        }
        set {
            guard let newValue, !newValue.isEmpty else {
                priceHistoryJSON = nil
                return
            }
            let points: [[Double]] = newValue.map { [$0.date.timeIntervalSince1970, $0.price] }
            if let data = try? JSONEncoder().encode(points) {
                priceHistoryJSON = String(data: data, encoding: .utf8)
            }
        }
    }

    var isInProduction: Bool {
        isCurrent ?? (productionYearEnd == nil)
    }

    var productionYearRange: String {
        let start = productionYearStart.map { String($0) } ?? "?"
        if let end = productionYearEnd {
            return "\(start)-\(end)"
        }
        return "\(start)-present"
    }

    var formattedMarketPrice: String? {
        guard let median = marketPriceMedian else { return nil }
        return currencyFormatter.string(from: NSNumber(value: median))
    }

    var marketPriceRange: String? {
        guard let min = marketPriceMin, let max = marketPriceMax else { return nil }
        let minStr = currencyFormatter.string(from: NSNumber(value: min)) ?? "$\(min)"
        let maxStr = currencyFormatter.string(from: NSNumber(value: max)) ?? "$\(max)"
        return "\(minStr) - \(maxStr)"
    }

    var fullDisplayName: String {
        displayName
    }

    init(
        id: String = UUID().uuidString,
        reference: String,
        displayName: String,
        collection: String? = nil,
        productionYearStart: Int? = nil,
        productionYearEnd: Int? = nil
    ) {
        self.id = id
        self.reference = reference
        self.displayName = displayName
        self.collection = collection
        self.productionYearStart = productionYearStart
        self.productionYearEnd = productionYearEnd
        self.lastUpdated = Date()
    }
}


struct WatchModelWithBrand: Decodable, Hashable, Sendable {
    var watchModel: WatchModel
    var brand: Brand?

    var fullDisplayName: String {
        var name = watchModel.displayName
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
}
