import Foundation
import SwiftUI

/// Quiet markers along the way: distance travelled, countries, provinces, cities, days recorded.
struct Milestone: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case distance, countries, provinces, cities, days

        var thresholds: [Int] {
            switch self {
            case .distance: [100, 500, 1_000, 5_000, 10_000, 40_075]
            case .countries: [3, 5, 10, 20, 50]
            case .provinces: [5, 10, 20, 34]
            case .cities: [10, 25, 50, 100]
            case .days: [30, 100, 365, 1_000]
            }
        }

        var symbol: String {
            switch self {
            case .distance: "point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath.fill"
            case .countries: "flag.fill"
            case .provinces: "square.grid.3x3.fill"
            case .cities: "building.2.fill"
            case .days: "calendar"
            }
        }

        var tint: Color {
            switch self {
            case .distance: .blue
            case .countries: .red
            case .provinces: .orange
            case .cities: .indigo
            case .days: .teal
            }
        }
    }

    let kind: Kind
    let threshold: Int

    var id: String { "\(kind.rawValue).\(threshold)" }

    var title: String {
        switch kind {
        case .distance where threshold == 40_075: String(localized: "绕地球一圈", bundle: .appLanguage)
        case .distance: String(localized: "移动 \(threshold.formatted(.number.locale(appLocale))) 公里", bundle: .appLanguage)
        case .countries: String(localized: "去过 \(threshold) 个国家和地区", bundle: .appLanguage)
        case .provinces where threshold == 34: String(localized: "走遍全国省级行政区", bundle: .appLanguage)
        case .provinces: String(localized: "点亮 \(threshold) 个省份", bundle: .appLanguage)
        case .cities: String(localized: "去过 \(threshold) 座城市", bundle: .appLanguage)
        case .days: String(localized: "记录 \(threshold) 天", bundle: .appLanguage)
        }
    }
}

/// Where the user stands: what's been reached (and when), and the next goal of each kind.
struct MilestoneProgress {
    struct Reached: Identifiable {
        let milestone: Milestone
        let date: Date
        var id: String { milestone.id }
    }

    struct Next: Identifiable {
        let milestone: Milestone
        let current: Double
        var id: String { milestone.id }
        var fraction: Double { min(1, current / Double(milestone.threshold)) }
    }

    var reached: [Reached] = []
    var next: [Next] = []

    init() {}

    /// Each kind's milestones from the dates things first happened: the 10th country is reached
    /// the day it was first visited.
    init(stays: [Stay], movements: [(date: Date, distance: Double)]) {
        let calendar = Calendar.current
        var firsts: [Milestone.Kind: [Date]] = [:]

        var countryFirst: [String: Date] = [:]
        var provinceFirst: [String: Date] = [:]
        var cityFirst: [String: Date] = [:]
        var days = Set<Date>()
        let cityNames = CityNames.canonical(for: stays)
        for stay in stays {
            if let code = stay.countryCode { countryFirst[code] = min(countryFirst[code] ?? .distantFuture, stay.arrival) }
            if let province = Province.containing(countryCode: stay.countryCode, region: stay.region, city: stay.city) {
                provinceFirst[province.id] = min(provinceFirst[province.id] ?? .distantFuture, stay.arrival)
            }
            if let key = CityNames.key(stay), let city = cityNames[key] {
                let cityKey = "\(stay.countryCode ?? "")|\(city)"
                cityFirst[cityKey] = min(cityFirst[cityKey] ?? .distantFuture, stay.arrival)
            }
            days.formUnion(calendar.days(in: DateInterval(start: stay.arrival, end: max(stay.departure ?? Date(), stay.arrival))))
        }
        firsts[.countries] = countryFirst.values.sorted()
        firsts[.provinces] = provinceFirst.values.sorted()
        firsts[.cities] = cityFirst.values.sorted()
        firsts[.days] = days.filter { $0 <= Date() }.sorted()

        for kind in Milestone.Kind.allCases {
            let current: Double
            var reachedDates: [Int: Date] = [:]
            if kind == .distance {
                var total = 0.0
                for movement in movements.sorted(by: { $0.date < $1.date }) {
                    total += movement.distance / 1000
                    for threshold in kind.thresholds where reachedDates[threshold] == nil && total >= Double(threshold) {
                        reachedDates[threshold] = movement.date
                    }
                }
                current = total
            } else {
                let dates = firsts[kind] ?? []
                for threshold in kind.thresholds where dates.count >= threshold { reachedDates[threshold] = dates[threshold - 1] }
                current = Double(dates.count)
            }
            for threshold in kind.thresholds {
                let milestone = Milestone(kind: kind, threshold: threshold)
                if let date = reachedDates[threshold] {
                    reached.append(Reached(milestone: milestone, date: date))
                } else {
                    next.append(Next(milestone: milestone, current: current))
                    break
                }
            }
        }
        reached.sort { $0.date > $1.date }
        next.sort { $0.fraction > $1.fraction }
    }
}
