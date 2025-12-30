import Foundation

actor CurrencyService {
    static let shared = CurrencyService()

    private var exchangeRates: [String: Decimal] = [:]
    private var lastFetchDate: Date?
    private let cacheValidityHours: Int = 6

    private init() {}

    func convert(_ amount: Decimal, from: String, to: String) async throws -> Decimal {
        if from == to { return amount }

        try await refreshRatesIfNeeded()

        let amountInUSD: Decimal
        if from == "USD" {
            amountInUSD = amount
        } else {
            guard let fromRate = exchangeRates[from], fromRate > 0 else {
                throw CurrencyError.rateNotFound(from)
            }
            amountInUSD = amount / fromRate
        }

        if to == "USD" {
            return amountInUSD
        }

        guard let toRate = exchangeRates[to] else {
            throw CurrencyError.rateNotFound(to)
        }
        return amountInUSD * toRate
    }

    func getRate(from: String, to: String) async throws -> Decimal {
        if from == to { return 1 }
        try await refreshRatesIfNeeded()

        let usdToFrom: Decimal
        let usdToTo: Decimal

        if from == "USD" {
            usdToFrom = 1
        } else {
            guard let rate = exchangeRates[from] else {
                throw CurrencyError.rateNotFound(from)
            }
            usdToFrom = rate
        }

        if to == "USD" {
            usdToTo = 1
        } else {
            guard let rate = exchangeRates[to] else {
                throw CurrencyError.rateNotFound(to)
            }
            usdToTo = rate
        }

        return usdToTo / usdToFrom
    }

    private func refreshRatesIfNeeded() async throws {
        if let lastFetch = lastFetchDate,
           Date().timeIntervalSince(lastFetch) < Double(cacheValidityHours * 3600),
           !exchangeRates.isEmpty {
            return
        }
        try await fetchRates()
    }

    private func fetchRates() async throws {
        let url = URL(string: "https://api.frankfurter.app/latest?from=USD")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CurrencyError.networkError
        }

        let rates = try Self.decodeRates(from: data)
        exchangeRates = rates
        exchangeRates["USD"] = 1
        lastFetchDate = Date()
    }

    private nonisolated static func decodeRates(from data: Data) throws -> [String: Decimal] {
        struct Response: Decodable {
            let rates: [String: Decimal]
        }
        return try JSONDecoder().decode(Response.self, from: data).rates
    }

    func forceRefresh() async throws {
        try await fetchRates()
    }
}

enum CurrencyError: LocalizedError {
    case rateNotFound(String)
    case networkError

    var errorDescription: String? {
        switch self {
        case .rateNotFound(let currency):
            return "Exchange rate not found for \(currency)"
        case .networkError:
            return "Failed to fetch exchange rates"
        }
    }
}
