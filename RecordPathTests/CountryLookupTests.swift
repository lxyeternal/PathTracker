import Foundation
import Testing
import CoreLocation
@testable import RecordPath

/// The country of a place worked out on the device, for when Apple's lookup has no answer.
struct CountryLookupTests {
    private func code(_ lat: Double, _ lon: Double) -> String? {
        CountryLookup.code(at: CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }

    @Test func placesAroundTheWorldAreInTheirCountries() {
        #expect(code(48.8584, 2.2945) == "FR")       // Eiffel Tower
        #expect(code(35.6586, 139.7454) == "JP")     // Tokyo Tower
        #expect(code(40.6892, -74.0445) == "US")     // Statue of Liberty, on an island
        #expect(code(-33.8568, 151.2153) == "AU")    // Sydney Opera House, on the shore
        #expect(code(1.2834, 103.8607) == "SG")      // Marina Bay
        #expect(code(29.9792, 31.1342) == "EG")      // Giza
        #expect(code(-13.1631, -72.5450) == "PE")    // Machu Picchu
        #expect(code(39.9163, 116.3972) == "CN")     // The Forbidden City
        #expect(code(64.1466, -21.9426) == "IS")     // Reykjavik
    }

    @Test func anEnclaveIsItsOwnCountryAndIndiaIsFoundWithoutAnOutline() {
        #expect(code(41.9022, 12.4539) == "VA")      // St Peter's, inside Italy
        #expect(code(43.7384, 7.4246) == "MC")       // Monaco
        #expect(code(27.1751, 78.0421) == "IN")      // Taj Mahal
        #expect(code(27.7172, 85.3240) == "NP")      // Kathmandu, India's neighbour
    }

    @Test func theOpenSeaIsNoCountry() {
        #expect(code(0, -150) == nil)
        #expect(code(-45, 60) == nil)
    }

    @MainActor
    @Test func aPlaceAppleCouldNotNameStillGetsItsCountry() {
        let stay = Stay(arrival: .now, coordinate: CLLocationCoordinate2D(latitude: 48.8584, longitude: 2.2945))
        PlaceTagger.fillCountryOffline(stay)
        #expect(stay.countryCode == "FR")
        #expect(stay.country != nil)

        let named = Stay(arrival: .now, coordinate: CLLocationCoordinate2D(latitude: 48.8584, longitude: 2.2945))
        named.countryCode = "XX"
        PlaceTagger.fillCountryOffline(named)
        #expect(named.countryCode == "XX")
    }
}
