import Foundation
import HealthKit
import CoreMotion

struct DailyActivity: Identifiable, Equatable {
    var day: Date
    var steps: Double
    var walkingDistance: Double
    var id: Date { day }
}

/// Daily steps and walking distance. HealthKit gives full history (and includes an Apple
/// Watch); the pedometer covers the last week when Health is unavailable or declined.
@MainActor
@Observable
final class ActivityProvider {
    private(set) var isAuthorizationRequested: Bool
    private(set) var today = DailyActivity(day: Calendar.current.startOfDay(for: Date()), steps: 0, walkingDistance: 0)

    private let store = HKHealthStore()
    private let pedometer = CMPedometer()
    private let stepType = HKQuantityType(.stepCount)
    private let distanceType = HKQuantityType(.distanceWalkingRunning)
    private var cache: [Date: DailyActivity] = [:]

    init() {
        isAuthorizationRequested = UserDefaults.standard.bool(forKey: "health.requested")
    }

    var isHealthAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async {
        guard isHealthAvailable else { return }
        try? await store.requestAuthorization(toShare: [], read: [stepType, distanceType])
        isAuthorizationRequested = true
        UserDefaults.standard.set(true, forKey: "health.requested")
        cache.removeAll()
        await refreshToday()
    }

    func refreshToday() async {
        let start = Calendar.current.startOfDay(for: Date())
        cache[start] = nil
        if let day = await activity(from: start, days: 1).first { today = day }
    }

    func activity(for day: Date) async -> DailyActivity {
        let start = Calendar.current.startOfDay(for: day)
        if let cached = cache[start], !Calendar.current.isDateInToday(day) { return cached }
        return await activity(from: start, days: 1).first ?? DailyActivity(day: start, steps: 0, walkingDistance: 0)
    }

    /// One entry per day, oldest first, including days with zero activity.
    func activity(from start: Date, days: Int) async -> [DailyActivity] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: start)
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else { return [] }

        var steps: [Date: Double] = [:]
        var distance: [Date: Double] = [:]
        if isHealthAvailable, isAuthorizationRequested {
            steps = await sums(of: stepType, unit: .count(), from: start, to: end)
            distance = await sums(of: distanceType, unit: .meter(), from: start, to: end)
        }
        if steps.values.reduce(0, +) == 0 {
            (steps, distance) = await pedometerSums(from: start, days: days)
        }

        #if DEBUG
        if UserDefaults.standard.bool(forKey: "debug.demoSteps") { (steps, distance) = Self.demoSteps(from: start, days: days) }
        #endif

        let result = (0..<days).compactMap { offset -> DailyActivity? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return DailyActivity(day: day, steps: steps[day] ?? 0, walkingDistance: distance[day] ?? 0)
        }
        for entry in result { cache[entry.day] = entry }
        return result
    }

    #if DEBUG
    /// Plausible, repeatable step counts so charts can be checked in the simulator.
    private static func demoSteps(from start: Date, days: Int) -> ([Date: Double], [Date: Double]) {
        var steps: [Date: Double] = [:], distance: [Date: Double] = [:]
        let calendar = Calendar.current
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start), day <= Date() else { continue }
            let seed = Double(Int(day.timeIntervalSince1970 / 86_400) % 97)
            let value = 4_000 + (seed * 7_919).truncatingRemainder(dividingBy: 9_000)
            let fraction = calendar.isDateInToday(day) ? min(1, Date().timeIntervalSince(day) / 86_400) : 1
            steps[day] = (value * fraction).rounded()
            distance[day] = value * fraction * 0.72
        }
        return (steps, distance)
    }
    #endif

    private func sums(of type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date) async -> [Date: Double] {
        let predicate = HKSamplePredicate.quantitySample(
            type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end))
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: predicate, options: .cumulativeSum, anchorDate: start,
            intervalComponents: DateComponents(day: 1))
        guard let collection = try? await query.result(for: store) else { return [:] }
        var values: [Date: Double] = [:]
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            values[statistics.startDate] = statistics.sumQuantity()?.doubleValue(for: unit) ?? 0
        }
        return values
    }

    private func pedometerSums(from start: Date, days: Int) async -> ([Date: Double], [Date: Double]) {
        guard CMPedometer.isStepCountingAvailable(),
              CMPedometer.authorizationStatus() != .denied else { return ([:], [:]) }
        let calendar = Calendar.current
        // The motion coprocessor only keeps about a week of history.
        let earliest = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: Date())) ?? start
        var steps: [Date: Double] = [:]
        var distance: [Date: Double] = [:]
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start), day >= earliest,
                  day <= Date(), let next = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            let data: CMPedometerData? = await withCheckedContinuation { continuation in
                pedometer.queryPedometerData(from: day, to: min(next, Date())) { data, _ in
                    continuation.resume(returning: data)
                }
            }
            steps[day] = data?.numberOfSteps.doubleValue ?? 0
            distance[day] = data?.distance?.doubleValue ?? 0
        }
        return (steps, distance)
    }
}
