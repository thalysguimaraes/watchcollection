import SwiftUI

import SwiftUI

struct CollectionItemCard: View {
    let item: CollectionItem
    var displayName: String
    var brandName: String?
    var reference: String?
    var primaryPhotoData: Data?
    var catalogImageURL: String?
    var marketPriceMedian: Int?
    @AppStorage("defaultCurrency") private var defaultCurrency = "USD"
    @State private var isPressed = false
    @State private var convertedMarketPrice: Decimal?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            imageSection
            infoSection
        }
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
        .task {
            await loadConvertedPrice()
        }
        .onChange(of: defaultCurrency) { _, _ in
            Task { await loadConvertedPrice() }
        }
    }

    private var imageSection: some View {
        ZStack(alignment: .topTrailing) {
            SmartWatchImage(
                localImageData: primaryPhotoData,
                remoteURL: catalogImageURL,
                height: 200,
                cacheKey: imageCacheKey
            )

            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            HStack(spacing: Theme.Spacing.xs) {
                if item.hasBox {
                    Image(systemName: "shippingbox.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                if item.hasPapers {
                    Image(systemName: "doc.text.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
            }
            .padding(Theme.Spacing.sm)
        }
    }

    private var imageCacheKey: String {
        if primaryPhotoData != nil {
            return "card_local_\(item.id)"
        } else if let url = catalogImageURL {
            return "card_remote_\(url.hashValue)"
        }
        return "card_placeholder_\(item.id)"
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let brand = brandName {
                Text(brand.uppercased())
                    .font(Theme.Typography.sans(.caption, weight: .bold))
                    .foregroundStyle(Theme.Colors.accent)
                    .tracking(1.5)
            }

            Text(displayName)
                .font(Theme.Typography.heading(.headline))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let ref = reference {
                Text(ref)
                    .font(Theme.Typography.sans(.caption))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.top, Theme.Spacing.xxs)
            }

            if let convertedPrice = convertedMarketPrice,
               let currency = Currency.from(code: defaultCurrency) {
                Text(currency.format(convertedPrice))
                    .font(Theme.Typography.heading(.subheadline))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.top, Theme.Spacing.xs)
            } else if let marketPrice = marketPriceMedian {
                Text(Currency.usd.format(Decimal(marketPrice)))
                    .font(Theme.Typography.heading(.subheadline))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .padding(Theme.Spacing.lg)
    }

    private func loadConvertedPrice() async {
        guard let marketPrice = marketPriceMedian else { return }
        guard defaultCurrency != "USD" else {
            convertedMarketPrice = Decimal(marketPrice)
            return
        }
        do {
            convertedMarketPrice = try await CurrencyService.shared.convert(
                Decimal(marketPrice),
                from: "USD",
                to: defaultCurrency
            )
        } catch {
            convertedMarketPrice = Decimal(marketPrice)
        }
    }

}

struct ConditionBadge: View {
    let condition: WatchCondition

    var body: some View {
        Text(condition.abbreviation)
            .font(Theme.Typography.sans(.caption2, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.Colors.surface)
            .overlay(
                Capsule()
                    .stroke(Theme.Colors.divider, lineWidth: 1)
            )
            .foregroundStyle(Theme.Colors.textSecondary)
            .clipShape(Capsule())
    }
}

#Preview {
    var item = CollectionItem(condition: .excellent)
    item.manualBrand = "Rolex"
    item.manualModel = "Submariner Date"
    item.manualReference = "116610LN"
    item.purchasePrice = "12500"
    item.purchaseCurrency = "USD"
    item.hasBox = true
    item.hasPapers = true

    return CollectionItemCard(
        item: item,
        displayName: "Submariner Date",
        brandName: "Rolex",
        reference: "116610LN"
    )
    .frame(width: 180)
    .padding()
}
