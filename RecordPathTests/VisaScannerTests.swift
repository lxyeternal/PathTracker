import Testing
import Foundation
@testable import RecordPath

struct VisaScannerTests {
    /// The lines Vision read from a specimen US visa, the first one short of its fillers.
    private let specimen = ["UNITED STATES OF AMERICA", "Issuing Post Name", "BEIJING", "Visa Type/Class", "R B1/B2",
                            "Issue Date", "16MAR2024", "Expiration Date", "15MAR2034",
                            "VNUSASPECIMEN‹‹TEST<‹<<<<<<<<", "A123456784CHN9001011M3403152B1B2<<<<<<<<<<<<"]

    @Test func readsTheMachineLines() throws {
        let reading = VisaScanner.parse(specimen)
        #expect(reading.verified)
        #expect(reading.country == "US")
        #expect(reading.number == "A12345678")
        #expect(reading.holder == "SPECIMEN TEST")
        #expect(reading.category == "B1/B2")
        #expect(reading.post == "BEIJING")
        let expiry = try #require(reading.expires)
        #expect(Calendar.current.dateComponents([.year, .month, .day], from: expiry) == DateComponents(year: 2034, month: 3, day: 15))
    }

    @Test func aWrongCheckDigitIsNotVerified() {
        var lines = specimen
        lines[lines.count - 1] = "A123456784CHN9001011M3403159B1B2<<<<<<<<<<<<"
        #expect(!VisaScanner.parse(lines).verified)
    }

    @Test func aSchengenStateMeansTheSchengenArea() {
        let reading = VisaScanner.parse(["VCFRASPECIMEN<<TEST<<<<<<<<<<<<", "X12345675CHN9001011M2612204<<<<<<<<<<<<<<<<"])
        #expect(reading.country == TravelDocument.schengen)
    }

    @Test func readsDatesTheWaysVisasPrintThem() {
        let dates = VisaScanner.allDates(in: "15MAR2034 · 15.03.2034 · 2034/03/15 · 2034年3月15日")
        #expect(dates.count == 4)
        #expect(Set(dates).count == 1)
    }

    @Test func checkDigitsFollowICAO() {
        // The example from ICAO 9303: document number L898902C3 has check digit 6.
        #expect(VisaScanner.check("L898902C3") == "6")
        #expect(VisaScanner.check("340315") == "2")
    }

    @Test func schengenCountsDaysInTheWindow() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let arrival = calendar.date(byAdding: .day, value: -10, to: today)!
        let departure = calendar.date(byAdding: .day, value: -1, to: today)!
        let old = calendar.date(byAdding: .day, value: -400, to: today)!
        let allowance = Schengen.allowance(stays: [("FR", arrival, departure), ("DE", old, old), ("JP", arrival, departure)], on: today)
        #expect(allowance.used == 10)
        #expect(allowance.remaining == 80)
    }
}
