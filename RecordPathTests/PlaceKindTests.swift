import Foundation
import Testing
import SwiftData
import CoreLocation
@testable import RecordPath

/// The types a person picks by hand: they show as the right kind of place and follow the
/// place to later visits.
@MainActor
struct PlaceKindTests {
    private let here = CLLocationCoordinate2D(latitude: 1.3009, longitude: 103.8390)
    private let sameBuilding = CLLocationCoordinate2D(latitude: 1.3012, longitude: 103.8393)
    private let acrossTown = CLLocationCoordinate2D(latitude: 1.3521, longitude: 103.9198)

    @Test func aMallAndARestaurantShowAsShoppingAndFood() {
        #expect(PlaceCategory(rawValue: "mall") == .shopping)
        #expect(PlaceCategory(rawValue: "restaurant") == .food)
        #expect(PlaceCategory(rawValue: "work") == .work)
    }

    @Test func markingAMallAppliesToEveryVisitNearbyAndKeepsItsName() throws {
        let context = ModelContext(PersistenceController.makeContainer(inMemory: true))
        let first = Stay(arrival: Date(timeIntervalSince1970: 1_000), coordinate: here)
        first.placeName = "ION Orchard"
        first.isLandmark = true
        let second = Stay(arrival: Date(timeIntervalSince1970: 90_000), coordinate: sameBuilding)
        let far = Stay(arrival: Date(timeIntervalSince1970: 180_000), coordinate: acrossTown)
        [first, second, far].forEach(context.insert)

        KnownPlaces.rename(first, to: "", category: .set("mall"), in: context)

        #expect(first.category == .shopping)
        #expect(second.category == .shopping)
        #expect(!first.isLandmark)
        #expect(first.customName == nil)
        #expect(first.displayName == "ION Orchard")
        #expect(far.categoryRaw == nil)
    }

    @Test func aLaterVisitToAMarkedRestaurantIsARestaurantToo() throws {
        let context = ModelContext(PersistenceController.makeContainer(inMemory: true))
        let first = Stay(arrival: Date(timeIntervalSince1970: 1_000), coordinate: here)
        context.insert(first)
        KnownPlaces.rename(first, to: nil, category: .set("restaurant"), in: context)

        let again = Stay(arrival: Date(timeIntervalSince1970: 90_000), coordinate: sameBuilding)
        let elsewhere = Stay(arrival: Date(timeIntervalSince1970: 180_000), coordinate: acrossTown)
        context.insert(again)
        context.insert(elsewhere)
        try context.save()
        KnownPlaces.applyName(to: again, in: context)
        KnownPlaces.applyName(to: elsewhere, in: context)

        #expect(again.categoryRaw == "restaurant")
        #expect(again.customName == nil)
        #expect(elsewhere.categoryRaw == nil)
    }
}
