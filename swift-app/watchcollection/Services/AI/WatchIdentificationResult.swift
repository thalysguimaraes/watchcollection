import Foundation

struct WatchIdentification: Sendable {
    var brand: String?
    var model: String?
    var reference: String?
    var collection: String?
    var material: String?
    var dialColor: String?
    var complications: [String]
    var rawDescription: String
    var source: String?

    var searchQuery: String {
        [brand, model, dialColor, reference].compactMap { $0 }.joined(separator: " ")
    }

    var displaySummary: String {
        var parts: [String] = []
        if let brand = brand { parts.append(brand) }
        if let model = model { parts.append(model) }
        if let reference = reference, reference.lowercased() != "unknown" {
            parts.append("(\(reference))")
        }
        return parts.isEmpty ? rawDescription : parts.joined(separator: " ")
    }
}

enum IdentificationState: Sendable {
    case selectSource
    case capturing(ImageSourceType)
    case analyzing
    case results(matches: [IdentificationMatch], identification: WatchIdentification)
    case noMatch(identification: WatchIdentification)
    case error(String)
}

enum ImageSourceType: Sendable {
    case camera
    case photoLibrary
}

struct IdentificationMatch: Sendable {
    let watch: WatchModelWithBrand
    let confidence: Double
    let matchType: MatchType
    let reason: String?

    enum MatchType: Sendable {
        case reference
        case brandModel
        case fuzzy
        case ai
        case ocr
    }
}
