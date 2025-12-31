import Foundation

@MainActor
final class CatalogMatcher {
    private let dataService: DataService
    private let claudeMatcher = ClaudeMatcher()

    init(dataService: DataService = DataService()) {
        self.dataService = dataService
    }

    func findMatches(for identification: WatchIdentification, limit: Int = 5) async throws -> [IdentificationMatch] {
        let candidates = try gatherCandidates(for: identification, hints: nil, limit: limit * 3)

        guard !candidates.isEmpty else {
            return []
        }

        do {
            let claudeMatches = try await claudeMatcher.matchToCatalog(
                identification: identification,
                candidates: candidates
            )

            if !claudeMatches.isEmpty {
                return Array(claudeMatches.prefix(limit))
            }
        } catch {
            print("Claude matcher failed: \(error), falling back to FTS")
        }

        return fallbackMatches(from: candidates, identification: identification, limit: limit)
    }

    func gatherCandidates(for identification: WatchIdentification, hints: OCRHints?, limit: Int = 40) throws -> [WatchModelWithBrand] {
        var allCandidates: [WatchModelWithBrand] = []
        let normalizedBrand = identification.brand?.lowercased()

        if let hints {
            for ref in hints.candidateReferences {
                let refResults = try dataService.searchCatalogFTS(query: ref)
                allCandidates.append(contentsOf: refResults)
            }

            for brand in hints.candidateBrands {
                let brandResults = try dataService.searchCatalogFTS(query: brand)
                allCandidates.append(contentsOf: brandResults)
            }
        }

        if let reference = identification.reference {
            let refResults = try dataService.searchCatalogFTS(query: reference)
            if let brand = normalizedBrand {
                let brandFiltered = refResults.filter { $0.brand?.name.lowercased() == brand }
                allCandidates.append(contentsOf: brandFiltered)
                if brandFiltered.isEmpty {
                    allCandidates.append(contentsOf: refResults)
                }
            } else {
                allCandidates.append(contentsOf: refResults)
            }
        }

        if let brand = identification.brand {
            let brandResults = try dataService.searchCatalogFTS(query: brand)
            let filtered = brandResults.filter { $0.brand?.name.lowercased() == normalizedBrand }
            allCandidates.append(contentsOf: filtered)
        }

        if let model = identification.model {
            let modelQuery = [identification.brand, model].compactMap { $0 }.joined(separator: " ")
            let modelResults = try dataService.searchCatalogFTS(query: modelQuery)
            if let brand = normalizedBrand {
                let brandFiltered = modelResults.filter { $0.brand?.name.lowercased() == brand }
                allCandidates.append(contentsOf: brandFiltered)
            } else {
                allCandidates.append(contentsOf: modelResults)
            }
        }

        var seen = Set<String>()
        return allCandidates.filter { watch in
            let id = watch.watchModel.id
            if seen.contains(id) { return false }
            seen.insert(id)
            return true
        }.prefix(limit).map { $0 }
    }

    func fallbackMatches(
        from candidates: [WatchModelWithBrand],
        identification: WatchIdentification,
        limit: Int
    ) -> [IdentificationMatch] {
        let normalizedBrand = identification.brand?.lowercased()
        let normalizedRef = identification.reference?.lowercased()
        let normalizedModel = identification.model?.lowercased()
        let modelKeywords = extractModelKeywords(from: normalizedModel)

        let scored = candidates.map { watch -> (WatchModelWithBrand, Double) in
            var score = 0.1
            let watchName = watch.watchModel.displayName.lowercased()
            let watchCollection = watch.watchModel.collection?.lowercased()

            if let brand = normalizedBrand,
               watch.brand?.name.lowercased() == brand {
                score += 0.15
            }

            if let ref = normalizedRef {
                if watch.watchModel.reference.lowercased() == ref {
                    score += 0.35
                } else if watch.watchModel.referenceAliases?.contains(where: { $0.lowercased() == ref }) == true {
                    score += 0.35
                } else if watch.watchModel.reference.lowercased().contains(ref) ||
                          ref.contains(watch.watchModel.reference.lowercased()) {
                    score += 0.1
                }
            }

            for keyword in modelKeywords {
                if watchName.contains(keyword) || watchCollection?.contains(keyword) == true {
                    score += 0.25
                }
            }

            if let model = normalizedModel {
                if watchName.contains(model) || watchCollection?.contains(model) == true {
                    score += 0.3
                }
            }

            return (watch, min(0.95, score))
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { IdentificationMatch(watch: $0.0, confidence: $0.1, matchType: .brandModel, reason: "FTS similarity \(String(format: "%.0f", $0.1 * 100))%") }
    }

    private func extractModelKeywords(from model: String?) -> [String] {
        guard let model = model else { return [] }
        let stopWords = Set(["de", "the", "a", "an", "of", "cartier", "rolex", "omega", "tudor", "patek", "philippe"])
        return model.components(separatedBy: .whitespaces)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }
}
