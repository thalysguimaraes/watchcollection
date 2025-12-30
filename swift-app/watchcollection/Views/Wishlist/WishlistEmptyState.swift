import SwiftUI

struct WishlistEmptyState: View {
    let onBrowseCatalog: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.05))
                    .frame(width: 180, height: 180)

                Circle()
                    .fill(Theme.Colors.accent.opacity(0.1))
                    .frame(width: 140, height: 140)

                Image(systemName: "heart.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Theme.Colors.accent)
            }

            VStack(spacing: Theme.Spacing.md) {
                Text("Your Wishlist is Empty")
                    .font(Theme.Typography.heading(.title2))
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Discover your next timepiece, track prices, and plan your future acquisitions.")
                    .font(Theme.Typography.sans(.subheadline))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }

            Button {
                onBrowseCatalog()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "books.vertical.fill")
                    Text("Browse Catalog")
                }
                .font(Theme.Typography.sans(.headline))
                .foregroundStyle(Theme.Colors.onAccent)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.accent)
                .clipShape(Capsule())
                .shadow(
                    color: Theme.Colors.accent.opacity(0.4),
                    radius: 12,
                    y: 6
                )
            }
            .padding(.top, Theme.Spacing.md)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    WishlistEmptyState {
        print("Browse tapped")
    }
}
