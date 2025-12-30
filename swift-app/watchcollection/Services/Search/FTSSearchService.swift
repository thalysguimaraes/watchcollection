import Foundation
import GRDB

final class FTSSearchService: Sendable {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    func search(query: String, limit: Int = 50) throws -> [FTSSearchResult] {
        let normalizedQuery = normalizeQuery(query)
        let tokens = tokenize(normalizedQuery)

        guard !tokens.isEmpty else { return [] }

        var results = try ftsSearch(tokens: tokens, limit: limit)

        if results.count < 5 {
            let fuzzyResults = try fuzzySearch(tokens: tokens, limit: limit, excluding: Set(results.map(\.id)))
            results.append(contentsOf: fuzzyResults)
        }

        return Array(results.prefix(limit))
    }

    private func normalizeQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
            .lowercased()
    }

    private func tokenize(_ query: String) -> [String] {
        var separators = CharacterSet.whitespaces
        separators.insert(charactersIn: "-")
        return query.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && $0.count >= 2 }
    }

    private func ftsSearch(tokens: [String], limit: Int) throws -> [FTSSearchResult] {
        try dbQueue.read { db in
            // Require every token to appear so brand-heavy queries (e.g. "rolex sea dweller")
            // don't return a generic list of Rolex models that push the true match out of the top results.
            let ftsQuery = tokens.map { "\($0)*" }.joined(separator: " AND ")

            let sql = """
                SELECT
                    f.watchModelId,
                    f.brandName,
                    f.displayName,
                    f.reference,
                    f.collection,
                    f.caliber,
                    f.caseMaterial,
                    f.dialColor
                FROM watchModelFTS f
                WHERE watchModelFTS MATCH ?
                ORDER BY
                    CASE
                        WHEN f.reference LIKE ? THEN 0
                        WHEN f.brandName LIKE ? THEN 1
                        WHEN f.displayName LIKE ? THEN 2
                        ELSE 3
                    END,
                    LENGTH(f.reference) ASC,
                    f.displayName
                LIMIT ?
            """

            let firstToken = tokens.first ?? ""
            let likePattern = "\(firstToken)%"

            let rows = try Row.fetchAll(db, sql: sql, arguments: [
                ftsQuery,
                likePattern,
                likePattern,
                likePattern,
                limit
            ])

            return rows.enumerated().map { index, row in
                var result = FTSSearchResult(row: row)
                result.relevanceScore = 100 - index
                return result
            }
        }
    }

    private func fuzzySearch(tokens: [String], limit: Int, excluding: Set<String>) throws -> [FTSSearchResult] {
        try dbQueue.read { db in
            guard let firstToken = tokens.first else { return [] }

            let likePattern = "%\(firstToken)%"

            let sql = """
                SELECT DISTINCT
                    f.watchModelId,
                    f.brandName,
                    f.displayName,
                    f.reference,
                    f.collection,
                    f.caliber,
                    f.caseMaterial,
                    f.dialColor
                FROM watchModelFTS f
                WHERE f.brandName LIKE ?
                   OR f.displayName LIKE ?
                   OR f.reference LIKE ?
                LIMIT 200
            """

            let candidates = try Row.fetchAll(db, sql: sql, arguments: [
                likePattern, likePattern, likePattern
            ])

            return candidates.compactMap { row -> FTSSearchResult? in
                let result = FTSSearchResult(row: row)

                guard !excluding.contains(result.id) else { return nil }

                let searchableText = result.searchableText

                var matchScore = 0
                for token in tokens {
                    if searchableText.contains(token) {
                        matchScore += 10
                    } else {
                        let words = searchableText.components(separatedBy: .whitespaces)
                        let bestFuzzyScore = words.map { $0.fuzzyScore(token) }.max() ?? 0
                        if bestFuzzyScore >= 0.7 {
                            matchScore += Int(bestFuzzyScore * 8)
                        }
                    }
                }

                guard matchScore > 0 else { return nil }

                var scoredResult = result
                scoredResult.relevanceScore = matchScore
                return scoredResult
            }
            .sorted { $0.relevanceScore > $1.relevanceScore }
            .prefix(limit)
            .map { $0 }
        }
    }

    func rebuildIndex() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM watchModelFTS")

            let sql = """
                INSERT INTO watchModelFTS (
                    watchModelId, brandName, displayName, reference,
                    collection, caliber, caseMaterial, dialColor
                )
                SELECT
                    w.id,
                    COALESCE(b.name, ''),
                    w.displayName,
                    w.reference || ' ' || COALESCE(
                        REPLACE(REPLACE(REPLACE(w.referenceAliasesJSON, '["', ''), '"]', ''), '","', ' '),
                        ''
                    ),
                    COALESCE(w.collection, ''),
                    COALESCE(json_extract(w.specsJSON, '$.movement.caliber'), ''),
                    COALESCE(json_extract(w.specsJSON, '$.caseMaterial'), ''),
                    COALESCE(json_extract(w.specsJSON, '$.dialColor'), '')
                FROM watchModel w
                LEFT JOIN brand b ON w.brandId = b.id
            """

            try db.execute(sql: sql)
        }
    }

    func rebuildIndexIfNeeded() throws {
        let needsRebuild = try dbQueue.read { db -> Bool in
            let ftsCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM watchModelFTS") ?? 0
            let watchCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM watchModel") ?? 0
            return watchCount > 0 && ftsCount == 0
        }

        if needsRebuild {
            print("FTS index empty, rebuilding...")
            try rebuildIndex()
            print("FTS index rebuilt successfully")
        }
    }

    func indexWatchModel(_ model: WatchModel, brandName: String?) throws {
        try dbQueue.write { db in
            try updateFTSIndex(db: db, model: model, brandName: brandName)
        }
    }

    func updateFTSIndex(db: Database, model: WatchModel, brandName: String?) throws {
        try db.execute(sql: "DELETE FROM watchModelFTS WHERE watchModelId = ?", arguments: [model.id])

        let specs = model.specs
        let caliber = specs?.movement?.caliber ?? ""
        let caseMaterial = specs?.caseMaterial ?? ""
        let dialColor = specs?.dialColor ?? ""

        var referenceWithAliases = model.reference
        if let aliases = model.referenceAliases, !aliases.isEmpty {
            referenceWithAliases += " " + aliases.joined(separator: " ")
        }

        try db.execute(sql: """
            INSERT INTO watchModelFTS (
                watchModelId, brandName, displayName, reference,
                collection, caliber, caseMaterial, dialColor
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
            model.id,
            brandName ?? "",
            model.displayName,
            referenceWithAliases,
            model.collection ?? "",
            caliber,
            caseMaterial,
            dialColor
        ])
    }

    func removeFromIndex(watchModelId: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM watchModelFTS WHERE watchModelId = ?", arguments: [watchModelId])
        }
    }
}
