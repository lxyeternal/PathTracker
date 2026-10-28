import Testing
import Foundation
import UIKit
import SwiftData
import CoreLocation
import MapKit
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

    @Test func markingASightAppliesToNearbyVisits() throws {
        let context = try makeContext()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let first = stay("CN", "苏州", arrival: base, hours: 2, lat: 31.32, lon: 120.63)
        let again = stay("CN", "苏州", arrival: base.addingTimeInterval(86_400), hours: 1, lat: 31.3205, lon: 120.6302)
        let elsewhere = stay("CN", "苏州", arrival: base.addingTimeInterval(3 * 3600), hours: 1, lat: 31.35, lon: 120.66)
        [first, again, elsewhere].forEach(context.insert)

        KnownPlaces.rename(first, to: "平江路", category: .sight, in: context)
        #expect(again.isLandmark && again.category == .landmark)
        #expect(!elsewhere.isLandmark)

        KnownPlaces.rename(first, to: nil, category: .clear, in: context)
        #expect(!again.isLandmark && again.tagState == .pending)
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
        ("上海", "中国上海市上海", "CN", "上海"),
        ("杭州", "中国浙江杭州", "CN", "杭州"),
    ])
    func normalizesCities(city: String, context: String, code: String, expected: String) {
        #expect(CityName.normalized(cityName: city, shortContext: context, countryCode: code) == expected)
    }

    @Test func hongKongAndMacauAreOneCityEach() {
        #expect(CityName.normalized(cityName: "中环", shortContext: "中国香港特别行政区中环", countryCode: "HK", regionName: "中国香港特别行政区") == "香港")
        #expect(CityName.normalized(cityName: "Central", shortContext: "Central, Central", countryCode: "HK", regionName: "Hong Kong SAR, China") == "Hong Kong")
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

struct WatchLinkTests {
    @Test func snapshotFromAnOlderAppVersionStillDecodes() throws {
        // An iPhone on an older version doesn't send fields added later.
        let old = #"{"generatedAt": 0, "language": "en", "distance": 1200}"#
        let snapshot = try #require(WatchSnapshot.decode(Data(old.utf8)))
        #expect(snapshot.language == "en")
        #expect(snapshot.distance == 1200)
        #expect(snapshot.isEnabled)
        #expect(snapshot.receivedRecordings.isEmpty)
    }

    @Test func recordingInfoSurvivesTheTrip() throws {
        let info = WatchRecordingInfo(id: UUID(), activity: .hiking, start: Date(timeIntervalSince1970: 1_800_000_000),
                                      end: Date(timeIntervalSince1970: 1_800_003_600), distance: 5400)
        #expect(WatchRecordingInfo(metadata: info.metadata) == info)
        #expect(WatchRecordingInfo(metadata: ["other": 1]) == nil)
    }

    @Test func routeIsSplitAtGapsAndKeptWithinBudget() {
        let morning = (0..<3000).map { point(31.2 + Double($0) * 0.00001, 121.4 + sin(Double($0) / 40) * 0.001, Double($0) * 2) }
        let evening = (0..<500).map { point(31.3, 121.5 + Double($0) * 0.0001, 20_000 + Double($0) * 2) }
        let segments = WatchBridge.segments(from: [
            (morning[0].timestamp, morning[2999].timestamp, morning),
            (evening[0].timestamp, evening[499].timestamp, evening),
        ])
        #expect(segments.count == 2)
        #expect(segments.reduce(0) { $0 + $1.count } <= 600)
        #expect(segments[0].first?.lat == morning[0].latitude)
        #expect(segments[1].last?.lon == evening[499].longitude)
    }

    @Test func nearbyChunksJoinIntoOneLine() {
        let a = (0..<20).map { point(31.2, 121.4 + Double($0) * 0.0002, Double($0) * 10) }
        let b = (0..<20).map { point(31.2, 121.404 + Double($0) * 0.0002, 300 + Double($0) * 10) }
        let segments = WatchBridge.segments(from: [(a[0].timestamp, a[19].timestamp, a), (b[0].timestamp, b[19].timestamp, b)])
        #expect(segments.count == 1)
    }
}

@MainActor
struct WatchRecordingImportTests {
    private func recording(start: TimeInterval = 0, minutes: Int = 30) -> ([TrackPoint], WatchRecordingInfo) {
        let points = (0...(minutes * 6)).map { point(31.2 + Double($0) * 0.0001, 121.4, start + Double($0) * 10) }
        let info = WatchRecordingInfo(id: UUID(), activity: .hiking, start: points[0].timestamp,
                                      end: points[points.count - 1].timestamp, distance: TrackPoint.distance(of: points))
        return (points, info)
    }

    @Test func becomesATripWithItsRoute() throws {
        let context = ModelContext(PersistenceController.makeContainer(inMemory: true))
        let (points, info) = recording()
        let trip = try #require(WatchRecordingImporter.importRecording(points: points, info: info, into: context))
        #expect(trip.id == info.id)
        #expect(trip.endDate == info.end)
        #expect(trip.coverEmoji == "🥾")
        let chunks = try context.fetch(FetchDescriptor<TrackChunk>())
        #expect(chunks.reduce(0) { $0 + $1.pointCount } >= points.count)
        #expect(chunks.allSatisfy { $0.tripID == info.id && $0.mode == .walking })
        #expect(WatchRecordingImporter.receivedIDs.first == info.id)
    }

    @Test func arrivingTwiceDoesNothingNew() throws {
        let context = ModelContext(PersistenceController.makeContainer(inMemory: true))
        let (points, info) = recording()
        WatchRecordingImporter.importRecording(points: points, info: info, into: context)
        WatchRecordingImporter.importRecording(points: points, info: info, into: context)
        #expect(try context.fetchCount(FetchDescriptor<Trip>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<TrackChunk>()) == 1)
    }

    @Test func routeTheIPhoneAlreadyRecordedIsntDoubled() throws {
        let context = ModelContext(PersistenceController.makeContainer(inMemory: true))
        let (points, info) = recording()
        // The iPhone was along and recorded the same half hour.
        context.insert(TrackChunk(points: points, mode: .walking, tripID: nil))
        let trip = try #require(WatchRecordingImporter.importRecording(points: points, info: info, into: context))
        #expect(try context.fetchCount(FetchDescriptor<TrackChunk>()) == 1)
        #expect(trip.interval.duration > 0)
    }
}

struct LinkedRecordingTests {
    @Test func elevationGainIgnoresGPSJitter() {
        // Wobbling ±3 m around 100 m, then a 40 m climb in steps and a small wobble at the top.
        let altitudes = [100.0, 103, 98, 101, 97, 100, 110, 120, 130, 140, 138, 141]
        let points = altitudes.enumerated().map { i, altitude in
            TrackPoint(latitude: 31.2, longitude: 121.4, altitude: altitude, speed: 1, accuracy: 5,
                       timestamp: Date(timeIntervalSince1970: Double(i) * 10))
        }
        #expect(TrackPoint.elevationGain(of: points) == 40)
    }

    @Test func paceReadsLikeAFitnessApp() {
        #expect(Format.pace(secondsPerKilometre: 365) == "6'05\" /km")
    }

    @Test func workoutTypeRoundTrips() {
        for activity in ActivityType.allCases {
            #expect(ActivityType(workoutType: activity.workoutType) == activity)
        }
    }

    @Test @MainActor func watchRecordingJoinsTheIPhoneTripItWasStartedFrom() throws {
        let context = ModelContext(PersistenceController.makeContainer(inMemory: true))
        let trip = Trip(title: "外滩", startDate: Date(timeIntervalSince1970: 1_800_000_000))
        context.insert(trip)
        let points = (0...60).map { point(31.24 - Double($0) * 0.0002, 121.49, Double($0) * 10) }
        let info = WatchRecordingInfo(id: UUID(), activity: .walking, start: points[0].timestamp,
                                      end: points[60].timestamp, distance: TrackPoint.distance(of: points), tripID: trip.id)
        let result = WatchRecordingImporter.importRecording(points: points, info: info, into: context)
        #expect(result?.id == trip.id)
        #expect(try context.fetchCount(FetchDescriptor<Trip>()) == 1)
        let chunks = try context.fetch(FetchDescriptor<TrackChunk>())
        #expect(!chunks.isEmpty && chunks.allSatisfy { $0.tripID == trip.id })
    }

    @Test func activeRecordingTravelsInTheSnapshot() throws {
        var snapshot = WatchSnapshot()
        snapshot.activeRecording = ActiveRecording(tripID: UUID(), title: "徒步", emoji: "🥾", start: Date(), watchActivity: .hiking)
        let decoded = try #require(WatchSnapshot.decode(snapshot.encoded()))
        #expect(decoded.activeRecording == snapshot.activeRecording)
    }
}

struct ChinaCoordinatesTests {
    @Test(arguments: [
        // WGS-84 → GCJ-02 reference values from the published transform.
        (31.1774276, 121.5272106, 31.17530398364597, 121.531541859215),
        (39.911954, 116.377817, 39.91334545536069, 116.38404722455657),
        (22.543847, 113.912316, 22.540796131694766, 113.9171764808363),
    ])
    func matchesTheReferenceTransform(lat: Double, lon: Double, gcjLat: Double, gcjLon: Double) {
        let shifted = CLLocationCoordinate2D(latitude: lat, longitude: lon).onMap
        #expect(abs(shifted.latitude - gcjLat) < 1e-6)
        #expect(abs(shifted.longitude - gcjLon) < 1e-6)
    }

    @Test(arguments: [
        ("北京", 39.9042, 116.4074), ("上海", 31.2304, 121.4737), ("深圳蛇口", 22.4855, 113.9150),
        ("深圳福田口岸", 22.5200, 114.0700), ("珠海拱北", 22.2220, 113.5520), ("横琴", 22.1200, 113.5300),
        ("厦门", 24.4798, 118.0894), ("平潭", 25.5000, 119.7800), ("三亚", 18.2528, 109.5119), ("海口", 20.0440, 110.1999),
        ("北海", 21.4810, 109.1200), ("拉萨", 29.6520, 91.1720), ("日喀则", 29.2670, 88.8800), ("乌鲁木齐", 43.8256, 87.6168),
        ("喀什", 39.4704, 75.9898), ("塔城", 46.7460, 82.9800), ("阿勒泰", 47.8440, 88.1400), ("哈尔滨", 45.8038, 126.5349),
        ("黑河", 50.2450, 127.4900), ("丹东", 40.1240, 124.3900), ("延吉", 42.9000, 129.5000), ("满洲里", 49.5970, 117.4300),
        ("海拉尔", 49.2120, 119.7400), ("二连浩特", 43.6500, 111.9800), ("瑞丽", 24.0100, 97.8500), ("腾冲", 25.0200, 98.5000),
        ("景洪", 22.0100, 100.8000), ("河口", 22.5200, 103.9500), ("东兴", 21.5480, 107.9700), ("凭祥", 22.1100, 106.7500),
    ])
    func mainlandCitiesShift(name: String, lat: Double, lon: Double) {
        #expect(ChinaCoordinates.isInMainland(CLLocationCoordinate2D(latitude: lat, longitude: lon)), "\(name)")
    }

    @Test(arguments: [
        ("香港中环", 22.2819, 114.1580), ("香港罗湖", 22.5280, 114.1130), ("大屿山", 22.2600, 113.9500), ("澳门", 22.1987, 113.5439),
        ("氹仔", 22.1560, 113.5560), ("台北", 25.0330, 121.5654), ("高雄", 22.6273, 120.3014), ("金门", 24.4500, 118.3500),
        ("马祖", 26.1600, 119.9400), ("首尔", 37.5665, 126.9780), ("平壤", 39.0392, 125.7625), ("东京", 35.6762, 139.6503),
        ("乌兰巴托", 47.8864, 106.9057), ("乔巴山", 48.0700, 114.5000), ("符拉迪沃斯托克", 43.1155, 131.8855),
        ("哈巴罗夫斯克", 48.4800, 135.0700), ("河内", 21.0278, 105.8342), ("万象", 17.9757, 102.6331), ("曼谷", 13.7563, 100.5018),
        ("仰光", 16.8409, 96.1735), ("密支那", 25.3800, 97.4000), ("腊戍", 22.9400, 97.7500), ("加德满都", 27.7172, 85.3240),
        ("新德里", 28.6139, 77.2090), ("阿拉木图", 43.2220, 76.8512), ("比什凯克", 42.8746, 74.5698), ("新加坡", 1.3521, 103.8198),
    ])
    func placesOutsideTheMainlandStayPut(name: String, lat: Double, lon: Double) {
        let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        #expect(!ChinaCoordinates.isInMainland(c), "\(name)")
        #expect(c.onMap.latitude == lat && c.onMap.longitude == lon)
    }
}

struct ProvinceTests {
    // What Apple's geocoder actually returns (checked against the live service), as
    // (country code, cityWithContext, city) → expected province.
    @Test(arguments: [
        ("CN", "中国浙江杭州", "杭州", "zhejiang"), ("CN", "中国山西太原", "太原", "shanxi"), ("CN", "中国陕西西安", "西安", "shaanxi"),
        ("CN", "中国西藏自治区拉萨", "拉萨", "xizang"), ("CN", "", "内蒙古自治区", "neimenggu"), ("CN", "", "广西壮族自治区", "guangxi"),
        ("CN", "中国重庆市重庆", "重庆", "chongqing"), ("CN", "", "上海", "shanghai"),
        ("CN", "Hangzhou, Zhejiang, China", "Hangzhou", "zhejiang"), ("CN", "Taiyuan, Shanxi, China", "Taiyuan", "shanxi"),
        ("CN", "Xi'an, Shaanxi, China", "Xi'an", "shaanxi"), ("CN", "Lhasa, Tibet, China", "Lhasa", "xizang"),
        ("CN", "", "Inner Mongolia", "neimenggu"), ("CN", "", "Xinjiang", "xinjiang"), ("CN", "Shanghai, China", "Shanghai", "shanghai"),
        ("HK", "Central, Central, Hong Kong SAR, China", "Central", "hongkong"), ("MO", "", "Macao", "macau"), ("TW", "", "Xinyi District", "taiwan"),
    ])
    func findsTheProvince(code: String, region: String, city: String, expected: String) {
        #expect(Province.containing(countryCode: code, region: region.isEmpty ? nil : region, city: city)?.id == expected)
    }

    @Test func placesAbroadHaveNoProvince() {
        #expect(Province.containing(countryCode: "JP", region: "Kyoto, Japan", city: "京都") == nil)
    }

    @Test func tileMapHas34DivisionsWithoutOverlap() {
        #expect(Province.all.count == 34)
        #expect(Set(Province.all.map { "\($0.row),\($0.column)" }).count == 34)
        #expect(Province.all.allSatisfy { $0.row < Province.rows && $0.column < Province.columns })
    }

    @Test func everyCountryBelongsToAContinent() {
        let codes = Continent.all.flatMap(\.regions)
        #expect(codes.count > 200)
        #expect(Set(codes).isSuperset(of: ["CN", "JP", "SG", "US", "FR", "BR", "AU", "ZA"]))
    }
}

@MainActor
struct YearReportTests {
    private func stay(_ name: String?, city: String, code: String, lat: Double, lon: Double,
                      _ y: Int, _ m: Int, _ d: Int, hours: Double = 2) -> Stay {
        let start = Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
        let stay = Stay(arrival: start, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        stay.departure = start.addingTimeInterval(hours * 3600)
        stay.city = city
        stay.countryCode = code
        stay.customName = name
        return stay
    }

    @Test func sameCityUnderTwoNamesCountsOnce() {
        let stays = [stay(nil, city: "上海", code: "CN", lat: 31.23, lon: 121.47, 2026, 3, 1),
                     stay(nil, city: "Shanghai", code: "CN", lat: 31.20, lon: 121.44, 2026, 3, 2),
                     stay(nil, city: "苏州", code: "CN", lat: 31.30, lon: 120.58, 2026, 3, 3)]
        let names = CityNames.canonical(for: stays)
        #expect(Set(names.values).count == 2)
        #expect(names["CN|Shanghai"] == names["CN|上海"])
        #expect(WorldInsights(stays: stays).cityCount == 2)
    }

    @Test func reportFindsTheStandoutsAndWhatWasNew() {
        let home = (31.23, 121.47)
        var stays = [stay("家", city: "上海", code: "CN", lat: home.0, lon: home.1, 2025, 12, 20, hours: 200)]
        for day in 1...10 { stays.append(stay("家", city: "上海", code: "CN", lat: home.0, lon: home.1, 2026, 1, day, hours: 14)) }
        for day in 1...4 { stays.append(stay("健身房", city: "上海", code: "CN", lat: 31.20, lon: 121.50, 2026, 2, day)) }
        stays.append(stay(nil, city: "京都", code: "JP", lat: 35.01, lon: 135.77, 2026, 5, 1, hours: 30))
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 8))!
        let movements = [YearReport.Movement(start: day, distance: 12_000, mode: .walking),
                         YearReport.Movement(start: day, distance: 1_500_000, mode: .flying),
                         YearReport.Movement(start: day.addingTimeInterval(-86_400 * 30), distance: 30_000, mode: .automotive)]

        let report = YearReport.make(year: 2026, stays: stays, movements: movements, steps: [], trips: [])
        #expect(report.distance == 1_542_000)
        #expect(report.flightDistance == 1_500_000)
        #expect(report.longestDay?.distance == 30_000)
        #expect(report.favoritePlace?.name == "健身房")
        #expect(report.favoritePlace?.visits == 4)
        #expect(report.farthestPlace?.name == "京都")
        #expect(report.newCountries == ["JP"])
        #expect(report.countries.first == "CN")
    }

    @Test func firstYearHasNothingToCallNew() {
        let stays = [stay(nil, city: "上海", code: "CN", lat: 31.23, lon: 121.47, 2026, 3, 1)]
        let report = YearReport.make(year: 2026, stays: stays, movements: [], steps: [], trips: [])
        #expect(report.countries == ["CN"])
        #expect(report.newCountries.isEmpty)
        #expect(report.newCities.isEmpty)
    }
}

@MainActor
struct ArrivalNotificationTests {
    private func stay(city: String, region: String? = nil, code: String, lat: Double, lon: Double) -> Stay {
        let stay = Stay(arrival: Date(), coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        stay.city = city
        stay.region = region
        stay.countryCode = code
        stay.tagState = .tagged
        return stay
    }

    private var history: [Stay] {
        [stay(city: "上海", code: "CN", lat: 31.23, lon: 121.47), stay(city: "杭州", region: "中国浙江杭州", code: "CN", lat: 30.27, lon: 120.15)]
    }

    @Test func newCountryWins() {
        let arrival = Notifier.firstArrival(stay(city: "东京", code: "JP", lat: 35.68, lon: 139.69), after: history)
        #expect(arrival?.id == "arrival.JP")
        #expect(arrival?.kind == .country)
    }

    @Test func sightsCelebrateOnlyTheFirstVisit() {
        let garden = stay(city: "苏州", code: "CN", lat: 31.3253, lon: 120.6283)
        garden.isLandmark = true
        #expect(Notifier.firstSight(garden, after: history)?.kind == .sight)
        let earlier = stay(city: "苏州", code: "CN", lat: 31.3255, lon: 120.6285)
        earlier.isLandmark = true
        #expect(Notifier.firstSight(garden, after: history + [earlier]) == nil)
        #expect(Notifier.firstSight(stay(city: "苏州", code: "CN", lat: 31.3, lon: 120.6), after: history) == nil)
    }

    @Test func celebrationsFindTheirMedal() {
        let item = Celebrations.Item(id: "milestone.countries.10", kind: .milestone, title: "", subtitle: "")
        #expect(item.milestone == Milestone(kind: .countries, threshold: 10))
        #expect(Celebrations.Item(id: "arrival.JP", kind: .country, title: "", subtitle: "").milestone == nil)
    }

    @Test func newProvinceWhenTheCountryIsKnown() {
        let arrival = Notifier.firstArrival(stay(city: "苏州", region: "中国江苏苏州", code: "CN", lat: 31.30, lon: 120.58), after: history)
        #expect(arrival?.id == "arrival.jiangsu")
    }

    @Test func newCityInAKnownProvince() {
        let arrival = Notifier.firstArrival(stay(city: "宁波", region: "中国浙江宁波", code: "CN", lat: 29.87, lon: 121.55), after: history)
        #expect(arrival?.id == "arrival.city.CN|宁波")
    }

    @Test func familiarPlacesAndTheVeryFirstPlaceStayQuiet() {
        #expect(Notifier.firstArrival(stay(city: "Shanghai", code: "CN", lat: 31.22, lon: 121.45), after: history) == nil)
        #expect(Notifier.firstArrival(stay(city: "上海", code: "CN", lat: 31.23, lon: 121.47), after: []) == nil)
    }
}

struct MilestoneTests {
    @Test @MainActor func reachedOnTheDayItHappened() {
        let days = (0..<12).map { Date(timeIntervalSince1970: 1_800_000_000 + Double($0) * 86_400) }
        let codes = ["CN", "JP", "KR", "TH", "SG", "FR"]
        let stays = codes.enumerated().map { i, code -> Stay in
            let stay = Stay(arrival: days[i * 2], coordinate: CLLocationCoordinate2D(latitude: Double(i * 5), longitude: Double(i * 7)))
            stay.departure = days[i * 2].addingTimeInterval(3600)
            stay.countryCode = code
            stay.city = "City\(i)"
            return stay
        }
        let movements = days.map { ($0, 60_000.0) }
        let progress = MilestoneProgress(stays: stays, movements: movements)
        let reached = Dictionary(uniqueKeysWithValues: progress.reached.map { ($0.id, $0.date) })
        #expect(reached["countries.3"] == days[4])
        #expect(reached["countries.5"] == days[8])
        #expect(reached["distance.500"] == days[8])
        #expect(reached["countries.10"] == nil)
        #expect(progress.next.contains { $0.id == "countries.10" && $0.current == 6 })
        #expect(progress.next.contains { $0.id == "distance.1000" })
    }
}

struct BadgeTests {
    @Test func everyMilestoneHasItsOwnLook() {
        for kind in Milestone.Kind.allCases {
            let symbols = kind.thresholds.map { Milestone(kind: kind, threshold: $0).symbol }
            #expect(Set(symbols).count == symbols.count, "\(kind) repeats a symbol")
            #expect(kind.colors.count == 2)
        }
        #expect(Milestone(kind: .distance, threshold: 100).tier == 0)
        #expect(Milestone(kind: .distance, threshold: 1_000).tier == 2)
    }

    @Test @MainActor func everyMilestoneIsListedReachedOrNot() {
        let progress = MilestoneProgress(stays: [], movements: [(Date(), 150_000)])
        #expect(progress.all.count == Milestone.Kind.allCases.reduce(0) { $0 + $1.thresholds.count })
        #expect(progress.all.first { $0.id == "distance.100" }?.isReached == true)
        #expect(progress.all.first { $0.id == "distance.500" }?.isReached == false)
        #expect(progress.all.first { $0.id == "distance.500" }?.fraction == 0.3)
    }

    @Test func rosetteFitsItsFrame() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let bounds = Rosette(points: 18, depth: 0.05).path(in: rect).boundingRect
        #expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(bounds))
        #expect(bounds.width > 95)
    }

    @Test func medalNumbersStayShort() {
        #expect(Milestone(kind: .distance, threshold: 100).badgeNumber == "100")
        #expect(Milestone(kind: .distance, threshold: 1_000).badgeNumber == "1K")
        #expect(Milestone(kind: .distance, threshold: 40_075).badgeNumber == "40K")
        #expect(Milestone(kind: .countries, threshold: 5).badgeNumber == "5")
    }
}

@MainActor
struct PostTests {
    @Test func photosPostedToAPlaceBelongToIt() throws {
        let context = ModelContext(PersistenceController.makeContainer(inMemory: true))
        let stay = Stay(arrival: Date(), coordinate: CLLocationCoordinate2D(latitude: 31.24, longitude: 121.49))
        context.insert(stay)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000)).image { $0.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000)) }
        let png = try #require(image.pngData())
        let photo = try #require(PhotoImport.makePhoto(from: png, fallbackDate: stay.arrival, fallbackCoordinate: stay.coordinate))
        photo.stay = stay
        context.insert(photo)
        try context.save()
        #expect(stay.photos?.count == 1)
        #expect(photo.placeTitle == stay.displayName)
        // Stored at a sensible size, not the original's.
        let stored = try #require(photo.imageData.flatMap(UIImage.init(data:)))
        #expect(max(stored.size.width, stored.size.height) * stored.scale <= 2048)
        // Deleting the visit takes its photos with it.
        context.delete(stay)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<TripPhoto>()) == 0)
    }
}

@MainActor
struct PhotoFootprintTests {
    private func shot(_ hour: Double, _ lat: Double, _ lon: Double, day: Int = 1) -> PhotoFootprints.Shot {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: day))!.addingTimeInterval(hour * 3600)
        return PhotoFootprints.Shot(date: date, latitude: lat, longitude: lon)
    }

    @Test func shotsTogetherBecomeOneVisit() {
        let shots = [shot(10, 31.240, 121.490), shot(10.5, 31.241, 121.491), shot(11, 31.2405, 121.4905),
                     shot(15, 31.200, 121.440),
                     shot(10, 31.240, 121.490, day: 2)]
        let visits = PhotoFootprints.visits(from: shots)
        #expect(visits.count == 3)
        #expect(visits[0].shots == 3)
        #expect(visits[0].end.timeIntervalSince(visits[0].start) == 3600)
        #expect(visits[2].shots == 1)
    }

    @Test func recordedPlacesArentAddedAgain() {
        let visit = PhotoFootprints.visits(from: [shot(10, 31.240, 121.490), shot(11, 31.240, 121.490)])[0]
        // A long stay that began well before the photos still covers them.
        let recorded = PhotoFootprints.Known(arrival: visit.start.addingTimeInterval(-5 * 3600), departure: visit.end.addingTimeInterval(600),
                                             latitude: 31.2402, longitude: 121.4901)
        let elsewhere = PhotoFootprints.Known(arrival: visit.start, departure: visit.end, latitude: 31.30, longitude: 121.50)
        let other = PhotoFootprints.Known(arrival: visit.start.addingTimeInterval(-86_400), departure: visit.start.addingTimeInterval(-80_000),
                                          latitude: 31.24, longitude: 121.49)
        #expect(PhotoFootprints.newVisits([visit], recorded: [other, recorded, elsewhere], imported: []).skipped == 1)
        #expect(PhotoFootprints.newVisits([visit], recorded: [other, elsewhere], imported: []).new.count == 1)

        let earlier = PhotoFootprints.Known(arrival: visit.start, departure: visit.end, latitude: visit.latitude, longitude: visit.longitude)
        #expect(PhotoFootprints.newVisits([visit], recorded: [], imported: [earlier]).new.isEmpty)
    }
}

@MainActor
struct MapFocusTests {
    @Test func focusesOnTheRecentBusyRegionNotTheWholeWorld() {
        let now = Date()
        func stays(_ count: Int, _ lat: Double, _ lon: Double, daysAgo: Double) -> [Stay] {
            (0..<count).map { i in
                Stay(arrival: now.addingTimeInterval(-(daysAgo + Double(i)) * 86_400),
                     coordinate: CLLocationCoordinate2D(latitude: lat + Double(i) * 0.01, longitude: lon))
            }
        }
        let singapore = stays(40, 1.30, 103.80, daysAgo: 0)
        let chengdu = stays(8, 30.60, 104.00, daysAgo: 30)
        let paris = stays(3, 48.85, 2.35, daysAgo: 60)
        let newYork = stays(3, 40.70, -74.00, daysAgo: 90)
        let focus = MapDot.focus(MapDot.dots(for: singapore + chengdu + paris + newYork))
        let lons = focus.map(\.coordinate.longitude)
        #expect(focus.count == 48)
        #expect(lons.allSatisfy { $0 > 90 && $0 < 120 })
    }

    @Test func tripMapOpensOnTheTripNotOnHome() {
        let home = CLLocationCoordinate2D(latitude: 1.36, longitude: 103.99)
        let europe = (0..<20).map { CLLocationCoordinate2D(latitude: 46 + Double($0) * 0.2, longitude: 7 + Double($0) * 0.3) }
        let stays = [home] + europe + [home]
        let region = TrackMap.mainRegion(stays, stays: stays)
        #expect(region.count == 20)
        #expect(region.allSatisfy { $0.latitude > 40 })
        // A trip that stays in one region keeps everything.
        #expect(TrackMap.mainRegion(europe, stays: europe).count == 20)
    }
}

@MainActor
struct CityStintTests {
    private func stay(_ city: String, day: Int, hour: Double = 10, lat: Double = 30.27, lon: Double = 120.15, photos: Bool = false) -> Stay {
        let date = Calendar.current.date(from: DateComponents(year: 2020, month: 8, day: day))!.addingTimeInterval(hour * 3600)
        let stay = Stay(arrival: date, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        stay.departure = date.addingTimeInterval(3600)
        stay.city = city
        stay.countryCode = "CN"
        stay.tagState = .tagged
        if photos { stay.sourceRaw = PhotoFootprints.source }
        return stay
    }

    @Test func consecutiveDaysInACityBecomeOneStint() {
        let stays = [stay("杭州", day: 21), stay("杭州", day: 21, hour: 15), stay("杭州", day: 22), stay("杭州", day: 23),
                     stay("嘉兴", day: 24, lat: 30.75, lon: 120.75), stay("杭州", day: 27)]
        let stints = CityStint.group(stays)
        #expect(stints.count == 3)
        let first = stints.last!
        #expect(first.city == "杭州" && first.stays.count == 4 && first.days == 3)
        #expect(stints.first?.city == "杭州" && stints.first?.days == 1)
    }

    @Test func sameDayPhotoVisitsInACityAreMerged() async throws {
        let container = try ModelContainer(for: Stay.self, TrackChunk.self, Trip.self, TripPhoto.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        let morning = stay("嘉兴", day: 7, hour: 9, photos: true)
        let noon = stay("嘉兴", day: 7, hour: 12, lat: 30.76, photos: true)
        let named = stay("嘉兴", day: 7, hour: 15, photos: true)
        named.customName = "南湖"
        let nextDay = stay("嘉兴", day: 8, photos: true)
        [morning, noon, named, nextDay].forEach(context.insert)
        try context.save()

        let merged = await PhotoFootprints.consolidate(in: context)
        #expect(merged == 1)
        let left = try context.fetch(FetchDescriptor<Stay>())
        #expect(left.count == 3)
        #expect(morning.departure == noon.departure)
    }
}

struct TripFinderTests {
    private func visit(day: Int, month: Int = 8, hour: Double = 10, lat: Double, lon: Double, city: String, code: String = "CN") -> TripFinder.Visit {
        let date = Calendar.current.date(from: DateComponents(year: 2020, month: month, day: day))!.addingTimeInterval(hour * 3600)
        return TripFinder.Visit(arrival: date, departure: date.addingTimeInterval(3600), latitude: lat, longitude: lon, city: city, countryCode: code)
    }

    private var home: [TripFinder.Visit] {
        (1...28).map { visit(day: $0, month: 7, lat: 31.23, lon: 121.47, city: "上海") }
            + [1, 2, 3, 10, 11, 12].map { visit(day: $0, lat: 31.23, lon: 121.47, city: "上海") }
    }

    @Test func daysAwayBecomeOneTrip() {
        let trip = [21, 22, 23].map { visit(day: $0, lat: 30.27, lon: 120.15, city: "杭州") }
        // Hangzhou is ~170 km from Shanghai.
        let found = TripFinder.find(home + trip)
        #expect(found.count == 1)
        #expect(found.first?.days == 3)
        #expect(found.first?.cities.first == "杭州")
    }

    @Test func aDayOutNearbyIsNotATrip() {
        let outing = [visit(day: 15, lat: 30.75, lon: 120.75, city: "嘉兴")]
        #expect(TripFinder.find(home + outing).isEmpty)
    }

    @Test func goingHomeSplitsTrips() {
        let first = [5, 6].map { visit(day: $0, lat: 30.27, lon: 120.15, city: "杭州") }
        let back = [visit(day: 7, lat: 31.23, lon: 121.47, city: "上海")]
        let second = [8, 9].map { visit(day: $0, lat: 30.27, lon: 120.15, city: "杭州") }
        #expect(TripFinder.find(home + first + back + second).count == 2)
    }

    @Test func aJumpAcrossTheWorldIsAnotherTrip() {
        let tokyo = [20, 21].map { visit(day: $0, lat: 35.68, lon: 139.76, city: "東京", code: "JP") }
        let paris = [22, 23].map { visit(day: $0, lat: 48.86, lon: 2.35, city: "Paris", code: "FR") }
        #expect(TripFinder.find(home + tokyo + paris).count == 2)
    }
}

struct StampTests {
    private let day: TimeInterval = 86_400
    private let start = Date(timeIntervalSince1970: 1_780_000_000)

    private func stay(_ code: String, _ city: String, day offset: Double, hours: Double, lat: Double, lon: Double,
                      airport: Bool = false, region: String? = nil) -> Stay {
        let stay = Stay(arrival: start.addingTimeInterval(offset * day), coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        stay.departure = stay.arrival.addingTimeInterval(hours * 3600)
        stay.countryCode = code
        stay.city = city
        stay.region = region
        if airport {
            stay.categoryRaw = MKPointOfInterestCategory.airport.rawValue
            stay.placeName = "\(city) Airport"
        }
        return stay
    }

    @Test func homeIssuesThePassportAndTripsAbroadGetEntryAndExit() {
        let stays = [
            stay("CN", "上海", day: 0, hours: 200, lat: 31.23, lon: 121.47, region: "上海市"),
            stay("JP", "成田", day: 9, hours: 2, lat: 35.77, lon: 140.39, airport: true),
            stay("JP", "東京", day: 9.2, hours: 60, lat: 35.68, lon: 139.76),
            stay("CN", "上海", day: 13, hours: 300, lat: 31.23, lon: 121.47, region: "上海市"),
        ]
        let book = StampBook(stays: stays)
        #expect(book.home == "CN")
        #expect(book.passport.map(\.kind) == [.entry, .exit])
        let entry = book.passport[0]
        #expect(entry.countryCode == "JP" && entry.byAir && entry.port == "成田 Airport")
        #expect(book.passport[1].days >= 3)
        #expect(book.provinces.map(\.provinceID) == ["shanghai"])
        #expect(book.cities.compactMap(\.city).sorted() == ["上海", "成田", "東京"].sorted())
    }

    @Test func aBlipAcrossTheBorderStampsNothing() {
        let stays = [
            stay("SG", "Singapore", day: 0, hours: 300, lat: 1.29, lon: 103.85),
            // Geocoded across the strait for twenty minutes.
            stay("MY", "Johor Bahru", day: 13, hours: 0.3, lat: 1.46, lon: 103.76),
            stay("SG", "Singapore", day: 13.1, hours: 100, lat: 1.29, lon: 103.85),
        ]
        #expect(StampBook(stays: stays).passport.isEmpty)
    }

    @Test func stillAbroadHasNoExitYet() {
        let stays = [
            stay("SG", "Singapore", day: 0, hours: 300, lat: 1.29, lon: 103.85),
            stay("TH", "Bangkok", day: 14, hours: 5, lat: 13.75, lon: 100.50),
        ]
        let book = StampBook(stays: stays)
        #expect(book.passport.map(\.kind) == [.entry])
        #expect(book.passport[0].byAir, "Singapore to Bangkok is a flight")
    }

    @Test func reunionNeedsAYearAway() {
        let old = stay("CN", "杭州", day: 0, hours: 2, lat: 30.25, lon: 120.14)
        let back = stay("CN", "杭州", day: 400, hours: 1, lat: 30.2501, lon: 120.1401)
        let soon = stay("CN", "杭州", day: 100, hours: 1, lat: 30.2501, lon: 120.1401)
        let reunion = Reunion.find(back, after: [old])
        #expect(reunion?.visits == 2)
        #expect(reunion?.lastVisit == old.arrival)
        #expect(Reunion.find(soon, after: [old]) == nil)
        let elsewhere = stay("CN", "杭州", day: 400, hours: 1, lat: 30.27, lon: 120.16)
        #expect(Reunion.find(elsewhere, after: [old]) == nil)
    }

    @Test func famousCitiesGetTheirOwnStampByNameOrPlace() {
        let hangzhou = CityStampStyle.of(city: "杭州市", countryCode: "CN", coordinate: CLLocationCoordinate2D(latitude: 30.27, longitude: 120.15))
        #expect(hangzhou.motto == "西子湖畔")
        let kuta = CityStampStyle.of(city: "Kuta", countryCode: "ID", coordinate: CLLocationCoordinate2D(latitude: -8.72, longitude: 115.17))
        #expect(kuta.title == "BALI")
        let somewhere = CityStampStyle.of(city: "Smalltown", countryCode: "US", coordinate: CLLocationCoordinate2D(latitude: 44, longitude: -100))
        #expect(somewhere.title == "Smalltown" && somewhere.motto == nil)
    }

    @Test func everyProvinceHasItsOwnSealCharacter() {
        let characters = Province.all.map { ProvinceSeal.character(for: $0.id) }
        #expect(Set(characters).count == Province.all.count)
        #expect(!characters.contains("印"))
    }

    @Test func everyCountryHasAStampStyle() {
        for continent in Continent.all {
            for code in continent.regions {
                #expect(!CountryStampStyle.of(code).native.isEmpty)
            }
        }
        #expect(CountryStampStyle.of("JP").native == "日本国")
    }

    @Test func stampsTiltTheSameWayEveryTime() {
        let a = Stamp(id: "entry.JP.1", kind: .entry, date: start)
        let b = Stamp(id: "entry.JP.1", kind: .entry, date: start)
        #expect(a.tilt == b.tilt && abs(a.tilt) <= 6.5)
    }
}
