import SwiftUI

struct AnalyzingView: View {
    let image: UIImage?

    @State private var isAnimating = false
    @State private var imageScale: CGFloat = 0.9
    @State private var imageOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var statusPhase = 0

    private let statusMessages = [
        "Scanning image...",
        "Identifying brand...",
        "Finding matches..."
    ]

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            if let image {
                ZStack {
                    Circle()
                        .strokeBorder(
                            Theme.Colors.accent.opacity(0.5),
                            style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                        )
                        .frame(width: 240, height: 240)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                        .animation(.linear(duration: 4).repeatForever(autoreverses: false), value: isAnimating)

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Theme.Colors.accent.opacity(isAnimating ? 1.0 : 0.4), lineWidth: 3)
                                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isAnimating)
                        )
                        .overlay(
                            ScanLineView()
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        )
                        .shadow(color: Theme.Colors.accent.opacity(isAnimating ? 0.6 : 0.1), radius: isAnimating ? 24 : 8)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isAnimating)
                }
                .scaleEffect(imageScale)
                .opacity(imageOpacity)
            }

            VStack(spacing: Theme.Spacing.md) {
                Text(statusMessages[statusPhase])
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.4), value: statusPhase)

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
                    .symbolEffect(.pulse)
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
            isAnimating = true
            startStatusTimer()
        }
    }

    private func startStatusTimer() {
        Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                statusPhase = (statusPhase + 1) % statusMessages.count
            }
        }
    }
}

private struct ScanLineView: View {
    @State private var offset: CGFloat = -100

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        .clear,
                        Theme.Colors.accent.opacity(0.4),
                        Theme.Colors.accent.opacity(0.6),
                        Theme.Colors.accent.opacity(0.4),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: 8)
            .offset(y: offset)
            .onAppear {
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                    offset = 100
                }
            }
    }
}

#Preview {
    AnalyzingView(image: nil)
}
