import Testing
import Foundation
import UIKit
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
        let reading = VisaScanner.parse(["VCFRASPECIMEN<<TEST<<<<<<<<<<<<", "X123456785CHN9001011M2612204<<<<<<<<<<<<<<<<"])
        #expect(reading.country == TravelDocument.schengen)
    }

    /// What OCR does to real visas: O read as 0 in the name, fillers read as * and X, a
    /// fragment of the second line wedged between the two, and a letter dropped from the name.
    @Test func survivesWhatOCRDoesToRealVisas() {
        let zeros = VisaScanner.parse(["VNUSAD0E<<J0HN<<<<<<<<<<<<<<<<<<", "X123456785CHN9001011M2708263B3<<<<<<<<<<<<<<"])
        #expect(zeros.holder == "DOE JOHN")
        #expect(zeros.verified)
        let noise = VisaScanner.parse(["VCDNKDOE<<JOHN<*<<<<<<<<<X<<<<<<<<<", "X123456785CHN9001011M2507134<1120617"])
        #expect(noise.holder == "DOE JOHN")
        #expect(noise.country == TravelDocument.schengen)
        let wedged = VisaScanner.parse(["V<BRADOE<<JOHN<<<<<<<<<<", "<<<08", "X123456785CHN9001011M3603055"])
        #expect(wedged.country == "BR")
        #expect(wedged.verified)
        let dropped = VisaScanner.parse(["DOE, JOHNNY", "VCDNKDOE<<JOHNY<<<<<<<<<<", "X123456785CHN9001011M2507134<1120617"])
        #expect(dropped.holder == "DOE JOHNNY")
    }

    @Test func theBirthdayIsNotTheIssueDate() {
        let reading = VisaScanner.parse(["Birth Date", "01JAN1990", "Issue Date", "28AUG2026", "Expiration Date", "26AUG2027",
                                         "VNUSADOE<<JOHN<<<<<<<<<<<<<<<<<", "X123456785CHN9001011M2708263B3<<<<<<<<<<<<<<"])
        #expect(Calendar.current.dateComponents([.year, .month, .day], from: reading.issued!) == DateComponents(year: 2026, month: 8, day: 28))
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

/// Reads real visa photos kept outside the repository — they carry a person's details — and
/// compares each with the reading it should give. Runs only when pointed at a folder:
/// TEST_RUNNER_VISA_SAMPLES=/path/to/folder, holding `name.jpg` next to `name.json`.
struct RealVisaTests {
    private struct Expected: Decodable {
        var country: String?, holder: String?, number: String?, expires: String?, issued: String?, category: String?
        var stayDays: Int?, entries: String?, verified: Bool?
    }

    @Test func realSamples() async throws {
        guard let folder = ProcessInfo.processInfo.environment["VISA_SAMPLES"] else { return }
        let files = try FileManager.default.contentsOfDirectory(atPath: folder).filter { $0.hasSuffix(".jpg") }.sorted()
        #expect(!files.isEmpty)
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        var report = ""
        defer { try? report.write(toFile: (folder as NSString).appendingPathComponent("report.txt"), atomically: true, encoding: .utf8) }
        for file in files {
            let base = (folder as NSString).appendingPathComponent((file as NSString).deletingPathExtension)
            let image = try #require(UIImage(contentsOfFile: base + ".jpg"))
            let expected = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: URL(fileURLWithPath: base + ".json")))
            let lines = await VisaScanner.lines(of: image)
            let reading = VisaScanner.parse(lines)
            report += "\(file) lines: \(lines.joined(separator: " | "))\n"
            let label = Comment(rawValue: file)
            report += "\(file): country=\(reading.country ?? "-") holder=\(reading.holder ?? "-") number=\(reading.number ?? "-") "
                + "expires=\(reading.expires.map(day.string) ?? "-") issued=\(reading.issued.map(day.string) ?? "-") "
                + "category=\(reading.category ?? "-") stay=\(reading.stayDays.map(String.init) ?? "-") "
                + "entries=\(reading.entries?.rawValue ?? "-") verified=\(reading.verified)\n"
            if let value = expected.country { #expect(reading.country == value, label) }
            if let value = expected.holder { #expect(reading.holder == value, label) }
            if let value = expected.number { #expect(reading.number == value, label) }
            if let value = expected.expires { #expect(reading.expires.map(day.string) == value, label) }
            if let value = expected.issued { #expect(reading.issued.map(day.string) == value, label) }
            if let value = expected.category { #expect(reading.category == value, label) }
            if let value = expected.stayDays { #expect(reading.stayDays == value, label) }
            if let value = expected.entries { #expect(reading.entries?.rawValue == value, label) }
            if let value = expected.verified { #expect(reading.verified == value, label) }
        }
    }
}
