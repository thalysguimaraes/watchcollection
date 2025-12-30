import SwiftUI

struct CollectionHeaderView: View {
    let onSortTapped: () -> Void
    @Binding var showingAddOptions: Bool
    let onAddManually: () -> Void
    let onIdentifyWithAI: () -> Void

    var body: some View {
        HStack {
            Button {
                Haptics.light()
                onSortTapped()
            } label: {
                Image(systemName: "line.3.horizontal")
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

            Button {
                Haptics.medium()
                showingAddOptions = true
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
            .popover(isPresented: $showingAddOptions, arrowEdge: .top) {
                AddOptionsPopover(
                    onAddManually: {
                        showingAddOptions = false
                        onAddManually()
                    },
                    onIdentifyWithAI: {
                        showingAddOptions = false
                        onIdentifyWithAI()
                    }
                )
                .presentationCompactAdaptation(.popover)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }
}

#Preview {
    @Previewable @State var showingAddOptions = false
    CollectionHeaderView(
        onSortTapped: {},
        showingAddOptions: $showingAddOptions,
        onAddManually: {},
        onIdentifyWithAI: {}
    )
    .padding(.vertical)
    .background(Theme.Colors.background)
}
