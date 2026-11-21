import Foundation
import Testing
import CoreLocation
@testable import RecordPath

/// Wherever someone has been, the passport map has something to outline.
@MainActor
struct CountryOutlineTests {
    /// India is left without an outline on purpose; the other three are too small or not a
    /// place at all (QO is "outlying Oceania").
    private let withoutOutline: Set<String> = ["IN", "BQ", "TK", "QO"]

    @Test func everyCountedRegionHasAnOutline() {
        let missing = Continent.all.flatMap(\.regions).filter { WorldStampMap.pieces(of: $0, visited: []).isEmpty }
        #expect(Set(missing) == withoutOutline)
    }

    @Test func outlinesAreRealShapes() {
        for code in Continent.all.flatMap(\.regions) {
            for ring in WorldStampMap.pieces(of: code, visited: []) {
                #expect(ring.count >= 4, "\(code) has a piece of \(ring.count) points")
                #expect(ring.allSatisfy { abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }, "\(code) is off the map")
            }
        }
    }

    @Test func aSmallCountryIsDrawn() {
        #expect(WorldStampMap.pieces(of: "SG", visited: []).count == 1)
        #expect(!WorldStampMap.pieces(of: "VA", visited: []).isEmpty)
        #expect(!WorldStampMap.pieces(of: "MT", visited: []).isEmpty)
    }

    @Test func chinaIsDrawnWholeWithTaiwanAndHainan() {
        let china = WorldStampMap.pieces(of: "CN", visited: [])
        func covers(_ latitude: Double, _ longitude: Double) -> Bool {
            china.contains { CountryBorders.contains($0, CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) }
        }
        #expect(covers(39.9, 116.4))   // Beijing
        #expect(covers(23.7, 121.0))   // Taiwan
        #expect(covers(19.2, 109.7))   // Hainan
        #expect(covers(29.6, 91.1))    // Lhasa
    }

    @Test func anIslandYouWentToIsDrawnEvenWhenSmall() {
        let bali = CLLocationCoordinate2D(latitude: -8.65, longitude: 115.22)
        let indonesia = WorldStampMap.pieces(of: "ID", visited: [bali])
        #expect(indonesia.contains { CountryBorders.contains($0, bali) })
    }

    @Test func overseasTerritoriesStandOnTheirOwn() {
        let cayenne = CLLocationCoordinate2D(latitude: 4.0, longitude: -53.0)
        #expect(WorldStampMap.pieces(of: "GF", visited: []).contains { CountryBorders.contains($0, cayenne) })
        #expect(!WorldStampMap.pieces(of: "FR", visited: []).contains { CountryBorders.contains($0, cayenne) })
        #expect(WorldStampMap.pieces(of: "FR", visited: []).contains { CountryBorders.contains($0, CLLocationCoordinate2D(latitude: 46.5, longitude: 2.5)) })
    }
}
