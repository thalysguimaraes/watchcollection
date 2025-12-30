import SwiftUI

struct WishlistDetailView: View {
    let item: WishlistItemWithWatch
    var onUpdate: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationRouter.self) private var router
    @Environment(DataRefreshStore.self) private var dataRefreshStore
    @State private var dataService = DataService()
    @State private var showDeleteConfirmation = false
    @State private var priority: WishlistPriority
    @State private var notes: String
    @State private var hasChanges = false
    @State private var dialColor: Color?

    private let heroHeight: CGFloat = 460

    init(item: WishlistItemWithWatch, onUpdate: (() -> Void)? = nil) {
        self.item = item
        self.onUpdate = onUpdate
        _priority = State(initialValue: item.wishlistItem.priority)
        _notes = State(initialValue: item.wishlistItem.notes ?? "")
    }

    private var heroBackgroundColor: Color {
        dialColor?.adjustedForBackground() ?? .black
    }

    private var heroBrandColor: Color {
        dialColor?.brightAccent() ?? Theme.Colors.accent
    }

    private var heroCacheKey: String {
        if let url = item.watchModel.catalogImageURL {
            return "wishlist_hero_\(url.hashValue)"
        }
        return "wishlist_placeholder_\(item.wishlistItem.id)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection

                VStack(spacing: Theme.Spacing.xl) {
                    ctaButtons
                    detailsCard
                    pricingCard
                    notesCard
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
                if hasChanges {
                    Button("Save") {
                        Haptics.medium()
                        saveChanges()
                    }
                    .font(Theme.Typography.sans(.body, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
            }
        }
        .confirmationDialog(
            "Remove from Wishlist",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Haptics.warning()
                removeFromWishlist()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: priority) { _, _ in hasChanges = true }
        .onChange(of: notes) { _, _ in hasChanges = true }
    }

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            heroBackgroundColor

            SmartWatchImage(
                localImageData: nil,
                remoteURL: item.watchModel.catalogImageURL,
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
                if let brandName = item.brand?.name {
                    Text(brandName.uppercased())
                        .font(Theme.Typography.sans(.caption, weight: .bold))
                        .foregroundStyle(heroBrandColor)
                        .tracking(2)
                }

                Text(item.watchModel.displayName)
                    .font(Theme.Typography.heading(.largeTitle))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Ref. \(item.watchModel.reference)")
                    .font(Theme.Typography.sans(.subheadline))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xxl + 40)
        }
        .frame(height: heroHeight)
    }

    private var ctaButtons: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button {
                Haptics.medium()
                router.presentQuickAddToCollection(item.watchModel, brand: item.brand)
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

            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.Colors.error)
                    .frame(width: 50, height: 50)
                    .background(Theme.Colors.error.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
            }
            .buttonStyle(.plain)
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            CardHeader(title: "Details", icon: "info.circle")

            VStack(spacing: Theme.Spacing.md) {
                HStack {
                    Text("Priority")
                        .font(Theme.Typography.sans(.body))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Menu {
                        ForEach(WishlistPriority.allCases, id: \.self) { p in
                            Button {
                                Haptics.selection()
                                priority = p
                            } label: {
                                Label(p.displayName, systemImage: p.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: priority.icon)
                            Text(priority.displayName)
                        }
                        .font(Theme.Typography.sans(.body, weight: .medium))
                        .foregroundStyle(priority.color)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(priority.color.opacity(0.15))
                        .clipShape(Capsule())
                    }
                }

                Divider()

                HStack {
                    Text("Added")
                        .font(Theme.Typography.sans(.body))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text(item.wishlistItem.dateAdded.formattedAbbreviated())
                        .font(Theme.Typography.sans(.body))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .shadow(
            color: .black.opacity(Theme.Shadow.cardOpacity),
            radius: Theme.Shadow.cardRadius,
            y: Theme.Shadow.cardY
        )
    }

    @ViewBuilder
    private var pricingCard: some View {
        if item.watchModel.retailPriceUSD != nil ||
           item.watchModel.marketPriceMedian != nil ||
           item.watchModel.priceHistory?.isEmpty == false {
            PricingCard(
                retailPriceUSD: item.watchModel.retailPriceUSD,
                marketPriceMedian: item.watchModel.marketPriceMedian,
                priceHistory: item.watchModel.priceHistory,
                currencyCode: "USD"
            )
        }
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            CardHeader(title: "Notes", icon: "note.text")

            TextEditor(text: $notes)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button)
                        .stroke(Theme.Colors.divider, lineWidth: 1)
                )
        }
        .padding(Theme.Spacing.xl)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .shadow(
            color: .black.opacity(Theme.Shadow.cardOpacity),
            radius: Theme.Shadow.cardRadius,
            y: Theme.Shadow.cardY
        )
    }

    private func saveChanges() {
        var updatedItem = item.wishlistItem
        updatedItem.priority = priority
        updatedItem.notes = notes.isEmpty ? nil : notes

        do {
            try dataService.updateWishlistItem(updatedItem)
            hasChanges = false
            onUpdate?()
            dataRefreshStore.notifyWishlistChanged()
        } catch {
            print("Failed to save: \(error)")
        }
    }

    private func removeFromWishlist() {
        do {
            try dataService.removeFromWishlist(item.wishlistItem)
            onUpdate?()
            dataRefreshStore.notifyWishlistChanged()
            dismiss()
        } catch {
            print("Failed to remove: \(error)")
        }
    }
}
