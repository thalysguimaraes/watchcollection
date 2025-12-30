import Foundation
import UIKit

struct EvalCase: Codable, Sendable {
    let id: String
    let imagePath: String
    let expectedBrand: String
    let expectedReference: String
}

struct EvalResult: Sendable {
    let id: String
    let expectedReference: String
    let predictedReference: String?
    let expectedBrand: String
    let predictedBrand: String?
    let topConfidence: Double?
    let success: Bool
}

actor OfflineEvalRunner {
    private let coordinator = WatchIdentificationCoordinator()

    func runAll(from path: String = "swift-app/watchcollection/Evaluation/evalset.json") async -> [EvalResult] {
        guard let data = FileManager.default.contents(atPath: path),
              let cases = try? JSONDecoder().decode([EvalCase].self, from: data) else {
            return []
        }

        var results: [EvalResult] = []
        for evalCase in cases {
            if let image = UIImage(contentsOfFile: evalCase.imagePath) {
                if let run = try? await coordinator.identify(image: image) {
                    let top = run.matches.first
                    let result = EvalResult(
                        id: evalCase.id,
                        expectedReference: evalCase.expectedReference,
                        predictedReference: run.identification.reference,
                        expectedBrand: evalCase.expectedBrand,
                        predictedBrand: run.identification.brand,
                        topConfidence: top?.confidence,
                        success: run.identification.reference?.lowercased() == evalCase.expectedReference.lowercased()
                    )
                    results.append(result)
                }
            }
        }
        return results
    }
}
