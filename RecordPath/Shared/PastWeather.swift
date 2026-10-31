import Foundation
import CoreLocation
import WeatherKit

/// The weather a day had at a place, from Apple Weather's history (it reaches back to August
/// 2021). Each place and day is asked for once and kept on the phone.
@MainActor
enum PastWeather {
    struct Day: Codable, Equatable {
        let condition: String
        let symbol: String
        let high: Double
        let low: Double
    }

    /// Apple Weather's history starts here.
    private static let earliest = Date(timeIntervalSince1970: 1_627_776_000)
    private static var cache: [String: Day] = load()
    private static var asked: Set<String> = []

    private static var url: URL { URL.cachesDirectory.appending(path: "past-weather.json") }

    private static func key(_ coordinate: CLLocationCoordinate2D, _ day: Date) -> String {
        String(format: "%.2f,%.2f|%.0f", coordinate.latitude, coordinate.longitude, Calendar.current.startOfDay(for: day).timeIntervalSince1970)
    }

    private static func load() -> [String: Day] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Day].self, from: data)) ?? [:]
    }

    static func day(_ day: Date, at coordinate: CLLocationCoordinate2D) async -> Day? {
        let key = key(coordinate, day)
        if let cached = cache[key] { return cached }
        let start = Calendar.current.startOfDay(for: day)
        guard start >= earliest, start <= Date(), !asked.contains(key) else { return nil }
        asked.insert(key)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return nil }
        do {
            // Rounded to ~1 km: the weather doesn't need more, and Apple gets no more than that.
            let rough = CLLocation(latitude: (coordinate.latitude * 100).rounded() / 100, longitude: (coordinate.longitude * 100).rounded() / 100)
            let forecast = try await WeatherService.shared.weather(for: rough,
                                                                   including: .daily(startDate: start, endDate: end))
            guard let weather = forecast.first else { return nil }
            let result = Day(condition: weather.condition.description, symbol: weather.symbolName,
                             high: weather.highTemperature.converted(to: .celsius).value,
                             low: weather.lowTemperature.converted(to: .celsius).value)
            cache[key] = result
            if let data = try? JSONEncoder().encode(cache) { try? data.write(to: url, options: .atomic) }
            return result
        } catch {
            Diagnostics.record("weather failed \(error.localizedDescription)")
            return nil
        }
    }

    /// Apple Weather's mark and the link to its data sources, which must sit beside the weather.
    static func attribution() async -> (light: URL, dark: URL, legal: URL)? {
        guard let attribution = try? await WeatherService.shared.attribution else { return nil }
        return (attribution.combinedMarkLightURL, attribution.combinedMarkDarkURL, attribution.legalPageURL)
    }
}
