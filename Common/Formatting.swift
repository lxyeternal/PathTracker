import Foundation

enum Format {
    static func distance(_ meters: Double) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        if meters < 1000 {
            return measurement.formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                                     numberFormatStyle: .number.precision(.fractionLength(0))).locale(appLocale))
        }
        return measurement.converted(to: .kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(meters < 100_000 ? 1 : 0))).locale(appLocale))
    }

    static func duration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = appLocale
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = interval >= 86_400 ? [.day, .hour] : interval >= 3600 ? [.hour, .minute] : [.minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(interval, 60)) ?? ""
    }

    static func speed(_ metersPerSecond: Double) -> String {
        Measurement(value: metersPerSecond * 3.6, unit: UnitSpeed.kilometersPerHour)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(1))).locale(appLocale))
    }

    /// "6'05\" /km".
    static func pace(secondsPerKilometre: Double) -> String {
        let total = Int(secondsPerKilometre.rounded())
        return String(format: "%d'%02d\"", total / 60, total % 60) + " /km"
    }

    static func elevation(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(0))).locale(appLocale))
    }

    static func steps(_ count: Double) -> String {
        Int(count).formatted(.number.locale(appLocale))
    }

    /// The time of day, on the clock of `zone` when given (a place's own time zone).
    static func time(_ date: Date, in zone: TimeZone? = nil) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: appLocale, timeZone: zone ?? .current))
    }

    static func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "今天", bundle: .appLanguage) }
        if calendar.isDateInYesterday(date) { return String(localized: "昨天", bundle: .appLanguage) }
        return date.formatted(.dateTime.month().day().locale(appLocale))
    }

    /// Weekday, plus the year when it isn't this year, shown under the day title.
    static func daySubtitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            let weekday = date.formatted(.dateTime.weekday(.wide).locale(appLocale))
            return calendar.isDateInToday(date) || calendar.isDateInYesterday(date)
                ? "\(date.formatted(.dateTime.month().day().locale(appLocale))) \(weekday)" : weekday
        }
        return date.formatted(.dateTime.year().weekday(.wide).locale(appLocale))
    }
}

extension Calendar {
    func dayInterval(for date: Date) -> DateInterval {
        dateInterval(of: .day, for: date) ?? DateInterval(start: startOfDay(for: date), duration: 86_400)
    }

    /// Every calendar day touched by an interval, so a stay over midnight counts for both days.
    func days(in interval: DateInterval) -> [Date] {
        var days: [Date] = []
        var day = startOfDay(for: interval.start)
        while day < interval.end || days.isEmpty {
            days.append(day)
            guard let next = date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }
}

extension String {
    /// 🇯🇵 from "JP".
    static func flag(for countryCode: String?) -> String {
        guard let code = countryCode?.uppercased(), code.count == 2 else { return "🏳️" }
        return code.unicodeScalars
            .compactMap { UnicodeScalar(127_397 + $0.value) }
            .map(String.init)
            .joined()
    }
}
