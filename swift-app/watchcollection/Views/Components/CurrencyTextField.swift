import SwiftUI

struct CurrencyTextField: View {
    let currency: Currency
    @Binding var value: Decimal?
    var placeholder: String = "Price"

    @State private var text: String = ""
    @State private var isUpdating = false
    @FocusState private var isFocused: Bool

    private var formatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = currency.locale
        f.minimumFractionDigits = currency.fractionDigits
        f.maximumFractionDigits = currency.fractionDigits
        f.usesGroupingSeparator = true
        return f
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .focused($isFocused)
            .onChange(of: text) { _, newValue in
                guard !isUpdating else { return }
                handleInput(newValue)
            }
            .onChange(of: currency.code) { _, _ in
                reformatCurrentValue()
            }
            .onAppear {
                initializeText()
            }
    }

    private func handleInput(_ input: String) {
        let digits = input.filter { $0.isNumber }
        guard digits.count <= 12 else {
            isUpdating = true
            text = formatCents(Int(digits.dropLast()) ?? 0)
            isUpdating = false
            return
        }

        let cents = Int(digits) ?? 0

        isUpdating = true
        text = cents > 0 ? formatCents(cents) : ""
        isUpdating = false

        if cents > 0 {
            let divisor = pow(10, currency.fractionDigits)
            value = Decimal(cents) / divisor
        } else {
            value = nil
        }
    }

    private func formatCents(_ cents: Int) -> String {
        let decimalValue = Decimal(cents) / pow(10, currency.fractionDigits)
        return formatter.string(from: decimalValue as NSDecimalNumber) ?? ""
    }

    private func reformatCurrentValue() {
        guard let currentValue = value, currentValue > 0 else {
            text = ""
            return
        }
        let cents = NSDecimalNumber(decimal: currentValue * pow(10, currency.fractionDigits)).intValue
        isUpdating = true
        text = formatCents(cents)
        isUpdating = false
    }

    private func initializeText() {
        guard text.isEmpty, let existingValue = value, existingValue > 0 else { return }
        let cents = NSDecimalNumber(decimal: existingValue * pow(10, currency.fractionDigits)).intValue
        text = formatCents(cents)
    }
}
