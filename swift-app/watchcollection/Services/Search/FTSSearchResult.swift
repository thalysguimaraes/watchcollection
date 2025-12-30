import Foundation
import GRDB

struct FTSSearchResult: Identifiable, Sendable {
    let id: String
    let brandName: String
    let displayName: String
    let reference: String
    let collection: String?
    let caliber: String?
    let caseMaterial: String?
    let dialColor: String?
    var relevanceScore: Int

    init(row: Row) {
        self.id = row["watchModelId"] ?? ""
        self.brandName = row["brandName"] ?? ""
        self.displayName = row["displayName"] ?? ""
        self.reference = row["reference"] ?? ""
        self.collection = row["collection"]
        self.caliber = row["caliber"]
        self.caseMaterial = row["caseMaterial"]
        self.dialColor = row["dialColor"]
        self.relevanceScore = 0
    }

    init(
        id: String,
        brandName: String,
        displayName: String,
        reference: String,
        collection: String? = nil,
        caliber: String? = nil,
        caseMaterial: String? = nil,
        dialColor: String? = nil,
        relevanceScore: Int = 0
    ) {
        self.id = id
        self.brandName = brandName
        self.displayName = displayName
        self.reference = reference
        self.collection = collection
        self.caliber = caliber
        self.caseMaterial = caseMaterial
        self.dialColor = dialColor
        self.relevanceScore = relevanceScore
    }

    var searchableText: String {
        [brandName, displayName, reference, collection, caliber, caseMaterial, dialColor]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }
}
