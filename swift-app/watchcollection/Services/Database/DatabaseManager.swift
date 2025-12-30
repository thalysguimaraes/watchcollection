import GRDB
import Foundation

final class DatabaseManager: Sendable {
    static let shared = DatabaseManager()

    let dbQueue: DatabaseQueue

    private init() {
        do {
            let fileManager = FileManager.default
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbURL = appSupport.appendingPathComponent("watchcollection.sqlite")

            var config = Configuration()
            config.foreignKeysEnabled = true
            config.readonly = false

            dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)
            try migrator.migrate(dbQueue)
        } catch {
            fatalError("Database initialization failed: \(error)")
        }
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1") { db in
            try db.create(table: "brand") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull().indexed()
                t.column("country", .text)
                t.column("logoURL", .text)
            }

            try db.create(table: "watchModel") { t in
                t.column("id", .text).primaryKey()
                t.column("reference", .text).notNull().indexed()
                t.column("displayName", .text).notNull().indexed()
                t.column("collection", .text)
                t.column("productionYearStart", .integer)
                t.column("productionYearEnd", .integer)
                t.column("specsJSON", .text)
                t.column("catalogImageURL", .text)
                t.column("wikidataID", .text)
                t.column("watchbaseID", .text)
                t.column("lastUpdated", .datetime).notNull()
                t.column("marketPriceMin", .integer)
                t.column("marketPriceMax", .integer)
                t.column("marketPriceMedian", .integer)
                t.column("marketPriceListings", .integer)
                t.column("marketPriceUpdatedAt", .datetime)
                t.column("brandId", .text).references("brand", onDelete: .setNull)
            }

            try db.create(table: "collectionItem") { t in
                t.column("id", .text).primaryKey()
                t.column("catalogWatchId", .text).references("watchModel", onDelete: .setNull)
                t.column("manualBrand", .text)
                t.column("manualModel", .text)
                t.column("manualReference", .text)
                t.column("serialNumber", .text)
                t.column("condition", .text).notNull()
                t.column("hasBox", .boolean).notNull().defaults(to: false)
                t.column("hasPapers", .boolean).notNull().defaults(to: false)
                t.column("hasWarrantyCard", .boolean).notNull().defaults(to: false)
                t.column("purchasePrice", .text)
                t.column("purchaseCurrency", .text).notNull().defaults(to: "USD")
                t.column("purchaseDate", .datetime)
                t.column("purchaseSource", .text)
                t.column("currentEstimatedValue", .text)
                t.column("lastValuationDate", .datetime)
                t.column("notes", .text)
                t.column("dateAdded", .datetime).notNull()
                t.column("lastModified", .datetime).notNull()
            }

            try db.create(table: "watchPhoto") { t in
                t.column("id", .text).primaryKey()
                t.column("imageData", .blob)
                t.column("thumbnailData", .blob)
                t.column("caption", .text)
                t.column("photoType", .text).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("dateAdded", .datetime).notNull()
                t.column("collectionItemId", .text).references("collectionItem", onDelete: .cascade)
            }

            try db.create(table: "priceRecord") { t in
                t.column("id", .text).primaryKey()
                t.column("price", .text).notNull()
                t.column("currency", .text).notNull()
                t.column("source", .text).notNull()
                t.column("condition", .text)
                t.column("hasBox", .boolean)
                t.column("hasPapers", .boolean)
                t.column("recordDate", .datetime).notNull()
                t.column("sourceURL", .text)
                t.column("watchModelId", .text).references("watchModel", onDelete: .cascade)
            }

            try db.create(index: "watchModel_brandId", on: "watchModel", columns: ["brandId"])
            try db.create(index: "collectionItem_catalogWatchId", on: "collectionItem", columns: ["catalogWatchId"])
            try db.create(index: "watchPhoto_collectionItemId", on: "watchPhoto", columns: ["collectionItemId"])
            try db.create(index: "priceRecord_watchModelId", on: "priceRecord", columns: ["watchModelId"])
        }

        migrator.registerMigration("v2_fts_search") { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE watchModelFTS USING fts4(
                    watchModelId,
                    brandName,
                    displayName,
                    reference,
                    collection,
                    caliber,
                    caseMaterial,
                    dialColor,
                    tokenize=porter
                )
            """)

            try db.execute(sql: """
                INSERT INTO watchModelFTS (
                    watchModelId, brandName, displayName, reference,
                    collection, caliber, caseMaterial, dialColor
                )
                SELECT
                    w.id,
                    COALESCE(b.name, ''),
                    w.displayName,
                    w.reference,
                    COALESCE(w.collection, ''),
                    COALESCE(json_extract(w.specsJSON, '$.movement.caliber'), ''),
                    COALESCE(json_extract(w.specsJSON, '$.caseMaterial'), ''),
                    COALESCE(json_extract(w.specsJSON, '$.dialColor'), '')
                FROM watchModel w
                LEFT JOIN brand b ON w.brandId = b.id
            """)
        }

        migrator.registerMigration("v3_watchcharts") { db in
            try db.alter(table: "watchModel") { t in
                t.add(column: "watchchartsId", .text)
                t.add(column: "watchchartsUrl", .text)
                t.add(column: "isCurrent", .boolean)
            }
        }

        migrator.registerMigration("v4_retail_price") { db in
            try db.alter(table: "watchModel") { t in
                t.add(column: "retailPriceUSD", .integer)
            }
        }

        migrator.registerMigration("v5_wishlist") { db in
            try db.create(table: "wishlistItem") { t in
                t.column("id", .text).primaryKey()
                t.column("watchModelId", .text).notNull().references("watchModel", onDelete: .cascade)
                t.column("priority", .text).notNull().defaults(to: "medium")
                t.column("targetPrice", .text)
                t.column("targetCurrency", .text).notNull().defaults(to: "USD")
                t.column("notes", .text)
                t.column("dateAdded", .datetime).notNull()
                t.column("notifyOnPriceDrop", .boolean).notNull().defaults(to: false)
            }

            try db.create(index: "wishlistItem_watchModelId", on: "wishlistItem", columns: ["watchModelId"])
        }

        migrator.registerMigration("v6_price_history") { db in
            try db.alter(table: "watchModel") { t in
                t.add(column: "priceHistoryJSON", .text)
                t.add(column: "priceHistorySource", .text)
            }
        }

        migrator.registerMigration("v7_reference_aliases") { db in
            try db.alter(table: "watchModel") { t in
                t.add(column: "referenceAliasesJSON", .text)
            }
        }

        return migrator
    }
}
