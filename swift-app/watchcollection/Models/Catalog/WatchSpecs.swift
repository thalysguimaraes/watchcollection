import Foundation

struct WatchSpecs: Codable, Hashable, Sendable {
    var caseDiameter: Double?
    var caseThickness: Double?
    var caseMaterial: String?
    var bezelMaterial: String?
    var crystalType: String?
    var waterResistance: Int?
    var lugWidth: Double?
    var dialColor: String?
    var dialNumerals: String?
    var movement: MovementSpecs?
    var braceletType: String?
    var complications: [String]?
    var features: [String]?
    var style: String?
}

struct MovementSpecs: Codable, Hashable, Sendable {
    var caliber: String?
    var type: MovementType?
    var powerReserve: Int?
    var frequency: Double?
    var jewelsCount: Int?
}

enum MovementType: String, Codable, CaseIterable, Sendable {
    case automatic = "Automatic"
    case manual = "Manual Wind"
    case quartz = "Quartz"
    case springDrive = "Spring Drive"
    case solar = "Solar"
    case kinetic = "Kinetic"
}
