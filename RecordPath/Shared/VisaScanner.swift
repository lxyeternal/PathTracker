import Foundation
import Vision
import UIKit
import CoreImage

/// Reads a visa from a photo, on the device. The two machine-readable lines at the foot of a
/// visa are the reliable part — country, number, name and the expiry date, each with a check
/// digit — and the printed text around them fills in the type, entries and length of stay.
enum VisaScanner {
    /// What could be read; anything missing is left for the person to fill in.
    struct Reading {
        var country: String?
        var category: String?
        var number: String?
        var holder: String?
        var post: String?
        var issued: Date?
        var expires: Date?
        /// From the machine lines; kept only to tell it apart from the visa's own dates.
        var birth: Date?
        var entries: TravelDocument.Entries?
        var stayDays: Int?
        /// The expiry came from the machine-readable lines and its check digit matched.
        var verified = false
        var isPassport = false
    }

    static func read(_ image: UIImage) async -> Reading {
        parse(await lines(of: image))
    }

    /// Everything legible on the page. When the machine lines don't come through, they are
    /// read once more from the bottom of the page alone, enlarged and in high contrast, the
    /// way dedicated MRZ readers do; both readings go into the parse.
    static func lines(of image: UIImage) async -> [String] {
        let lines = await recognize(image)
        guard !parse(lines).verified, let zone = machineZone(of: image) else { return lines }
        return lines + (await recognize(zone, languages: ["en-US"]))
    }

    /// The lower part of the page, where the machine lines are, enlarged, grey and crisp.
    static func machineZone(of image: UIImage) -> UIImage? {
        let upright = UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(at: .zero) }
        guard let cgImage = upright.cgImage else { return nil }
        let width = CGFloat(cgImage.width), height = CGFloat(cgImage.height)
        let crop = CGRect(x: 0, y: height * 0.55, width: width, height: height * 0.45).integral
        guard let zone = cgImage.cropping(to: crop) else { return nil }
        let scale = min(3, max(1, 2_400 / width))
        let filtered = CIImage(cgImage: zone)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.35])
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale])
        guard let output = CIContext().createCGImage(filtered, from: filtered.extent) else { return nil }
        return UIImage(cgImage: output)
    }

    private static func recognize(_ image: UIImage, languages: [String] = ["en-US", "zh-Hans", "ja-JP", "fr-FR", "de-DE", "pt-BR"]) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                // Top to bottom, so labels come before their values.
                let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                continuation.resume(returning: sorted.compactMap { $0.topCandidates(1).first?.string })
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) } catch { continuation.resume(returning: []) }
            }
        }
    }

    // MARK: Parsing

    static func parse(_ lines: [String]) -> Reading {
        var reading = Reading()
        if let mrz = machineReadable(lines) {
            apply(mrz, to: &reading)
            if !mrz.givenNames.contains(" "), let fuller = printedName(surname: mrz.surname, given: mrz.givenNames, in: lines) {
                reading.holder = "\(mrz.surname) \(fuller)"
            }
        }
        let text = lines.joined(separator: "\n")
        let upper = text.uppercased()

        if reading.country == nil {
            if upper.contains("SCHENGEN") || text.contains("申根") { reading.country = TravelDocument.schengen }
            else if upper.contains("UNITED STATES") { reading.country = "US" }
            else if upper.contains("JAPAN") || text.contains("日本国") { reading.country = "JP" }
            else if upper.contains("UNITED KINGDOM") { reading.country = "GB" }
            else if upper.contains("CANADA") { reading.country = "CA" }
            else if upper.contains("BRASIL/BRAZIL") || upper.contains("REPUBLICA FEDERATIVA DO BRASIL") { reading.country = "BR" }
            else if upper.contains("REPUBLIC OF KOREA") || text.contains("대한민국") { reading.country = "KR" }
        }
        reading.post = post(in: lines)
        reading.entries = reading.entries ?? entries(in: upper, text: text)
        reading.stayDays = reading.stayDays ?? stayDays(in: upper, text: text)
        if reading.category == nil { reading.category = category(in: upper, country: reading.country) }

        let calendar = Calendar.current
        // The holder's birthday is printed too; it's neither the start nor the end of anything.
        let dates = allDates(in: text).filter { date in reading.birth.map { !calendar.isDate($0, inSameDayAs: date) } ?? true }
            .filter { $0 > calendar.date(byAdding: .year, value: -15, to: .now)! }
        if reading.expires == nil, let last = dates.max() { reading.expires = last }
        if let expires = reading.expires {
            // The latest date before the expiry within ten years of it: the issue date, or the
            // first day of validity, either of which is where the visa's life starts.
            let floor = calendar.date(byAdding: .year, value: -10, to: expires)!
            reading.issued = labelled(lines, labels: issueLabels).filter { $0 < expires && $0 >= floor }.first
                ?? dates.filter { $0 < expires && $0 >= floor && !calendar.isDate($0, inSameDayAs: expires) }.max()
        }
        return reading
    }

    /// The machine-readable zone of a visa (V…) or a passport (P…): two lines of 36 or 44.
    struct MRZ {
        let documentType: Character
        let issuer: String
        let surname: String
        let givenNames: String
        let number: String
        let birth: Date?
        let expiry: Date?
        let expiryChecked: Bool
    }

    /// A line as the machine wrote it: capitals, digits and fillers. Anything else OCR saw
    /// there — «, ‹, *, a stray bracket — can only have been a filler.
    static func machineLine(_ line: String) -> String {
        String(line.uppercased().filter { $0 != " " }.map { c -> Character in
            (c.isASCII && (c.isUppercase || c.isNumber)) || c == "<" ? c : "<"
        })
    }

    static func machineReadable(_ lines: [String]) -> MRZ? {
        let cleaned = lines.map(machineLine)
        // The first line ends in fillers and OCR often drops some; the second's fields sit at
        // fixed places, and only its last check digit may go missing.
        // OCR sometimes puts a stray fragment between the two: look a few lines on for the second.
        let pairs = cleaned.indices.flatMap { i in
            cleaned[(i + 1)..<min(i + 4, cleaned.count)].map { (cleaned[i], $0) }
        }
        for (first, second) in pairs
        where (first.first == "V" || first.first == "P") && first.count >= 12 && second.count >= 27
            && first.filter({ $0 == "<" }).count >= 2 && second.prefix(9).contains(where: \.isNumber)
            && second.dropFirst(10).prefix(3).allSatisfy({ !$0.isNumber || "0125686".contains($0) }) {
            let one = Array(first)
            var two = Array(second)
            // Each field is digits or letters by definition: put right what OCR swapped.
            func set(_ range: Range<Int>, _ fix: (String) -> String) {
                guard range.upperBound <= two.count else { return }
                two.replaceSubrange(range, with: Array(fix(String(two[range]))))
            }
            set(9..<10, numeric); set(10..<13, alphabetic); set(13..<20, numeric); set(21..<27, numeric)
            if two.count > 27 { set(27..<28, numeric) }
            let number = corrected(String(two[0..<9]), check: two[9])
            let birthDigits = String(two[13..<19]), expiryDigits = String(two[21..<27])
            let numberOK = check(number) == two[9], birthOK = check(birthDigits) == two[19]
            // Without its own check digit the expiry still stands when the rest of the line checks out.
            let expiryOK = two.count > 27 ? check(expiryDigits) == two[27] : numberOK && birthOK
            let issuer = alphabetic(String(one[2..<5])).replacingOccurrences(of: "<", with: "")
            // SURNAME<<GIVEN<NAMES<<<<: anything after the next double filler is noise.
            let names = String(one[5...]).components(separatedBy: "<<").filter { !$0.isEmpty }
            func name(_ part: String?) -> String {
                alphabetic(part ?? "").replacingOccurrences(of: "<", with: " ").trimmingCharacters(in: .whitespaces)
            }
            let given = names.count > 1 && names[1].count > 1 ? name(names[1]) : ""
            return MRZ(documentType: one[0], issuer: issuer, surname: name(names.first), givenNames: given,
                       number: number.replacingOccurrences(of: "<", with: ""),
                       birth: date(yymmdd: birthDigits, future: false), expiry: date(yymmdd: expiryDigits, future: true),
                       expiryChecked: expiryOK)
        }
        return nil
    }

    /// A document number OCR may have misread: tries the letters and digits that look alike,
    /// a few at a time, until one reading matches its check digit.
    static func corrected(_ field: String, check digit: Character) -> String {
        if check(field) == digit { return field }
        let swaps: [Character: Character] = ["0": "O", "O": "0", "1": "I", "I": "1", "5": "S", "S": "5", "8": "B", "B": "8",
                                             "2": "Z", "Z": "2", "6": "G", "G": "6", "D": "0", "Q": "0"]
        let chars = Array(field)
        let doubtful = chars.indices.filter { swaps[chars[$0]] != nil }.prefix(6)
        for mask in 1..<(1 << doubtful.count) {
            var attempt = chars
            for (bit, index) in doubtful.enumerated() where mask & (1 << bit) != 0 { attempt[index] = swaps[chars[index]]! }
            let candidate = String(attempt)
            if check(candidate) == digit { return candidate }
        }
        return field
    }

    /// The name as printed on the page, "DOE, JOHN" or "JOHN DOE", when it's a fuller
    /// version of what the machine lines gave: OCR drops a letter there now and then.
    static func printedName(surname: String, given: String, in lines: [String]) -> String? {
        guard surname.count >= 2 else { return nil }
        for line in lines {
            let words = line.uppercased().components(separatedBy: CharacterSet.letters.inverted).filter { $0.count >= 2 }
            guard words.contains(surname) else { continue }
            for word in words where word != surname && word.count >= given.count && word.count <= given.count + 2 {
                // The machine's reading must be the printed one with a letter or two missing.
                var rest = Substring(word)
                if given.allSatisfy({ c in
                    guard let at = rest.firstIndex(of: c) else { return false }
                    rest = rest[rest.index(after: at)...]
                    return true
                }), word != given {
                    return word
                }
            }
        }
        return nil
    }

    private static func apply(_ mrz: MRZ, to reading: inout Reading) {
        reading.isPassport = mrz.documentType == "P"
        let code = alpha2(mrz.issuer)
        reading.country = code.map { !reading.isPassport && Schengen.members.contains($0) ? TravelDocument.schengen : $0 }
        reading.number = mrz.number.isEmpty ? nil : mrz.number
        let name = [mrz.surname, mrz.givenNames].filter { !$0.isEmpty }.joined(separator: " ")
        reading.holder = name.isEmpty ? nil : name
        reading.birth = mrz.birth
        if mrz.expiryChecked { reading.expires = mrz.expiry }
        reading.verified = mrz.expiryChecked && mrz.expiry != nil
    }

    /// In a field that must be letters — names, country codes — the digits OCR mistook for them.
    private static func alphabetic(_ text: String) -> String {
        String(text.map { c -> Character in
            switch c {
            case "0": "O"
            case "1": "I"
            case "2": "Z"
            case "5": "S"
            case "6": "G"
            case "8": "B"
            default: c
            }
        })
    }

    /// OCR reads digits as letters now and then: in a field that must be digits, fix the usual ones.
    private static func numeric(_ text: String) -> String {
        String(text.map { c -> Character in
            switch c {
            case "O", "Q", "D": "0"
            case "I", "L": "1"
            case "Z": "2"
            case "S": "5"
            case "B": "8"
            case "G": "6"
            default: c
            }
        })
    }

    /// ICAO 9303's check digit: weights 7, 3, 1 over digits, letters as 10–35, fillers as 0.
    static func check(_ field: String) -> Character {
        let weights = [7, 3, 1]
        var total = 0
        for (i, c) in field.enumerated() {
            let value: Int
            if let digit = c.wholeNumberValue { value = digit }
            else if let ascii = c.asciiValue, c.isLetter { value = Int(ascii) - 55 }
            else { value = 0 }
            total += value * weights[i % 3]
        }
        return Character(String(total % 10))
    }

    private static func date(yymmdd: String, future: Bool) -> Date? {
        guard yymmdd.count == 6, let yy = Int(yymmdd.prefix(2)), let mm = Int(yymmdd.dropFirst(2).prefix(2)),
              let dd = Int(yymmdd.suffix(2)) else { return nil }
        let year = future ? 2000 + yy : (yy > 50 ? 1900 + yy : 2000 + yy)
        return Calendar.current.date(from: DateComponents(year: year, month: mm, day: dd))
    }

    private static let issueLabels = ["ISSUE DATE", "DATE OF ISSUE", "DATA DE EMISS", "AUSSTELLUNGSDATUM", "発給日", "签发日期"]

    /// Dates printed right after one of the labels, in order.
    private static func labelled(_ lines: [String], labels: [String]) -> [Date] {
        lines.indices.compactMap { i in
            guard labels.contains(where: { lines[i].uppercased().contains($0) }) else { return nil }
            return lines[(i + 1)...].prefix(3).lazy.compactMap { allDates(in: $0).first }.first
                ?? allDates(in: lines[i]).first
        }
    }

    /// The line after "Issuing Post Name" or "Issued in".
    private static func post(in lines: [String]) -> String? {
        for (label, value) in zip(lines, lines.dropFirst()) {
            let key = label.uppercased()
            if key.contains("ISSUING POST") || key.hasPrefix("ISSUED IN") || key.contains("DELIVRE A") || label.contains("発給地") {
                let cleaned = value.trimmingCharacters(in: .whitespaces)
                if cleaned.count >= 3, cleaned.count <= 24, cleaned.allSatisfy({ $0.isLetter || $0 == " " }) { return cleaned.uppercased() }
            }
        }
        return nil
    }

    private static func entries(in upper: String, text: String) -> TravelDocument.Entries? {
        if upper.range(of: #"\bMULT"#, options: .regularExpression) != nil || text.contains("多次") || text.contains("数次") { return .multiple }
        if upper.contains("DOUBLE") || text.contains("两次") || text.contains("二次") { return .double }
        if upper.contains("SINGLE") || text.contains("一次") || text.contains("1次") { return .single }
        // "Entries M" / "Entries S" on a US visa.
        if let match = upper.range(of: #"ENTRIES\s*\n?\s*([MS2])\b"#, options: .regularExpression) {
            let value = upper[match].last
            return value == "M" ? .multiple : value == "2" ? .double : .single
        }
        return nil
    }

    private static func stayDays(in upper: String, text: String) -> Int? {
        let patterns = [#"DURATION OF STAY\D{0,20}(\d{1,3})"#, #"DUREE DU SEJOUR\D{0,20}(\d{1,3})"#, #"(\d{1,3})\s*(DAYS|JOURS|TAGE|DIAS|DÍAS|GIORNI)"#,
                        #"停留期间?\D{0,6}(\d{1,3})"#, #"(\d{1,3})\s*日"#, #"(\d{1,3})\s*天"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let source = pattern.contains("停留") || pattern.contains("日") || pattern.contains("天") ? text : upper
            if let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
               let range = Range(match.range(at: 1), in: source), let days = Int(source[range]), (1...365).contains(days) {
                return days
            }
        }
        return nil
    }

    private static func category(in upper: String, country: String?) -> String? {
        // "B1/B2", which OCR also reads as B1/82 or 81/B2.
        if upper.range(of: #"\b[B8]-?1\s?/\s?[B8]-?2\b"#, options: .regularExpression) != nil { return "B1/B2" }
        if let match = upper.range(of: #"\b(B1|B2|F-?1|J-?1|H-?1B|L-?1|O-?1)\b"#, options: .regularExpression) {
            return String(upper[match]).replacingOccurrences(of: "-", with: "")
        }
        if country == "BR", upper.contains("VIVIS") { return "VIVIS" }
        if country == TravelDocument.schengen {
            if upper.range(of: #"TYPE[^\n]{0,30}\bC\b"#, options: .regularExpression) != nil { return "C" }
            if upper.range(of: #"TYPE[^\n]{0,30}\bD\b"#, options: .regularExpression) != nil { return "D" }
            return "C"
        }
        if upper.contains("TEMPORARY VISITOR") { return String(localized: "短期滞在", bundle: .appLanguage) }
        if upper.contains("VISITOR") || upper.contains("TOURIS") { return String(localized: "旅游", bundle: .appLanguage) }
        if upper.contains("STUDENT") { return String(localized: "学生", bundle: .appLanguage) }
        if upper.contains("BUSINESS") { return String(localized: "商务", bundle: .appLanguage) }
        return nil
    }

    /// Every date printed on it, in the ways visas write them: 15MAR2024, 15 MAR 2024,
    /// 15.03.2024, 2024/03/15, 2024年3月15日.
    static func allDates(in text: String) -> [Date] {
        let calendar = Calendar(identifier: .gregorian)
        let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        var found: [Date] = []
        func add(_ y: Int, _ m: Int, _ d: Int) {
            guard (1990...2099).contains(y), (1...12).contains(m), (1...31).contains(d),
                  let date = calendar.date(from: DateComponents(year: y, month: m, day: d)) else { return }
            found.append(date)
        }
        func each(_ pattern: String, in source: String, _ body: ([String]) -> Void) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                body((1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: source).map { String(source[$0]) } })
            }
        }
        let upper = text.uppercased()
        each(#"(\d{1,2})\s?(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[A-Z]*\s?(\d{4}|\d{2})\b"#, in: upper) { g in
            guard g.count == 3, let d = Int(g[0]), let m = months.firstIndex(of: g[1]), var y = Int(g[2]) else { return }
            if y < 100 { y += 2000 }
            add(y, m + 1, d)
        }
        // Bilingual months, 28 SET/SEP 1998: the English one after the slash.
        each(#"(\d{1,2})\s?[A-Z]{3}\s?/\s?(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)\s?(\d{4})"#, in: upper) { g in
            guard g.count == 3, let d = Int(g[0]), let m = months.firstIndex(of: g[1]), let y = Int(g[2]) else { return }
            add(y, m + 1, d)
        }
        // Two-digit years, 17-06-25, as on Schengen stickers.
        each(#"\b(\d{2})-(\d{2})-(\d{2})\b"#, in: text) { g in
            guard g.count == 3, let d = Int(g[0]), let m = Int(g[1]), let y = Int(g[2]) else { return }
            add(2000 + y, m, d)
        }
        each(#"\b(\d{1,2})[./-](\d{1,2})[./-](\d{4})\b"#, in: text) { g in
            guard g.count == 3, let d = Int(g[0]), let m = Int(g[1]), let y = Int(g[2]) else { return }
            add(y, m, d)
        }
        each(#"\b(\d{4})[./-](\d{1,2})[./-](\d{1,2})\b"#, in: text) { g in
            guard g.count == 3, let y = Int(g[0]), let m = Int(g[1]), let d = Int(g[2]) else { return }
            add(y, m, d)
        }
        each(#"(\d{4})\s?年\s?(\d{1,2})\s?月\s?(\d{1,2})\s?日"#, in: text) { g in
            guard g.count == 3, let y = Int(g[0]), let m = Int(g[1]), let d = Int(g[2]) else { return }
            add(y, m, d)
        }
        return found
    }

    /// ICAO country codes on visas are three letters (Germany is "D").
    static func alpha2(_ code: String) -> String? {
        if code == "D" { return "DE" }
        if code.count == 2 { return code }
        return alpha3Codes[code]
    }

    /// The other way: the three letters a visa prints for a country.
    static func alpha3(_ alpha2: String) -> String? {
        if alpha2 == "DE" { return "D" }
        return alpha3Codes.first { $0.value == alpha2 }?.key
    }

    private static let alpha3Codes: [String: String] = [
        "USA": "US", "CAN": "CA", "MEX": "MX", "GBR": "GB", "IRL": "IE", "FRA": "FR", "DEU": "DE", "ITA": "IT", "ESP": "ES",
        "PRT": "PT", "NLD": "NL", "BEL": "BE", "LUX": "LU", "CHE": "CH", "AUT": "AT", "DNK": "DK", "NOR": "NO", "SWE": "SE",
        "FIN": "FI", "ISL": "IS", "POL": "PL", "CZE": "CZ", "SVK": "SK", "HUN": "HU", "SVN": "SI", "HRV": "HR", "GRC": "GR",
        "MLT": "MT", "EST": "EE", "LVA": "LV", "LTU": "LT", "LIE": "LI", "BGR": "BG", "ROU": "RO", "CYP": "CY", "TUR": "TR",
        "RUS": "RU", "UKR": "UA", "CHN": "CN", "HKG": "HK", "MAC": "MO", "TWN": "TW", "JPN": "JP", "KOR": "KR", "PRK": "KP",
        "SGP": "SG", "MYS": "MY", "THA": "TH", "VNM": "VN", "IDN": "ID", "PHL": "PH", "KHM": "KH", "LAO": "LA", "MMR": "MM",
        "IND": "IN", "LKA": "LK", "NPL": "NP", "PAK": "PK", "BGD": "BD", "MDV": "MV", "ARE": "AE", "SAU": "SA", "QAT": "QA",
        "ISR": "IL", "EGY": "EG", "MAR": "MA", "ZAF": "ZA", "KEN": "KE", "AUS": "AU", "NZL": "NZ", "BRA": "BR", "ARG": "AR",
        "CHL": "CL", "PER": "PE", "COL": "CO", "CUB": "CU", "IRN": "IR", "KAZ": "KZ", "UZB": "UZ", "MNG": "MN", "GEO": "GE",
        "ARM": "AM", "AZE": "AZ", "SRB": "RS", "MNE": "ME", "ALB": "AL", "MKD": "MK", "BIH": "BA", "JOR": "JO", "OMN": "OM",
        "BHR": "BH", "KWT": "KW", "TUN": "TN", "ETH": "ET", "TZA": "TZ", "NGA": "NG",
    ]
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
