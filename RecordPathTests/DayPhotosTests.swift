import Foundation
import Testing
import CoreLocation
@testable import RecordPath

/// Which pictures taken during a visit count as taken at the place.
struct DayPhotosTests {
    private let place = CLLocation(latitude: 1.3009, longitude: 103.8390)
    private let sameSite = CLLocation(latitude: 1.3050, longitude: 103.8420)
    private let anotherCity = CLLocation(latitude: 3.1390, longitude: 101.6869)

    @Test func aPhotoTakenSomewhereElseIsLeftOut() {
        #expect(DayPhotos.belongs(photoAt: sameSite, to: place, locatedOnly: false))
        #expect(!DayPhotos.belongs(photoAt: anotherCity, to: place, locatedOnly: false))
        #expect(!DayPhotos.belongs(photoAt: anotherCity, to: place, locatedOnly: true))
    }

    @Test func aPictureWithNoLocationStaysUnlessThePersonLeavesThoseOut() {
        #expect(DayPhotos.belongs(photoAt: nil, to: place, locatedOnly: false))
        #expect(!DayPhotos.belongs(photoAt: nil, to: place, locatedOnly: true))
        #expect(DayPhotos.belongs(photoAt: sameSite, to: place, locatedOnly: true))
    }
}
