import SwiftUI
import SwiftData
import CoreLocation

/// The stamps that aren't about one place: the four corners of everywhere you've been and the
/// highest point, lines crossed, where each year began, and sets of cities.
struct CommemorativeView: View {
    let book: StampBook
    @Environment(\.modelContext) private var context
    @State private var highest: Stamp?
    @State private var showsOtherSets = false

    private func special(_ code: String) -> Stamp? { book.specials.first { $0.code == code } }
    private var newYears: [Stamp] { book.specials.filter { ($0.code ?? "").hasPrefix("newyear") }.reversed() }
    private var started: [StampSet.Progress] {
        book.sets.filter { !$0.visited.isEmpty }
            .sorted { ($0.isComplete ? 1 : 0, Double($0.visited.count) / Double($0.group.members.count))
                > ($1.isComplete ? 1 : 0, Double($1.visited.count) / Double($1.group.members.count)) }
    }
    private var notStarted: [StampSet.Progress] { book.sets.filter(\.visited.isEmpty) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            corners
            crossings
            if !newYears.isEmpty { newYearRow }
            sets
        }
        .task(id: book.since) {
            highest = await HighestPoint.find(container: context.container)
        }
    }

    // MARK: 四至

    /// North at the top, south at the bottom, west and east either side, as on a map.
    private var corners: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("你的四至", detail: "去过的最北、最南、最东、最西，和最高的地方")
            VStack(spacing: 4) {
                cornerStamp("record.north")
                HStack(spacing: 4) {
                    cornerStamp("record.west")
                    ZStack {
                        Circle().stroke(StampPaper.line, lineWidth: 1)
                        Image(systemName: "location.north.line.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(StampPaper.line.mix(with: .black, by: 0.3))
                    }
                    .frame(width: 56, height: 56)
                    cornerStamp("record.east")
                }
                cornerStamp("record.south")
                if let highest {
                    Divider().overlay(StampPaper.line).padding(.vertical, 8)
                    labelled(highest)
                }
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background { StampPaper(style: .book) }
            .clipShape(.rect(cornerRadius: 24, style: .continuous))
        }
    }

    @ViewBuilder
    private func cornerStamp(_ code: String) -> some View {
        if let stamp = special(code) {
            labelled(stamp).frame(maxWidth: .infinity)
        } else {
            Color.clear.frame(height: 40)
        }
    }

    private func labelled(_ stamp: Stamp) -> some View {
        VStack(spacing: 4) {
            StampArt(stamp: stamp)
                .frame(width: 96, height: 96)
                .stampIn(stamp, delay: 0.2, tilt: stamp.tilt * 0.6)
            Text(stamp.city ?? "")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.3, green: 0.27, blue: 0.24))
                .lineLimit(1)
        }
    }

    // MARK: Lines crossed

    private var crossings: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("跨越", detail: "一生可能只有一次")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(["equator", "dateline", "arctic", "antarctic"], id: \.self) { code in
                    if let stamp = special(code) {
                        crossing(stamp, earned: true)
                    } else if code == "equator" || code == "dateline" {
                        // Waiting, faintly. The polar ones stay out of sight until they happen.
                        crossing(Stamp(id: "special.\(code)", kind: .special, date: .distantPast, code: code,
                                       value: code == "equator" ? "0°00′" : "180°"), earned: false)
                    }
                }
            }
            .padding(14)
            .background { StampPaper(style: .book) }
            .clipShape(.rect(cornerRadius: 24, style: .continuous))
        }
    }

    private func crossing(_ stamp: Stamp, earned: Bool) -> some View {
        VStack(spacing: 6) {
            Group {
                if earned {
                    StampArt(stamp: stamp).stampIn(stamp, delay: 0.3, tilt: stamp.tilt * 0.6)
                } else {
                    StampArt(stamp: stamp, inked: false)
                }
            }
            .frame(height: 104)
            Text(earned ? (stamp.city ?? "") : (stamp.code == "equator" ? String(localized: "还没跨过赤道", bundle: .appLanguage)
                                                                         : String(localized: "还没越过日期变更线", bundle: .appLanguage)))
                .font(.caption.weight(earned ? .semibold : .regular))
                .foregroundStyle(Color(red: 0.3, green: 0.27, blue: 0.24).opacity(earned ? 1 : 0.55))
                .lineLimit(1)
        }
    }

    // MARK: New Year's Eves

    private var newYearRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("跨年", detail: "每一年，从哪里开始")
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(newYears) { stamp in
                        VStack(spacing: 4) {
                            StampArt(stamp: stamp)
                                .frame(width: 104, height: 104)
                                .stampIn(stamp, delay: 0.2, tilt: stamp.tilt * 0.6)
                            Text(stamp.city ?? "")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(red: 0.3, green: 0.27, blue: 0.24))
                                .lineLimit(1)
                                .frame(width: 104)
                        }
                    }
                }
                .padding(14)
            }
            .scrollIndicators(.hidden)
            .background { StampPaper(style: .book) }
            .clipShape(.rect(cornerRadius: 24, style: .continuous))
        }
    }

    // MARK: Sets

    private var sets: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("套章", detail: "集齐一组城市，盖一枚联合章")
            if started.isEmpty {
                Text("去过其中任何一座城市，这一套就会出现在这里。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            ForEach(started) { progress in SetRow(progress: progress) }
            if !notStarted.isEmpty {
                DisclosureGroup(isExpanded: $showsOtherSets.animation(.smooth)) {
                    VStack(spacing: 10) {
                        ForEach(notStarted) { progress in SetRow(progress: progress) }
                    }
                    .padding(.top, 10)
                } label: {
                    Text("还有 \(notStarted.count) 套").font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 4)
                .tint(.secondary)
            }
        }
    }

    private func header(_ title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.bold())
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }
}

/// One set: its stamp (faint until complete), the cities in it, and how many are done.
private struct SetRow: View {
    let progress: StampSet.Progress

    private var ghost: Stamp {
        Stamp(id: "set.\(progress.group.id)", kind: .set, date: .distantPast, code: progress.group.id)
    }

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let stamp = progress.stamp {
                    StampArt(stamp: stamp).stampIn(stamp, delay: 0.3, tilt: stamp.tilt * 0.4)
                } else {
                    StampArt(stamp: ghost, inked: false)
                }
            }
            .frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: progress.group.title).font(.headline)
                    Spacer()
                    Text(verbatim: "\(progress.visited.count) / \(progress.group.members.count)")
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(progress.isComplete ? progress.group.ink.color : .secondary)
                }
                ProgressView(value: Double(progress.visited.count), total: Double(progress.group.members.count))
                    .tint(progress.group.ink.color)
                members
            }
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 22, style: .continuous))
    }

    /// The cities, the ones visited in full colour.
    private var members: some View {
        progress.group.members.enumerated().reduce(Text(verbatim: "")) { text, item in
            let visited = progress.visited[item.element] != nil
            let name = Text(verbatim: item.element)
                .foregroundStyle(visited ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .fontWeight(visited ? .semibold : .regular)
            return item.offset == 0 ? name : text + Text(verbatim: "  ") + name
        }
        .font(.footnote)
        .lineLimit(2)
    }
}

/// The highest point reached on the ground, from the altitudes along the tracks. Worked out
/// once in the background and remembered until there are new tracks.
enum HighestPoint {
    private struct Found: Codable {
        var latitude: Double, longitude: Double, altitude: Double, date: Date, city: String?, chunks: Int
    }
    private static let key = "stamps.highest"

    static func find(container: ModelContainer) async -> Stamp? {
        let cached = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Found.self, from: $0) }
        let found: Found? = await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            let flying = MovementMode.flying.rawValue
            let descriptor = FetchDescriptor<TrackChunk>(predicate: #Predicate { $0.modeRaw != flying })
            let count = (try? context.fetchCount(descriptor)) ?? 0
            if let cached, cached.chunks == count { return cached }
            var best: Found?
            for chunk in (try? context.fetch(descriptor)) ?? [] {
                // A high reading or two is GPS noise: take the 95th percentile of each track.
                let points = chunk.points.filter { $0.accuracy < 30 && $0.altitude != 0 }
                guard points.count >= 10 else { continue }
                let sorted = points.sorted { $0.altitude < $1.altitude }
                let point = sorted[Int(Double(sorted.count - 1) * 0.95)]
                if point.altitude > (best?.altitude ?? 300) {
                    best = Found(latitude: point.latitude, longitude: point.longitude, altitude: point.altitude,
                                 date: point.timestamp, city: nil, chunks: count)
                }
            }
            guard var result = best else { return nil }
            let lat = result.latitude, lon = result.longitude
            let near = (try? context.fetch(FetchDescriptor<Stay>(predicate: #Predicate {
                $0.latitude > lat - 0.3 && $0.latitude < lat + 0.3 && $0.longitude > lon - 0.3 && $0.longitude < lon + 0.3
            }))) ?? []
            let here = CLLocation(latitude: lat, longitude: lon)
            result.city = near.filter { $0.city != nil }.min { $0.location.distance(from: here) < $1.location.distance(from: here) }?.city
            return result
        }.value
        guard let found else { return nil }
        if let data = try? JSONEncoder().encode(found) { UserDefaults.standard.set(data, forKey: key) }
        return Stamp(id: "special.record.high", kind: .special, date: found.date, city: found.city,
                     latitude: found.latitude, longitude: found.longitude, code: "record.high",
                     value: "\(Int(found.altitude).formatted()) m")
    }
}
