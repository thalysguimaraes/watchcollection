import SwiftUI

struct EditWishlistItemSheet: View {
    let item: WishlistItem

    @Environment(\.dismiss) private var dismiss
    @Environment(DataRefreshStore.self) private var dataRefreshStore
    @State private var priority: WishlistPriority
    @State private var notes: String
    @State private var dataService = DataService()

    init(item: WishlistItem) {
        self.item = item
        _priority = State(initialValue: item.priority)
        _notes = State(initialValue: item.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                prioritySection
                notesSection
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Edit Wishlist Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Haptics.light()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Haptics.success()
                        saveChanges()
                    }
                    .font(Theme.Typography.sans(.body, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
        .tint(Theme.Colors.accent)
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
                .frame(minHeight: 100)
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

    private func saveChanges() {
        var updatedItem = item
        updatedItem.priority = priority
        updatedItem.notes = notes.isEmpty ? nil : notes

        do {
            try dataService.updateWishlistItem(updatedItem)
            dataRefreshStore.notifyWishlistChanged()
        } catch {
            print("Failed to save: \(error)")
        }

        dismiss()
    }
}
