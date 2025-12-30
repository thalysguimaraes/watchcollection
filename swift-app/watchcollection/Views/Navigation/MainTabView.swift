import SwiftUI

struct MainTabView: View {
    @State private var router = NavigationRouter()
    @State private var dataRefreshStore = DataRefreshStore()

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            CollectionListView()
                .environment(router)
                .environment(dataRefreshStore)
                .tabItem {
                    Label("Collection", systemImage: router.selectedTab == 0 ? "clock.fill" : "clock")
                }
                .tag(0)

            WishlistView()
                .environment(router)
                .environment(dataRefreshStore)
                .tabItem {
                    Label("Wishlist", systemImage: router.selectedTab == 1 ? "heart.fill" : "heart")
                }
                .tag(1)

            CatalogBrowseView()
                .environment(router)
                .environment(dataRefreshStore)
                .tabItem {
                    Label("Catalog", systemImage: router.selectedTab == 2 ? "books.vertical.fill" : "books.vertical")
                }
                .tag(2)

            SettingsView()
                .environment(dataRefreshStore)
                .tabItem {
                    Label("Settings", systemImage: router.selectedTab == 3 ? "gearshape.fill" : "gearshape")
                }
                .tag(3)
        }
        .tint(Theme.Colors.accent)
        .onChange(of: router.selectedTab) { _, _ in
            Haptics.selection()
        }
        .sheet(item: $router.presentedSheet) { sheet in
            switch sheet {
            case .addWatch:
                AddWatchFlow()
                    .environment(router)
                    .environment(dataRefreshStore)
            case .editWatch(let item):
                EditWatchView(item: item)
                    .environment(router)
                    .environment(dataRefreshStore)
            case .photoViewer(let photo):
                PhotoViewerSheet(photo: photo)
            case .quickAddToCollection(let model, let brand):
                QuickAddToCollectionSheet(model: model, brand: brand)
                    .environment(dataRefreshStore)
            case .addToWishlist(let model, let brand):
                AddToWishlistSheet(model: model, brand: brand)
                    .environment(dataRefreshStore)
            case .editWishlistItem(let item):
                EditWishlistItemSheet(item: item)
                    .environment(dataRefreshStore)
            case .watchIdentification:
                WatchIdentificationFlow()
                    .environment(router)
                    .environment(dataRefreshStore)
            }
        }
    }
}

struct EditWatchView: View {
    let item: CollectionItem
    @Environment(NavigationRouter.self) private var router

    var body: some View {
        NavigationStack {
            Text("Edit \(item.displayName)")
                .navigationTitle("Edit Watch")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            router.dismiss()
                        }
                        .accessibilityIdentifier("editWatch.cancelButton")
                    }
                }
        }
    }
}

struct PhotoViewerSheet: View {
    let photo: WatchPhoto

    var body: some View {
        if let data = photo.imageData,
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
        } else {
            ContentUnavailableView("No Image", systemImage: "photo")
        }
    }
}

#Preview {
    MainTabView()
}
