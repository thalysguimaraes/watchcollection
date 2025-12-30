import Foundation
import Vision
import UIKit

struct OCRHints: Sendable {
    let rawText: String
    let candidateBrands: [String]
    let candidateReferences: [String]
    let confidence: Double

    static var empty: OCRHints {
        OCRHints(rawText: "", candidateBrands: [], candidateReferences: [], confidence: 0)
    }
}

actor WatchOCRService {
    static let shared = WatchOCRService()

    func extractHints(from image: UIImage) async -> OCRHints {
        guard let cgImage = image.cgImage else { return .empty }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.015

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return .empty
        }

        let observations = request.results ?? []
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let rawText = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !rawText.isEmpty else { return .empty }

        let candidateBrands = extractBrands(from: lines)
        let candidateRefs = extractReferences(from: rawText)

        let confidence = observations
            .compactMap { $0.topCandidates(1).first?.confidence }
            .average(default: 0)

        return OCRHints(
            rawText: rawText,
            candidateBrands: candidateBrands,
            candidateReferences: candidateRefs,
            confidence: confidence
        )
    }

    private func extractBrands(from lines: [String]) -> [String] {
        let lowerLines = lines.map { $0.lowercased() }
        let matches = BrandLexicon.known.filter { brand in
            let lower = brand.lowercased()
            return lowerLines.contains(where: { $0.contains(lower) })
        }

        return Array(Set(matches))
    }

    private func extractReferences(from text: String) -> [String] {
        var refs: [String] = []
        if let primary = WatchIdentificationParser.extractReference(from: text) {
            refs.append(primary)
        }

        let tokens = text.components(separatedBy: .whitespacesAndNewlines)
        let pattern = #"^[A-Z0-9-]{3,10}$"#
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        for token in tokens {
            if let regex,
               regex.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)) != nil {
                refs.append(token)
            }
        }

        return Array(Set(refs))
    }
}

private extension Collection where Element == Double {
    func average(default defaultValue: Double) -> Double {
        guard !isEmpty else { return defaultValue }
        let total = reduce(0, +)
        return total / Double(count)
    }
}
