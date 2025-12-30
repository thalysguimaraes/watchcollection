import Foundation

struct IdentificationFeedbackEntry: Codable, Sendable {
    let id: UUID
    let watchId: String
    let brand: String?
    let reference: String?
    let confidence: Double
    let reason: String?
    let imageKey: String
    let recordedAt: Date
}

actor IdentificationFeedbackStore {
    private let storageKey = "WatchIdentificationFeedback"
    private let maxEntries = 200

    func recordSelection(match: IdentificationMatch, identification: WatchIdentification, imageKey: String) {
        var entries = load()
        let entry = IdentificationFeedbackEntry(
            id: UUID(),
            watchId: match.watch.watchModel.id,
            brand: identification.brand,
            reference: identification.reference,
            confidence: match.confidence,
            reason: match.reason,
            imageKey: imageKey,
            recordedAt: Date()
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        persist(entries)
    }

    func load() -> [IdentificationFeedbackEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([IdentificationFeedbackEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    private func persist(_ entries: [IdentificationFeedbackEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
