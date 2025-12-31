import SwiftUI
import Charts

struct DetailPriceChartView: View {
    let priceHistory: [PriceHistoryPoint]
    var accentColor: Color = Theme.Colors.accent

    @State private var selectedRange: PriceHistoryRange = .oneYear
    @State private var selectedDate: Date?

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

    private var yDomain: ClosedRange<Double> {
        let values = filteredData.map(\.price)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 100
        let range = maxValue - minValue
        let bottomPadding = range * 0.8
        let topPadding = range * 0.2
        return (minValue - bottomPadding)...(maxValue + topPadding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Price History")
                    .font(Theme.Typography.sans(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)

                Spacer()

                HStack(spacing: Theme.Spacing.xxs) {
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
                                .background(selectedRange == range ? accentColor : Color.clear)
                                .foregroundStyle(selectedRange == range ? .white : Theme.Colors.textSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)

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
                            accentColor.opacity(0.35),
                            accentColor.forChartGradient().opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Price", point.price)
                )
                .foregroundStyle(accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
            }

            if let selectedPoint {
                RuleMark(x: .value("Date", selectedPoint.date))
                    .foregroundStyle(accentColor.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                PointMark(
                    x: .value("Date", selectedPoint.date),
                    y: .value("Price", selectedPoint.price)
                )
                .foregroundStyle(accentColor)
                .symbolSize(80)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selectedDate)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let selectedPoint {
                    let xPosition = proxy.position(forX: selectedPoint.date) ?? 0
                    let yPosition = proxy.position(forY: selectedPoint.price) ?? 0

                    DetailChartPopover(
                        value: selectedPoint.price,
                        date: selectedPoint.date,
                        accentColor: accentColor
                    )
                    .position(
                        x: min(max(xPosition, 50), geometry.size.width - 50),
                        y: max(yPosition - 35, 25)
                    )
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .frame(height: 180)
        .onChange(of: selectedDate) { _, newValue in
            if newValue != nil {
                Haptics.selection()
            }
        }
        .animation(.easeOut(duration: 0.15), value: selectedPoint?.date)
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
        .frame(height: 180)
        .frame(maxWidth: .infinity)
    }
}

private struct DetailChartPopover: View {
    let value: Double
    let date: Date
    var accentColor: Color = Theme.Colors.accent

    private var formattedValue: String {
        Currency.usd.format(Decimal(value))
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(formattedValue)
                .font(Theme.Typography.sans(.caption, weight: .semibold))
                .foregroundStyle(.white)
            Text(formattedDate)
                .font(Theme.Typography.sans(.caption2))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(accentColor)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}

#Preview {
    let sampleData: [PriceHistoryPoint] = (0..<365).map { i in
        let date = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
        let basePrice = 4000.0
        let trend = Double(365 - i) * 2
        let variation = Double.random(in: -200...200)
        return PriceHistoryPoint(date: date, price: basePrice + trend + variation)
    }.reversed()

    return ScrollView {
        VStack(spacing: 20) {
            DetailPriceChartView(priceHistory: sampleData)
        }
        .padding(.vertical)
    }
    .background(Theme.Colors.background)
}
