import SwiftUI

struct AddWatchFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataRefreshStore.self) private var dataRefreshStore
    @State private var step: AddWatchStep = .search
    @State private var viewModel = AddWatchViewModel()
    @State private var dataService = DataService()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    StepIndicator(currentStep: step)
                        .padding(.top, Theme.Spacing.sm)
                        .padding(.bottom, Theme.Spacing.md)

                    Group {
                        switch step {
                        case .search:
                            CatalogSearchStep(viewModel: $viewModel) {
                                Haptics.medium()
                                withAnimation(Theme.Animation.smooth) {
                                    step = .quickDetails
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                        case .quickDetails:
                            QuickDetailsStep(viewModel: $viewModel) {
                                Haptics.success()
                                saveWatch()
                            }
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                        }
                    }
                }
            }
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Haptics.light()
                        dismiss()
                    }
                    .accessibilityIdentifier("addWatch.cancelButton")
                    .foregroundStyle(Theme.Colors.textSecondary)
                }

                if step != .search {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            Haptics.light()
                            withAnimation(Theme.Animation.smooth) {
                                step = .search
                            }
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .foregroundStyle(Theme.Colors.accent)
                        }
                        .accessibilityIdentifier("addWatch.backButton")
                    }
                }
            }
        }
        .tint(Theme.Colors.accent)
    }

    private func saveWatch() {
        var item = CollectionItem(
            condition: viewModel.condition,
            purchaseCurrency: viewModel.purchaseCurrency
        )

        if viewModel.isManualEntry {
            item.manualBrand = viewModel.manualBrand.isEmpty ? nil : viewModel.manualBrand
            item.manualModel = viewModel.manualModel.isEmpty ? nil : viewModel.manualModel
            item.manualReference = viewModel.manualReference.isEmpty ? nil : viewModel.manualReference
        } else if let selected = viewModel.selectedCatalogWatch {
            item.catalogWatchId = selected.watchModel.id
        }

        item.serialNumber = viewModel.serialNumber.isEmpty ? nil : viewModel.serialNumber
        item.hasBox = viewModel.hasBox
        item.hasPapers = viewModel.hasPapers
        item.purchasePriceDecimal = viewModel.purchasePrice
        item.purchaseDate = viewModel.purchaseDate
        item.notes = viewModel.notes.isEmpty ? nil : viewModel.notes

        do {
            try dataService.addCollectionItem(item)
            dataRefreshStore.notifyCollectionChanged()
        } catch {
            print("Failed to save item: \(error)")
        }
        dismiss()
    }
}

struct StepIndicator: View {
    let currentStep: AddWatchStep

    private let steps: [AddWatchStep] = [.search, .quickDetails]

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ForEach(steps.indices, id: \.self) { index in
                HStack(spacing: Theme.Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(isCompleted(index) || isCurrent(index) ? Theme.Colors.accent : Theme.Colors.surface)
                            .frame(width: 28, height: 28)

                        if isCompleted(index) {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.Colors.onAccent)
                        } else {
                            Text("\(index + 1)")
                                .font(Theme.Typography.sans(.caption, weight: .semibold))
                                .foregroundStyle(isCurrent(index) ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
                        }
                    }

                    Text(steps[index].shortTitle)
                        .font(Theme.Typography.sans(.caption, weight: isCurrent(index) ? .semibold : .regular))
                        .foregroundStyle(isCurrent(index) ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                }

                if index < steps.count - 1 {
                    Rectangle()
                        .fill(isCompleted(index) ? Theme.Colors.accent : Theme.Colors.surface)
                        .frame(height: 2)
                        .frame(maxWidth: 40)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
    }

    private func isCurrent(_ index: Int) -> Bool {
        steps[index] == currentStep
    }

    private func isCompleted(_ index: Int) -> Bool {
        guard let currentIndex = steps.firstIndex(of: currentStep) else { return false }
        return index < currentIndex
    }
}

@Observable
class AddWatchViewModel {
    var searchQuery = ""
    var selectedCatalogWatch: WatchModelWithBrand?
    var isManualEntry = false

    var manualBrand = ""
    var manualModel = ""
    var manualReference = ""

    var serialNumber = ""
    var condition: WatchCondition = .excellent
    var hasBox = false
    var hasPapers = false

    var purchasePrice: Decimal?
    var purchaseCurrency = "USD"
    var purchaseDate: Date?

    var notes = ""
}

enum AddWatchStep {
    case search
    case quickDetails

    var title: String {
        switch self {
        case .search: return "Find Watch"
        case .quickDetails: return "Add Details"
        }
    }

    var shortTitle: String {
        switch self {
        case .search: return "Search"
        case .quickDetails: return "Details"
        }
    }
}

struct CatalogSearchStep: View {
    @Binding var viewModel: AddWatchViewModel
    let onNext: () -> Void
    @State private var localResults: [WatchModelWithBrand] = []
    @State private var isSearchFocused = false
    @FocusState private var searchFieldFocused: Bool
    @State private var dataService = DataService()
    @State private var searchTask: Task<Void, Never>?
    @State private var searchError: String?

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.md)

            if let error = searchError {
                searchErrorState(error)
            } else if localResults.isEmpty && viewModel.searchQuery.isEmpty {
                searchEmptyState
            } else if localResults.isEmpty && viewModel.searchQuery.count >= 2 {
                noResultsState
            } else {
                searchResultsList
            }

            Spacer()

            manualEntryButton
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(isSearchFocused ? Theme.Colors.accent : Theme.Colors.textSecondary)
                .animation(Theme.Animation.quick, value: isSearchFocused)

            TextField("Search brand, model, or reference...", text: $viewModel.searchQuery)
                .font(Theme.Typography.sans(.body))
                .focused($searchFieldFocused)
                .accessibilityIdentifier("addWatch.searchField")
                .onChange(of: searchFieldFocused) { _, focused in
                    withAnimation(Theme.Animation.quick) {
                        isSearchFocused = focused
                    }
                }
                .onChange(of: viewModel.searchQuery) { _, newValue in
                    searchTask?.cancel()
                    searchError = nil
                    searchTask = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        await searchCatalog(query: newValue)
                    }
                }

            if !viewModel.searchQuery.isEmpty {
                Button {
                    Haptics.light()
                    viewModel.searchQuery = ""
                    localResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .accessibilityIdentifier("addWatch.clearSearchButton")
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.button)
                .fill(Theme.Colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.button)
                .stroke(isSearchFocused ? Theme.Colors.accent : Color.clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    private var searchEmptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.Colors.accent.opacity(0.6))
            }

            VStack(spacing: Theme.Spacing.sm) {
                Text("Search Your Watch")
                    .font(Theme.Typography.heading(.title3))
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Search by brand, model, or reference number")
                    .font(Theme.Typography.sans(.subheadline))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.xxxl)
    }

    private var noResultsState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 50))
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.5))

            VStack(spacing: Theme.Spacing.sm) {
                Text("No Results Found")
                    .font(Theme.Typography.heading(.headline))
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Try different keywords or add your watch manually")
                    .font(Theme.Typography.sans(.subheadline))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.xxxl)
    }

    private func searchErrorState(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(Theme.Colors.warning.opacity(0.7))

            VStack(spacing: Theme.Spacing.sm) {
                Text("Search Error")
                    .font(Theme.Typography.heading(.headline))
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(message)
                    .font(Theme.Typography.sans(.subheadline))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.xxxl)
    }

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.md) {
                ForEach(Array(localResults.enumerated()), id: \.element.watchModel.id) { index, result in
                    SearchResultRow(result: result)
                        .accessibilityIdentifier("addWatch.searchResult.\(result.watchModel.id)")
                        .onTapGesture {
                            Haptics.medium()
                            viewModel.selectedCatalogWatch = result
                            viewModel.isManualEntry = false
                            onNext()
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .animation(
                            Theme.Animation.smooth.delay(Double(index) * 0.03),
                            value: localResults.count
                        )
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
    }

    private var manualEntryButton: some View {
        Button {
            Haptics.medium()
            viewModel.isManualEntry = true
            onNext()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "plus.circle.fill")
                Text("Add Manually")
            }
            .font(Theme.Typography.sans(.subheadline, weight: .medium))
            .foregroundStyle(Theme.Colors.accent)
            .padding(.vertical, Theme.Spacing.md)
            .frame(maxWidth: .infinity)
            .background(Theme.Colors.accent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
        }
        .accessibilityIdentifier("addWatch.manualEntryButton")
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.lg)
    }

    @MainActor
    private func searchCatalog(query: String) async {
        guard query.count >= 2 else {
            localResults = []
            searchError = nil
            return
        }

        do {
            localResults = try dataService.searchCatalogFTS(query: query)
            searchError = nil
        } catch {
            localResults = []
            searchError = "Search failed. Try again."
        }
    }
}

struct SearchResultRow: View {
    let result: WatchModelWithBrand
    @State private var isPressed = false

    private var model: WatchModel { result.watchModel }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            imageView
                .frame(width: 60, height: 60)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let brand = result.brand?.name {
                    Text(brand.uppercased())
                        .font(Theme.Typography.sans(.caption2, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                        .tracking(1)
                }

                Text(model.displayName)
                    .font(Theme.Typography.heading(.subheadline))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)

                HStack(spacing: Theme.Spacing.sm) {
                    Text("Ref. \(model.reference)")
                        .font(Theme.Typography.sans(.caption))
                        .foregroundStyle(Theme.Colors.textSecondary)

                    if let price = model.formattedMarketPrice {
                        Text("•")
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(price)
                            .font(Theme.Typography.sans(.caption, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(Theme.Colors.card)
        )
        .shadow(
            color: .black.opacity(Theme.Shadow.cardOpacity),
            radius: Theme.Shadow.cardRadius,
            y: Theme.Shadow.cardY
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(Theme.Animation.quick, value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    @ViewBuilder
    private var imageView: some View {
        if let urlString = model.catalogImageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholderIcon
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                @unknown default:
                    placeholderIcon
                }
            }
        } else {
            placeholderIcon
        }
    }

    private var placeholderIcon: some View {
        Image(systemName: "clock.fill")
            .font(.title3)
            .foregroundStyle(Theme.Colors.textSecondary.opacity(0.4))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct QuickDetailsStep: View {
    @Binding var viewModel: AddWatchViewModel
    let onSave: () -> Void

    private var watchName: String {
        if viewModel.isManualEntry {
            return "\(viewModel.manualBrand) \(viewModel.manualModel)"
        }
        return viewModel.selectedCatalogWatch?.fullDisplayName ?? "Watch"
    }

    private var watchImageURL: String? {
        viewModel.selectedCatalogWatch?.watchModel.catalogImageURL
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                watchPreviewCard

                if viewModel.isManualEntry {
                    manualInfoSection
                }

                conditionSection
                purchaseSection
                optionalSection
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, 100)
        }
        .safeAreaInset(edge: .bottom) {
            saveButton
        }
    }

    private var watchPreviewCard: some View {
        HStack(spacing: Theme.Spacing.lg) {
            AsyncImage(url: URL(string: watchImageURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure, .empty:
                    Image(systemName: "clock.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.Colors.textSecondary.opacity(0.4))
                @unknown default:
                    Image(systemName: "clock.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.Colors.textSecondary.opacity(0.4))
                }
            }
            .frame(width: 80, height: 80)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let brand = viewModel.selectedCatalogWatch?.brand?.name ?? (viewModel.manualBrand.isEmpty ? nil : viewModel.manualBrand) {
                    Text(brand.uppercased())
                        .font(Theme.Typography.sans(.caption, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                        .tracking(1)
                }

                Text(watchName)
                    .font(Theme.Typography.heading(.headline))
                    .foregroundStyle(Theme.Colors.textPrimary)

                if let ref = viewModel.selectedCatalogWatch?.watchModel.reference ?? (viewModel.manualReference.isEmpty ? nil : viewModel.manualReference) {
                    Text("Ref. \(ref)")
                        .font(Theme.Typography.sans(.caption))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(Theme.Colors.card)
        )
        .shadow(
            color: .black.opacity(Theme.Shadow.cardOpacity),
            radius: Theme.Shadow.cardRadius,
            y: Theme.Shadow.cardY
        )
    }

    private var manualInfoSection: some View {
        FormSection(title: "Watch Info", icon: "clock.fill") {
            VStack(spacing: Theme.Spacing.md) {
                FormTextField(label: "Brand", text: $viewModel.manualBrand, required: true, accessibilityIdentifier: "addWatch.brandField")
                FormTextField(label: "Model", text: $viewModel.manualModel, required: true, accessibilityIdentifier: "addWatch.modelField")
                FormTextField(label: "Reference", text: $viewModel.manualReference, required: false, accessibilityIdentifier: "addWatch.referenceField")
            }
        }
    }

    private var conditionSection: some View {
        FormSection(title: "Condition & Completeness", icon: "star.fill") {
            VStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Condition")
                        .font(Theme.Typography.sans(.subheadline))
                        .foregroundStyle(Theme.Colors.textSecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(WatchCondition.allCases, id: \.self) { condition in
                                ConditionChip(
                                    condition: condition,
                                    isSelected: viewModel.condition == condition
                                ) {
                                    Haptics.selection()
                                    viewModel.condition = condition
                                }
                            }
                        }
                    }
                }

                Divider()

                HStack {
                    Text("Box")
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Toggle("", isOn: $viewModel.hasBox)
                        .toggleStyle(AccentToggleStyle())
                        .onChange(of: viewModel.hasBox) { _, _ in
                            Haptics.toggle()
                        }
                        .accessibilityIdentifier("addWatch.hasBoxToggle")
                }

                HStack {
                    Text("Papers / Warranty Card")
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Toggle("", isOn: $viewModel.hasPapers)
                        .toggleStyle(AccentToggleStyle())
                        .onChange(of: viewModel.hasPapers) { _, _ in
                            Haptics.toggle()
                        }
                        .accessibilityIdentifier("addWatch.hasPapersToggle")
                }
            }
        }
    }

    private var purchaseSection: some View {
        FormSection(title: "Purchase", icon: "creditcard.fill") {
            VStack(spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    Menu {
                        ForEach(Currency.all) { currency in
                            Button {
                                Haptics.selection()
                                viewModel.purchaseCurrency = currency.code
                            } label: {
                                HStack {
                                    Text("\(currency.flag) \(currency.code)")
                                    if viewModel.purchaseCurrency == currency.code {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(Currency.from(code: viewModel.purchaseCurrency)?.flag ?? "")
                            Text(viewModel.purchaseCurrency)
                                .fontWeight(.medium)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(Theme.Spacing.sm)
                        .background(Theme.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
                    }
                    .accessibilityIdentifier("addWatch.currencyMenu")

                    CurrencyTextField(
                        currency: Currency.from(code: viewModel.purchaseCurrency) ?? .usd,
                        value: $viewModel.purchasePrice
                    )
                    .accessibilityIdentifier("addWatch.purchasePriceField")
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
                }

                DatePicker(
                    "Date",
                    selection: Binding(
                        get: { viewModel.purchaseDate ?? Date() },
                        set: { viewModel.purchaseDate = $0 }
                    ),
                    displayedComponents: .date
                )
                .tint(Theme.Colors.accent)
                .accessibilityIdentifier("addWatch.purchaseDatePicker")
            }
        }
    }

    private var optionalSection: some View {
        FormSection(title: "Optional", icon: "doc.text.fill") {
            VStack(spacing: Theme.Spacing.md) {
                FormTextField(label: "Serial Number", text: $viewModel.serialNumber, required: false, accessibilityIdentifier: "addWatch.serialNumberField")

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Notes")
                        .font(Theme.Typography.sans(.subheadline))
                        .foregroundStyle(Theme.Colors.textSecondary)

                    TextEditor(text: $viewModel.notes)
                        .frame(minHeight: 80)
                        .padding(Theme.Spacing.sm)
                        .scrollContentBackground(.hidden)
                        .background(Theme.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
                        .accessibilityIdentifier("addWatch.notesField")
                }
            }
        }
    }

    private var saveButton: some View {
        Button {
            onSave()
        } label: {
            Text("Add to Collection")
                .font(Theme.Typography.sans(.headline))
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(
                    canSave
                        ? Theme.Colors.accent
                        : Theme.Colors.textSecondary.opacity(0.3)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
        }
        .disabled(!canSave)
        .accessibilityIdentifier("addWatch.saveButton")
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(.ultraThinMaterial)
    }

    private var canSave: Bool {
        if viewModel.isManualEntry {
            return !viewModel.manualBrand.isEmpty && !viewModel.manualModel.isEmpty
        }
        return viewModel.selectedCatalogWatch != nil
    }
}

struct FormSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.Colors.accent)
                Text(title)
                    .font(Theme.Typography.heading(.headline))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            content
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(Theme.Colors.card)
        )
        .shadow(
            color: .black.opacity(Theme.Shadow.cardOpacity),
            radius: Theme.Shadow.cardRadius,
            y: Theme.Shadow.cardY
        )
    }
}

struct FormTextField: View {
    let label: String
    @Binding var text: String
    let required: Bool
    var accessibilityIdentifier: String? = nil

    private var fallbackAccessibilityId: String {
        "formField.\(label.replacingOccurrences(of: " ", with: ""))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xxs) {
                Text(label)
                    .font(Theme.Typography.sans(.subheadline))
                    .foregroundStyle(Theme.Colors.textSecondary)
                if required {
                    Text("*")
                        .foregroundStyle(Theme.Colors.accent)
                }
            }

            TextField("", text: $text)
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
                .accessibilityIdentifier(accessibilityIdentifier ?? fallbackAccessibilityId)
        }
    }
}

struct ConditionChip: View {
    let condition: WatchCondition
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(condition.abbreviation)
                .font(Theme.Typography.sans(.caption, weight: .semibold))
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(isSelected ? conditionColor : Theme.Colors.surface)
                .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : Theme.Colors.surface, lineWidth: 1)
                )
        }
        .accessibilityIdentifier("addWatch.condition.\(condition.abbreviation.lowercased())")
        .buttonStyle(.plain)
    }

    private var conditionColor: Color {
        switch condition {
        case .unworn: return Theme.Condition.unworn
        case .excellent: return Theme.Condition.excellent
        case .veryGood: return Theme.Condition.veryGood
        case .good: return Theme.Condition.good
        case .fair: return Theme.Condition.fair
        case .poor: return Theme.Condition.poor
        }
    }
}
