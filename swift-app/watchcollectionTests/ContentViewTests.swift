import SwiftUI
import Testing
import ViewInspector
@testable import watchcollection

@MainActor
@Suite("SwiftUI smoke tests")
struct SwiftUISmokeTests {
    @Test
    func contentViewEmbedsMainTab() throws {
        let sut = ContentView()
        #expect(throws: Never.self) {
            _ = try sut.inspect().find(MainTabView.self)
        }
    }

    @Test
    func statCardDisplaysValueAndLabel() throws {
        let sut = StatCard(value: "25", label: "Watches", icon: "clock", color: .blue)
        let valueText = try sut.inspect().find(ViewType.Text.self) { try $0.string() == "25" }
        let labelText = try sut.inspect().find(ViewType.Text.self) { try $0.string() == "Watches" }

        #expect(try valueText.string() == "25")
        #expect(try labelText.string() == "Watches")
    }
}
