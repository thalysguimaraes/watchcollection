import SwiftUI

struct QuickAddToCollectionSheet: View {
    let model: WatchModel
    let brand: Brand?

    @Environment(\.dismiss) private var dismiss
    @Environment(DataRefreshStore.self) private var dataRefreshStore
    @State private var showExpandedDetails = false
    @State private var condition: WatchCondition = .excellent
    @State private var hasBox = false
    @State private var hasPapers = false
    @State private var purchasePrice: Decimal?
    @State private var purchaseCurrency = "USD"
    @State private var purchaseDate: Date = Date()
    @State private var showDatePicker = false
    @State private var serialNumber = ""
    @State private var notes = ""
    @State private var dataService = DataService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    watchPreviewCard
                    quickOptionsSection
                    expandedDetailsSection
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, 100)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Haptics.light()
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                saveButton
            }
        }
        .tint(Theme.Colors.accent)
    }

    private var watchPreviewCard: some View {
        HStack(spacing: Theme.Spacing.lg) {
            AsyncImage(url: URL(string: model.catalogImageURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Image(systemName: "clock.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.Colors.textSecondary.opacity(0.4))
                }
            }
            .frame(width: 80, height: 80)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let brandName = brand?.name {
                    Text(brandName.uppercased())
                        .font(Theme.Typography.sans(.caption, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                        .tracking(1)
                }

                Text(model.displayName)
                    .font(Theme.Typography.heading(.headline))
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Ref. \(model.reference)")
                    .font(Theme.Typography.sans(.caption))
                    .foregroundStyle(Theme.Colors.textSecondary)
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

    private var quickOptionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "star.fill")
                    .foregroundStyle(Theme.Colors.accent)
                Text("Quick Details")
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
                }

                HStack {
                    Text("Papers")
                        .font(Theme.Typography.sans(.body))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Toggle("", isOn: $hasPapers)
                        .toggleStyle(AccentToggleStyle())
                        .labelsHidden()
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

    private var expandedDetailsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Button {
                Haptics.selection()
                withAnimation(Theme.Animation.smooth) {
                    showExpandedDetails.toggle()
                }
            } label: {
                HStack {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(Theme.Colors.accent)
                        Text("More Details")
                            .font(Theme.Typography.heading(.headline))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .rotationEffect(.degrees(showExpandedDetails ? 0 : -90))
                }
            }
            .buttonStyle(.plain)

            if showExpandedDetails {
                VStack(spacing: Theme.Spacing.md) {
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

                        CurrencyTextField(
                            currency: Currency.from(code: purchaseCurrency) ?? .usd,
                            value: $purchasePrice
                        )
                        .font(Theme.Typography.sans(.body))
                        .padding(Theme.Spacing.sm)
                        .background(Theme.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
                    }

                    HStack {
                        Text("Purchase Date")
                            .font(Theme.Typography.sans(.body))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                        DatePicker(
                            "",
                            selection: $purchaseDate,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                    }

                    TextField("Serial Number", text: $serialNumber)
                        .font(Theme.Typography.sans(.body))
                        .padding(Theme.Spacing.sm)
                        .background(Theme.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Notes")
                            .font(Theme.Typography.sans(.subheadline))
                            .foregroundStyle(Theme.Colors.textSecondary)

                        TextEditor(text: $notes)
                            .frame(minHeight: 60)
                            .scrollContentBackground(.hidden)
                            .background(Theme.Colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
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

    private var saveButton: some View {
        Button {
            Haptics.success()
            saveToCollection()
        } label: {
            Text("Add to Collection")
                .font(Theme.Typography.sans(.headline))
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(.ultraThinMaterial)
    }

    private func saveToCollection() {
        var item = CollectionItem(
            catalogWatchId: model.id,
            condition: condition,
            purchaseCurrency: purchaseCurrency
        )

        item.manualBrand = brand?.name
        item.manualModel = model.displayName
        item.manualReference = model.reference
        item.hasBox = hasBox
        item.hasPapers = hasPapers
        item.purchasePriceDecimal = purchasePrice
        item.purchaseDate = purchaseDate
        item.serialNumber = serialNumber.isEmpty ? nil : serialNumber
        item.notes = notes.isEmpty ? nil : notes

        do {
            try dataService.addCollectionItem(item)
            try? dataService.removeFromWishlist(watchModelId: model.id)
            dataRefreshStore.notifyCollectionChanged()
            dataRefreshStore.notifyWishlistChanged()
        } catch {
            print("Failed to save: \(error)")
        }

        dismiss()
    }
}
