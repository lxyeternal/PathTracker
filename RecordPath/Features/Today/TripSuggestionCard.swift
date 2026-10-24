import SwiftUI
import SwiftData
import CoreLocation

/// "你好像在京都" — when today's places are in a different city from where the user
/// usually is, offer to collect this outing into a trip.
struct TripSuggestionCard: View {
    let todayStays: [Stay]
    /// Where the user usually is; looked up by the parent, since this view is often empty.
    let home: CLLocation?

    @Environment(\.modelContext) private var context
    @Environment(LocationEngine.self) private var engine
    @Query(filter: #Predicate<Trip> { $0.endDate == nil }) private var openTrips: [Trip]
    @AppStorage("tripSuggestion.dismissed") private var dismissedKey = ""

    private var awayStay: Stay? {
        guard let home else { return nil }
        return todayStays.last { $0.city != nil && Self.isAway($0, from: home) }
    }

    private var dismissKey: String {
        "\(awayStay?.city ?? "")|\(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)"
    }

    var body: some View {
        Group {
            if let awayStay, let city = awayStay.city, openTrips.isEmpty, engine.activeTripID == nil, dismissedKey != dismissKey {
                HStack(alignment: .top, spacing: 14) {
                    Text(String.flag(for: awayStay.countryCode))
                        .font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("你好像在\(city)").font(.subheadline.weight(.semibold))
                        Text("要把这次出行记成一段旅程吗？旅程会用更高的精度记录路线。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button("开始旅程") { start(city: city, from: awayStay) }
                                .buttonStyle(.glassProminent)
                                .controlSize(.small)
                            Button("不用了") {
                                withAnimation { dismissedKey = dismissKey }
                            }
                            .controlSize(.small)
                        }
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(.background.secondary, in: .rect(cornerRadius: 20, style: .continuous))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func start(city: String, from stay: Stay) {
        // Begin where today's time away started, so the morning isn't lost.
        let firstAway = home.flatMap { home in todayStays.first { Self.isAway($0, from: home) } } ?? stay
        let trip = Trip(title: String(localized: "\(city)之旅"), startDate: firstAway.arrival)
        trip.coverEmoji = "🧳"
        context.insert(trip)
        try? context.save()
        withAnimation { engine.beginTrip(trip) }
    }

    /// The city with the most days recorded over the last two months.
    /// Where the user spends most days, as a point. Places are compared by distance rather than
    /// by city name, because names change with the system language ("上海" vs "Shanghai").
    static func homeBase(in context: ModelContext) -> CLLocation? {
        let since = Date().addingTimeInterval(-60 * 86_400)
        let descriptor = FetchDescriptor<Stay>(predicate: #Predicate { $0.arrival >= since })
        let stays = (try? context.fetch(descriptor)) ?? []
        // Grid cells of about 20 km; the one with the most distinct days is home.
        var cells: [String: (days: Set<Date>, lat: Double, lon: Double, count: Int)] = [:]
        for stay in stays {
            let key = "\(Int((stay.latitude * 5).rounded()))|\(Int((stay.longitude * 5).rounded()))"
            var cell = cells[key] ?? ([], 0, 0, 0)
            cell.days.insert(Calendar.current.startOfDay(for: stay.arrival))
            cell.lat += stay.latitude
            cell.lon += stay.longitude
            cell.count += 1
            cells[key] = cell
        }
        guard let best = cells.values.max(by: { $0.days.count < $1.days.count }), best.days.count >= 5 else { return nil }
        return CLLocation(latitude: best.lat / Double(best.count), longitude: best.lon / Double(best.count))
    }

    static let awayDistance: CLLocationDistance = 50_000

    static func isAway(_ stay: Stay, from home: CLLocation) -> Bool {
        stay.location.distance(from: home) > awayDistance
    }
}
