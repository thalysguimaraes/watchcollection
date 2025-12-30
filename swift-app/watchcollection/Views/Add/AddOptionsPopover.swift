import SwiftUI

struct AddOptionsPopover: View {
    let onAddManually: () -> Void
    let onIdentifyWithAI: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.medium()
                onAddManually()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16))
                        .frame(width: 24)
                    Text("Add Manually")
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 12)
            }

            Divider()
                .background(Theme.Colors.divider)

            Button {
                Haptics.medium()
                onIdentifyWithAI()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                        .frame(width: 24)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("Identify with AI")
                        .font(.system(size: 15, weight: .medium))
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer()
                    Text("NEW")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.Colors.accent)
                        .clipShape(Capsule())
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 220)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
    }
}

#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        AddOptionsPopover(
            onAddManually: {},
            onIdentifyWithAI: {}
        )
    }
}
