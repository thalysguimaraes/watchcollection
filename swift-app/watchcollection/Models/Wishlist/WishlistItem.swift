import Foundation
import SwiftUI

struct WishlistItem: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var watchModelId: String
    var priority: WishlistPriority
    var targetPrice: String?
    var targetCurrency: String
    var notes: String?
    var dateAdded: Date
    var notifyOnPriceDrop: Bool

    var targetPriceDecimal: Decimal? {
        get { targetPrice.flatMap { Decimal(string: $0) } }
        set { targetPrice = newValue.map { "\($0)" } }
    }

    init(
        id: String = UUID().uuidString,
        watchModelId: String,
        priority: WishlistPriority = .medium,
        targetCurrency: String = "USD"
    ) {
        self.id = id
        self.watchModelId = watchModelId
        self.priority = priority
        self.targetCurrency = targetCurrency
        self.dateAdded = Date()
        self.notifyOnPriceDrop = false
    }
}

enum WishlistPriority: String, Codable, CaseIterable, Sendable {
    case high = "high"
    case medium = "medium"
    case low = "low"

    var displayName: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    var icon: String {
        switch self {
        case .high: return "flame.fill"
        case .medium: return "star.fill"
        case .low: return "bookmark.fill"
        }
    }

    var color: Color {
        switch self {
        case .high: return Theme.Colors.error
        case .medium: return Theme.Colors.warning
        case .low: return Theme.Colors.textSecondary
        }
    }

    var sortOrder: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}
