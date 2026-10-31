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
    /// The "today" the page was last showing, so it can follow the clock past midnight.
    private var today = Calendar.current.startOfDay(for: Date())

    init() {
        for name in [Notification.Name.NSCalendarDayChanged, UIApplication.didBecomeActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.followTheClock() }
            }
        }
    }

    /// The app stays alive for days while it records; if the page was on today when the date
    /// changed, move it on to the new today rather than leaving it on "yesterday".
    func followTheClock() {
        let now = Calendar.current.startOfDay(for: Date())
        guard now != today else { return }
        if day == today { day = now }
        today = now
    }

    func show(day date: Date) {
        withAnimation(.smooth) {
            day = Calendar.current.startOfDay(for: min(date, Date()))
            section = .today
        }
        jumpCount += 1
    }
}
