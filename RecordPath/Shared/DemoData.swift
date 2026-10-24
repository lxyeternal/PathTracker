#if DEBUG
import Foundation
import SwiftData
import CoreLocation
import MapKit

/// Realistic sample history for development and screenshots: two weeks of home ↔ school
/// commutes in Shanghai plus a past trip to Tokyo and Kyoto. Replaces all existing data.
enum DemoData {
    private struct Place {
        let name: String
        let coordinate: CLLocationCoordinate2D
        let category: String?
        let city: String
        let country: String
        let code: String
        var landmark = false
    }

    private static let poi = MKPointOfInterestCategory.self

    private static let home = Place(name: "静安公寓", coordinate: .init(latitude: 31.2245, longitude: 121.4466),
                                    category: nil, city: "上海", country: "中国", code: "CN")
    private static let school = Place(name: "复旦大学邯郸校区", coordinate: .init(latitude: 31.2989, longitude: 121.5016),
                                      category: poi.university.rawValue, city: "上海", country: "中国", code: "CN")
    private static let cafe = Place(name: "Manner Coffee", coordinate: .init(latitude: 31.2968, longitude: 121.5122),
                                    category: poi.cafe.rawValue, city: "上海", country: "中国", code: "CN")
    private static let gym = Place(name: "江湾体育场", coordinate: .init(latitude: 31.3046, longitude: 121.5121),
                                   category: poi.stadium.rawValue, city: "上海", country: "中国", code: "CN", landmark: true)
    private static let bund = Place(name: "外滩", coordinate: .init(latitude: 31.2400, longitude: 121.4900),
                                    category: poi.landmark.rawValue, city: "上海", country: "中国", code: "CN", landmark: true)
    private static let park = Place(name: "世纪公园", coordinate: .init(latitude: 31.2155, longitude: 121.5465),
                                    category: poi.park.rawValue, city: "上海", country: "中国", code: "CN", landmark: true)
    private static let mall = Place(name: "静安嘉里中心", coordinate: .init(latitude: 31.2240, longitude: 121.4530),
                                    category: poi.store.rawValue, city: "上海", country: "中国", code: "CN")

    private static let hotelTokyo = Place(name: "新宿华盛顿酒店", coordinate: .init(latitude: 35.6866, longitude: 139.6923),
                                          category: poi.hotel.rawValue, city: "东京", country: "日本", code: "JP")
    private static let sensoji = Place(name: "浅草寺", coordinate: .init(latitude: 35.7148, longitude: 139.7967),
                                       category: poi.landmark.rawValue, city: "东京", country: "日本", code: "JP", landmark: true)
    private static let tower = Place(name: "东京塔", coordinate: .init(latitude: 35.6586, longitude: 139.7454),
                                     category: poi.landmark.rawValue, city: "东京", country: "日本", code: "JP", landmark: true)
    private static let shibuya = Place(name: "涩谷十字路口", coordinate: .init(latitude: 35.6595, longitude: 139.7005),
                                       category: poi.landmark.rawValue, city: "东京", country: "日本", code: "JP", landmark: true)
    private static let ramen = Place(name: "一兰拉面 涩谷店", coordinate: .init(latitude: 35.6617, longitude: 139.6993),
                                     category: poi.restaurant.rawValue, city: "东京", country: "日本", code: "JP")
    private static let kyotoHotel = Place(name: "京都格兰比亚酒店", coordinate: .init(latitude: 34.9858, longitude: 135.7588),
                                          category: poi.hotel.rawValue, city: "京都", country: "日本", code: "JP")
    private static let fushimi = Place(name: "伏见稻荷大社", coordinate: .init(latitude: 34.9671, longitude: 135.7727),
                                       category: poi.landmark.rawValue, city: "京都", country: "日本", code: "JP", landmark: true)
    private static let kiyomizu = Place(name: "清水寺", coordinate: .init(latitude: 34.9949, longitude: 135.7850),
                                        category: poi.landmark.rawValue, city: "京都", country: "日本", code: "JP", landmark: true)
    private static let pudong = Place(name: "浦东国际机场", coordinate: .init(latitude: 31.1443, longitude: 121.8083),
                                      category: poi.airport.rawValue, city: "上海", country: "中国", code: "CN")
    private static let narita = Place(name: "成田国际机场", coordinate: .init(latitude: 35.7720, longitude: 140.3929),
                                      category: poi.airport.rawValue, city: "成田", country: "日本", code: "JP")

    @MainActor
    static func generate(in context: ModelContext) {
        try? context.delete(model: TrackChunk.self)
        try? context.delete(model: Stay.self)
        try? context.delete(model: TripPhoto.self)
        try? context.delete(model: Trip.self)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var generator = SystemRandomNumberGenerator()

        // Two weeks of everyday life.
        var carry: Stay?
        for offset in (0...13).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            var plan: [(Place, Double, Double, MovementMode)] // place, arrive hour, leave hour, mode to get there
            if isWeekend {
                plan = [(home, 0, 10.5, .walking),
                        (offset % 2 == 0 ? park : bund, 11.3, 14.6, .automotive),
                        (mall, 15.4, 17.8, .automotive),
                        (home, 18.1, 24, .walking)]
            } else {
                plan = [(home, 0, 7.9, .walking),
                        (school, 8.6, 12.1, .automotive),
                        (cafe, 12.3, 13.2, .walking),
                        (school, 13.4, 17.4, .walking),
                        (gym, 17.6, 18.8, .walking),
                        (home, 19.5, 24, .cycling)]
            }
            carry = write(day: day, plan: plan, carry: carry, in: context, using: &generator)
        }

        // A trip to Japan a month ago.
        if let tripStart = calendar.date(byAdding: .day, value: -32, to: today) {
            let days: [[(Place, Double, Double, MovementMode)]] = [
                [(home, 0, 6.5, .walking), (pudong, 7.6, 9.5, .automotive), (narita, 13.0, 13.8, .flying),
                 (hotelTokyo, 15.3, 17.5, .automotive), (shibuya, 17.9, 19.0, .walking), (ramen, 19.1, 20.0, .walking),
                 (hotelTokyo, 20.6, 24, .automotive)],
                [(hotelTokyo, 0, 9.0, .walking), (sensoji, 9.8, 11.6, .automotive), (tower, 12.6, 14.3, .automotive),
                 (hotelTokyo, 15.2, 24, .automotive)],
                [(hotelTokyo, 0, 8.0, .walking), (kyotoHotel, 10.6, 12.5, .automotive), (kiyomizu, 13.0, 15.0, .automotive),
                 (kyotoHotel, 15.6, 24, .walking)],
                [(kyotoHotel, 0, 7.5, .walking), (fushimi, 8.0, 10.6, .automotive), (kyotoHotel, 11.1, 12.0, .automotive),
                 (pudong, 18.0, 19.0, .flying), (home, 20.3, 24, .automotive)],
            ]
            var tripCarry: Stay?
            for (index, plan) in days.enumerated() {
                if let day = calendar.date(byAdding: .day, value: index, to: tripStart) {
                    tripCarry = write(day: day, plan: plan, carry: tripCarry, in: context, using: &generator)
                }
            }
            let trip = Trip(title: "东京 · 京都", startDate: tripStart.addingTimeInterval(6.5 * 3600))
            trip.endDate = calendar.date(byAdding: .day, value: 3, to: tripStart)?.addingTimeInterval(20.3 * 3600)
            trip.coverEmoji = "🗻"
            trip.notes = "第一次去日本。浅草寺人很多，伏见稻荷的千本鸟居一路爬到山顶。"
            context.insert(trip)
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: "debug.demoSteps")
    }

    /// Writes one day's stays and the tracks between them. `carry` is last night's stay,
    /// which a plan entry starting at 00:00 continues instead of starting a new visit.
    @MainActor
    @discardableResult
    private static func write(day: Date, plan: [(Place, Double, Double, MovementMode)], carry: Stay?, in context: ModelContext,
                              using generator: inout SystemRandomNumberGenerator) -> Stay? {
        let now = Date()
        var previous: (Place, Date)?
        var last: Stay?
        for (place, arriveHour, leaveHour, mode) in plan {
            let arrival = arriveHour == 0 ? day : day.addingTimeInterval(arriveHour * 3600 + Double.random(in: -400...400, using: &generator))
            let departure = leaveHour >= 24 ? day.addingTimeInterval(86_400 + 7.5 * 3600)
                : day.addingTimeInterval(leaveHour * 3600 + Double.random(in: -400...400, using: &generator))
            guard arrival < now else { break }

            if let (from, left) = previous, left < arrival {
                let points = route(from: from.coordinate, to: place.coordinate, start: left, end: min(arrival, now),
                                   jitter: mode == .flying ? 0 : 6, using: &generator)
                for start in stride(from: 0, to: points.count, by: 380) {
                    let slice = Array(points[max(0, start - 1)..<min(start + 380, points.count)])
                    if slice.count > 1 { context.insert(TrackChunk(points: slice, mode: mode, tripID: nil)) }
                }
            }

            if arriveHour == 0, let carry,
               carry.location.distance(from: CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)) < 200 {
                carry.departure = departure > now ? nil : departure
                last = carry
            } else {
                let stay = Stay(arrival: arrival, coordinate: place.coordinate.jittered(by: 15, using: &generator))
                stay.departure = departure > now ? nil : departure
                stay.placeName = place.name
                stay.categoryRaw = place.category
                stay.city = place.city
                stay.country = place.country
                stay.countryCode = place.code
                stay.isLandmark = place.landmark
                stay.tagState = .tagged
                context.insert(stay)
                last = stay
            }
            previous = (place, departure)
        }
        return last
    }

    /// A gently curving path between two places with a point every ~25 m.
    private static func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, start: Date, end: Date,
                              jitter: Double, using generator: inout SystemRandomNumberGenerator) -> [TrackPoint] {
        let a = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let b = CLLocation(latitude: to.latitude, longitude: to.longitude)
        let distance = a.distance(from: b)
        let count = max(2, min(Int(distance / 25), 3000))
        let duration = end.timeIntervalSince(start)
        let bend = Double.random(in: -0.18...0.18, using: &generator)
        var points: [TrackPoint] = []
        for i in 0...count {
            let t = Double(i) / Double(count)
            // Offset perpendicular to the straight line so routes look like streets, not rulers.
            let curve = sin(t * .pi) * bend
            let lat = from.latitude + (to.latitude - from.latitude) * t - (to.longitude - from.longitude) * curve
            let lon = from.longitude + (to.longitude - from.longitude) * t + (to.latitude - from.latitude) * curve
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon).jittered(by: jitter, using: &generator)
            points.append(TrackPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 8,
                                     speed: distance / max(duration, 1), accuracy: 6,
                                     timestamp: start.addingTimeInterval(duration * t)))
        }
        return points
    }
}

private extension CLLocationCoordinate2D {
    func jittered(by meters: Double, using generator: inout SystemRandomNumberGenerator) -> CLLocationCoordinate2D {
        guard meters > 0 else { return self }
        let dLat = Double.random(in: -meters...meters, using: &generator) / 111_320
        let dLon = Double.random(in: -meters...meters, using: &generator) / (111_320 * cos(latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: latitude + dLat, longitude: longitude + dLon)
    }
}
#endif
