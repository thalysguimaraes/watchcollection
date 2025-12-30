import SwiftUI

struct IdentificationResultsView: View {
    let matches: [WatchModelWithBrand]
    let identification: WatchIdentification
    let onSelectMatch: (WatchModelWithBrand) -> Void
    let onSearchManually: () -> Void
    let onRetry: () -> Void

    @State private var iconScale: CGFloat = 0.5
    @State private var headerOpacity: Double = 0
    @State private var showContent = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                headerSection

                if !matches.isEmpty {
                    matchesSection
                }

                aiDescriptionSection

                actionsSection
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.background)
        .onAppear {
            withAnimation(Theme.Animation.bouncy.delay(0.1)) {
                iconScale = 1.0
            }
            withAnimation(Theme.Animation.smooth.delay(0.15)) {
                headerOpacity = 1.0
            }
            withAnimation(Theme.Animation.smooth.delay(0.2)) {
                showContent = true
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: matches.isEmpty ? "questionmark.circle" : "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(matches.isEmpty ? Theme.Colors.textSecondary : Theme.Colors.success)
                .scaleEffect(iconScale)

            Text(matches.isEmpty ? "No Exact Match Found" : "Watch Identified!")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .opacity(headerOpacity)

            Text(matches.isEmpty
                 ? "We couldn't find an exact match in the catalog"
                 : "We found \(matches.count) potential match\(matches.count == 1 ? "" : "es")")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textSecondary)
                .opacity(headerOpacity)
        }
        .padding(.top, Theme.Spacing.md)
    }

    @ViewBuilder
    private var matchesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Matches")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .opacity(showContent ? 1 : 0)

            ForEach(Array(matches.enumerated()), id: \.element.watchModel.id) { index, match in
                MatchCard(watch: match) {
                    onSelectMatch(match)
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)
                .animation(
                    Theme.Animation.smooth.delay(0.25 + Double(index) * 0.08),
                    value: showContent
                )
            }
        }
    }

    private var aiDescriptionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.Colors.accent)
                Text("AI Analysis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if let brand = identification.brand {
                    DetailRow(label: "Brand", value: brand)
                }
                if let model = identification.model {
                    DetailRow(label: "Model", value: model)
                }
                if let reference = identification.reference {
                    DetailRow(label: "Reference", value: reference)
                }
                if let material = identification.material {
                    DetailRow(label: "Material", value: material)
                }
                if let dialColor = identification.dialColor {
                    DetailRow(label: "Dial", value: dialColor)
                }
                if !identification.complications.isEmpty {
                    DetailRow(label: "Complications", value: identification.complications.joined(separator: ", "))
                }

                Divider()
                    .padding(.vertical, Theme.Spacing.xs)

                Text(identification.rawDescription)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineSpacing(4)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .opacity(showContent ? 1 : 0)
        .offset(y: showContent ? 0 : 15)
        .animation(Theme.Animation.smooth.delay(0.35), value: showContent)
    }

    private var actionsSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            Button {
                Haptics.medium()
                onSearchManually()
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Search Catalog")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                Haptics.light()
                onRetry()
            } label: {
                HStack {
                    Image(systemName: "camera")
                    Text("Try Another Photo")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.top, Theme.Spacing.md)
        .opacity(showContent ? 1 : 0)
        .offset(y: showContent ? 0 : 15)
        .animation(Theme.Animation.smooth.delay(0.4), value: showContent)
    }
}

private struct MatchCard: View {
    let watch: WatchModelWithBrand
    let onSelect: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            Haptics.light()
            onSelect()
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                if let imageURL = watch.watchModel.catalogImageURL {
                    AsyncImage(url: URL(string: imageURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            Rectangle()
                                .fill(Theme.Colors.surface)
                                .overlay(
                                    Image(systemName: "clock")
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                )
                        }
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.Colors.surface)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "clock")
                                .foregroundStyle(Theme.Colors.textTertiary)
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let brand = watch.brand {
                        Text(brand.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Text(watch.watchModel.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(watch.watchModel.reference)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.Colors.accent)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(
                color: .black.opacity(Theme.Shadow.cardOpacity),
                radius: Theme.Shadow.cardRadius,
                y: Theme.Shadow.cardY
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(Theme.Animation.quick, value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
        }
    }
}
