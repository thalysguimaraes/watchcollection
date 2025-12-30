import Foundation

extension Date {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    func formattedLong() -> String {
        Self.dateFormatter.dateStyle = .long
        Self.dateFormatter.timeStyle = .none
        return Self.dateFormatter.string(from: self)
    }

    func formattedAbbreviated() -> String {
        Self.dateFormatter.dateStyle = .medium
        Self.dateFormatter.timeStyle = .none
        return Self.dateFormatter.string(from: self)
    }
}
