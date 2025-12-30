import SwiftUI
import Observation

@Observable
@MainActor
final class WatchIdentificationViewModel {
    var state: IdentificationState = .selectSource
    var selectedImage: UIImage?
    private var lastContext: IdentificationContext?
    private let coordinator = WatchIdentificationCoordinator()
    private let feedbackStore = IdentificationFeedbackStore()

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
        do {
            let run = try await coordinator.identify(image: image)

            lastContext = run.context
            state = run.matches.isEmpty ? .noMatch(identification: run.identification) : .results(matches: run.matches, identification: run.identification)

            Haptics.success()
        } catch {
            Haptics.error()
            state = .error(error.localizedDescription)
        }
    }

    func refineMatches(with identification: WatchIdentification) {
        guard let context = lastContext else { return }
        state = .analyzing
        Task {
            do {
                let run = try await coordinator.rerun(with: identification, context: context)
                lastContext = run.context
                state = run.matches.isEmpty ? .noMatch(identification: run.identification) : .results(matches: run.matches, identification: run.identification)
                Haptics.success()
            } catch {
                Haptics.error()
                state = .error(error.localizedDescription)
            }
        }
    }

    func recordSelection(_ match: IdentificationMatch, identification: WatchIdentification) {
        guard let context = lastContext else { return }
        feedbackStore.recordSelection(match: match, identification: identification, imageKey: context.processedImage.cacheKey)
    }

    func retry() {
        selectedImage = nil
        state = .selectSource
        lastContext = nil
    }

    func cancel() {
        state = .selectSource
    }
}
