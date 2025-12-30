import Foundation

struct Currency: Codable, Hashable, Identifiable {
    let code: String
    let symbol: String
    let name: String
    let flag: String

    var id: String { code }

    static let usd = Currency(code: "USD", symbol: "$", name: "US Dollar", flag: "🇺🇸")
    static let brl = Currency(code: "BRL", symbol: "R$", name: "Brazilian Real", flag: "🇧🇷")
    static let eur = Currency(code: "EUR", symbol: "€", name: "Euro", flag: "🇪🇺")
    static let gbp = Currency(code: "GBP", symbol: "£", name: "British Pound", flag: "🇬🇧")
    static let chf = Currency(code: "CHF", symbol: "CHF", name: "Swiss Franc", flag: "🇨🇭")
    static let jpy = Currency(code: "JPY", symbol: "¥", name: "Japanese Yen", flag: "🇯🇵")

    static let all: [Currency] = [.usd, .brl, .eur, .gbp, .chf, .jpy]

    static func from(code: String) -> Currency? {
        all.first { $0.code == code }
    }

    var locale: Locale {
        switch code {
        case "USD": return Locale(identifier: "en_US")
        case "GBP": return Locale(identifier: "en_GB")
        case "EUR": return Locale(identifier: "de_DE")
        case "BRL": return Locale(identifier: "pt_BR")
        case "CHF": return Locale(identifier: "de_CH")
        case "JPY": return Locale(identifier: "ja_JP")
        default: return Locale(identifier: "en_US")
        }
    }

    var fractionDigits: Int {
        code == "JPY" ? 0 : 2
    }

    var decimalSeparator: String {
        switch code {
        case "EUR", "BRL": return ","
        default: return "."
        }
    }

    var groupingSeparator: String {
        switch code {
        case "CHF": return "'"
        case "EUR", "BRL": return "."
        default: return ","
        }
    }

    func format(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.currencySymbol = symbol
        formatter.locale = locale
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(symbol)\(amount)"
    }

    func formatCompact(_ amount: Decimal) -> String {
        let value = NSDecimalNumber(decimal: amount).doubleValue
        let absValue = abs(value)

        let suffix: String
        let divisor: Double

        if absValue >= 1_000_000 {
            suffix = "M"
            divisor = 1_000_000
        } else if absValue >= 1_000 {
            suffix = "K"
            divisor = 1_000
        } else {
            return format(amount)
        }

        let shortened = value / divisor
        let formatted = shortened.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", shortened)
            : String(format: "%.1f", shortened)

        return "\(symbol)\(formatted)\(suffix)"
    }

    func formatInput(_ rawDigits: String) -> String {
        let digits = rawDigits.filter { $0.isNumber }
        guard !digits.isEmpty else { return "" }

        let integerDigits: String
        let decimalDigits: String

        if fractionDigits > 0 && digits.count > fractionDigits {
            let splitIndex = digits.index(digits.endIndex, offsetBy: -fractionDigits)
            integerDigits = String(digits[..<splitIndex])
            decimalDigits = String(digits[splitIndex...])
        } else if fractionDigits > 0 {
            integerDigits = "0"
            decimalDigits = String(repeating: "0", count: fractionDigits - digits.count) + digits
        } else {
            integerDigits = digits
            decimalDigits = ""
        }

        var formattedInteger = ""
        for (index, char) in integerDigits.reversed().enumerated() {
            if index > 0 && index % 3 == 0 {
                formattedInteger = groupingSeparator + formattedInteger
            }
            formattedInteger = String(char) + formattedInteger
        }

        if formattedInteger.isEmpty {
            formattedInteger = "0"
        }

        if fractionDigits > 0 {
            return formattedInteger + decimalSeparator + decimalDigits
        } else {
            return formattedInteger
        }
    }

    func parseInput(_ formatted: String) -> Decimal? {
        var cleaned = formatted
        cleaned = cleaned.replacingOccurrences(of: groupingSeparator, with: "")
        cleaned = cleaned.replacingOccurrences(of: decimalSeparator, with: ".")
        cleaned = cleaned.filter { $0.isNumber || $0 == "." }
        return Decimal(string: cleaned)
    }

    func rawDigits(from formatted: String) -> String {
        formatted.filter { $0.isNumber }
    }
}
