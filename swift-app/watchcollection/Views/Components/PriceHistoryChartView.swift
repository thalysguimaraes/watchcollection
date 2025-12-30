import SwiftUI
import Charts

enum PriceHistoryRange: String, CaseIterable {
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"

    var monthsBack: Int {
        switch self {
        case .threeMonths: return 3
        case .sixMonths: return 6
        case .oneYear: return 12
        }
    }
}

struct PriceHistoryChartView: View {
    let priceHistory: [PriceHistoryPoint]
    let currencyCode: String

    @State private var selectedRange: PriceHistoryRange = .oneYear
    @State private var selectedDate: Date?

    private var currency: Currency {
        Currency.from(code: currencyCode) ?? .usd
    }

    private var filteredData: [PriceHistoryPoint] {
        guard let latestDate = priceHistory.last?.date else {
            return priceHistory
        }
        let cutoff = Calendar.current.date(byAdding: .month, value: -selectedRange.monthsBack, to: latestDate) ?? latestDate
        return priceHistory.filter { $0.date >= cutoff }
    }

    private var selectedPoint: PriceHistoryPoint? {
        guard let selectedDate else { return nil }
        return filteredData.min(by: {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        })
    }

    private var currentPrice: Double? {
        filteredData.last?.price
    }

    private var yDomain: ClosedRange<Double> {
        let values = filteredData.map(\.price)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 100
        let padding = (maxValue - minValue) * 0.1
        return (minValue - padding)...(maxValue + padding)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                ForEach(PriceHistoryRange.allCases, id: \.self) { range in
                    Button {
                        Haptics.selection()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedRange = range
                        }
                    } label: {
                        Text(range.rawValue)
                            .font(Theme.Typography.sans(.caption, weight: .medium))
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, Theme.Spacing.xs)
                            .background(selectedRange == range ? Theme.Colors.accent : Color.clear)
                            .foregroundStyle(selectedRange == range ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            if filteredData.isEmpty {
                emptyState
            } else {
                chartContent
            }
        }
    }

    private var chartContent: some View {
        Chart {
            ForEach(filteredData, id: \.date) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Price", point.price)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Theme.Colors.accent.opacity(0.35),
                            Theme.Colors.accent.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.stepEnd)

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Price", point.price)
                )
                .foregroundStyle(Theme.Colors.accent)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.stepEnd)
            }

            if let selectedPoint {
                RuleMark(x: .value("Date", selectedPoint.date))
                    .foregroundStyle(Theme.Colors.accent.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                PointMark(
                    x: .value("Date", selectedPoint.date),
                    y: .value("Price", selectedPoint.price)
                )
                .foregroundStyle(Theme.Colors.accent)
                .symbolSize(80)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: xAxisStride)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Theme.Colors.divider)
                AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                    .font(Theme.Typography.sans(.caption2))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Theme.Colors.divider)
                AxisValueLabel {
                    if let price = value.as(Double.self) {
                        Text(currency.formatCompact(Decimal(price)))
                            .font(Theme.Typography.sans(.caption2))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let selectedPoint {
                    let xPosition = proxy.position(forX: selectedPoint.date) ?? 0
                    let yPosition = proxy.position(forY: selectedPoint.price) ?? 0

                    PricePopover(
                        value: selectedPoint.price,
                        date: selectedPoint.date,
                        currency: currency
                    )
                    .position(
                        x: min(max(xPosition, 60), geometry.size.width - 60),
                        y: max(yPosition - 40, 30)
                    )
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .frame(height: 200)
        .onChange(of: selectedDate) { _, newValue in
            if newValue != nil {
                Haptics.selection()
            }
        }
        .animation(.easeOut(duration: 0.15), value: selectedPoint?.date)
    }

    private var xAxisStride: Int {
        switch selectedRange {
        case .threeMonths: return 1
        case .sixMonths: return 1
        case .oneYear: return 2
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.5))
            Text("No data for this period")
                .font(Theme.Typography.sans(.subheadline))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }
}

private struct PricePopover: View {
    let value: Double
    let date: Date
    let currency: Currency

    private var formattedValue: String {
        currency.format(Decimal(value))
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(formattedValue)
                .font(Theme.Typography.sans(.subheadline, weight: .semibold))
                .foregroundStyle(.white)
            Text(formattedDate)
                .font(Theme.Typography.sans(.caption2))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.accent)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }
}

struct PriceHistorySection: View {
    let priceHistory: [PriceHistoryPoint]?
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("PRICE HISTORY")
                .font(Theme.Typography.sans(.caption, weight: .bold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .tracking(1.5)

            if let history = priceHistory, !history.isEmpty {
                PriceHistoryChartView(
                    priceHistory: history,
                    currencyCode: currencyCode
                )
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            } else {
                emptyCard
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.4))
            Text("No price history available")
                .font(Theme.Typography.sans(.subheadline))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("Price tracking data not available for this watch")
                .font(Theme.Typography.sans(.caption))
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxxl)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

struct PricingCard: View {
    let retailPriceUSD: Int?
    let marketPriceMedian: Int?
    let priceHistory: [PriceHistoryPoint]?
    let currencyCode: String

    private var currency: Currency {
        Currency.from(code: currencyCode) ?? .usd
    }

    private var premiumPercentage: Int? {
        guard let retail = retailPriceUSD, let market = marketPriceMedian, retail > 0 else {
            return nil
        }
        return Int(round(Double(market - retail) / Double(retail) * 100))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                CardHeader(title: "Pricing", icon: "dollarsign.circle")
                pricesSummary
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.xl)

            if let history = priceHistory, !history.isEmpty {
                Divider()
                    .padding(.horizontal, Theme.Spacing.xl)

                PriceHistoryChartView(
                    priceHistory: history,
                    currencyCode: currencyCode
                )
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.lg)
                .clipped()
            } else {
                Spacer().frame(height: Theme.Spacing.xl)
            }
        }
        .clipped()
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .shadow(
            color: .black.opacity(Theme.Shadow.cardOpacity),
            radius: Theme.Shadow.cardRadius,
            y: Theme.Shadow.cardY
        )
    }

    private var pricesSummary: some View {
        VStack(spacing: Theme.Spacing.md) {
            if let retail = retailPriceUSD {
                HStack {
                    Text("MSRP")
                        .font(Theme.Typography.sans(.body))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text(Currency.usd.format(Decimal(retail)))
                        .font(Theme.Typography.sans(.body, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }

            if let market = marketPriceMedian {
                if retailPriceUSD != nil {
                    Divider()
                }
                HStack {
                    Text("Market Value")
                        .font(Theme.Typography.sans(.body))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Currency.usd.format(Decimal(market)))
                            .font(Theme.Typography.sans(.body, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accent)

                        if let premium = premiumPercentage {
                            HStack(spacing: 4) {
                                Image(systemName: premium >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.caption2)
                                Text("\(abs(premium))% \(premium >= 0 ? "above" : "below") retail")
                                    .font(Theme.Typography.sans(.caption))
                            }
                            .foregroundStyle(premium >= 0 ? Theme.Colors.success : Theme.Colors.error)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    let sampleData: [PriceHistoryPoint] = (0..<270).map { i in
        let date = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
        let basePrice = 15000.0
        let variation = Double.random(in: -500...500)
        return PriceHistoryPoint(date: date, price: basePrice + variation)
    }.reversed()

    return ScrollView {
        VStack(spacing: 20) {
            PriceHistorySection(priceHistory: sampleData, currencyCode: "USD")
            PriceHistorySection(priceHistory: nil, currencyCode: "USD")
        }
        .padding()
    }
    .background(Theme.Colors.background)
}
