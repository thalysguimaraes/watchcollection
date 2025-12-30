import SwiftUI

struct CollectionListView: View {
    @Environment(NavigationRouter.self) private var router
    @Environment(DataRefreshStore.self) private var dataRefreshStore
    @State private var itemsWithDetails: [CollectionItemWithDetails] = []
    @State private var primaryPhotos: [String: Data] = [:]
    @State private var stats: CollectionStats?
    @State private var sortOption: CollectionSortOption = .dateAdded
    @State private var showDeleteConfirmation = false
    @State private var itemToDelete: CollectionItem?
    @State private var dataService = DataService()
    @State private var showingSortSheet = false
    @State private var showingAddOptions = false
    @AppStorage("defaultCurrency") private var defaultCurrency = "USD"

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Spacing.lg),
        GridItem(.flexible(), spacing: Theme.Spacing.lg)
    ]

    private var items: [CollectionItem] {
        itemsWithDetails.map(\.collectionItem)
    }

    private var portfolioChartData: [ChartDataPoint]? {
        PortfolioChartDataGenerator.generate(from: itemsWithDetails)
    }

    private func loadItems() {
        do {
            itemsWithDetails = try dataService.fetchCollectionItemsWithDetails(sortBy: sortOption)
            for detail in itemsWithDetails {
                if let photo = try? dataService.fetchPrimaryPhoto(forItem: detail.collectionItem.id) {
                    primaryPhotos[detail.collectionItem.id] = photo.imageData
                }
            }
        } catch {
            print("Failed to load items: \(error)")
        }
    }

    var sortedItemsWithDetails: [CollectionItemWithDetails] {
        itemsWithDetails.sorted { first, second in
            switch sortOption {
            case .dateAdded:
                return first.collectionItem.dateAdded > second.collectionItem.dateAdded
            case .brand:
                return (first.brandName ?? "") < (second.brandName ?? "")
            case .condition:
                return first.collectionItem.condition.sortOrder < second.collectionItem.condition.sortOrder
            case .purchasePrice:
                return (first.collectionItem.purchasePriceDecimal ?? 0) > (second.collectionItem.purchasePriceDecimal ?? 0)
            case .name:
                return first.displayName < second.displayName
            }
        }
    }

    var body: some View {
        NavigationStack(path: Binding(
            get: { router.collectionPath },
            set: { router.collectionPath = $0 }
        )) {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                if items.isEmpty {
                    CollectionEmptyState {
                        Haptics.medium()
                        router.presentAddWatch()
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                            CollectionHeaderView(
                                onSortTapped: { showingSortSheet = true },
                                showingAddOptions: $showingAddOptions,
                                onAddManually: { router.presentAddWatch() },
                                onIdentifyWithAI: { router.presentWatchIdentification() }
                            )
                            .padding(.top, Theme.Spacing.sm)

                            if let stats = stats {
                                PortfolioSummaryView(
                                    totalValueUSD: stats.totalMarketValueUSD,
                                    currencyCode: defaultCurrency
                                )

                                PortfolioChartView(
                                    dataPoints: portfolioChartData ?? MockChartData.generate(currentValue: stats.totalMarketValueUSD),
                                    currencyCode: defaultCurrency
                                )
                            }

                            Text("\(items.count) watches")
                                .font(Theme.Typography.sans(.subheadline))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .padding(.horizontal, Theme.Spacing.lg)
                                .padding(.top, Theme.Spacing.md)

                            LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                                ForEach(sortedItemsWithDetails, id: \.collectionItem.id) { detail in
                                    CollectionItemCard(
                                        item: detail.collectionItem,
                                        displayName: detail.displayName,
                                        brandName: detail.brandName,
                                        reference: detail.reference,
                                        primaryPhotoData: primaryPhotos[detail.collectionItem.id],
                                        catalogImageURL: detail.catalogWatch?.catalogImageURL,
                                        marketPriceMedian: detail.catalogWatch?.marketPriceMedian
                                    )
                                    .onTapGesture {
                                        Haptics.light()
                                        router.navigateToWatch(detail.collectionItem)
                                    }
                                    .contextMenu {
                                        Button {
                                            Haptics.light()
                                            router.presentEditWatch(detail.collectionItem)
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }

                                        Button(role: .destructive) {
                                            itemToDelete = detail.collectionItem
                                            showDeleteConfirmation = true
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                        }
                        .padding(.bottom, Theme.Spacing.xxxl)
                    }
                    .refreshable {
                        Haptics.light()
                        loadItems()
                        loadStats()
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: CollectionDestination.self) { dest in
                switch dest {
                case .watchDetail(let item):
                    WatchDetailView(item: item)
                case .editWatch(let item):
                    EditWatchView(item: item)
                }
            }
            .task {
                loadItems()
                loadStats()
            }
            .onChange(of: sortOption) { _, _ in
                loadItems()
            }
            .onChange(of: dataRefreshStore.collectionRefreshToken) { _, _ in
                loadItems()
                loadStats()
            }
        }
        .tint(Theme.Colors.accent)
        .sheet(isPresented: $showingSortSheet) {
            SortOptionsSheet(selectedOption: $sortOption, isPresented: $showingSortSheet)
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Delete Watch",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    Haptics.warning()
                    withAnimation(Theme.Animation.smooth) {
                        deleteItem(item)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func loadStats() {
        stats = try? dataService.collectionStats()
    }

    private func deleteItem(_ item: CollectionItem) {
        do {
            try dataService.deleteCollectionItem(item)
            loadItems()
            loadStats()
            dataRefreshStore.notifyCollectionChanged()
        } catch {
            print("Failed to delete item: \(error)")
        }
    }
}

struct SortOptionsSheet: View {
    @Binding var selectedOption: CollectionSortOption
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sort by")
                .font(Theme.Typography.sans(.headline, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.md)

            ForEach(CollectionSortOption.allCases, id: \.self) { option in
                Button {
                    Haptics.selection()
                    withAnimation(Theme.Animation.smooth) {
                        selectedOption = option
                    }
                    isPresented = false
                } label: {
                    HStack {
                        Image(systemName: option.icon)
                            .font(.system(size: 16))
                            .frame(width: 24)
                            .foregroundStyle(selectedOption == option ? Theme.Colors.accent : Theme.Colors.textSecondary)
                        Text(option.rawValue)
                            .font(Theme.Typography.sans(.body))
                        Spacer()
                        if selectedOption == option {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(selectedOption == option ? Theme.Colors.accent.opacity(0.1) : Color.clear)
                }
            }

            Spacer()
        }
        .background(Theme.Colors.surface)
    }
}

#Preview {
    CollectionListView()
        .environment(NavigationRouter())
        .environment(DataRefreshStore())
}
