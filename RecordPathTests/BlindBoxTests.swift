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
        // But a weekend can still give the closest there is.
        #expect(!draws(.weekend, context: nowhere, count: 5).isEmpty)
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
}
