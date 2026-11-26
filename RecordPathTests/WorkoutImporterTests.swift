import Foundation
import Testing
import HealthKit
@testable import RecordPath

/// Past workouts from Health as tracks.
struct WorkoutImporterTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// A point `metres` north of the start, `seconds` in.
    private func point(_ metres: Double, at seconds: TimeInterval) -> TrackPoint {
        TrackPoint(latitude: 30 + metres / 111_320, longitude: 120, altitude: 0, speed: 0, accuracy: 5,
                   timestamp: start.addingTimeInterval(seconds))
    }

    @Test func aRideCountsAsCyclingAndSkiingAsJustMoving() {
        #expect(WorkoutImporter.mode(for: .cycling) == .cycling)
        #expect(WorkoutImporter.mode(for: .hiking) == .walking)
        #expect(WorkoutImporter.mode(for: .running) == .running)
        #expect(WorkoutImporter.mode(for: .downhillSkiing) == .unknown)
    }

    @Test func aPointASecondIsThinnedButTheLengthStays() {
        // Ten minutes at 6 m/s, a point every second, as a Watch records a ride.
        let ride = (0...600).map { point(Double($0) * 6, at: TimeInterval($0)) }
        let parts = WorkoutImporter.segments(of: ride, spacing: 20)
        #expect(parts.count == 1)
        #expect(parts[0].count < 200)
        #expect(parts[0].first == ride.first)
        #expect(parts[0].last == ride.last)
        #expect(abs(TrackPoint.distance(of: parts[0]) - TrackPoint.distance(of: ride)) < 1)
    }

    @Test func aPauseCutsTheRouteInTwo() {
        let before = (0...60).map { point(Double($0) * 6, at: TimeInterval($0)) }
        // Twenty minutes later, starting again two kilometres away.
        let after = (0...60).map { point(2_000 + Double($0) * 6, at: 1_260 + TimeInterval($0)) }
        let parts = WorkoutImporter.segments(of: after + before)
        #expect(parts.count == 2)
        #expect(parts[0].last == before.last)
        #expect(parts[1].first == after.first)
        // The gap between the two is not part of either.
        #expect(abs(parts.reduce(0) { $0 + TrackPoint.distance(of: $1) } - TrackPoint.distance(of: before) * 2) < 1)
    }

    @Test func standingStillIsNotARoute() {
        let still = (0...300).map { point(0, at: TimeInterval($0)) }
        #expect(WorkoutImporter.segments(of: still).allSatisfy { TrackPoint.distance(of: $0) < 1 })
        #expect(WorkoutImporter.segments(of: []).isEmpty)
    }

    @Test func theSummarySaysWhatCameInAndWhatDidNot() {
        let nothing = SettingsView.workoutMessage(WorkoutImporter.Result())
        #expect(nothing.contains("没有读到") || nothing.contains("No workouts"))
        let some = SettingsView.workoutMessage(WorkoutImporter.Result(imported: 3, alreadyRecorded: 2, withoutRoute: 1, distance: 66_000))
        #expect(some.split(separator: "\n").count == 3)
        #expect(some.contains("66"))
    }
}
