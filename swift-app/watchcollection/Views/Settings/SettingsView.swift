import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultCurrency") private var defaultCurrency = "USD"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    preferencesSection
                    dataSection
                    aboutSection
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxxl)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.Colors.background, for: .navigationBar)
        }
        .tint(Theme.Colors.accent)
    }

    private var preferencesSection: some View {
        SettingsSection(title: "Preferences", icon: "gearshape.fill") {
            VStack(spacing: Theme.Spacing.md) {
                HStack {
                    Text("Default Currency")
                        .font(Theme.Typography.sans(.body))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Menu {
                        ForEach(Currency.all) { currency in
                            Button {
                                Haptics.selection()
                                defaultCurrency = currency.code
                            } label: {
                                HStack {
                                    Text("\(currency.flag) \(currency.name)")
                                    if defaultCurrency == currency.code {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(Currency.from(code: defaultCurrency)?.flag ?? "")
                            Text(defaultCurrency)
                                .font(Theme.Typography.sans(.body, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accent.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var dataSection: some View {
        SettingsSection(title: "Data", icon: "externaldrive.fill") {
            VStack(spacing: Theme.Spacing.md) {
                Button {
                    Haptics.medium()
                } label: {
                    HStack {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Theme.Colors.accent)
                            Text("Export Collection")
                                .font(Theme.Typography.sans(.body))
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }

                Divider()

                Button {
                    Haptics.medium()
                } label: {
                    HStack {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundStyle(Theme.Colors.accent)
                            Text("Import Collection")
                                .font(Theme.Typography.sans(.body))
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        SettingsSection(title: "About", icon: "info.circle.fill") {
            VStack(spacing: Theme.Spacing.sm) {
                HStack {
                    Text("Version")
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .font(Theme.Typography.sans(.body))

                Divider()

                HStack {
                    Text("Build")
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text("1")
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .font(Theme.Typography.sans(.body))

                Divider()

                Link(destination: URL(string: "https://github.com")!) {
                    HStack {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .foregroundStyle(Theme.Colors.accent)
                            Text("Source Code")
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .font(Theme.Typography.sans(.body))
                }
            }
        }
    }
}

struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(value)
                        .font(Theme.Typography.heading(.title))
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(label)
                        .font(Theme.Typography.sans(.caption))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(Theme.Colors.card)
        )
        .shadow(
            color: .black.opacity(Theme.Shadow.cardOpacity),
            radius: Theme.Shadow.cardRadius,
            y: Theme.Shadow.cardY
        )
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.Colors.accent)
                Text(title)
                    .font(Theme.Typography.heading(.headline))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            content
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(Theme.Colors.card)
        )
        .shadow(
            color: .black.opacity(Theme.Shadow.cardOpacity),
            radius: Theme.Shadow.cardRadius,
            y: Theme.Shadow.cardY
        )
    }
}

#Preview {
    SettingsView()
}
