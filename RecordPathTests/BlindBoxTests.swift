import Testing
import Foundation
import CoreLocation
@testable import RecordPath

/// Reproducible draws.
private struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        var value = state
        value ^= value >> 33
        value = value &* 0xff51_afd7_ed55_8ccd
        return value ^ (value >> 33)
    }
}

struct BlindBoxTests {
    private let beijing = CLLocation(latitude: 39.9, longitude: 116.4)

    private func draws(_ span: BlindBox.Span, mood: BlindBox.Mood = .any, context: BlindBox.Context, nearby: [BlindBox.Place] = [], count: Int = 200) -> [BlindBox.Draw] {
        var generator = Seeded(state: 42)
        return (0..<count).compactMap { _ in BlindBox.draw(span: span, mood: mood, context: context, nearby: nearby, using: &generator) }
    }

    @Test func everyLeftOutPlaceExists() {
        for id in BlindBox.leftOut { #expect(BlindBox.mustSee(id: id) != nil, Comment(rawValue: id)) }
    }

    @Test func neverGivesWhatsBeenSeenOrLeftOut() {
        let seen: Set<String> = ["forbidden-city", "kyoto", "tokyo"]
        let results = draws(.long, context: .init(visited: seen, here: beijing))
        #expect(!results.isEmpty)
        for draw in results {
            #expect(!seen.contains(draw.place.id))
            #expect(!BlindBox.leftOut.contains(draw.place.id))
        }
    }

    @Test func stayWithinReachOfTheTimeThereIs() {
        for span in [BlindBox.Span.weekend, .holiday, .long] {
            for draw in draws(span, context: .init(here: beijing)) {
                #expect(span.range.contains((draw.distance ?? 0) / 1000), Comment(rawValue: draw.place.id))
            }
        }
    }

    @Test func aDayOutNeverSendsSomeoneFar() {
        // In the middle of the Pacific nothing is a day away: say so, don't send them to Tokyo.
        let nowhere = BlindBox.Context(here: CLLocation(latitude: 0, longitude: -160))
        #expect(draws(.day, context: nowhere, count: 5).isEmpty)
        // Nor does a weekend: the closest there is, Hawaiʻi, is 2,300 km off.
        #expect(draws(.weekend, context: nowhere, count: 5).isEmpty)
        // A few days can still give the closest there is.
        let holiday = draws(.holiday, context: nowhere, count: 5)
        #expect(!holiday.isEmpty)
        #expect(holiday.allSatisfy { ($0.distance ?? .infinity) <= 2_500_000 })
    }

    @Test func nearNeedsToKnowWhereThePersonIs() {
        // Someone new, with no place recorded and no home yet, used to get Mexico for a weekend.
        #expect(draws(.day, context: .init(), count: 5).isEmpty)
        #expect(draws(.weekend, context: .init(), count: 5).isEmpty)
        #expect(!draws(.long, context: .init(), count: 5).isEmpty)
    }

    @Test func aWeekendStaysCloseEvenWhereLittleIsLeft() {
        // Everything within a weekend of Beijing seen: what's offered is still within 1,200 km.
        let near = (MustSee.china + MustSee.world).filter {
            beijing.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= 700_000
        }
        for draw in draws(.weekend, context: .init(visited: Set(near.map(\.id)), here: beijing)) {
            #expect((draw.distance ?? .infinity) <= 1_200_000, Comment(rawValue: draw.place.id))
        }
    }

    @Test func aPlaceOfThePersonsOwnCanBeDrawn() {
        let own = BlindBox.Place(id: "wish-1", name: "Nikko", region: "Japan", latitude: 36.75, longitude: 139.60, kind: .heritage)
        let results = draws(.long, context: .init(wishes: [own.id], here: beijing, custom: [own]), count: 400)
        let drawn = results.filter { $0.place.id == own.id }
        #expect(!drawn.isEmpty)
        #expect(drawn.contains { $0.reason == .wished })
    }

    @Test func neverRepeatsWhileSomethingElseIsInReach() {
        // Kuala Lumpur: one of the two hundred a weekend away. Opened once, it mustn't come again
        // while anything else can be reached, even if that means letting the range stretch.
        let kualaLumpur = CLLocation(latitude: 3.14, longitude: 101.69)
        let first = draws(.weekend, context: .init(here: kualaLumpur), count: 50)
        let only = Set(first.map(\.place.id))
        #expect(!only.isEmpty)
        let again = draws(.weekend, context: .init(here: kualaLumpur, recent: only), count: 50)
        #expect(!again.isEmpty)
        #expect(again.allSatisfy { !only.contains($0.place.id) })
        #expect(again.allSatisfy { ($0.distance ?? .infinity) <= 1_200_000 })
    }

    @Test func citiesKeepTheBoxFromRunningDry() {
        let kualaLumpur = CLLocation(latitude: 3.14, longitude: 101.69)
        let cities = BlindBoxPlanner.cities(awayFrom: [kualaLumpur.coordinate])
        // Not the city the person is in, nor one the lists already have.
        #expect(!cities.contains { $0.id == "city-Kuala Lumpur" })
        #expect(!cities.contains { $0.id == "city-Tokyo" })
        #expect(cities.contains { $0.id == "city-Penang" })
        let results = draws(.weekend, context: .init(here: kualaLumpur, cities: cities), count: 300)
        #expect(Set(results.map(\.place.id)).count >= 3)
    }

    @Test func cityNamesLoseTheirStateLetters() {
        #expect(CityName.tidy("里约热内卢 - RJ") == "里约热内卢")
        #expect(CityName.tidy("Rio de Janeiro - RJ") == "Rio de Janeiro")
        #expect(CityName.tidy("Mascot NSW") == "Mascot")
        #expect(CityName.tidy("New York") == "New York")
        #expect(CityName.tidy("LA") == "LA")
        #expect(CityName.tidy("上海") == "上海")
    }

    @Test func suburbsBelongToTheirCity() {
        #expect(WorldCities.near(CLLocation(latitude: -33.93, longitude: 151.19))?.chinese == "悉尼")
        #expect(WorldCities.near(CLLocation(latitude: 7.88, longitude: 98.39))?.english == "Phuket")
        #expect(WorldCities.near(CLLocation(latitude: -22.95, longitude: -43.21))?.chinese == "里约热内卢")
        // The middle of nowhere is nobody's suburb.
        #expect(WorldCities.near(CLLocation(latitude: 7.35, longitude: 100.33)) == nil)
        #expect(WorldCities.near(CLLocation(latitude: 39.9, longitude: 116.4)) == nil)
    }

    @Test func aDayOutUsesWhatsNearby() {
        let lake = BlindBox.Place(id: "nearby-lake", name: "Lake", region: "Beijing", latitude: 40.2, longitude: 116.4, kind: .water)
        let results = draws(.day, mood: .quiet, context: .init(here: beijing), nearby: [lake])
        #expect(results.contains { $0.place.id == lake.id })
        #expect(results.allSatisfy { $0.place.placeKind == .water || $0.place.placeKind == .wild })
    }

    @Test func moodDecidesTheKind() {
        for draw in draws(.long, mood: .history, context: .init(here: beijing)) { #expect(draw.place.placeKind == .heritage) }
    }

    @Test func wishesComeUpMoreOften() {
        let wish = "machu-picchu"
        guard BlindBox.mustSee(id: wish) != nil else { return }
        let plain = draws(.long, context: .init(here: beijing), count: 1000).filter { $0.place.id == wish }.count
        let wished = draws(.long, context: .init(wishes: [wish], here: beijing), count: 1000).filter { $0.place.id == wish }.count
        #expect(wished > plain * 2)
    }

    @Test func aRecentPlaceIsNotGivenAgainWhileThereAreOthers() {
        let recent: Set<String> = ["kyoto"]
        #expect(!draws(.long, context: .init(here: beijing, recent: recent)).contains { $0.place.id == "kyoto" })
    }

    @Test func theVisaReasonOnlyAppearsForItsCountry() throws {
        let until = try #require(Calendar.current.date(byAdding: .year, value: 5, to: .now))
        let context = BlindBox.Context(here: beijing, visas: ["JP": (name: "日本", until: until)])
        let results = draws(.long, context: context)
        let withVisa = results.filter { if case .visa = $0.reason { true } else { false } }
        #expect(!withVisa.isEmpty)
        for draw in withVisa { #expect(draw.place.mustSee?.regionEn == "Japan") }
    }

    @Test func aReasonForAKindNeverSaysWhatsFalse() {
        // Mountains have been lit, so nothing may claim there hasn't been one.
        let context = BlindBox.Context(visited: ["wutaishan", "fuji", "changbaishan", "forbidden-city"], here: beijing)
        for draw in draws(.long, context: context) {
            if case let .newKind(kind, _) = draw.reason { #expect(kind != MustSeePlace.Kind.mountain.rawValue) }
        }
        #expect(context.favourite == .mountain)
    }

    @Test func everyWorldRegionHasACountry() {
        for place in MustSee.world { #expect(!BlindBox.countries(of: place).isEmpty, Comment(rawValue: place.regionEn)) }
    }

    @Test func aTicketKnowsWhichSideOfTheBorderItIs() throws {
        #expect(BlindBox.countries(of: .init(try #require(BlindBox.mustSee(id: "forbidden-city")))) == ["CN"])
        #expect(BlindBox.countries(of: .init(try #require(BlindBox.mustSee(id: "victoria-harbour")))) == ["HK"])
        #expect(BlindBox.countries(of: .init(try #require(BlindBox.mustSee(id: "taipei-101")))) == ["TW"])
        #expect(BlindBox.countries(of: .init(try #require(BlindBox.mustSee(id: "kyoto")))) == ["JP"])
        let lake = BlindBox.Place(id: "nearby-lake", name: "Lake", region: "", latitude: 40.2, longitude: 116.4, kind: .water)
        #expect(BlindBox.countries(of: lake).isEmpty)
    }

    @Test func aLongerTripGetsStopsNearby() throws {
        let place = try #require(BlindBox.mustSee(id: "forbidden-city"))
        let stops = BlindBox.stops(around: .init(place), span: .holiday, context: .init())
        #expect(stops.count == 2)
        #expect(!stops.contains(place.id))
        for id in stops {
            let stop = try #require(BlindBox.mustSee(id: id))
            #expect(place.coordinate.latitude.distance(to: stop.latitude).magnitude < 4)
        }
        #expect(BlindBox.stops(around: .init(place), span: .day, context: .init()).isEmpty)
    }

    @Test func stopsStayOnTheSameSideOfTheBorder() throws {
        // Alishan is near Gulangyu on the map, and a permit away.
        let gulangyu = try #require(BlindBox.mustSee(id: "gulangyu"))
        for span in [BlindBox.Span.holiday, .long] {
            for id in BlindBox.stops(around: .init(gulangyu), span: span, context: .init()) {
                let stop = try #require(BlindBox.mustSee(id: id))
                #expect(BlindBox.countries(of: .init(stop)) == ["CN"], Comment(rawValue: id))
            }
        }
    }

    @Test func daysAreSharedOutWithMoreForTheMainPlace() {
        #expect(BlindBox.itinerary(days: 4, places: 3) == [1...2, 3...3, 4...4])
        #expect(BlindBox.itinerary(days: 7, places: 4) == [1...4, 5...5, 6...6, 7...7])
        #expect(BlindBox.itinerary(days: 2, places: 2) == [1...1, 2...2])
        #expect(BlindBox.itinerary(days: 2, places: 3) == [1...2])
        #expect(BlindBox.itinerary(days: 4, places: 0).isEmpty)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func holidaysFollowTheirOwnCalendars() throws {
        let calendar = Calendar.current
        let spring = try #require(Holiday.next(after: date(2027, 1, 10)))
        #expect(calendar.isDate(spring.date, inSameDayAs: date(2027, 2, 6)))
        #expect(spring.span == .long)
        let midAutumn = try #require(Holiday.next(after: date(2027, 8, 1)))
        #expect(calendar.isDate(midAutumn.date, inSameDayAs: date(2027, 9, 15)))
        let national = try #require(Holiday.next(after: date(2027, 9, 20)))
        #expect(calendar.isDate(national.date, inSameDayAs: date(2027, 10, 1)))
        #expect(national.span == .long)
        let today = try #require(Holiday.next(after: date(2027, 10, 1)))
        #expect(today.daysAway(from: date(2027, 10, 1)) == 0)
    }

    @Test func theMomentFitsTheWeek() {
        // 2027-03-06 is a Saturday, a long way from any holiday.
        #expect(BlindBoxMoment.at(date(2027, 3, 6, hour: 9), holiday: nil).span == .day)
        #expect(BlindBoxMoment.at(date(2027, 3, 3), holiday: nil).span == .weekend)
        let holiday = Holiday(name: "X", date: date(2027, 3, 13), span: .long)
        #expect(BlindBoxMoment.at(date(2027, 3, 3), holiday: holiday).span == .long)
        let farOff = Holiday(name: "X", date: date(2027, 6, 13), span: .long)
        #expect(BlindBoxMoment.at(date(2027, 3, 3), holiday: farOff).span == .weekend)
    }

    @Test func aDayOutIsTodayOnlyWhileTheMorningIsYoung() {
        let calendar = Calendar.current
        #expect(calendar.isDate(BlindBox.dayOut(from: date(2027, 3, 3, hour: 9)), inSameDayAs: date(2027, 3, 3)))
        #expect(calendar.isDate(BlindBox.dayOut(from: date(2027, 3, 3, hour: 15)), inSameDayAs: date(2027, 3, 4)))
    }

    @Test func setOffWhenThePersonUsuallyGetsMoving() {
        #expect(BlindBox.departure(early: 0.3, night: 0) == 450)
        #expect(BlindBox.departure(early: 0, night: 0.3) == 600)
        #expect(BlindBox.departure(early: 0, night: 0) == 510)
    }

    @Test func aTicketOnlyCountsArrivalsAfterItWasKept() throws {
        let place = try #require(BlindBox.mustSee(id: "forbidden-city"))
        let kept = date(2027, 3, 1)
        let ticket = BlindBox.Ticket(draw: .init(place: .init(place), reason: .none, span: .day, distance: nil), kept: kept)
        func visit(_ day: Date, near: Bool = true) -> MustSee.Visit {
            MustSee.Visit(latitude: near ? place.latitude : 31, longitude: near ? place.longitude : 121, arrival: day, countryCode: "CN")
        }
        #expect(BlindBox.arrival(of: ticket, in: [visit(date(2027, 2, 1))]) == nil)
        #expect(BlindBox.arrival(of: ticket, in: [visit(date(2027, 4, 1), near: false)]) == nil)
        let first = date(2027, 4, 1)
        #expect(BlindBox.arrival(of: ticket, in: [visit(date(2027, 5, 1)), visit(first)]) == first)
    }

    @Test func aDayOutDrawsFromTownItsEdgeAndFartherOut() {
        let here = CLLocation(latitude: 45.677, longitude: -111.043)
        func place(_ id: String, kilometresNorth: Double) -> BlindBox.Place {
            BlindBox.Place(id: id, name: id, region: "", latitude: 45.677 + kilometresNorth / 111, longitude: -111.043, kind: .wild)
        }
        // A great park two hours out with a hundred overlooks, a few things in town.
        let far = (0..<100).map { place("far-\($0)", kilometresNorth: 100 + Double($0) / 10) }
        let town = (0..<5).map { place("town-\($0)", kilometresNorth: 5 + Double($0)) }
        let edge = (0..<30).map { place("edge-\($0)", kilometresNorth: 20 + Double($0)) }
        let kept = BlindBoxPlanner.balanced(far + town + edge, known: ["edge-29"], from: here)
        #expect(kept.filter { $0.id.hasPrefix("far") }.count == 20)
        #expect(kept.filter { $0.id.hasPrefix("town") }.count == 5)
        #expect(kept.filter { $0.id.hasPrefix("edge") }.count == 20)
        // What Apple Maps knows as a sight is kept ahead of what only matched a word.
        #expect(kept.contains { $0.id == "edge-29" })
    }

    @Test func somewhereCloseIsADayOutWhenNothingIsFarther() {
        // An island: everything worth a day is within a few kilometres.
        let singapore = CLLocation(latitude: 1.3521, longitude: 103.8198)
        let garden = BlindBox.Place(id: "nearby-garden", name: "Garden", region: "", latitude: 1.40, longitude: 103.82, kind: .wild)
        var generator = SystemRandomNumberGenerator()
        var context = BlindBox.Context()
        context.here = singapore
        let draw = BlindBox.draw(span: .day, mood: .quiet, context: context, nearby: [garden], using: &generator)
        #expect(draw != nil)
    }
}
