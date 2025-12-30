import SwiftUI

import SwiftUI

struct CatalogBrowseView: View {
    @Environment(NavigationRouter.self) private var router
    @State private var brands: [Brand] = []
    @State private var brandModelCounts: [String: Int] = [:]
    @State private var searchText = ""
    @State private var searchResults: [WatchSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var catalogService = CatalogService()
    @State private var dataService = DataService()
    @State private var isLoadingResult = false

    private var sortedBrands: [Brand] {
        brands.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func loadBrands() {
        do {
            let brandsWithCounts = try dataService.fetchBrandsWithModelCount()
            brands = brandsWithCounts.map(\.brand)
            brandModelCounts = Dictionary(uniqueKeysWithValues: brandsWithCounts.map { ($0.brand.id, $0.modelCount) })
        } catch {
            print("Failed to load brands: \(error)")
        }
    }

    var body: some View {
        NavigationStack(path: Binding(
            get: { router.catalogPath },
            set: { router.catalogPath = $0 }
        )) {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                Group {
                    if searchText.isEmpty {
                        brandList
                    } else {
                        searchResultsList
                    }
                }
            }
            .navigationTitle("Catalog")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.Colors.background, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Search catalog...")
            .task {
                loadBrands()
            }
            .onChange(of: searchText) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await performSearch(query: newValue)
                }
            }
            .navigationDestination(for: CatalogDestination.self) { dest in
                switch dest {
                case .watchModel(let model):
                    CatalogWatchDetailView(model: model)
                case .brand(let brand):
                    BrandDetailView(brand: brand)
                }
            }
        }
        .tint(Theme.Colors.accent)
    }

    private var brandList: some View {
        ScrollView {
            if brands.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: Theme.Spacing.md) {
                    ForEach(sortedBrands) { brand in
                        BrandCard(brand: brand, modelCount: brandModelCounts[brand.id] ?? 0)
                            .onTapGesture {
                                Haptics.light()
                                router.catalogPath.append(CatalogDestination.brand(brand))
                            }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xxxl)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(Theme.Colors.accent.opacity(0.6))
            }

            VStack(spacing: Theme.Spacing.sm) {
                Text("No Catalog Data")
                    .font(Theme.Typography.heading(.title3))
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Add watches to your collection to populate the catalog")
                    .font(Theme.Typography.sans(.subheadline))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xxxl)
            }

            Spacer()
        }
    }

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.md) {
                if isSearching {
                    searchLoadingState
                } else if searchResults.isEmpty && searchText.count >= 2 {
                    searchEmptyState
                } else {
                    ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, result in
                        SearchResultCard(result: result)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .animation(
                                Theme.Animation.smooth.delay(Double(index) * 0.05),
                                value: searchResults.count
                            )
                            .onTapGesture {
                                Haptics.light()
                                navigateToResult(result)
                            }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
        }
        .overlay {
            if isLoadingResult {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .overlay {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.5)
                    }
            }
        }
    }

    private var searchLoadingState: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(Theme.Colors.accent)
            Text("Searching...")
                .font(Theme.Typography.sans(.subheadline))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xxxl)
    }

    private var searchEmptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.5))

            Text("No results found")
                .font(Theme.Typography.heading(.headline))
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Try a different search term")
                .font(Theme.Typography.sans(.subheadline))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xxxl)
    }

    private func performSearch(query: String) async {
        guard query.count >= 2 else {
            searchResults = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            searchResults = try await catalogService.searchWatch(query: query)
        } catch {
            if !Task.isCancelled {
                searchResults = []
            }
        }
    }

    private func navigateToResult(_ result: WatchSearchResult) {
        switch result {
        case .cached(let model):
            router.catalogPath.append(CatalogDestination.watchModel(model))
        case .wikidata:
            isLoadingResult = true
            Task {
                defer { isLoadingResult = false }
                do {
                    let model = try catalogService.fetchWatchDetails(result: result)
                    await MainActor.run {
                        router.catalogPath.append(CatalogDestination.watchModel(model))
                    }
                } catch {
                    print("Failed to fetch watch details: \(error)")
                }
            }
        }
    }
}

struct BrandCard: View {
    let brand: Brand
    let modelCount: Int
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            brandLogo

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(brand.name)
                    .font(Theme.Typography.heading(.headline))
                    .foregroundStyle(Theme.Colors.textPrimary)

                if let country = brand.country {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(countryFlag(for: country))
                        Text(country)
                            .font(Theme.Typography.sans(.caption))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                Text("\(modelCount)")
                    .font(Theme.Typography.heading(.title3))
                    .foregroundStyle(Theme.Colors.accent)

                Text("models")
                    .font(Theme.Typography.sans(.caption2))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
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

    private var brandLogo: some View {
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
                                .fill(Theme.Colors.surface)
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                    @unknown default:
                        fallbackLogo
                    }
                }
            } else {
                fallbackLogo
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Theme.Colors.divider, lineWidth: 1)
        )
    }

    private var fallbackLogo: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.surface)
            brandInitial
        }
    }

    private var brandInitial: some View {
        Text(String(brand.name.prefix(1)))
            .font(Theme.Typography.heading(.title2))
            .foregroundStyle(Theme.Colors.accent)
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

struct SearchResultCard: View {
    let result: WatchSearchResult

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Icon based on source? Or generic watch icon
            Circle()
                .fill(Theme.Colors.surface)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "watch.analog")
                        .foregroundStyle(Theme.Colors.textSecondary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(result.displayName)
                    .font(Theme.Typography.heading(.subheadline))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)

                if let ref = result.reference {
                    Text(ref)
                        .font(Theme.Typography.sans(.caption))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .shadow(
            color: .black.opacity(Theme.Shadow.cardOpacity),
            radius: Theme.Shadow.cardRadius,
            y: Theme.Shadow.cardY
        )
    }
}

struct CatalogWatchDetailView: View {
    let model: WatchModel
    var brandName: String?
    var brand: Brand?

    @Environment(NavigationRouter.self) private var router
    @Environment(DataRefreshStore.self) private var dataRefreshStore
    @State private var isOnWishlist = false
    @State private var dataService = DataService()
    @State private var dialColor: Color?

    private let heroHeight: CGFloat = 460

    private var heroBackgroundColor: Color {
        dialColor?.adjustedForBackground() ?? .black
    }

    private var heroBrandColor: Color {
        dialColor?.brightAccent() ?? Theme.Colors.accent
    }

    private var heroCacheKey: String {
        if let url = model.catalogImageURL {
            return "catalog_hero_\(url.hashValue)"
        }
        return "catalog_placeholder_\(model.id)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection

                VStack(spacing: Theme.Spacing.xl) {
                    ctaButtons
                    specsCard
                    pricingCard
                    if model.wikidataID != nil || model.watchbaseID != nil {
                        sourcesCard
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.xxxl)
                .frame(maxWidth: .infinity)
                .background(Theme.Colors.background)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: Theme.Radius.sheet,
                        topTrailingRadius: Theme.Radius.sheet
                    )
                )
                .offset(y: -40)
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationTitle(model.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
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

    private var ctaButtons: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button {
                Haptics.medium()
                toggleWishlist()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: isOnWishlist ? "heart.fill" : "heart")
                    Text(isOnWishlist ? "On Wishlist" : "Add to Wishlist")
                }
                .font(Theme.Typography.sans(.subheadline, weight: .medium))
                .foregroundStyle(isOnWishlist ? Theme.Colors.onAccent : Theme.Colors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(isOnWishlist ? Theme.Colors.accent : Theme.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button)
                        .stroke(Theme.Colors.accent, lineWidth: isOnWishlist ? 0 : 1.5)
                )
            }
            .buttonStyle(.plain)

            Button {
                Haptics.medium()
                router.presentQuickAddToCollection(model, brand: brand)
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "plus.circle.fill")
                    Text("I Own This")
                }
                .font(Theme.Typography.sans(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
            }
            .buttonStyle(.plain)
        }
        .shadow(
            color: .black.opacity(Theme.Shadow.floatingOpacity),
            radius: Theme.Shadow.floatingRadius,
            y: Theme.Shadow.floatingY
        )
    }

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            heroBackgroundColor

            SmartWatchImage(
                localImageData: nil,
                remoteURL: model.catalogImageURL,
                height: heroHeight,
                cacheKey: heroCacheKey,
                onDialColorDetected: { color in
                    withAnimation(Theme.Animation.standard) {
                        dialColor = color
                    }
                }
            )

            VStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .black.opacity(0.95),
                                .black.opacity(0.7),
                                .black.opacity(0.3),
                                .clear
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: heroHeight * 0.6)
                    .blur(radius: 1)
            }
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if let brand = brandName {
                    Text(brand.uppercased())
                        .font(Theme.Typography.sans(.caption, weight: .bold))
                        .foregroundStyle(heroBrandColor)
                        .tracking(2)
                }

                Text(model.displayName)
                    .font(Theme.Typography.heading(.largeTitle))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Ref. \(model.reference)")
                    .font(Theme.Typography.sans(.subheadline))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xxl + 40)
        }
        .frame(height: heroHeight)
    }

    private var specsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            CardHeader(title: "Specifications", icon: "ruler")

            if let specs = model.specs {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    if specs.caseDiameter != nil || specs.caseMaterial != nil || specs.waterResistance != nil {
                        SpecSection(title: "Case") {
                            if let diameter = specs.caseDiameter {
                                DetailRowStyled(label: "Diameter", value: "\(Int(diameter))mm")
                            }
                            if let thickness = specs.caseThickness {
                                DetailRowStyled(label: "Thickness", value: String(format: "%.1fmm", thickness))
                            }
                            if let material = specs.caseMaterial {
                                DetailRowStyled(label: "Material", value: material)
                            }
                            if let bezel = specs.bezelMaterial {
                                DetailRowStyled(label: "Bezel", value: bezel)
                            }
                            if let crystal = specs.crystalType {
                                DetailRowStyled(label: "Crystal", value: crystal)
                            }
                            if let wr = specs.waterResistance {
                                DetailRowStyled(label: "Water Resistance", value: "\(wr)m")
                            }
                            if let lug = specs.lugWidth {
                                DetailRowStyled(label: "Lug Width", value: "\(Int(lug))mm")
                            }
                        }
                    }

                    if specs.dialColor != nil || specs.dialNumerals != nil {
                        SpecSection(title: "Dial") {
                            if let color = specs.dialColor {
                                DetailRowStyled(label: "Color", value: color)
                            }
                            if let numerals = specs.dialNumerals {
                                DetailRowStyled(label: "Numerals", value: numerals)
                            }
                        }
                    }

                    if let movement = specs.movement, (movement.caliber != nil || movement.type != nil) {
                        SpecSection(title: "Movement") {
                            if let type = movement.type {
                                DetailRowStyled(label: "Type", value: type.rawValue)
                            }
                            if let caliber = movement.caliber {
                                DetailRowStyled(label: "Caliber", value: caliber)
                            }
                            if let pr = movement.powerReserve {
                                DetailRowStyled(label: "Power Reserve", value: "\(pr) hours")
                            }
                            if let freq = movement.frequency {
                                DetailRowStyled(label: "Frequency", value: "\(Int(freq)) bph")
                            }
                            if let jewels = movement.jewelsCount {
                                DetailRowStyled(label: "Jewels", value: "\(jewels)")
                            }
                        }
                    }

                    if let style = specs.style {
                        SpecSection(title: "Style") {
                            DetailRowStyled(label: "Category", value: style)
                        }
                    }
                }

                if let complications = specs.complications, !complications.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Complications")
                            .font(Theme.Typography.sans(.caption, weight: .bold))
                            .foregroundStyle(Theme.Colors.textSecondary)

                        FlowLayout(spacing: Theme.Spacing.xs) {
                            ForEach(complications, id: \.self) { complication in
                                SpecChip(text: complication, color: Theme.Colors.accent)
                            }
                        }
                    }
                }

                if let features = specs.features, !features.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Features")
                            .font(Theme.Typography.sans(.caption, weight: .bold))
                            .foregroundStyle(Theme.Colors.textSecondary)

                        FlowLayout(spacing: Theme.Spacing.xs) {
                            ForEach(features, id: \.self) { feature in
                                SpecChip(text: feature, color: Theme.Colors.textSecondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .background(cardBackground)
    }

    @ViewBuilder
    private var pricingCard: some View {
        if model.retailPriceUSD != nil || model.marketPriceMedian != nil || model.priceHistory != nil {
            PricingCard(
                retailPriceUSD: model.retailPriceUSD,
                marketPriceMedian: model.marketPriceMedian,
                priceHistory: model.priceHistory,
                currencyCode: "USD"
            )
        }
    }

    private var productionCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            CardHeader(title: "Production", icon: "clock.arrow.circlepath")

            VStack(spacing: Theme.Spacing.md) {
                DetailRowStyled(label: "Years", value: model.productionYearRange)

                HStack {
                    Text("Status")
                        .font(Theme.Typography.sans(.subheadline))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    HStack(spacing: Theme.Spacing.xs) {
                        Circle()
                            .fill(model.isInProduction ? Theme.Colors.success : Theme.Colors.textSecondary)
                            .frame(width: 8, height: 8)
                        Text(model.isInProduction ? "In Production" : "Discontinued")
                            .font(Theme.Typography.sans(.body, weight: .medium))
                            .foregroundStyle(model.isInProduction ? Theme.Colors.success : Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .background(cardBackground)
    }

    private var sourcesCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            CardHeader(title: "Data Sources", icon: "link")

            VStack(spacing: Theme.Spacing.md) {
                if let wikidata = model.wikidataID {
                    DetailRowStyled(label: "Wikidata", value: wikidata)
                }
                if let watchbase = model.watchbaseID {
                    DetailRowStyled(label: "WatchBase", value: watchbase)
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card)
            .fill(Theme.Colors.card)
            .shadow(
                color: .black.opacity(Theme.Shadow.cardOpacity),
                radius: Theme.Shadow.cardRadius,
                y: Theme.Shadow.cardY
            )
    }
}

struct SpecGridRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .font(Theme.Typography.sans(.subheadline))
                .foregroundStyle(Theme.Colors.textSecondary)
                .gridColumnAlignment(.leading)
            Text(value)
                .font(Theme.Typography.sans(.body))
                .foregroundStyle(Theme.Colors.textPrimary)
                .gridColumnAlignment(.leading)
        }
    }
}

struct SpecSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.sans(.caption, weight: .bold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(1)

            content()
        }
        .padding(.bottom, Theme.Spacing.sm)
    }
}

struct SpecChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(Theme.Typography.sans(.caption, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX - spacing)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}

#Preview {
    CatalogBrowseView()
        .environment(NavigationRouter())
}
