import Foundation

private let iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

struct CatalogResponse: Codable {
    let version: String
    let brands: [CatalogBrandDTO]
}

struct CatalogBrandDTO: Codable {
    let id: String
    let name: String
    let country: String?
    let tier: String?
    let models: [CatalogModelDTO]
}

struct MarketPriceDTO: Codable {
    let minUsd: Int?
    let maxUsd: Int?
    let medianUsd: Int?
    let listings: Int?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case minUsd = "min_usd"
        case maxUsd = "max_usd"
        case medianUsd = "median_usd"
        case listings
        case updatedAt = "updated_at"
    }
}

struct MarketPriceHistoryDTO: Codable {
    let source: String?
    let points: [[Double]]?
}

struct CaseInfoDTO: Codable {
    let diameterMm: Double?
    let thicknessMm: Double?
    let material: String?
    let bezelMaterial: String?
    let crystal: String?
    let waterResistanceM: Int?
    let lugWidthMm: Double?
    let dialColor: String?
    let dialNumerals: String?

    enum CodingKeys: String, CodingKey {
        case diameterMm = "diameter_mm"
        case thicknessMm = "thickness_mm"
        case material
        case bezelMaterial = "bezel_material"
        case crystal
        case waterResistanceM = "water_resistance_m"
        case lugWidthMm = "lug_width_mm"
        case dialColor = "dial_color"
        case dialNumerals = "dial_numerals"
    }
}

struct MovementInfoDTO: Codable {
    let type: String?
    let caliber: String?
    let powerReserveHours: Int?
    let frequencyBph: Int?
    let jewelsCount: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case caliber
        case powerReserveHours = "power_reserve_hours"
        case frequencyBph = "frequency_bph"
        case jewelsCount = "jewels_count"
    }
}

struct CatalogModelDTO: Codable {
    let reference: String
    let referenceAliases: [String]?
    let displayName: String
    let collection: String?
    let style: String?
    let productionYearStart: Int?
    let productionYearEnd: Int?
    let caseInfo: CaseInfoDTO?
    let movement: MovementInfoDTO?
    let complications: [String]?
    let features: [String]?
    let retailPriceUsd: Int?
    let catalogImageUrl: String?
    let marketPrice: MarketPriceDTO?
    let marketPriceHistory: MarketPriceHistoryDTO?
    let watchchartsId: String?
    let watchchartsUrl: String?
    let isCurrent: Bool?

    enum CodingKeys: String, CodingKey {
        case reference
        case referenceAliases = "reference_aliases"
        case displayName = "display_name"
        case collection
        case style
        case productionYearStart = "production_year_start"
        case productionYearEnd = "production_year_end"
        case caseInfo = "case"
        case movement
        case complications
        case features
        case retailPriceUsd = "retail_price_usd"
        case catalogImageUrl = "catalog_image_url"
        case marketPrice = "market_price"
        case marketPriceHistory = "market_price_history"
        case watchchartsId = "watchcharts_id"
        case watchchartsUrl = "watchcharts_url"
        case isCurrent = "is_current"
    }

    func toWatchModel() -> WatchModel {
        var model = WatchModel(
            reference: reference,
            displayName: displayName,
            collection: collection,
            productionYearStart: productionYearStart,
            productionYearEnd: productionYearEnd
        )

        model.catalogImageURL = catalogImageUrl
        model.watchchartsId = watchchartsId
        model.watchchartsUrl = watchchartsUrl
        model.isCurrent = isCurrent
        model.retailPriceUSD = retailPriceUsd
        model.referenceAliases = referenceAliases

        if let price = marketPrice {
            model.marketPriceMin = price.minUsd
            model.marketPriceMax = price.maxUsd
            model.marketPriceMedian = price.medianUsd
            model.marketPriceListings = price.listings
            if let updatedAt = price.updatedAt {
                model.marketPriceUpdatedAt = iso8601Formatter.date(from: updatedAt)
            }
        }

        var specs = WatchSpecs()
        var hasSpecs = false

        if let caseInfo {
            specs.caseDiameter = caseInfo.diameterMm
            specs.caseThickness = caseInfo.thicknessMm
            specs.caseMaterial = caseInfo.material
            specs.bezelMaterial = caseInfo.bezelMaterial
            specs.crystalType = caseInfo.crystal
            specs.waterResistance = caseInfo.waterResistanceM
            specs.lugWidth = caseInfo.lugWidthMm
            specs.dialColor = caseInfo.dialColor
            specs.dialNumerals = caseInfo.dialNumerals
            hasSpecs = true
        }

        if let movementInfo = movement {
            var movementSpecs = MovementSpecs()
            movementSpecs.caliber = movementInfo.caliber
            movementSpecs.type = MovementType.from(rawValue: movementInfo.type)
            movementSpecs.powerReserve = movementInfo.powerReserveHours
            if let bph = movementInfo.frequencyBph {
                movementSpecs.frequency = Double(bph)
            }
            movementSpecs.jewelsCount = movementInfo.jewelsCount
            specs.movement = movementSpecs
            hasSpecs = true
        }

        if let complications, !complications.isEmpty {
            specs.complications = complications
            hasSpecs = true
        }

        if let features, !features.isEmpty {
            specs.features = features
            hasSpecs = true
        }

        if let style {
            specs.style = style
            hasSpecs = true
        }

        if hasSpecs {
            model.specs = specs
        }

        if let history = marketPriceHistory, let points = history.points, !points.isEmpty {
            if let data = try? JSONEncoder().encode(points) {
                model.priceHistoryJSON = String(data: data, encoding: .utf8)
            }
            model.priceHistorySource = history.source
        }

        return model
    }
}

extension MovementType {
    static func from(rawValue: String?) -> MovementType? {
        guard let rawValue else { return nil }
        switch rawValue.lowercased() {
        case "automatic":
            return .automatic
        case "manual", "manual wind":
            return .manual
        case "quartz":
            return .quartz
        case "spring drive", "springdrive":
            return .springDrive
        case "solar":
            return .solar
        case "kinetic":
            return .kinetic
        default:
            return nil
        }
    }
}
