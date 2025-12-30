import SwiftUI

struct AnalyzingView: View {
    let image: UIImage?

    @State private var pulse: Bool = false
    @State private var imageScale: CGFloat = 0.9
    @State private var imageOpacity: Double = 0
    @State private var textOpacity: Double = 0

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Theme.Colors.accent.opacity(pulse ? 0.8 : 0.3), lineWidth: 3)
                    )
                    .shadow(color: Theme.Colors.accent.opacity(pulse ? 0.4 : 0.15), radius: pulse ? 20 : 10)
                    .scaleEffect(imageScale)
                    .opacity(imageOpacity)
            }

            VStack(spacing: Theme.Spacing.md) {
                Text("Analyzing your watch...")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Our AI is identifying the brand, model, and details")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }
            .opacity(textOpacity)

            Spacer()

            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                Text("Powered by AI")
                    .font(.system(size: 12))
            }
            .foregroundStyle(Theme.Colors.textTertiary)
            .padding(.bottom, Theme.Spacing.xl)
            .opacity(textOpacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
        .onAppear {
            withAnimation(Theme.Animation.smooth) {
                imageScale = 1.0
                imageOpacity = 1.0
            }
            withAnimation(Theme.Animation.smooth.delay(0.15)) {
                textOpacity = 1.0
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

#Preview {
    AnalyzingView(image: nil)
}
