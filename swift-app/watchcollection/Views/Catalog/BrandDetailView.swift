import SwiftUI

struct BrandDetailView: View {
    let brand: Brand
    @Environment(NavigationRouter.self) private var router
    @State private var searchText = ""
    @State private var selectedCollection: String?
    @State private var models: [WatchModel] = []
    @State private var dataService = DataService()
    @State private var showNavTitle = false

    private func loadModels() {
        do {
            let modelsWithBrand = try dataService.fetchWatchModelsWithBrand(forBrandId: brand.id)
            models = modelsWithBrand.map(\.watchModel)
        } catch {
            print("Failed to load models: \(error)")
        }
    }

    private var filteredModels: [WatchModel] {
        var result = models.sorted { $0.displayName < $1.displayName }

        if let collection = selectedCollection {
            if collection == "Other" {
                result = result.filter { $0.collection == nil || $0.collection?.isEmpty == true }
            } else {
                result = result.filter { $0.collection == collection }
            }
        }

        if searchText.isEmpty {
            return result
        }
        return result.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.reference.localizedCaseInsensitiveContains(searchText) ||
            ($0.collection?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var collections: [String] {
        let allCollections = models.compactMap { $0.collection }.filter { !$0.isEmpty }
        return Array(Set(allCollections)).sorted()
    }

    private var uncategorizedCount: Int {
        models.filter { $0.collection == nil || $0.collection?.isEmpty == true }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroHeader
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ScrollOffsetKey.self,
                                value: geo.frame(in: .named("scroll")).minY
                            )
                        }
                    )

                VStack(spacing: Theme.Spacing.xxl) {
                    if !collections.isEmpty {
                        collectionPills
                    }

                    modelsSection
                }
                .padding(.top, Theme.Spacing.xxl)
            }
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetKey.self) { offset in
            let newValue = offset < -100
            if newValue != showNavTitle {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showNavTitle = newValue
                }
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(showNavTitle ? .hidden : .visible, for: .navigationBar)
        .toolbarBackground(Theme.Colors.card, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(brand.name)
                    .font(Theme.Typography.heading(.headline))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if showNavTitle {
                LinearGradient(
                    colors: [Theme.Colors.card, Theme.Colors.card.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 50)
                .allowsHitTesting(false)
            }
        }
        .searchable(text: $searchText, prompt: "Search models...")
        .task {
            loadModels()
        }
        .animation(.easeInOut(duration: 0.2), value: showNavTitle)
    }

    private var heroHeader: some View {
        VStack(spacing: Theme.Spacing.md) {
            Group {
                if let url = brand.logoDevURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            fallbackLogo
                        case .empty:
                            ZStack {
                                Circle()
                                    .fill(Theme.Colors.accent.opacity(0.15))
                                ProgressView()
                            }
                        @unknown default:
                            fallbackLogo
                        }
                    }
                } else {
                    fallbackLogo
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Theme.Colors.divider, lineWidth: 1)
            )

            if let country = brand.country {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(countryFlag(for: country))
                        .font(.title3)
                    Text(country)
                        .font(Theme.Typography.sans(.subheadline))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            HStack(spacing: Theme.Spacing.xl) {
                StatColumn(value: "\(models.count)", label: "Models")

                if !collections.isEmpty {
                    Divider()
                        .frame(height: 30)
                    StatColumn(value: "\(collections.count)", label: "Collections")
                }
            }
            .padding(.top, Theme.Spacing.sm)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.card)
    }

    private var fallbackLogo: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.accent.opacity(0.15))
            brandInitial
        }
    }

    private var brandInitial: some View {
        Text(String(brand.name.prefix(1)))
            .font(.system(size: 40, weight: .bold))
            .foregroundStyle(Theme.Colors.accent)
    }

    private var averageMarketPrice: String? {
        let prices = models.compactMap { $0.marketPriceMedian }
        guard !prices.isEmpty else { return nil }
        let avg = prices.reduce(0, +) / prices.count
        return Currency.usd.format(Decimal(avg))
    }

    private var collectionPills: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("COLLECTIONS")
                .font(Theme.Typography.sans(.caption, weight: .bold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .tracking(1.5)
                .padding(.horizontal, Theme.Spacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    CollectionPill(
                        name: "All",
                        isSelected: selectedCollection == nil,
                        count: models.count
                    ) {
                        Haptics.selection()
                        withAnimation(Theme.Animation.quick) {
                            selectedCollection = nil
                        }
                    }

                    ForEach(collections, id: \.self) { collection in
                        CollectionPill(
                            name: collection,
                            isSelected: selectedCollection == collection,
                            count: models.filter { $0.collection == collection }.count
                        ) {
                            Haptics.selection()
                            withAnimation(Theme.Animation.quick) {
                                selectedCollection = selectedCollection == collection ? nil : collection
                            }
                        }
                    }

                    if uncategorizedCount > 0 {
                        CollectionPill(
                            name: "Other",
                            isSelected: selectedCollection == "Other",
                            count: uncategorizedCount
                        ) {
                            Haptics.selection()
                            withAnimation(Theme.Animation.quick) {
                                selectedCollection = selectedCollection == "Other" ? nil : "Other"
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("MODELS")
                    .font(Theme.Typography.sans(.caption, weight: .bold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .tracking(1.5)

                Spacer()

                Text("\(filteredModels.count)")
                    .font(Theme.Typography.sans(.caption, weight: .medium))
                    .foregroundStyle(Theme.Colors.accent)
            }
            .padding(.horizontal, Theme.Spacing.lg)

            LazyVStack(spacing: Theme.Spacing.md) {
                ForEach(filteredModels) { model in
                    WatchModelCard(model: model, brandContext: brand.name, brand: brand)
                        .onTapGesture {
                            Haptics.light()
                            router.catalogPath.append(CatalogDestination.watchModel(model))
                        }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
    }

    private func countryFlag(for country: String) -> String {
        let flags: [String: String] = [
            "Switzerland": "🇨🇭",
            "Germany": "🇩🇪",
            "Japan": "🇯🇵",
            "France": "🇫🇷",
            "Italy": "🇮🇹",
            "United Kingdom": "🇬🇧",
            "USA": "🇺🇸",
            "United States": "🇺🇸"
        ]
        return flags[country] ?? "🌍"
    }
}

struct StatColumn: View {
    let value: String
    let label: String
    var isAccent: Bool = false

    var body: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            Text(value)
                .font(Theme.Typography.heading(.title3))
                .foregroundStyle(isAccent ? Theme.Colors.accent : Theme.Colors.textPrimary)

            Text(label)
                .font(Theme.Typography.sans(.caption2))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

struct CollectionPill: View {
    let name: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(name)
                    .font(Theme.Typography.sans(.caption, weight: .medium))

                Text("\(count)")
                    .font(Theme.Typography.sans(.caption2))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        isSelected
                            ? Theme.Colors.accent.opacity(0.3)
                            : Theme.Colors.textSecondary.opacity(0.2)
                    )
                    .clipShape(Capsule())
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                isSelected
                    ? Theme.Colors.accent.opacity(0.15)
                    : Theme.Colors.card
            )
            .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textSecondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Theme.Colors.accent.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct WatchModelCard: View {
    let model: WatchModel
    var brandContext: String? = nil
    var brand: Brand? = nil
    @Environment(NavigationRouter.self) private var router
    @Environment(DataRefreshStore.self) private var dataRefreshStore
    @State private var isPressed = false
    @State private var isOnWishlist = false
    @State private var dataService = DataService()

    private var displayName: String {
        guard let brand = brandContext else { return model.displayName }
        let name = model.displayName
        if let range = name.range(of: brand, options: [.caseInsensitive, .anchored]) {
            return String(name[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return name
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            imageView
                .frame(width: 70, height: 70)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(displayName)
                    .font(Theme.Typography.heading(.subheadline))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)

                Text("Ref. \(model.reference)")
                    .font(Theme.Typography.sans(.caption))
                    .foregroundStyle(Theme.Colors.textSecondary)

                if let specs = model.specs, let diameter = specs.caseDiameter {
                    HStack(spacing: 2) {
                        Image(systemName: "circle")
                            .font(.system(size: 8))
                        Text("\(Int(diameter))mm")
                    }
                    .font(Theme.Typography.sans(.caption2))
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            Spacer()

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    Haptics.medium()
                    toggleWishlist()
                } label: {
                    Image(systemName: isOnWishlist ? "heart.fill" : "heart")
                        .font(.system(size: 16))
                        .foregroundStyle(isOnWishlist ? Theme.Colors.error : Theme.Colors.textSecondary)
                }
                .buttonStyle(.plain)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.5))
            }
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
        .contextMenu {
            Button {
                Haptics.medium()
                router.presentQuickAddToCollection(model, brand: brand)
            } label: {
                Label("Add to Collection", systemImage: "plus.circle")
            }

            Button {
                Haptics.medium()
                toggleWishlist()
            } label: {
                Label(
                    isOnWishlist ? "Remove from Wishlist" : "Add to Wishlist",
                    systemImage: isOnWishlist ? "heart.slash" : "heart"
                )
            }
        }
        .task {
            checkWishlistStatus()
        }
        .onChange(of: dataRefreshStore.wishlistRefreshToken) { _, _ in
            checkWishlistStatus()
        }
    }

    private func checkWishlistStatus() {
        isOnWishlist = (try? dataService.isOnWishlist(watchModelId: model.id)) ?? false
    }

    private func toggleWishlist() {
        if isOnWishlist {
            try? dataService.removeFromWishlist(watchModelId: model.id)
        } else {
            let item = WishlistItem(watchModelId: model.id)
            try? dataService.addToWishlist(item)
        }
        isOnWishlist.toggle()
        dataRefreshStore.notifyWishlistChanged()
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
            .font(.title2)
            .foregroundStyle(Theme.Colors.textSecondary.opacity(0.4))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    let brand = Brand(name: "Rolex", country: "Switzerland")

    return NavigationStack {
        BrandDetailView(brand: brand)
            .environment(NavigationRouter())
            .environment(DataRefreshStore())
    }
}
