import Foundation

final class WikidataClient: Sendable {
    private let networkClient: NetworkClient
    private let endpoint = "https://query.wikidata.org/sparql"

    init(networkClient: NetworkClient = NetworkClient()) {
        self.networkClient = networkClient
    }

    func searchWatches(query: String) async throws -> [WikidataWatchDTO] {
        let sparql = """
        SELECT ?item ?itemLabel ?brandLabel ?modelNumber ?inception ?image WHERE {
          ?item wdt:P31/wdt:P279* wd:Q178794 .
          ?item rdfs:label ?label .
          FILTER(LANG(?label) = "en")
          FILTER(CONTAINS(LCASE(?label), "\(query.lowercased())"))
          OPTIONAL { ?item wdt:P176 ?brand . }
          OPTIONAL { ?item wdt:P13351 ?modelNumber . }
          OPTIONAL { ?item wdt:P571 ?inception . }
          OPTIONAL { ?item wdt:P18 ?image . }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        }
        LIMIT 50
        """

        return try await executeSparql(sparql)
    }

    func fetchWatch(id: String) async throws -> WikidataWatchDTO {
        let sparql = """
        SELECT ?item ?itemLabel ?brandLabel ?modelNumber ?inception ?image
               ?caseDiameter ?waterResistance ?caliber WHERE {
          BIND(wd:\(id) AS ?item)
          OPTIONAL { ?item wdt:P176 ?brand . }
          OPTIONAL { ?item wdt:P13351 ?modelNumber . }
          OPTIONAL { ?item wdt:P571 ?inception . }
          OPTIONAL { ?item wdt:P18 ?image . }
          OPTIONAL { ?item wdt:P2386 ?caseDiameter . }
          OPTIONAL { ?item wdt:P2793 ?waterResistance . }
          OPTIONAL { ?item wdt:P7937 ?caliber . }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        }
        LIMIT 1
        """

        let results = try await executeSparql(sparql)
        guard let first = results.first else {
            throw WikidataError.notFound
        }
        return first
    }

    func fetchBrands() async throws -> [WikidataBrandDTO] {
        let sparql = """
        SELECT DISTINCT ?brand ?brandLabel ?country ?countryLabel WHERE {
          ?watch wdt:P31/wdt:P279* wd:Q178794 .
          ?watch wdt:P176 ?brand .
          OPTIONAL { ?brand wdt:P17 ?country . }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        }
        ORDER BY ?brandLabel
        LIMIT 200
        """

        guard var urlComponents = URLComponents(string: endpoint) else {
            throw NetworkError.invalidURL
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "query", value: sparql),
            URLQueryItem(name: "format", value: "json")
        ]

        guard let url = urlComponents.url else {
            throw NetworkError.invalidURL
        }

        let response: WikidataSparqlResponse = try await networkClient.fetch(
            WikidataSparqlResponse.self,
            from: url,
            headers: ["Accept": "application/sparql-results+json"]
        )

        return response.results.bindings.compactMap { binding -> WikidataBrandDTO? in
            guard let brandUri = binding["brand"]?.value,
                  let brandLabel = binding["brandLabel"]?.value else { return nil }

            let id = extractWikidataID(from: brandUri)
            let country = binding["countryLabel"]?.value

            return WikidataBrandDTO(
                wikidataID: id,
                name: brandLabel,
                country: country
            )
        }
    }

    private func executeSparql(_ sparql: String) async throws -> [WikidataWatchDTO] {
        guard var urlComponents = URLComponents(string: endpoint) else {
            throw NetworkError.invalidURL
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "query", value: sparql),
            URLQueryItem(name: "format", value: "json")
        ]

        guard let url = urlComponents.url else {
            throw NetworkError.invalidURL
        }

        let response: WikidataSparqlResponse = try await networkClient.fetch(
            WikidataSparqlResponse.self,
            from: url,
            headers: ["Accept": "application/sparql-results+json"]
        )

        return response.results.bindings.compactMap { binding -> WikidataWatchDTO? in
            guard let itemUri = binding["item"]?.value,
                  let itemLabel = binding["itemLabel"]?.value else { return nil }

            let id = extractWikidataID(from: itemUri)

            var caseDiameter: Double?
            if let diameterStr = binding["caseDiameter"]?.value {
                caseDiameter = Double(diameterStr)
            }
            var waterResistance: Int?
            if let wrStr = binding["waterResistance"]?.value {
                waterResistance = Int(wrStr)
            }

            return WikidataWatchDTO(
                wikidataID: id,
                displayName: itemLabel,
                brand: binding["brandLabel"]?.value,
                modelNumber: binding["modelNumber"]?.value,
                inceptionYear: parseYear(binding["inception"]?.value),
                imageURL: binding["image"]?.value,
                caseDiameter: caseDiameter,
                waterResistance: waterResistance,
                caliber: binding["caliber"]?.value
            )
        }
    }

    private func extractWikidataID(from uri: String) -> String {
        uri.components(separatedBy: "/").last ?? uri
    }

    private func parseYear(_ dateString: String?) -> Int? {
        guard let dateString else { return nil }
        let components = dateString.components(separatedBy: "-")
        return components.first.flatMap { Int($0) }
    }
}

struct WikidataSparqlResponse: Sendable {
    let results: WikidataResults

    enum CodingKeys: String, CodingKey {
        case results
    }
}

extension WikidataSparqlResponse: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = try container.decode(WikidataResults.self, forKey: .results)
    }
}

struct WikidataResults: Sendable {
    let bindings: [[String: WikidataValue]]

    enum CodingKeys: String, CodingKey {
        case bindings
    }
}

extension WikidataResults: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bindings = try container.decode([[String: WikidataValue]].self, forKey: .bindings)
    }
}

struct WikidataValue: Sendable {
    let type: String
    let value: String

    enum CodingKeys: String, CodingKey {
        case type, value
    }
}

extension WikidataValue: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        value = try container.decode(String.self, forKey: .value)
    }
}

struct WikidataWatchDTO: Sendable {
    let wikidataID: String
    let displayName: String
    let brand: String?
    let modelNumber: String?
    let inceptionYear: Int?
    let imageURL: String?
    let caseDiameter: Double?
    let waterResistance: Int?
    let caliber: String?

    func toWatchModel() -> WatchModel {
        var model = WatchModel(
            reference: modelNumber ?? wikidataID,
            displayName: displayName,
            productionYearStart: inceptionYear
        )
        model.wikidataID = wikidataID
        model.catalogImageURL = imageURL

        if caseDiameter != nil || waterResistance != nil || caliber != nil {
            var specs = WatchSpecs()
            specs.caseDiameter = caseDiameter
            specs.waterResistance = waterResistance
            if let caliber {
                specs.movement = MovementSpecs(caliber: caliber)
            }
            model.specs = specs
        }

        return model
    }
}

struct WikidataBrandDTO: Sendable {
    let wikidataID: String
    let name: String
    let country: String?
}

enum WikidataError: Error {
    case notFound
    case queryFailed
}
