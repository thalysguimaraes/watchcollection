import SwiftUI

struct WishlistItemCard: View {
    let item: WishlistItemWithWatch
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            imageView
                .frame(width: 70, height: 70)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.sm) {
                    if let brand = item.brand?.name {
                        Text(brand.uppercased())
                            .font(Theme.Typography.sans(.caption2, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accent)
                            .tracking(1)
                    }

                    Spacer()

                    PriorityBadge(priority: item.wishlistItem.priority)
                }

                Text(item.watchModel.displayName)
                    .font(Theme.Typography.heading(.subheadline))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)

                HStack(spacing: Theme.Spacing.sm) {
                    Text("Ref. \(item.watchModel.reference)")
                        .font(Theme.Typography.sans(.caption))
                        .foregroundStyle(Theme.Colors.textSecondary)

                    if let price = item.watchModel.formattedMarketPrice {
                        Text("•")
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(price)
                            .font(Theme.Typography.sans(.caption, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.5))
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
        if let urlString = item.watchModel.catalogImageURL,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure, .empty:
                    placeholderIcon
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

struct PriorityBadge: View {
    let priority: WishlistPriority

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: priority.icon)
                .font(.system(size: 8))
            Text(priority.displayName)
                .font(Theme.Typography.sans(.caption2, weight: .medium))
        }
        .foregroundStyle(priority.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(priority.color.opacity(0.15))
        .clipShape(Capsule())
    }
}
