import Testing
import Foundation
import UIKit
import SwiftData
import CoreLocation
@testable import RecordPath

private func point(_ lat: Double, _ lon: Double, _ seconds: TimeInterval, speed: Double = 1.4) -> TrackPoint {
    TrackPoint(latitude: lat, longitude: lon, altitude: 10, speed: speed, accuracy: 5,
               timestamp: Date(timeIntervalSince1970: 1_800_000_000 + seconds))
}

struct TrackCodecTests {
    @Test func roundTripKeepsEveryValue() {
        let points = (0..<500).map { point(31.2 + Double($0) * 0.0001, 121.4 + Double($0) * 0.0002, Double($0) * 5) }
        let decoded = TrackCodec.decode(TrackCodec.encode(points))
        #expect(decoded.count == points.count)
        for (a, b) in zip(points, decoded) {
            #expect(a.latitude == b.latitude)
            #expect(a.longitude == b.longitude)
            #expect(abs(a.timestamp.timeIntervalSince(b.timestamp)) < 0.01)
        }
    }

    @Test func encodingIsCompact() {
        let points = (0..<1000).map { point(31.2 + Double($0) * 0.00005, 121.4, Double($0) * 3) }
        // 32 bytes of raw data per point before compression.
        #expect(TrackCodec.encode(points).count < 32 * 1000)
    }

    @Test func emptyAndGarbageInputAreSafe() {
        #expect(TrackCodec.decode(TrackCodec.encode([])).isEmpty)
        #expect(TrackCodec.decode(Data([9, 9, 9])).isEmpty)
    }
}

struct SimplificationTests {
    @Test func straightLineCollapsesToEndpoints() {
        let points = (0...100).map { point(31.2 + Double($0) * 0.0001, 121.4, Double($0)) }
        let simplified = points.simplified(tolerance: 3)
        #expect(simplified.count == 2)
        #expect(simplified.first == points.first)
        #expect(simplified.last == points.last)
    }

    @Test func cornersAreKept() {
        let leg1 = (0...50).map { point(31.2 + Double($0) * 0.0001, 121.4, Double($0)) }
        let leg2 = (1...50).map { point(31.205, 121.4 + Double($0) * 0.0001, 50 + Double($0)) }
        let simplified = (leg1 + leg2).simplified(tolerance: 3)
        #expect(simplified.count == 3)
    }
}

struct DistanceTests {
    @Test func distanceMatchesCoreLocation() {
        let a = point(31.2245, 121.4466, 0)
        let b = point(31.2989, 121.5016, 600)
        let expected = a.location.distance(from: b.location)
        #expect(abs(TrackPoint.distance(of: [a, b]) - expected) < 0.001)
    }

    @Test func speedClassification() {
        #expect(MotionClassifier.mode(forSpeeds: [1.2, 1.4, 1.3]) == .walking)
        #expect(MotionClassifier.mode(forSpeeds: [4, 5, 5.5]) == .cycling)
        #expect(MotionClassifier.mode(forSpeeds: [12, 15, 20]) == .automotive)
        #expect(MotionClassifier.mode(forSpeeds: [220, 240]) == .flying)
        #expect(MotionClassifier.mode(forSpeeds: []) == .walking)
    }
}

@MainActor
struct InsightsTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(PersistenceController.makeContainer(inMemory: true))
    }

    private func stay(_ code: String, _ city: String, arrival: Date, hours: Double, landmark: String? = nil,
                      lat: Double = 31.2, lon: Double = 121.4) -> Stay {
        let stay = Stay(arrival: arrival, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        stay.departure = arrival.addingTimeInterval(hours * 3600)
        stay.countryCode = code
        stay.country = code
        stay.city = city
        if let landmark {
            stay.placeName = landmark
            stay.isLandmark = true
        }
        return stay
    }

    @Test func countsCountriesCitiesDaysAndLandmarks() throws {
        let context = try makeContext()
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let stays = [
            stay("CN", "上海", arrival: day.addingTimeInterval(8 * 3600), hours: 2),
            stay("CN", "上海", arrival: day.addingTimeInterval(20 * 3600), hours: 10), // runs past midnight
            stay("JP", "东京", arrival: day.addingTimeInterval(3 * 86_400), hours: 3, landmark: "东京塔", lat: 35.66, lon: 139.75),
            stay("JP", "京都", arrival: day.addingTimeInterval(4 * 86_400), hours: 3, landmark: "清水寺", lat: 34.99, lon: 135.78),
            stay("JP", "京都", arrival: day.addingTimeInterval(5 * 86_400), hours: 1, landmark: "清水寺", lat: 34.99, lon: 135.78),
        ]
        stays.forEach(context.insert)

        let insights = WorldInsights(stays: stays)
        #expect(insights.countries.count == 2)
        #expect(insights.cityCount == 3)
        #expect(insights.landmarks.count == 2) // the second 清水寺 visit is not a new landmark
        let china = try #require(insights.countries.first { $0.code == "CN" })
        #expect(china.days.count == 2) // the overnight stay touches the next day
        let japan = try #require(insights.countries.first { $0.code == "JP" })
        #expect(japan.days.count == 3)
        #expect(insights.trackedDays == 5)
    }

    @Test func frequentPlacesNeedThreeVisits() throws {
        let context = try makeContext()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var stays: [Stay] = (0..<4).map { stay("CN", "上海", arrival: base.addingTimeInterval(Double($0) * 86_400), hours: 8) }
        stays.append(stay("CN", "上海", arrival: base.addingTimeInterval(3600), hours: 1, lat: 31.25, lon: 121.45))
        stays.forEach(context.insert)
        let insights = WorldInsights(stays: stays)
        #expect(insights.frequentPlaces.count == 1)
        #expect(insights.frequentPlaces.first?.visits == 4)
    }

    @Test func renamingAppliesToNearbyVisitsOnly() throws {
        let context = try makeContext()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let home1 = stay("CN", "上海", arrival: base, hours: 8)
        let home2 = stay("CN", "上海", arrival: base.addingTimeInterval(86_400), hours: 8, lat: 31.2005, lon: 121.4005)
        let school = stay("CN", "上海", arrival: base.addingTimeInterval(3600 * 9), hours: 8, lat: 31.3, lon: 121.5)
        [home1, home2, school].forEach(context.insert)

        KnownPlaces.rename(home1, to: "家", category: .set("home"), in: context)
        #expect(home2.customName == "家")
        #expect(home2.category == .home)
        #expect(school.customName == nil)

        let newVisit = Stay(arrival: base.addingTimeInterval(2 * 86_400), coordinate: CLLocationCoordinate2D(latitude: 31.2002, longitude: 121.4001))
        KnownPlaces.applyName(to: newVisit, in: context)
        #expect(newVisit.customName == "家")
    }
}

@MainActor
struct TimelineTests {
    @Test func interleavesStaysAndMoves() throws {
        let context = ModelContext(PersistenceController.makeContainer(inMemory: true))
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let home = Stay(arrival: base, coordinate: CLLocationCoordinate2D(latitude: 31.2, longitude: 121.4))
        home.departure = base.addingTimeInterval(3600)
        let school = Stay(arrival: base.addingTimeInterval(5400), coordinate: CLLocationCoordinate2D(latitude: 31.3, longitude: 121.5))
        school.departure = base.addingTimeInterval(9000)
        let route = (0...60).map { point(31.2 + Double($0) * 0.001, 121.4 + Double($0) * 0.001, 3600 + Double($0) * 30, speed: 10) }
        let chunk = TrackChunk(points: route, mode: .automotive, tripID: nil)
        [home, school].forEach(context.insert)
        context.insert(chunk)

        let entries = Timeline.entries(stays: [school, home], chunks: [chunk])
        #expect(entries.count == 3)
        guard case .stay(let first) = entries[0], case .move(let move) = entries[1], case .stay(let last) = entries[2] else {
            Issue.record("Unexpected order: \(entries.map(\.id))")
            return
        }
        #expect(first === home)
        #expect(last === school)
        #expect(move.mode == .automotive)
    }
}

@MainActor
struct GPXTests {
    @Test func exportsTracksAndWaypoints() throws {
        let context = ModelContext(PersistenceController.makeContainer(inMemory: true))
        let points = (0..<3).map { point(31.2 + Double($0) * 0.001, 121.4, Double($0) * 10) }
        let chunk = TrackChunk(points: points, mode: .walking, tripID: nil)
        let stay = Stay(arrival: points[0].timestamp, coordinate: points[0].coordinate)
        stay.customName = "家 & <学校>"
        context.insert(chunk)
        context.insert(stay)

        let xml = GPXDocument(name: "测试", chunks: [chunk], stays: [stay]).xml()
        #expect(xml.contains("<gpx version=\"1.1\""))
        #expect(xml.components(separatedBy: "<trkpt").count - 1 == 3)
        #expect(xml.contains("<wpt"))
        #expect(xml.contains("家 &amp; &lt;学校&gt;"))
        // Must be well-formed XML.
        let parser = XMLParser(data: Data(xml.utf8))
        #expect(parser.parse())
    }
}

struct FormattingTests {
    @Test func flags() {
        #expect(String.flag(for: "JP") == "🇯🇵")
        #expect(String.flag(for: "cn") == "🇨🇳")
        #expect(String.flag(for: nil) == "🏳️")
    }

    @Test func daysInIntervalIncludesBothEnds() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000)).addingTimeInterval(22 * 3600)
        let days = calendar.days(in: DateInterval(start: start, duration: 4 * 3600))
        #expect(days.count == 2)
    }

    @Test func photoMetadataReadsNothingFromPlainData() {
        let metadata = PhotoMetadata(data: Data([0, 1, 2]))
        #expect(metadata.date == nil)
        #expect(metadata.coordinate == nil)
    }
}

@MainActor
struct RoundTwoTests {
    private func stay(_ name: String, _ lat: Double, _ lon: Double, arrival: Date, hours: Double,
                      in context: ModelContext) -> Stay {
        let stay = Stay(arrival: arrival, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        stay.departure = arrival.addingTimeInterval(hours * 3600)
        stay.placeName = name
        stay.city = "上海"
        context.insert(stay)
        return stay
    }

    @Test func routeHistoryFindsEveryCommute() throws {
        let context = ModelContext(PersistenceController.makeContainer(inMemory: true))
        let base = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        var homes: [Stay] = [], schools: [Stay] = []
        for day in 0..<5 {
            let morning = base.addingTimeInterval(Double(day) * 86_400)
            homes.append(stay("家", 31.2245, 121.4466, arrival: morning, hours: 8, in: context))
            // 30, 35, 40, 45, 50 minutes to school.
            let arrival = morning.addingTimeInterval(8 * 3600 + Double(30 + day * 5) * 60)
            schools.append(stay("学校", 31.2989, 121.5016, arrival: arrival, hours: 8, in: context))
        }
        try context.save()

        let trips = RouteHistory.trips(from: homes[0], to: schools[0], in: context)
        #expect(trips.count == 5)
        #expect(trips.map(\.duration).min() == TimeInterval(30 * 60))
        #expect(trips.first!.departure > trips.last!.departure) // newest first
        // School → home here spans the night (over 4 h), which isn't one trip.
        #expect(RouteHistory.trips(from: schools[0], to: homes[0], in: context).isEmpty)
    }

    @Test func placeVisitsGroupByNameAndDistance() throws {
        let context = ModelContext(PersistenceController.makeContainer(inMemory: true))
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let a = stay("Manner Coffee", 31.2968, 121.5122, arrival: base, hours: 1, in: context)
        let b = stay("Manner Coffee", 31.2969, 121.5121, arrival: base.addingTimeInterval(86_400), hours: 1, in: context)
        // Same chain, different shop across town: a different place.
        let c = stay("Manner Coffee", 31.2245, 121.4466, arrival: base.addingTimeInterval(2 * 86_400), hours: 1, in: context)
        let groups = PlaceVisits.group([a, b, c])
        #expect(groups.count == 2)
        #expect(groups.contains { $0.visits.count == 2 })
        #expect(PlaceVisits.around(a, in: [a, b, c]).visits.count == 2)
    }

    @Test func speedFormatting() {
        #expect(Format.speed(10).contains("36"))
    }
}

@MainActor
struct RoundFourTests {
    @Test func gpxRoundTripAndNoDuplicates() throws {
        let source = ModelContext(PersistenceController.makeContainer(inMemory: true))
        let points = (0..<50).map { point(31.2 + Double($0) * 0.0005, 121.4, Double($0) * 10) }
        let chunk = TrackChunk(points: points, mode: .walking, tripID: nil)
        source.insert(chunk)
        let xml = GPXDocument(name: "测试", chunks: [chunk], stays: []).xml()
        let url = URL.temporaryDirectory.appending(path: "roundtrip-\(UUID().uuidString).gpx")
        try xml.write(to: url, atomically: true, encoding: .utf8)

        let target = ModelContext(PersistenceController.makeContainer(inMemory: true))
        let first = try GPXImporter.importFile(at: url, into: target)
        #expect(first.tracks == 1)
        #expect(first.points == 50)
        let imported = try target.fetch(FetchDescriptor<TrackChunk>())
        #expect(imported.count == 1)
        #expect(abs(imported[0].distance - chunk.distance) < 1)

        let second = try GPXImporter.importFile(at: url, into: target)
        #expect(second.tracks == 0)
        #expect(second.skippedDuplicates == 1)
        #expect(try target.fetchCount(FetchDescriptor<TrackChunk>()) == 1)
    }

    /// Our own export can split a track (privacy zones) so times no longer match exactly;
    /// re-importing it must still add nothing, places included.
    @Test func reimportingSplitExportAddsNothing() throws {
        let context = ModelContext(PersistenceController.makeContainer(inMemory: true))
        let points = (0..<100).map { point(31.2 + Double($0) * 0.0005, 121.4, Double($0) * 10) }
        let chunk = TrackChunk(points: points, mode: .walking, tripID: nil)
        let stay = Stay(arrival: points[0].timestamp, coordinate: points[0].coordinate)
        stay.placeName = "起点"
        context.insert(chunk)
        context.insert(stay)
        try context.save()

        // Simulate an export that cut the track in two around a hidden area.
        let first = TrackChunk(points: Array(points[0..<40]), mode: .walking, tripID: nil)
        let second = TrackChunk(points: Array(points[55..<100]), mode: .walking, tripID: nil)
        let xml = GPXDocument(name: "split", chunks: [first, second], stays: [stay]).xml()
        let url = URL.temporaryDirectory.appending(path: "split-\(UUID().uuidString).gpx")
        try xml.write(to: url, atomically: true, encoding: .utf8)

        let result = try GPXImporter.importFile(at: url, into: context)
        #expect(result.tracks == 0)
        #expect(result.places == 0)
        #expect(try context.fetchCount(FetchDescriptor<TrackChunk>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Stay>()) == 1)
    }

    @Test func importRejectsGarbage() throws {
        let url = URL.temporaryDirectory.appending(path: "bad-\(UUID().uuidString).gpx")
        try "not a gpx file".write(to: url, atomically: true, encoding: .utf8)
        let context = ModelContext(PersistenceController.makeContainer(inMemory: true))
        #expect(throws: (any Error).self) { try GPXImporter.importFile(at: url, into: context) }
    }

    @Test func privacyZoneCutsTrack() {
        let zones = PrivacyZones.shared
        let home = CLLocationCoordinate2D(latitude: 31.2, longitude: 121.4)
        zones.add(name: "测试家", at: home)
        defer { if let zone = zones.zone(near: home) { zones.remove(zone) } }
        // Walk from 1 km south of home, through it, to 1 km north.
        let walk = (0...40).map { point(31.191 + Double($0) * 0.00045, 121.4, Double($0) * 10) }
        let segments = zones.visibleSegments(of: walk)
        #expect(segments.count == 2)
        #expect(segments.allSatisfy { $0.allSatisfy { !zones.isHidden($0.coordinate) } })
    }
}

@MainActor
struct ScaleTests {
    /// Three years of everyday life: ~6 stays a day.
    @Test func insightsStayFastWithYearsOfData() throws {
        let context = ModelContext(PersistenceController.makeContainer(inMemory: true))
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let places: [(Double, Double, String, String)] = [
            (31.2245, 121.4466, "CN", "上海"), (31.2989, 121.5016, "CN", "上海"), (31.2968, 121.5122, "CN", "上海"),
            (35.6586, 139.7454, "JP", "东京"), (48.8584, 2.2945, "FR", "巴黎"), (40.7580, -73.9855, "US", "纽约"),
        ]
        var stays: [Stay] = []
        for day in 0..<(365 * 3) {
            for slot in 0..<6 {
                let place = places[(day / 90 % 2 == 1 && slot > 2) ? 3 + (day % 3) : slot % 3]
                let stay = Stay(arrival: base.addingTimeInterval(Double(day) * 86_400 + Double(slot) * 4 * 3600),
                                coordinate: CLLocationCoordinate2D(latitude: place.0 + Double(day % 7) * 0.0002, longitude: place.1))
                stay.departure = stay.arrival.addingTimeInterval(3 * 3600)
                stay.countryCode = place.2
                stay.city = place.3
                stays.append(stay)
            }
        }
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            let insights = WorldInsights(stays: stays)
            #expect(insights.countries.count == 4)
            #expect(insights.trackedDays >= 365 * 3)
        }
        #expect(elapsed < .seconds(3), "WorldInsights took \(elapsed) for \(stays.count) stays")
        _ = context
    }
}

struct TripDateTests {
    @Test func singleDayTripShowsOneDate() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let trip = Trip(title: "t", startDate: day)
        trip.endDate = calendar.date(byAdding: .day, value: 1, to: day)
        #expect(trip.dateRangeText == day.formatted(.dateTime.year().month().day()))

        trip.endDate = calendar.date(byAdding: .day, value: 3, to: day)
        #expect(trip.dateRangeText != day.formatted(.dateTime.year().month().day()))
    }
}

struct CityNameTests {
    @Test(arguments: [
        ("Minato", "Minato, Tokyo", "JP", "Tokyo"),
        ("港区", "港区, 东京都", "JP", "东京"),
        ("Kyoto", "Kyoto, Kyoto", "JP", "Kyoto"),
        ("City of Westminster, London", "London, England", "GB", "London"),
        ("New York", "New York, NY", "US", "New York"),
        ("Hangzhou", "Hangzhou, Zhejiang", "CN", "Hangzhou"),
        ("Shanghai", "Shanghai", "CN", "Shanghai"),
    ])
    func normalizesCities(city: String, context: String, code: String, expected: String) {
        #expect(CityName.normalized(cityName: city, shortContext: context, countryCode: code) == expected)
    }

    @Test func fallsBackToCityNameWithoutContext() {
        #expect(CityName.normalized(cityName: "Brooklyn", shortContext: "", countryCode: "US") == "Brooklyn")
        #expect(CityName.normalized(cityName: nil, shortContext: nil, countryCode: nil) == nil)
    }
}

struct ImportDuplicateTests {
    @Test func coverageThreshold() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let recorded = [DateInterval(start: base, duration: 3600)]
        // Fully inside an existing track: duplicate.
        #expect(GPXImporter.isAlreadyRecorded(DateInterval(start: base.addingTimeInterval(600), duration: 600), in: recorded))
        // Only half covered: new data.
        #expect(!GPXImporter.isAlreadyRecorded(DateInterval(start: base.addingTimeInterval(1800), duration: 3600), in: recorded))
        // A different day entirely.
        #expect(!GPXImporter.isAlreadyRecorded(DateInterval(start: base.addingTimeInterval(86_400), duration: 600), in: recorded))
    }
}

@MainActor
struct HomeBaseTests {
    @Test func homeIsFoundByDistanceNotName() throws {
        let context = ModelContext(PersistenceController.makeContainer(inMemory: true))
        let today = Calendar.current.startOfDay(for: Date())
        for day in 1...10 {
            let stay = Stay(arrival: today.addingTimeInterval(-Double(day) * 86_400 + 8 * 3600),
                            coordinate: CLLocationCoordinate2D(latitude: 31.2245, longitude: 121.4466))
            stay.departure = stay.arrival.addingTimeInterval(3600)
            stay.city = day.isMultiple(of: 2) ? "上海" : "Shanghai" // same city, two languages
            context.insert(stay)
        }
        let home = try #require(TripSuggestionCard.homeBase(in: context))
        let pudong = Stay(arrival: today, coordinate: CLLocationCoordinate2D(latitude: 31.24, longitude: 121.50))
        let hangzhou = Stay(arrival: today, coordinate: CLLocationCoordinate2D(latitude: 30.25, longitude: 120.15))
        #expect(!TripSuggestionCard.isAway(pudong, from: home))
        #expect(TripSuggestionCard.isAway(hangzhou, from: home))
    }
}

struct AvatarTests {
    @Test @MainActor func cropsToACentredSquareAndCapsTheSize() throws {
        let wide = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        }
        let square = try #require(AccountManager.squareAvatar(from: wide))
        #expect(square.size.width == square.size.height)
        #expect(square.size.width <= AccountManager.avatarSide)

        let small = UIGraphicsImageRenderer(size: CGSize(width: 90, height: 120),
                                            format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { _ in }
        #expect(AccountManager.squareAvatar(from: small)?.size == CGSize(width: 90, height: 90))
    }
}

struct AppLanguageTests {
    @Test func explicitChoicesResolveToThemselves() {
        #expect(AppLanguage.chinese.resolved == "zh-Hans")
        #expect(AppLanguage.english.resolved == "en")
        #expect(AppLanguage.english.locale.language.languageCode == .english)
        #expect(["zh-Hans", "en"].contains(AppLanguage.system.resolved))
    }

    @Test func everyLanguageIsNamedInItself() {
        #expect(AppLanguage.chinese.nativeName == "简体中文")
        #expect(AppLanguage.english.nativeName == "English")
    }
}
