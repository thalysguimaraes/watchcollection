import Foundation
import GRDB

private let catalogDecoder = JSONDecoder()

enum CatalogImportError: Error, LocalizedError {
    case networkError(Error)
    case decodingFailed(Error)
    case importFailed(Error)
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Failed to decode catalog: \(error.localizedDescription)"
        case .importFailed(let error):
            return "Failed to import catalog: \(error.localizedDescription)"
        case .serverError(let code):
            return "Server error: \(code)"
        }
    }
}

final class CatalogImporter: Sendable {
    private let dbQueue: DatabaseQueue
    private let baseURL: String
    private let session: URLSession
    private let ftsService: FTSSearchService

    private static let importedVersionKey = "catalog_imported_version"
    private static let importedDateKey = "catalog_imported_date"
    private static let catalogETagKey = "catalog_etag"

    init(
        dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue,
        baseURL: String = APIConstants.catalogBaseURL,
        session: URLSession = CatalogImporter.makeSession()
    ) {
        self.dbQueue = dbQueue
        self.baseURL = baseURL
        self.session = session
        self.ftsService = FTSSearchService(dbQueue: dbQueue)
    }

    var importedVersion: String? {
        UserDefaults.standard.string(forKey: Self.importedVersionKey)
    }

    var importedDate: Date? {
        let timestamp = UserDefaults.standard.double(forKey: Self.importedDateKey)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    private var catalogETag: String? {
        UserDefaults.standard.string(forKey: Self.catalogETagKey)
    }

    func importCatalogIfNeeded() async throws {
        switch try await fetchCatalog() {
        case .notModified:
            print("Catalog up to date (version: \(importedVersion ?? "unknown"))")
            return
        case .updated(let catalog, let etag):
            try performImport(catalog)
            try ftsService.rebuildIndex()
            updateImportMetadata(version: catalog.version, etag: etag)
            print("Catalog imported successfully (version: \(catalog.version))")
        }
    }

    func importCatalog() async throws {
        switch try await fetchCatalog(ignoreETag: true) {
        case .notModified:
            return
        case .updated(let catalog, let etag):
            try performImport(catalog)
            try ftsService.rebuildIndex()
            updateImportMetadata(version: catalog.version, etag: etag)
            print("Catalog imported successfully (version: \(catalog.version))")
        }
    }

    private enum CatalogFetchResult {
        case notModified
        case updated(CatalogResponse, String?)
    }

    private func fetchCatalog(ignoreETag: Bool = false) async throws -> CatalogFetchResult {
        let url = URL(string: "\(baseURL)/catalog")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadRevalidatingCacheData
        if !ignoreETag, let etag = catalogETag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CatalogImportError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CatalogImportError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 304 {
            if importedVersion == nil && !ignoreETag {
                return try await fetchCatalog(ignoreETag: true)
            }
            return .notModified
        }

        guard httpResponse.statusCode == 200 else {
            throw CatalogImportError.serverError(httpResponse.statusCode)
        }

        let catalog: CatalogResponse
        do {
            catalog = try catalogDecoder.decode(CatalogResponse.self, from: data)
        } catch {
            throw CatalogImportError.decodingFailed(error)
        }

        let responseETag = httpResponse.value(forHTTPHeaderField: "ETag")
        return .updated(catalog, responseETag)
    }

    private func updateImportMetadata(version: String, etag: String?) {
        UserDefaults.standard.set(version, forKey: Self.importedVersionKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.importedDateKey)
        if let etag = etag {
            UserDefaults.standard.set(etag, forKey: Self.catalogETagKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.catalogETagKey)
        }
    }

    private func performImport(_ catalog: CatalogResponse) throws {
        try dbQueue.write { db in
            var totalModels = 0

            for brandDTO in catalog.brands {
                var brand = getOrCreateBrand(brandDTO, in: db)
                try brand.save(db)

                for modelDTO in brandDTO.models {
                    var model = modelDTO.toWatchModel()
                    model.brandId = brand.id
                    try model.save(db)
                    totalModels += 1
                }
            }

            print("Imported \(catalog.brands.count) brands, \(totalModels) models")
        }
    }

    private func getOrCreateBrand(_ dto: CatalogBrandDTO, in db: Database) -> Brand {
        if let existing = try? Brand.fetchOne(db, key: dto.id) {
            var updated = existing
            updated.name = dto.name
            updated.country = dto.country
            return updated
        }

        return Brand(
            id: dto.id,
            name: dto.name,
            country: dto.country
        )
    }

    func resetImportState() {
        UserDefaults.standard.removeObject(forKey: Self.importedVersionKey)
        UserDefaults.standard.removeObject(forKey: Self.importedDateKey)
        UserDefaults.standard.removeObject(forKey: Self.catalogETagKey)
        print("Catalog import state reset")
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadRevalidatingCacheData
        config.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024,
            diskPath: nil
        )
        return URLSession(configuration: config)
    }
}
