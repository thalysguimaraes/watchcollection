import Foundation

enum PhotoType: String, Codable, CaseIterable, Sendable {
    case dial = "Dial"
    case caseback = "Caseback"
    case bracelet = "Bracelet"
    case box = "Box"
    case papers = "Papers"
    case general = "General"
    case wristShot = "Wrist Shot"

    var icon: String {
        switch self {
        case .dial: return "clock.fill"
        case .caseback: return "gearshape.fill"
        case .bracelet: return "link"
        case .box: return "shippingbox.fill"
        case .papers: return "doc.fill"
        case .general: return "photo.fill"
        case .wristShot: return "hand.raised.fill"
        }
    }
}

struct WatchPhoto: Codable, Identifiable, Equatable {
    var id: String
    var imageData: Data?
    var thumbnailData: Data?
    var caption: String?
    var photoType: PhotoType
    var sortOrder: Int
    var dateAdded: Date
    var collectionItemId: String?

    init(
        id: String = UUID().uuidString,
        imageData: Data? = nil,
        photoType: PhotoType = .general,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.imageData = imageData
        self.photoType = photoType
        self.sortOrder = sortOrder
        self.dateAdded = Date()
    }
}

