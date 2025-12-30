import SwiftUI

struct AddToWishlistSheet: View {
    let model: WatchModel
    let brand: Brand?

    @Environment(\.dismiss) private var dismiss
    @Environment(DataRefreshStore.self) private var dataRefreshStore
    @State private var priority: WishlistPriority = .medium
    @State private var notes = ""
    @State private var dataService = DataService()

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                watchPreviewCard
                prioritySection
                notesSection
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Add to Wishlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Haptics.light()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Haptics.success()
                        addToWishlist()
                    }
                    .font(Theme.Typography.sans(.body, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
        .tint(Theme.Colors.accent)
    }

    private var watchPreviewCard: some View {
        HStack(spacing: Theme.Spacing.lg) {
            AsyncImage(url: URL(string: model.catalogImageURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Image(systemName: "clock.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.Colors.textSecondary.opacity(0.4))
                }
            }
            .frame(width: 80, height: 80)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let brandName = brand?.name {
                    Text(brandName.uppercased())
                        .font(Theme.Typography.sans(.caption, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                        .tracking(1)
                }

                Text(model.displayName)
                    .font(Theme.Typography.heading(.headline))
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Ref. \(model.reference)")
                    .font(Theme.Typography.sans(.caption))
                    .foregroundStyle(Theme.Colors.textSecondary)

                if let price = model.formattedMarketPrice {
                    Text(price)
                        .font(Theme.Typography.sans(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }

            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .shadow(
            color: .black.opacity(Theme.Shadow.cardOpacity),
            radius: Theme.Shadow.cardRadius,
            y: Theme.Shadow.cardY
        )
    }

    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(Theme.Colors.accent)
                Text("Priority")
                    .font(Theme.Typography.heading(.headline))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            HStack(spacing: Theme.Spacing.md) {
                ForEach(WishlistPriority.allCases, id: \.self) { p in
                    Button {
                        Haptics.selection()
                        priority = p
                    } label: {
                        VStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: p.icon)
                                .font(.title2)
                                .foregroundStyle(priority == p ? Theme.Colors.onAccent : p.color)
                            Text(p.displayName)
                                .font(Theme.Typography.sans(.caption, weight: .medium))
                                .foregroundStyle(priority == p ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(priority == p ? p.color : Theme.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .shadow(
            color: .black.opacity(Theme.Shadow.cardOpacity),
            radius: Theme.Shadow.cardRadius,
            y: Theme.Shadow.cardY
        )
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "note.text")
                    .foregroundStyle(Theme.Colors.accent)
                Text("Notes")
                    .font(Theme.Typography.heading(.headline))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

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
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .shadow(
            color: .black.opacity(Theme.Shadow.cardOpacity),
            radius: Theme.Shadow.cardRadius,
            y: Theme.Shadow.cardY
        )
    }

    private func addToWishlist() {
        var item = WishlistItem(
            watchModelId: model.id,
            priority: priority
        )
        item.notes = notes.isEmpty ? nil : notes

        do {
            try dataService.addToWishlist(item)
            dataRefreshStore.notifyWishlistChanged()
        } catch {
            print("Failed to add to wishlist: \(error)")
        }

        dismiss()
    }
}
