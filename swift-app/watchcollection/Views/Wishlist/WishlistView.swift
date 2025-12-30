import SwiftUI

struct WishlistView: View {
    @Environment(NavigationRouter.self) private var router
    @Environment(DataRefreshStore.self) private var dataRefreshStore
    @State private var items: [WishlistItemWithWatch] = []
    @State private var searchText = ""
    @State private var sortOption: WishlistSortOption = .dateAdded
    @State private var showDeleteConfirmation = false
    @State private var itemToDelete: WishlistItemWithWatch?
    @State private var dataService = DataService()

    private func loadItems() {
        do {
            items = try dataService.fetchWishlistItems()
        } catch {
            print("Failed to load wishlist: \(error)")
        }
    }

    var filteredItems: [WishlistItemWithWatch] {
        var result = items

        if !searchText.isEmpty {
            result = result.filter { item in
                item.displayName.localizedCaseInsensitiveContains(searchText) ||
                item.watchModel.reference.localizedCaseInsensitiveContains(searchText) ||
                (item.brand?.name.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return result.sorted { first, second in
            switch sortOption {
            case .dateAdded:
                return first.wishlistItem.dateAdded > second.wishlistItem.dateAdded
            case .priority:
                return first.wishlistItem.priority.sortOrder < second.wishlistItem.priority.sortOrder
            case .price:
                return (first.watchModel.marketPriceMedian ?? 0) < (second.watchModel.marketPriceMedian ?? 0)
            case .name:
                return first.displayName < second.displayName
            }
        }
    }

    var body: some View {
        NavigationStack(path: Binding(
            get: { router.wishlistPath },
            set: { router.wishlistPath = $0 }
        )) {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                if items.isEmpty {
                    WishlistEmptyState {
                        Haptics.medium()
                        router.selectedTab = 2
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.md) {
                            ForEach(filteredItems, id: \.wishlistItem.id) { item in
                                WishlistItemCard(item: item)
                                    .onTapGesture {
                                        Haptics.light()
                                        router.navigateToWishlistDetail(item)
                                    }
                                    .contextMenu {
                                        Button {
                                            Haptics.medium()
                                            router.presentQuickAddToCollection(
                                                item.watchModel,
                                                brand: item.brand
                                            )
                                        } label: {
                                            Label("Add to Collection", systemImage: "plus.circle")
                                        }

                                        Button(role: .destructive) {
                                            itemToDelete = item
                                            showDeleteConfirmation = true
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.md)
                        .padding(.bottom, Theme.Spacing.xxxl)
                    }
                    .refreshable {
                        Haptics.light()
                        loadItems()
                    }
                }
            }
            .navigationTitle("Wishlist")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.Colors.background, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Search wishlist")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(WishlistSortOption.allCases, id: \.self) { option in
                            Button {
                                Haptics.selection()
                                withAnimation(Theme.Animation.smooth) {
                                    sortOption = option
                                }
                            } label: {
                                Label(option.rawValue, systemImage: sortOption == option ? "checkmark" : option.icon)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
            }
            .navigationDestination(for: WishlistDestination.self) { dest in
                switch dest {
                case .wishlistDetail(let item):
                    WishlistDetailView(item: item, onUpdate: loadItems)
                case .catalogWatch(let model):
                    Text("Catalog Watch: \(model.displayName)")
                }
            }
            .task {
                loadItems()
            }
            .onChange(of: dataRefreshStore.wishlistRefreshToken) { _, _ in
                loadItems()
            }
        }
        .tint(Theme.Colors.accent)
        .confirmationDialog(
            "Remove from Wishlist",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let item = itemToDelete {
                    Haptics.warning()
                    withAnimation(Theme.Animation.smooth) {
                        deleteItem(item)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func deleteItem(_ item: WishlistItemWithWatch) {
        do {
            try dataService.removeFromWishlist(item.wishlistItem)
            loadItems()
            dataRefreshStore.notifyWishlistChanged()
        } catch {
            print("Failed to delete: \(error)")
        }
    }
}

#Preview {
    WishlistView()
        .environment(NavigationRouter())
        .environment(DataRefreshStore())
}
