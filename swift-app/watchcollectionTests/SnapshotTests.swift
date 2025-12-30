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
}
