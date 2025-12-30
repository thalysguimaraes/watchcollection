import SwiftUI

struct EditWatchSheet: View {
    let item: CollectionItem

    @Environment(\.dismiss) private var dismiss
    @Environment(DataRefreshStore.self) private var dataRefreshStore

    @State private var condition: WatchCondition
    @State private var hasBox: Bool
    @State private var hasPapers: Bool
    @State private var hasWarrantyCard: Bool
    @State private var serialNumber: String
    @State private var purchasePrice: Decimal?
    @State private var purchaseCurrency: String
    @State private var purchaseDate: Date?
    @State private var showDatePicker: Bool
    @State private var purchaseSource: String
    @State private var currentEstimatedValue: Decimal?
    @State private var notes: String
    @State private var dataService = DataService()

    init(item: CollectionItem) {
        self.item = item
        _condition = State(initialValue: item.condition)
        _hasBox = State(initialValue: item.hasBox)
        _hasPapers = State(initialValue: item.hasPapers)
        _hasWarrantyCard = State(initialValue: item.hasWarrantyCard)
        _serialNumber = State(initialValue: item.serialNumber ?? "")
        _purchasePrice = State(initialValue: item.purchasePriceDecimal)
        _purchaseCurrency = State(initialValue: item.purchaseCurrency)
        _purchaseDate = State(initialValue: item.purchaseDate)
        _showDatePicker = State(initialValue: item.purchaseDate != nil)
        _purchaseSource = State(initialValue: item.purchaseSource ?? "")
        _currentEstimatedValue = State(initialValue: item.currentEstimatedValueDecimal)
        _notes = State(initialValue: item.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    watchPreviewCard
                    conditionSection
                    purchaseDetailsSection
                    notesSection
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxxl)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Edit Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Haptics.light()
                        dismiss()
                    }
                    .accessibilityIdentifier("editWatch.cancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Haptics.success()
                        saveChanges()
                    }
                    .font(Theme.Typography.sans(.body, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityIdentifier("editWatch.saveButton")
                }
            }
        }
        .tint(Theme.Colors.accent)
    }

    private var watchPreviewCard: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "clock.fill")
                .font(.system(size: 30))
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.4))
                .frame(width: 70, height: 70)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let brand = item.manualBrand, !brand.isEmpty {
                    Text(brand.uppercased())
                        .font(Theme.Typography.sans(.caption, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                        .tracking(1)
                }

                Text(item.manualModel ?? "Unknown Watch")
                    .font(Theme.Typography.heading(.headline))
                    .foregroundStyle(Theme.Colors.textPrimary)

                if let ref = item.manualReference {
                    Text("Ref. \(ref)")
                        .font(Theme.Typography.sans(.caption))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .shadow(
            color: .black.opacity(Theme.Shadow.cardOpacity),
            radius: Theme.Shadow.cardRadius,
            y: Theme.Shadow.cardY
        )
    }

    private var conditionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "star.fill")
                    .foregroundStyle(Theme.Colors.accent)
                Text("Condition & Completeness")
                    .font(Theme.Typography.heading(.headline))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            VStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Condition")
                        .font(Theme.Typography.sans(.subheadline))
                        .foregroundStyle(Theme.Colors.textSecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(WatchCondition.allCases, id: \.self) { cond in
                                ConditionChip(
                                    condition: cond,
                                    isSelected: condition == cond
                                ) {
                                    Haptics.selection()
                                    condition = cond
                                }
                                .accessibilityIdentifier("editWatch.condition.\(cond.abbreviation)")
                            }
                        }
                    }
                }

                Divider()

                HStack {
                    Text("Box")
                        .font(Theme.Typography.sans(.body))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Toggle("", isOn: $hasBox)
                        .toggleStyle(AccentToggleStyle())
                        .labelsHidden()
                        .accessibilityIdentifier("editWatch.hasBoxToggle")
                }

                HStack {
                    Text("Papers")
                        .font(Theme.Typography.sans(.body))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Toggle("", isOn: $hasPapers)
                        .toggleStyle(AccentToggleStyle())
                        .labelsHidden()
                        .accessibilityIdentifier("editWatch.hasPapersToggle")
                }

                HStack {
                    Text("Warranty Card")
                        .font(Theme.Typography.sans(.body))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Toggle("", isOn: $hasWarrantyCard)
                        .toggleStyle(AccentToggleStyle())
                        .labelsHidden()
                        .accessibilityIdentifier("editWatch.hasWarrantyToggle")
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .shadow(
            color: .black.opacity(Theme.Shadow.cardOpacity),
            radius: Theme.Shadow.cardRadius,
            y: Theme.Shadow.cardY
        )
    }

    private var purchaseDetailsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(Theme.Colors.accent)
                Text("Purchase Details")
                    .font(Theme.Typography.heading(.headline))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            VStack(spacing: Theme.Spacing.md) {
                TextField("Serial Number", text: $serialNumber)
                    .font(Theme.Typography.sans(.body))
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
                    .accessibilityIdentifier("editWatch.serialNumberField")

                HStack(spacing: Theme.Spacing.md) {
                    Menu {
                        ForEach(Currency.all) { currency in
                            Button {
                                Haptics.selection()
                                purchaseCurrency = currency.code
                            } label: {
                                HStack {
                                    Text("\(currency.flag) \(currency.code)")
                                    if purchaseCurrency == currency.code {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(Currency.from(code: purchaseCurrency)?.flag ?? "")
                            Text(purchaseCurrency)
                                .fontWeight(.medium)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(Theme.Spacing.sm)
                        .background(Theme.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
                    }
                    .accessibilityIdentifier("editWatch.currencyMenu")

                    CurrencyTextField(
                        currency: Currency.from(code: purchaseCurrency) ?? .usd,
                        value: $purchasePrice
                    )
                    .font(Theme.Typography.sans(.body))
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
                    .accessibilityIdentifier("editWatch.purchasePriceField")
                }

                HStack {
                    Text("Purchase Date")
                        .font(Theme.Typography.sans(.body))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    if showDatePicker {
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { purchaseDate ?? Date() },
                                set: { purchaseDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .accessibilityIdentifier("editWatch.purchaseDatePicker")

                        Button {
                            Haptics.light()
                            showDatePicker = false
                            purchaseDate = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    } else {
                        Button {
                            Haptics.selection()
                            showDatePicker = true
                            purchaseDate = Date()
                        } label: {
                            Text("Add Date")
                                .font(Theme.Typography.sans(.body))
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                }

                TextField("Purchase Source (e.g., AD, Grey Market)", text: $purchaseSource)
                    .font(Theme.Typography.sans(.body))
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
                    .accessibilityIdentifier("editWatch.purchaseSourceField")

                Divider()

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Current Estimated Value")
                        .font(Theme.Typography.sans(.subheadline))
                        .foregroundStyle(Theme.Colors.textSecondary)

                    CurrencyTextField(
                        currency: Currency.from(code: purchaseCurrency) ?? .usd,
                        value: $currentEstimatedValue
                    )
                    .font(Theme.Typography.sans(.body))
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
                    .accessibilityIdentifier("editWatch.currentValueField")
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .shadow(
            color: .black.opacity(Theme.Shadow.cardOpacity),
            radius: Theme.Shadow.cardRadius,
            y: Theme.Shadow.cardY
        )
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "note.text")
                    .foregroundStyle(Theme.Colors.accent)
                Text("Notes")
                    .font(Theme.Typography.heading(.headline))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            TextEditor(text: $notes)
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button)
                        .stroke(Theme.Colors.divider, lineWidth: 1)
                )
                .accessibilityIdentifier("editWatch.notesField")
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .shadow(
            color: .black.opacity(Theme.Shadow.cardOpacity),
            radius: Theme.Shadow.cardRadius,
            y: Theme.Shadow.cardY
        )
    }

    private func saveChanges() {
        var updatedItem = item
        updatedItem.condition = condition
        updatedItem.hasBox = hasBox
        updatedItem.hasPapers = hasPapers
        updatedItem.hasWarrantyCard = hasWarrantyCard
        updatedItem.serialNumber = serialNumber.isEmpty ? nil : serialNumber
        updatedItem.purchasePriceDecimal = purchasePrice
        updatedItem.purchaseCurrency = purchaseCurrency
        updatedItem.purchaseDate = purchaseDate
        updatedItem.purchaseSource = purchaseSource.isEmpty ? nil : purchaseSource
        updatedItem.currentEstimatedValueDecimal = currentEstimatedValue
        updatedItem.notes = notes.isEmpty ? nil : notes

        do {
            try dataService.updateCollectionItem(updatedItem)
            dataRefreshStore.notifyCollectionChanged()
        } catch {
            print("Failed to save: \(error)")
        }

        dismiss()
    }
}
