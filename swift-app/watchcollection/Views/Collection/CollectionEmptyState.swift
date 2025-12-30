import SwiftUI

import SwiftUI

struct CollectionEmptyState: View {
    let onAddTapped: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.1))
                    .frame(width: 140, height: 140)

                Circle()
                    .fill(Theme.Colors.accent.opacity(0.05))
                    .frame(width: 180, height: 180)

                Image(systemName: "clock.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Theme.Colors.accent)
            }

            VStack(spacing: Theme.Spacing.md) {
                Text("Start Your Collection")
                    .font(Theme.Typography.heading(.title2))
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Track your watches, monitor their value, and build your horological portfolio.")
                    .font(Theme.Typography.sans(.subheadline))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }

            Button {
                onAddTapped()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Your First Watch")
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
    ZStack {
        Color(hex: "0D0D0D")
            .ignoresSafeArea()
        CollectionEmptyState {
            print("Add tapped")
        }
    }
}
