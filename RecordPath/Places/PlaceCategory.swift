import SwiftUI
import MapKit
import CoreLocation

/// A friendly grouping of MapKit's point-of-interest categories, used for icons and colors.
enum PlaceCategory: Equatable {
    case home, school, work
    case food, cafe, nightlife, shopping
    case landmark, museum, park, nature, entertainment, sports
    case transport, airport, hotel, health, other

    init(rawValue: String?) {
        guard let rawValue else { self = .other; return }
        switch rawValue {
        case "home": self = .home
        case "school": self = .school
        case "work": self = .work
        default: self = PlaceCategory(MKPointOfInterestCategory(rawValue: rawValue))
        }
    }

    init(_ category: MKPointOfInterestCategory) {
        switch category {
        case .restaurant, .bakery, .foodMarket, .brewery, .winery, .distillery: self = .food
        case .cafe: self = .cafe
        case .nightlife: self = .nightlife
        case .store: self = .shopping
        case .landmark, .castle, .fortress, .nationalMonument: self = .landmark
        case .museum, .library, .planetarium: self = .museum
        case .park, .amusementPark, .zoo, .aquarium: self = .park
        case .nationalPark, .beach, .campground, .hiking: self = .nature
        case .theater, .movieTheater, .musicVenue, .fairground, .stadium: self = .entertainment
        case .fitnessCenter, .golf, .skiing, .swimming, .tennis, .soccer, .basketball: self = .sports
        case .publicTransport, .parking, .gasStation, .evCharger, .marina: self = .transport
        case .airport: self = .airport
        case .hotel: self = .hotel
        case .hospital, .pharmacy: self = .health
        case .school, .university: self = .school
        default: self = .other
        }
    }

    /// Categories that count as "知名景点" when the user stays near them.
    static let landmarkCategories: [MKPointOfInterestCategory] = [
        .landmark, .castle, .fortress, .nationalMonument, .museum, .nationalPark, .park,
        .amusementPark, .zoo, .aquarium, .beach, .stadium, .theater, .planetarium,
    ]

    /// Whether a search result is a sight worth calling a landmark. Scenic viewpoints only
    /// have a category constant from iOS 27, so they are matched by raw value.
    static func isSight(_ category: MKPointOfInterestCategory?) -> Bool {
        guard let category else { return false }
        return landmarkCategories.contains(category) || category.rawValue == "MKPOICategoryScenicView"
    }

    /// Distance plus a handicap by how "famous" a kind of place is, for choosing among
    /// several points of interest around one spot.
    static func rankingScore(_ category: MKPointOfInterestCategory?, distance: CLLocationDistance) -> Double {
        let handicap: Double
        switch category {
        case .landmark, .nationalMonument, .castle, .fortress: handicap = 0
        case .museum, .nationalPark, .zoo, .aquarium, .planetarium, .stadium, .theater: handicap = 60
        case .park, .beach: handicap = 90
        case .amusementPark: handicap = 150
        default: handicap = 120
        }
        return distance + handicap
    }

    /// Small facilities that are never what someone means by "where I was".
    static let utilityCategories: Set<MKPointOfInterestCategory> = [
        .atm, .parking, .evCharger, .gasStation, .mailbox, .restroom,
    ]

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .school: "graduationcap.fill"
        case .work: "briefcase.fill"
        case .food: "fork.knife"
        case .cafe: "cup.and.saucer.fill"
        case .nightlife: "wineglass.fill"
        case .shopping: "bag.fill"
        case .landmark: "building.columns.fill"
        case .museum: "building.columns"
        case .park: "tree.fill"
        case .nature: "mountain.2.fill"
        case .entertainment: "theatermasks.fill"
        case .sports: "figure.run"
        case .transport: "tram.fill"
        case .airport: "airplane"
        case .hotel: "bed.double.fill"
        case .health: "cross.case.fill"
        case .other: "mappin"
        }
    }

    var tint: Color {
        switch self {
        case .home: .blue
        case .school, .work: .indigo
        case .food: .orange
        case .cafe: .brown
        case .nightlife: .purple
        case .shopping: .pink
        case .landmark, .museum: .yellow
        case .park, .nature: .green
        case .entertainment: .purple
        case .sports: .mint
        case .transport, .airport: .teal
        case .hotel: .cyan
        case .health: .red
        case .other: .gray
        }
    }
}
