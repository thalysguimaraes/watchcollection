import SwiftUI

struct CollectionHeaderView: View {
    @Binding var sortOption: CollectionSortOption
    let onAddManually: () -> Void
    let onIdentifyWithAI: () -> Void

    var body: some View {
        HStack {
            Menu {
                ForEach(CollectionSortOption.allCases, id: \.self) { option in
                    Button {
                        Haptics.selection()
                        withAnimation(Theme.Animation.smooth) {
                            sortOption = option
                        }
                    } label: {
                        Label(option.rawValue, systemImage: sortOption == option ? "checkmark" : option.icon)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Theme.Colors.surface)
                    .clipShape(Circle())
                    .shadow(
                        color: .black.opacity(0.08),
                        radius: 8,
                        y: 2
                    )
            }

            Spacer()

            Menu {
                Button {
                    Haptics.medium()
                    onAddManually()
                } label: {
                    Label("Add Manually", systemImage: "square.and.pencil")
                }

                Button {
                    Haptics.medium()
                    onIdentifyWithAI()
                } label: {
                    Label("Identify with AI", systemImage: "sparkles")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Colors.onAccent)
                    .frame(width: 44, height: 44)
                    .background(Theme.Colors.accent)
                    .clipShape(Circle())
                    .shadow(
                        color: Theme.Colors.accent.opacity(0.4),
                        radius: 8,
                        y: 4
                    )
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }
}

#Preview {
    @Previewable @State var sortOption: CollectionSortOption = .dateAdded
    CollectionHeaderView(
        sortOption: $sortOption,
        onAddManually: {},
        onIdentifyWithAI: {}
    )
    .padding(.vertical)
    .background(Theme.Colors.background)
}
