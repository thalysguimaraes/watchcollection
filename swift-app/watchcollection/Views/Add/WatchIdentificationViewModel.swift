import SwiftUI
import Observation

@Observable
@MainActor
final class WatchIdentificationViewModel {
    var state: IdentificationState = .selectSource
    var selectedImage: UIImage?

    private let catalogMatcher = CatalogMatcher()

    var stateKey: String {
        switch state {
        case .selectSource: return "selectSource"
        case .capturing: return "capturing"
        case .analyzing: return "analyzing"
        case .results: return "results"
        case .noMatch: return "noMatch"
        case .error: return "error"
        }
    }

    func selectImage(_ image: UIImage) {
        selectedImage = image
        state = .analyzing
        Task {
            await identifyWatch(image)
        }
    }

    func identifyWatch(_ image: UIImage) async {
        guard let imageData = image.prepareForAI() else {
            Haptics.error()
            state = .error("Failed to process image")
            return
        }

        do {
            let identification = try await WatchAIService.shared.identifyWatch(imageData: imageData)

            let matches = try await catalogMatcher.findMatches(for: identification)

            if matches.isEmpty {
                state = .noMatch(identification: identification)
            } else {
                let watchMatches = matches.map { $0.watch }
                state = .results(matches: watchMatches, identification: identification)
            }

            Haptics.success()
        } catch {
            Haptics.error()
            state = .error(error.localizedDescription)
        }
    }

    func retry() {
        selectedImage = nil
        state = .selectSource
    }

    func cancel() {
        state = .selectSource
    }
}
