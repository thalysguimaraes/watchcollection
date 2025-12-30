import SwiftUI
import Testing
import ViewInspector
@testable import watchcollection

@MainActor
@Suite("EditWatchSheet tests")
struct EditWatchSheetTests {
    private func makeTestItem() -> CollectionItem {
        var item = CollectionItem(condition: .excellent)
        item.manualBrand = "Omega"
        item.manualModel = "Speedmaster Reduced"
        item.manualReference = "3510.50"
        item.serialNumber = "12345678"
        item.hasBox = true
        item.hasPapers = true
        item.hasWarrantyCard = false
        item.purchasePrice = "3500"
        item.purchaseCurrency = "USD"
        item.purchaseDate = Date()
        item.notes = "Test notes"
        return item
    }

    @Test
    func editWatchSheetDisplaysBrandName() throws {
        let item = makeTestItem()
        let sut = EditWatchSheet(item: item)
            .environment(DataRefreshStore())

        let brandText = try sut.inspect().find(ViewType.Text.self) { text in
            try text.string() == "OMEGA"
        }
        #expect(try brandText.string() == "OMEGA")
    }

    @Test
    func editWatchSheetDisplaysModelName() throws {
        let item = makeTestItem()
        let sut = EditWatchSheet(item: item)
            .environment(DataRefreshStore())

        let modelText = try sut.inspect().find(ViewType.Text.self) { text in
            try text.string() == "Speedmaster Reduced"
        }
        #expect(try modelText.string() == "Speedmaster Reduced")
    }

    @Test
    func editWatchSheetDisplaysReference() throws {
        let item = makeTestItem()
        let sut = EditWatchSheet(item: item)
            .environment(DataRefreshStore())

        let refText = try sut.inspect().find(ViewType.Text.self) { text in
            try text.string() == "Ref. 3510.50"
        }
        #expect(try refText.string() == "Ref. 3510.50")
    }

    @Test
    func editWatchSheetHasCancelButton() throws {
        let item = makeTestItem()
        let sut = EditWatchSheet(item: item)
            .environment(DataRefreshStore())

        #expect(throws: Never.self) {
            _ = try sut.inspect().find(ViewType.Button.self) { button in
                try button.labelView().text().string() == "Cancel"
            }
        }
    }

    @Test
    func editWatchSheetHasSaveButton() throws {
        let item = makeTestItem()
        let sut = EditWatchSheet(item: item)
            .environment(DataRefreshStore())

        #expect(throws: Never.self) {
            _ = try sut.inspect().find(ViewType.Button.self) { button in
                try button.labelView().text().string() == "Save"
            }
        }
    }

    @Test
    func editWatchSheetDisplaysConditionLabel() throws {
        let item = makeTestItem()
        let sut = EditWatchSheet(item: item)
            .environment(DataRefreshStore())

        let conditionLabel = try sut.inspect().find(ViewType.Text.self) { text in
            try text.string() == "Condition"
        }
        #expect(try conditionLabel.string() == "Condition")
    }

    @Test
    func editWatchSheetDisplaysNotesSection() throws {
        let item = makeTestItem()
        let sut = EditWatchSheet(item: item)
            .environment(DataRefreshStore())

        let notesLabel = try sut.inspect().find(ViewType.Text.self) { text in
            try text.string() == "Notes"
        }
        #expect(try notesLabel.string() == "Notes")
    }
}
