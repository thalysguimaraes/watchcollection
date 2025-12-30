import UIKit

struct IdentificationRun: Sendable {
    let identification: WatchIdentification
    let matches: [IdentificationMatch]
    let context: IdentificationContext
}

struct IdentificationContext: Sendable {
    let processedImage: ProcessedImage
    let ocrHints: OCRHints
    let candidates: [WatchModelWithBrand]
    let baseIdentification: WatchIdentification?
}

@MainActor
final class WatchIdentificationCoordinator {
    private let matcher = CatalogMatcher()

    func identify(image: UIImage) async throws -> IdentificationRun {
        guard let processed = await ImagePreprocessor.shared.process(image) else {
            throw WatchAIError.imageProcessingFailed
        }

        let hints = await WatchOCRService.shared.extractHints(from: processed.processedImage)
        var identification = WatchIdentification(
            brand: hints.candidateBrands.first,
            model: nil,
            reference: hints.candidateReferences.first,
            collection: nil,
            material: nil,
            dialColor: nil,
            complications: [],
            rawDescription: hints.rawText,
            source: "ocr"
        )

        var candidates = try matcher.gatherCandidates(for: identification, hints: hints, limit: 60)

        if let ref = identification.reference?.lowercased(),
           let exact = candidates.first(where: { $0.watchModel.reference.lowercased() == ref || ($0.watchModel.referenceAliases?.contains(where: { $0.lowercased() == ref }) ?? false) }) {
            let match = IdentificationMatch(
                watch: exact,
                confidence: 0.96,
                matchType: .ocr,
                reason: "OCR reference match"
            )
            let context = IdentificationContext(
                processedImage: processed,
                ocrHints: hints,
                candidates: candidates,
                baseIdentification: identification
            )
            return IdentificationRun(identification: identification, matches: [match], context: context)
        }

        let needsWebSearch = candidates.isEmpty
        let aiIdentification = try await WatchAIService.shared.describeWatch(
            imageData: processed.uploadData,
            allowWebSearch: needsWebSearch
        )

        identification = mergeIdentification(primary: aiIdentification, secondary: identification)

        let augmentedCandidates = try matcher.gatherCandidates(for: identification, hints: hints, limit: 80)
        candidates.append(contentsOf: augmentedCandidates)
        candidates = dedupe(candidates)

        let ranked = try await WatchAIService.shared.rankCandidates(
            imageData: processed.uploadData,
            candidates: candidates,
            hints: hints,
            preferredIdentification: identification
        )

        let matches = ranked.matches.isEmpty
            ? matcher.fallbackMatches(from: candidates, identification: ranked.identification, limit: 5)
            : ranked.matches

        let context = IdentificationContext(
            processedImage: processed,
            ocrHints: hints,
            candidates: candidates,
            baseIdentification: ranked.identification
        )

        return IdentificationRun(identification: ranked.identification, matches: matches, context: context)
    }

    func rerun(with identification: WatchIdentification, context: IdentificationContext) async throws -> IdentificationRun {
        var candidates = try matcher.gatherCandidates(for: identification, hints: context.ocrHints, limit: 80)
        candidates.append(contentsOf: context.candidates)
        candidates = dedupe(candidates)

        let ranked = try await WatchAIService.shared.rankCandidates(
            imageData: context.processedImage.uploadData,
            candidates: candidates,
            hints: context.ocrHints,
            preferredIdentification: identification
        )

        let matches = ranked.matches.isEmpty
            ? matcher.fallbackMatches(from: candidates, identification: ranked.identification, limit: 5)
            : ranked.matches

        let newContext = IdentificationContext(
            processedImage: context.processedImage,
            ocrHints: context.ocrHints,
            candidates: candidates,
            baseIdentification: ranked.identification
        )

        return IdentificationRun(identification: ranked.identification, matches: matches, context: newContext)
    }

    private func dedupe(_ candidates: [WatchModelWithBrand]) -> [WatchModelWithBrand] {
        var seen = Set<String>()
        var unique: [WatchModelWithBrand] = []
        for watch in candidates {
            let id = watch.watchModel.id
            if !seen.contains(id) {
                seen.insert(id)
                unique.append(watch)
            }
        }
        return unique
    }

    private func mergeIdentification(primary: WatchIdentification, secondary: WatchIdentification) -> WatchIdentification {
        var merged = primary
        if merged.brand == nil { merged.brand = secondary.brand }
        if merged.model == nil { merged.model = secondary.model }
        if merged.reference == nil { merged.reference = secondary.reference }
        if merged.collection == nil { merged.collection = secondary.collection }
        if merged.material == nil { merged.material = secondary.material }
        if merged.dialColor == nil { merged.dialColor = secondary.dialColor }
        if merged.complications.isEmpty { merged.complications = secondary.complications }
        if merged.rawDescription.isEmpty { merged.rawDescription = secondary.rawDescription }
        return merged
    }
}
