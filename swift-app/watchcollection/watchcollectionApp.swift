import SwiftUI

@main
struct watchcollectionApp: App {
    init() {
        _ = DatabaseManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    startCatalogImport()
                }
        }
    }

    private func startCatalogImport() {
        Task(priority: .utility) {
            let importer = CatalogImporter()
            do {
                try await importer.importCatalogIfNeeded()
            } catch {
                print("Catalog import failed: \(error)")
            }

            let ftsService = FTSSearchService()
            do {
                try ftsService.rebuildIndexIfNeeded()
            } catch {
                print("FTS index rebuild failed: \(error)")
            }
        }
    }
}
