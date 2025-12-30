import SwiftUI

import SwiftUI

struct WatchDetailView: View {
    let item: CollectionItem
    @Environment(NavigationRouter.self) private var router
    @State private var catalogWatch: WatchModel?
    @State private var brand: Brand?
    @State private var photos: [WatchPhoto] = []
    @State private var purchasePriceInUSD: Decimal?
    @State private var marketPriceInPurchaseCurrency: Decimal?
    @State private var isLoadingConversion = false
    @State private var dialColor: Color?
    @AppStorage("defaultCurrency") private var defaultCurrency = "USD"

    private let heroHeight: CGFloat = 460
    private let dataService = DataService()

    private var displayName: String {
        if let watch = catalogWatch {
            var name = watch.displayName
            if let bn = brandName {
                let prefixes = [bn + " ", bn.uppercased() + " ", bn.lowercased() + " "]
                for prefix in prefixes {
                    if name.hasPrefix(prefix) {
                        name = String(name.dropFirst(prefix.count))
                        break
                    }
                }
            }
            return name
        }
        return item.manualModel ?? "Unknown Watch"
    }

    private var brandName: String? {
        brand?.name ?? item.manualBrand
    }

    private var reference: String? {
        catalogWatch?.reference ?? item.manualReference
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection

                VStack(spacing: Theme.Spacing.xl) {
                    detailsCard
                    valuationCard

                    if let notes = item.notes, !notes.isEmpty {
                        notesCard(notes)
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Haptics.light()
                    router.presentEditWatch(item)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
        }
        .task {
            loadRelatedData()
        }
    }

    private func loadRelatedData() {
        if let watchId = item.catalogWatchId {
            catalogWatch = try? dataService.fetchWatchModel(byID: watchId)
            if let brandId = catalogWatch?.brandId {
                brand = try? dataService.fetchBrand(byID: brandId)
            }
        }
        photos = (try? dataService.fetchPhotos(forItem: item.id)) ?? []

        Task {
            await loadCurrencyConversions()
        }
    }

    private func loadCurrencyConversions() async {
        guard let purchasePrice = item.purchasePriceDecimal,
              let marketPrice = catalogWatch?.marketPriceMedian else { return }

        isLoadingConversion = true
        defer { isLoadingConversion = false }

        do {
            if item.purchaseCurrency != "USD" {
                purchasePriceInUSD = try await CurrencyService.shared.convert(
                    purchasePrice,
                    from: item.purchaseCurrency,
                    to: "USD"
                )
            } else {
                purchasePriceInUSD = purchasePrice
            }

            marketPriceInPurchaseCurrency = try await CurrencyService.shared.convert(
                Decimal(marketPrice),
                from: "USD",
                to: item.purchaseCurrency
            )
        } catch {
            purchasePriceInUSD = nil
            marketPriceInPurchaseCurrency = nil
        }
    }

    private var heroBackgroundColor: Color {
        if let dc = dialColor {
            return dc.adjustedForBackground()
        }
        return .black
    }

    private var heroBrandColor: Color {
        if let dc = dialColor {
            return dc.brightAccent()
        }
        return Theme.Colors.accent
    }

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            heroBackgroundColor

            SmartWatchImage(
                localImageData: photos.first?.imageData,
                remoteURL: catalogWatch?.catalogImageURL,
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

                Text(displayName)
                    .font(Theme.Typography.heading(.largeTitle))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let ref = reference {
                    Text("Ref. \(ref)")
                        .font(Theme.Typography.sans(.subheadline))
                        .foregroundStyle(.white.opacity(0.85))
                }

                HStack(spacing: Theme.Spacing.sm) {
                    if item.hasBox {
                        DetailChip(icon: "shippingbox.fill", text: "Box", light: true)
                    }
                    if item.hasPapers {
                        DetailChip(icon: "doc.text.fill", text: "Papers", light: true)
                    }
                }
                .padding(.top, Theme.Spacing.xs)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xxl + 40)
        }
        .frame(height: heroHeight)
    }

    private var heroCacheKey: String {
        if let photo = photos.first {
            return "hero_local_\(photo.id)"
        } else if let url = catalogWatch?.catalogImageURL {
            return "hero_remote_\(url.hashValue)"
        }
        return "hero_placeholder_\(item.id)"
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            CardHeader(title: "Details", icon: "info.circle", iconColor: heroBrandColor)

            Grid(horizontalSpacing: Theme.Spacing.lg, verticalSpacing: Theme.Spacing.md) {
                GridRow {
                    Text("Condition")
                        .font(Theme.Typography.sans(.subheadline))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .gridColumnAlignment(.leading)
                    
                    Text(item.condition.rawValue)
                        .font(Theme.Typography.sans(.body))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .gridColumnAlignment(.trailing)
                }
                
                Divider()

                if let serial = item.serialNumber {
                    GridRow {
                        Text("Serial Number")
                            .font(Theme.Typography.sans(.subheadline))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(serial)
                            .font(Theme.Typography.sans(.body))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    Divider()
                }

                if let specs = catalogWatch?.specs {
                    if let diameter = specs.caseDiameter {
                        GridRow {
                            Text("Case Size")
                                .font(Theme.Typography.sans(.subheadline))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text("\(Int(diameter))mm")
                                .font(Theme.Typography.sans(.body))
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        Divider()
                    }
                    if let material = specs.caseMaterial {
                        GridRow {
                            Text("Case Material")
                                .font(Theme.Typography.sans(.subheadline))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(material)
                                .font(Theme.Typography.sans(.body))
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        Divider()
                    }
                    if let crystal = specs.crystalType {
                        GridRow {
                            Text("Crystal")
                                .font(Theme.Typography.sans(.subheadline))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(crystal)
                                .font(Theme.Typography.sans(.body))
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        Divider()
                    }
                    if let wr = specs.waterResistance {
                        GridRow {
                            Text("Water Resistance")
                                .font(Theme.Typography.sans(.subheadline))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text("\(wr)m")
                                .font(Theme.Typography.sans(.body))
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        Divider()
                    }
                    if let dialColor = specs.dialColor {
                        GridRow {
                            Text("Dial")
                                .font(Theme.Typography.sans(.subheadline))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(dialColor)
                                .font(Theme.Typography.sans(.body))
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        Divider()
                    }
                    if let movement = specs.movement {
                        if let type = movement.type {
                            GridRow {
                                Text("Movement")
                                    .font(Theme.Typography.sans(.subheadline))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                Text(type.rawValue)
                                    .font(Theme.Typography.sans(.body))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                            Divider()
                        }
                        if let caliber = movement.caliber {
                            GridRow {
                                Text("Caliber")
                                    .font(Theme.Typography.sans(.subheadline))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                Text(caliber)
                                    .font(Theme.Typography.sans(.body))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                            Divider()
                        }
                        if let powerReserve = movement.powerReserve {
                            GridRow {
                                Text("Power Reserve")
                                    .font(Theme.Typography.sans(.subheadline))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                Text("\(powerReserve)h")
                                    .font(Theme.Typography.sans(.body))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                            Divider()
                        }
                    }
                }

                GridRow {
                    Text("Added")
                        .font(Theme.Typography.sans(.subheadline))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(item.dateAdded.formattedLong())
                        .font(Theme.Typography.sans(.body))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .background(cardBackground)
    }

    @ViewBuilder
    private var valuationCard: some View {
        let hasPurchaseData = item.purchasePriceDecimal != nil
        let hasMarketData = catalogWatch?.marketPriceMedian != nil
        let hasPriceHistory = catalogWatch?.priceHistory?.isEmpty == false

        if hasPurchaseData || hasMarketData || hasPriceHistory {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                CardHeader(title: "Valuation", icon: "chart.line.uptrend.xyaxis", iconColor: heroBrandColor)

                valuationSummary

                if let history = catalogWatch?.priceHistory, !history.isEmpty {
                    Divider()
                        .padding(.vertical, Theme.Spacing.xs)

                    PriceHistoryChartView(
                        priceHistory: history,
                        currencyCode: "USD"
                    )
                }
            }
            .padding(Theme.Spacing.xl)
            .background(cardBackground)
        }
    }

    private var valuationSummary: some View {
        VStack(spacing: Theme.Spacing.md) {
            if let price = item.purchasePriceDecimal {
                let currency = Currency.from(code: item.purchaseCurrency) ?? .usd
                HStack {
                    Text("Paid")
                        .font(Theme.Typography.sans(.body))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text(currency.format(price))
                        .font(Theme.Typography.sans(.body, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }

            if let marketPriceConverted = marketPriceInPurchaseCurrency,
               let purchasePrice = item.purchasePriceDecimal,
               purchasePrice > 0 {
                let currency = Currency.from(code: item.purchaseCurrency) ?? .usd
                let marketDouble = NSDecimalNumber(decimal: marketPriceConverted).doubleValue
                let purchaseDouble = NSDecimalNumber(decimal: purchasePrice).doubleValue
                let percentageInt = Int(((marketDouble - purchaseDouble) / purchaseDouble) * 100)
                let isPositive = marketPriceConverted >= purchasePrice

                Divider()

                HStack {
                    Text("Current Value")
                        .font(Theme.Typography.sans(.body))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    if isLoadingConversion {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(currency.format(marketPriceConverted))
                                .font(Theme.Typography.sans(.body, weight: .semibold))
                                .foregroundStyle(Theme.Colors.accent)

                            HStack(spacing: 4) {
                                Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                                    .font(.caption2)
                                Text("\(abs(percentageInt))% \(isPositive ? "gain" : "loss")")
                                    .font(Theme.Typography.sans(.caption))
                            }
                            .foregroundStyle(isPositive ? Theme.Colors.success : Theme.Colors.error)
                        }
                    }
                }
            } else if let model = catalogWatch, let median = model.marketPriceMedian {
                if item.purchasePriceDecimal != nil {
                    Divider()
                }
                HStack {
                    Text("Current Value")
                        .font(Theme.Typography.sans(.body))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text(Currency.usd.format(Decimal(median)))
                        .font(Theme.Typography.sans(.body, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
    }

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            CardHeader(title: "Notes", icon: "text.alignleft", iconColor: heroBrandColor)

            Text(notes)
                .font(Theme.Typography.sans(.body))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(4)
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

struct CardHeader: View {
    let title: String
    let icon: String
    var iconColor: Color = Theme.Colors.accent

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
            Text(title)
                .font(Theme.Typography.heading(.headline))
                .foregroundStyle(Theme.Colors.primary)
        }
        .padding(.bottom, Theme.Spacing.xs)
    }
}

struct DetailChip: View {
    let icon: String
    let text: String
    var light: Bool = false

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(Theme.Typography.sans(.caption, weight: .medium))
        }
        .foregroundStyle(light ? .white : Theme.Colors.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(light ? .ultraThinMaterial : .regularMaterial)
        .clipShape(Capsule())
    }
}

struct DetailRowStyled: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(Theme.Typography.sans(.subheadline))
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.Typography.sans(.body))
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct ProductionBadge: View {
    let isInProduction: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: isInProduction ? "checkmark.circle.fill" : "clock.arrow.circlepath")
                .font(.caption2)
            Text(isInProduction ? "In Production" : "Discontinued")
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(isInProduction ? Theme.Colors.success : Theme.Colors.textSecondary)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(isInProduction ? Theme.Colors.success.opacity(0.15) : Theme.Colors.surface)
        .clipShape(Capsule())
    }
}

#Preview {
    var item = CollectionItem(condition: .excellent)
    item.manualBrand = "Rolex"
    item.manualModel = "Submariner Date"
    item.manualReference = "116610LN"
    item.serialNumber = "K123456"
    item.hasBox = true
    item.hasPapers = true
    item.purchasePrice = "12500"
    item.purchaseCurrency = "USD"
    item.purchaseDate = Date()
    item.notes = "Great daily wearer, minor desk diving marks on clasp."

    return NavigationStack {
        WatchDetailView(item: item)
            .environment(NavigationRouter())
    }
}
