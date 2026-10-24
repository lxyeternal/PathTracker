import SwiftUI

/// App-wide navigation state, so any screen can say "show me that day".
@MainActor
@Observable
final class AppNavigator {
    enum Section: Hashable { case today, world, trips, stats }

    var section: Section = .today
    var day: Date = Calendar.current.startOfDay(for: Date())
    /// Bumped to ask open sheets to close after a jump.
    private(set) var jumpCount = 0

    func show(day date: Date) {
        withAnimation(.smooth) {
            day = Calendar.current.startOfDay(for: min(date, Date()))
            section = .today
        }
        jumpCount += 1
    }
}
