import SwiftUI
import Testing
import SnapshotTesting
@testable import watchcollection

private let recordSnapshots = false

@MainActor
@Suite("Snapshots")
struct SnapshotTests {
    @Test
    func statCard_iPhone13Pro() throws {
        let sut = StatCard(value: "9.5", label: "Condition", icon: "star.fill", color: .yellow)
        let hosting = UIHostingController(rootView: sut.frame(width: 220))
        assertSnapshot(of: hosting, as: .image(on: .iPhone13Pro), record: recordSnapshots)
    }

    @Test
    func editWatchSheet_iPhone13Pro() throws {
        var item = CollectionItem(condition: .excellent)
        item.manualBrand = "Omega"
        item.manualModel = "Speedmaster Reduced"
        item.manualReference = "3510.50"
        item.serialNumber = "12345678"
        item.hasBox = true
        item.hasPapers = true
        item.purchasePrice = "3500"
        item.purchaseCurrency = "USD"
        item.notes = "Minor desk diving marks on clasp"

        let sut = EditWatchSheet(item: item)
            .environment(DataRefreshStore())
        let hosting = UIHostingController(rootView: sut)
        assertSnapshot(of: hosting, as: .image(on: .iPhone13Pro), record: recordSnapshots)
    }
}
