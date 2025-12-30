import Foundation

enum PriceSource: String, Codable, CaseIterable, Sendable {
    case chrono24 = "Chrono24"
    case watchCharts = "WatchCharts"
    case manual = "Manual"
    case auction = "Auction"
    case retailer = "Retailer"

    var icon: String {
        switch self {
        case .chrono24: return "globe"
        case .watchCharts: return "chart.line.uptrend.xyaxis"
        case .manual: return "hand.raised.fill"
        case .auction: return "hammer.fill"
        case .retailer: return "storefront.fill"
        }
    }
}

struct PriceRecord: Codable, Identifiable, Equatable {
    var id: String
    var price: String
    var currency: String
    var source: PriceSource
    var condition: WatchCondition?
    var hasBox: Bool?
    var hasPapers: Bool?
    var recordDate: Date
    var sourceURL: String?
    var watchModelId: String?

    var priceDecimal: Decimal {
        get { Decimal(string: price) ?? 0 }
        set { price = "\(newValue)" }
    }

    var formattedPrice: String {
        Currency.from(code: currency)?.format(priceDecimal) ?? "\(currency) \(price)"
    }

    init(
        id: String = UUID().uuidString,
        price: Decimal,
        currency: String = "USD",
        source: PriceSource,
        recordDate: Date = Date()
    ) {
        self.id = id
        self.price = "\(price)"
        self.currency = currency
        self.source = source
        self.recordDate = recordDate
    }
}

