import Foundation
import GRDB

final class CatalogService: Sendable {
    private let wikidataClient: WikidataClient
    private let dataService: DataService

    init(wikidataClient: WikidataClient = WikidataClient(), dataService: DataService = DataService()) {
        self.wikidataClient = wikidataClient
        self.dataService = dataService
    }

    func searchWatch(query: String) async throws -> [WatchSearchResult] {
        let localResults = try dataService.searchCatalogFTS(query: query)

        if !localResults.isEmpty {
            return localResults.map { .cached($0.watchModel) }
        }

        let wikidataResults = try await wikidataClient.searchWatches(query: query)
        return wikidataResults.map { .wikidata($0) }
    }

    func fetchWatchDetails(result: WatchSearchResult) throws -> WatchModel {
        switch result {
        case .cached(let model):
            return model

        case .wikidata(let dto):
            var model = dto.toWatchModel()

            if let brandName = dto.brand {
                let brand = try getOrCreateBrand(name: brandName)
                model.brandId = brand.id
            }

            try dataService.addWatchModel(model)
            return model
        }
    }

    func getOrCreateBrand(name: String) throws -> Brand {
        if let existing = try dataService.fetchBrand(byName: name) {
            return existing
        }

        let brand = Brand(name: name)
        try dataService.addBrand(brand)
        return brand
    }

    func loadBrandsFromWikidata() async throws -> [Brand] {
        let dtos = try await wikidataClient.fetchBrands()
        var brands: [Brand] = []

        for dto in dtos {
            let brand = Brand(
                id: dto.wikidataID,
                name: dto.name,
                country: dto.country
            )
            try dataService.upsertBrand(brand)
            brands.append(brand)
        }

        return brands
    }
}

enum WatchSearchResult: Identifiable, Sendable {
    case cached(WatchModel)
    case wikidata(WikidataWatchDTO)

    var id: String {
        switch self {
        case .cached(let model): return model.id
        case .wikidata(let dto): return dto.wikidataID
        }
    }

    var displayName: String {
        switch self {
        case .cached(let model): return model.displayName
        case .wikidata(let dto):
            if let brand = dto.brand {
                return "\(brand) \(dto.displayName)"
            }
            return dto.displayName
        }
    }

    var reference: String? {
        switch self {
        case .cached(let model): return model.reference
        case .wikidata(let dto): return dto.modelNumber
        }
    }

    var brandName: String? {
        switch self {
        case .cached: return nil
        case .wikidata(let dto): return dto.brand
        }
    }

    var imageURL: String? {
        switch self {
        case .cached(let model): return model.catalogImageURL
        case .wikidata(let dto): return dto.imageURL
        }
    }

    var source: DataSource {
        switch self {
        case .cached: return .cached
        case .wikidata: return .wikidata
        }
    }
}

enum DataSource: String, Sendable {
    case cached = "Local"
    case wikidata = "Wikidata"

    var icon: String {
        switch self {
        case .cached: return "internaldrive"
        case .wikidata: return "globe"
        }
    }
}

enum CatalogError: Error, LocalizedError {
    case notFound
    case networkError(Error)
    case parseError

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Watch not found in catalog"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .parseError:
            return "Failed to parse catalog data"
        }
    }
}
