import Foundation

struct CollectionStats: Sendable {
    let totalCount: Int
    let fullSetCount: Int
    let withBoxCount: Int
    let withPapersCount: Int
    let totalMarketValueUSD: Decimal
    let itemsWithMarketValue: Int

    var isEmpty: Bool {
        totalCount == 0
    }
}
