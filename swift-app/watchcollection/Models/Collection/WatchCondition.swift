import Foundation

enum WatchCondition: String, Codable, CaseIterable, Sendable {
    case unworn = "Unworn"
    case excellent = "Excellent"
    case veryGood = "Very Good"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"

    var abbreviation: String {
        switch self {
        case .unworn: return "NOS"
        case .excellent: return "EXC"
        case .veryGood: return "VG"
        case .good: return "G"
        case .fair: return "F"
        case .poor: return "P"
        }
    }

    var sortOrder: Int {
        switch self {
        case .unworn: return 0
        case .excellent: return 1
        case .veryGood: return 2
        case .good: return 3
        case .fair: return 4
        case .poor: return 5
        }
    }

    var description: String {
        switch self {
        case .unworn:
            return "Never worn, with original stickers"
        case .excellent:
            return "Minimal signs of wear, near mint"
        case .veryGood:
            return "Light wear, well maintained"
        case .good:
            return "Visible wear, fully functional"
        case .fair:
            return "Significant wear, may need service"
        case .poor:
            return "Heavy wear or damage, needs repair"
        }
    }
}
