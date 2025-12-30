import Foundation

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

enum MockChartData {
    static let mockGrowthPercent: Double = 12.9

    static func generate(currentValue: Decimal, monthsBack: Int = 6) -> [ChartDataPoint] {
        let calendar = Calendar.current
        let today = Date()
        var points: [ChartDataPoint] = []

        let currentDouble = Double(truncating: currentValue as NSDecimalNumber)
        let startValue = currentDouble / (1 + mockGrowthPercent / 100)
        let valueRange = currentDouble - startValue

        for month in (0...monthsBack).reversed() {
            guard let date = calendar.date(byAdding: .month, value: -month, to: today) else { continue }
            let progress = Double(monthsBack - month) / Double(monthsBack)
            let noise = Double.random(in: -0.02...0.02)
            let value = startValue + (valueRange * progress) + (startValue * noise)
            points.append(ChartDataPoint(date: date, value: value))
        }

        return points
    }

    static func mockChangeAmount(for currentValue: Decimal) -> Decimal {
        currentValue * Decimal(mockGrowthPercent / 100)
    }
}

enum PortfolioChartDataGenerator {
    static func generate(from items: [CollectionItemWithDetails]) -> [ChartDataPoint]? {
        var allHistories: [(history: [PriceHistoryPoint], currentPrice: Double)] = []

        for item in items {
            guard let watch = item.catalogWatch,
                  let history = watch.priceHistory,
                  !history.isEmpty else {
                continue
            }
            let current = Double(watch.marketPriceMedian ?? 0)
            allHistories.append((history: history, currentPrice: current))
        }

        guard !allHistories.isEmpty else { return nil }

        var allDates: Set<Date> = []
        for (history, _) in allHistories {
            for point in history {
                let normalized = Calendar.current.startOfDay(for: point.date)
                allDates.insert(normalized)
            }
        }

        let sortedDates = allDates.sorted()
        guard !sortedDates.isEmpty else { return nil }

        var priceByDatePerWatch: [[Date: Double]] = []
        for (history, _) in allHistories {
            var dict: [Date: Double] = [:]
            for point in history {
                let normalized = Calendar.current.startOfDay(for: point.date)
                dict[normalized] = point.price
            }
            priceByDatePerWatch.append(dict)
        }

        var chartPoints: [ChartDataPoint] = []
        var lastKnownPrices: [Double] = Array(repeating: 0, count: allHistories.count)

        for i in 0..<allHistories.count {
            if let first = allHistories[i].history.first {
                lastKnownPrices[i] = first.price
            }
        }

        for date in sortedDates {
            var total: Double = 0
            for i in 0..<allHistories.count {
                if let price = priceByDatePerWatch[i][date] {
                    lastKnownPrices[i] = price
                }
                total += lastKnownPrices[i]
            }
            chartPoints.append(ChartDataPoint(date: date, value: total))
        }

        let minPoints = 3
        if chartPoints.count < minPoints {
            return nil
        }

        return chartPoints
    }
}
