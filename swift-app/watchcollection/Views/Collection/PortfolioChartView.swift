import SwiftUI
import Charts

struct PortfolioChartView: View {
    let dataPoints: [ChartDataPoint]
    let currencyCode: String

    @State private var selectedDate: Date?

    private var currency: Currency {
        Currency.from(code: currencyCode) ?? .usd
    }

    private var selectedPoint: ChartDataPoint? {
        guard let selectedDate else { return nil }
        return dataPoints.min(by: {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        })
    }

    private var yDomain: ClosedRange<Double> {
        let values = dataPoints.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 100
        let range = maxValue - minValue
        let bottomPadding = range * 1.5
        let topPadding = range * 0.25
        return (minValue - bottomPadding)...(maxValue + topPadding)
    }

    var body: some View {
        Chart {
            ForEach(dataPoints) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Theme.Colors.chartSubtle.opacity(0.35),
                            Theme.Colors.chartSubtle.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(Theme.Colors.chartSubtle)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
            }

            if let selectedPoint {
                RuleMark(x: .value("Date", selectedPoint.date))
                    .foregroundStyle(Theme.Colors.chartSubtle.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                PointMark(
                    x: .value("Date", selectedPoint.date),
                    y: .value("Value", selectedPoint.value)
                )
                .foregroundStyle(Theme.Colors.chartSubtle)
                .symbolSize(100)
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
                    let yPosition = proxy.position(forY: selectedPoint.value) ?? 0

                    ChartPopover(
                        value: selectedPoint.value,
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
        .frame(height: 160)
        .clipped()
        .onChange(of: selectedDate) { _, newValue in
            if newValue != nil {
                Haptics.selection()
            }
        }
        .animation(.easeOut(duration: 0.15), value: selectedPoint?.id)
    }
}

struct ChartPopover: View {
    let value: Double
    let date: Date
    let currency: Currency

    private var formattedValue: String {
        currency.format(Decimal(value))
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(formattedValue)
                .font(Theme.Typography.sans(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.Colors.onPrimary)
            Text(formattedDate)
                .font(Theme.Typography.sans(.caption2))
                .foregroundStyle(Theme.Colors.onPrimary.opacity(0.7))
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.popoverBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

#Preview {
    PortfolioChartView(
        dataPoints: MockChartData.generate(currentValue: 147280),
        currencyCode: "BRL"
    )
    .padding(.vertical)
    .background(Theme.Colors.background)
}
