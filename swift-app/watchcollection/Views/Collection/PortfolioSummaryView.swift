import SwiftUI

struct PortfolioSummaryView: View {
    let totalValueUSD: Decimal
    let currencyCode: String

    @AppStorage("hidePortfolioValues") private var hideValues = false
    @State private var convertedValue: Decimal?
    @State private var convertedChange: Decimal?

    private var currency: Currency {
        Currency.from(code: currencyCode) ?? .usd
    }

    private var changePercent: Double {
        MockChartData.mockGrowthPercent
    }

    private var isPositive: Bool {
        changePercent >= 0
    }

    private var redactedText: String { "••••••" }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Your collection")
                .font(Theme.Typography.sans(.subheadline))
                .foregroundStyle(Theme.Colors.textSecondary)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if hideValues {
                        Text(redactedText)
                            .font(.system(size: 34, weight: .bold, design: .default))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    } else if let value = convertedValue {
                        Text(currency.format(value))
                            .font(.system(size: 34, weight: .bold, design: .default))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    } else {
                        Text(Currency.usd.format(totalValueUSD))
                            .font(.system(size: 34, weight: .bold, design: .default))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }

                    if let change = convertedChange ?? MockChartData.mockChangeAmount(for: totalValueUSD) as Decimal? {
                        HStack(spacing: Theme.Spacing.xs) {
                            if hideValues {
                                Text(redactedText)
                                    .font(Theme.Typography.sans(.caption, weight: .medium))
                            } else {
                                Text("+ \(currency.format(change)) (\(String(format: "%.1f", changePercent))%)")
                                    .font(Theme.Typography.sans(.caption, weight: .medium))
                            }
                            Text("in the last 6 months")
                                .font(Theme.Typography.sans(.caption))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .foregroundStyle(isPositive ? Theme.Colors.success : Theme.Colors.error)
                    }
                }

                Spacer()

                Button {
                    Haptics.light()
                    withAnimation {
                        hideValues.toggle()
                    }
                } label: {
                    Image(systemName: hideValues ? "eye.slash" : "eye")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(Theme.Colors.surface)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
                .symbolEffect(.bounce, value: hideValues)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .task {
            await loadConvertedValues()
        }
    }

    private func loadConvertedValues() async {
        guard currencyCode != "USD" else {
            convertedValue = totalValueUSD
            convertedChange = MockChartData.mockChangeAmount(for: totalValueUSD)
            return
        }

        do {
            convertedValue = try await CurrencyService.shared.convert(totalValueUSD, from: "USD", to: currencyCode)
            let changeUSD = MockChartData.mockChangeAmount(for: totalValueUSD)
            convertedChange = try await CurrencyService.shared.convert(changeUSD, from: "USD", to: currencyCode)
        } catch {
            convertedValue = totalValueUSD
            convertedChange = MockChartData.mockChangeAmount(for: totalValueUSD)
        }
    }
}

#Preview {
    PortfolioSummaryView(totalValueUSD: 25000, currencyCode: "BRL")
        .padding()
        .background(Theme.Colors.background)
}
