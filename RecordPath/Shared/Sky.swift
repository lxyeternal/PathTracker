import Foundation
import CoreLocation

/// The sky over a place on a day, worked out on the phone: when the sun rose and set, and what
/// the moon looked like.
enum Sky {
    struct Sun: Equatable {
        /// nil in a polar night or under the midnight sun.
        let rise: Date?
        let set: Date?
    }

    enum MoonPhase: CaseIterable {
        case new, waxingCrescent, firstQuarter, waxingGibbous, full, waningGibbous, lastQuarter, waningCrescent

        var title: String {
            switch self {
            case .new: String(localized: "新月", bundle: .appLanguage)
            case .waxingCrescent: String(localized: "峨眉月", bundle: .appLanguage)
            case .firstQuarter: String(localized: "上弦月", bundle: .appLanguage)
            case .waxingGibbous: String(localized: "盈凸月", bundle: .appLanguage)
            case .full: String(localized: "满月", bundle: .appLanguage)
            case .waningGibbous: String(localized: "亏凸月", bundle: .appLanguage)
            case .lastQuarter: String(localized: "下弦月", bundle: .appLanguage)
            case .waningCrescent: String(localized: "残月", bundle: .appLanguage)
            }
        }

        var symbol: String {
            switch self {
            case .new: "moonphase.new.moon"
            case .waxingCrescent: "moonphase.waxing.crescent"
            case .firstQuarter: "moonphase.first.quarter"
            case .waxingGibbous: "moonphase.waxing.gibbous"
            case .full: "moonphase.full.moon"
            case .waningGibbous: "moonphase.waning.gibbous"
            case .lastQuarter: "moonphase.last.quarter"
            case .waningCrescent: "moonphase.waning.crescent"
            }
        }
    }

    struct Moon: Equatable {
        let phase: MoonPhase
        /// How much of the face is lit, 0…1.
        let illumination: Double
    }

    private static func julianDay(_ date: Date) -> Double { date.timeIntervalSince1970 / 86_400 + 2_440_587.5 }
    private static func date(julianDay: Double) -> Date { Date(timeIntervalSince1970: (julianDay - 2_440_587.5) * 86_400) }

    /// Sunrise and sunset on the day around `day` at a place, by the sunrise equation (good to
    /// a minute or two, which is all a memory needs).
    static func sun(on day: Date, at coordinate: CLLocationCoordinate2D) -> Sun {
        let rad = Double.pi / 180
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        let n = (julianDay(noon) - 2_451_545.0 + 0.0008).rounded()
        let meanNoon = n - coordinate.longitude / 360
        let anomaly = (357.5291 + 0.98560028 * meanNoon).truncatingRemainder(dividingBy: 360)
        let centre = 1.9148 * sin(anomaly * rad) + 0.02 * sin(2 * anomaly * rad) + 0.0003 * sin(3 * anomaly * rad)
        let longitude = (anomaly + centre + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
        let transit = 2_451_545.0 + meanNoon + 0.0053 * sin(anomaly * rad) - 0.0069 * sin(2 * longitude * rad)
        let declination = asin(sin(longitude * rad) * sin(23.4397 * rad))
        let latitude = coordinate.latitude * rad
        let cosHour = (sin(-0.833 * rad) - sin(latitude) * sin(declination)) / (cos(latitude) * cos(declination))
        guard abs(cosHour) <= 1 else { return Sun(rise: nil, set: nil) }
        let hour = acos(cosHour) / rad / 360
        return Sun(rise: date(julianDay: transit - hour), set: date(julianDay: transit + hour))
    }

    /// The moon's phase at a moment, from its mean synodic month.
    static func moon(at moment: Date) -> Moon {
        let synodic = 29.530588853
        var age = ((julianDay(moment) - 2_451_550.1) / synodic).truncatingRemainder(dividingBy: 1)
        if age < 0 { age += 1 }
        let illumination = (1 - cos(2 * .pi * age)) / 2
        let phase: MoonPhase = switch age {
        case ..<0.03, 0.97...: .new
        case ..<0.22: .waxingCrescent
        case ..<0.28: .firstQuarter
        case ..<0.47: .waxingGibbous
        case ..<0.53: .full
        case ..<0.72: .waningGibbous
        case ..<0.78: .lastQuarter
        default: .waningCrescent
        }
        return Moon(phase: phase, illumination: illumination)
    }
}
