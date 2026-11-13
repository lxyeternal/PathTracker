import Foundation

/// `<=` and `>=` on dates, kept inside the app.
///
/// The iOS 27.2 SDK added its own, back-deployed "before 27.2": on a system that says it is
/// 27.2 the app calls the copy in Foundation. Early 27.2 betas say 27.2 and have no such
/// copy, so the call lands on nothing and the app dies on launch. These shadow the SDK's
/// and never leave the binary.
extension Date {
    @inline(__always)
    static func <= (lhs: Date, rhs: Date) -> Bool {
        lhs.timeIntervalSinceReferenceDate <= rhs.timeIntervalSinceReferenceDate
    }

    @inline(__always)
    static func >= (lhs: Date, rhs: Date) -> Bool {
        lhs.timeIntervalSinceReferenceDate >= rhs.timeIntervalSinceReferenceDate
    }
}
