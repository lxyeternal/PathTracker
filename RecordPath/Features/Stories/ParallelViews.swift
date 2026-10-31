import SwiftUI
import MapKit
import CloudKit

struct ParallelRoute: Hashable {}

/// On 你的故事: the friend whose footprints crossed yours the most, or an invitation.
struct ParallelCard: View {
    @State private var sharing = ParallelSharing.shared

    var body: some View {
        let mutual = sharing.friends.filter { $0.state == .mutual }
        NavigationLink(value: ParallelRoute()) {
            HStack(spacing: 14) {
                CrossingPaths()
                    .frame(width: 56, height: 72)
                VStack(alignment: .leading, spacing: 3) {
                    Text("平行足迹").font(.system(.headline, design: .serif)).foregroundStyle(.primary)
                    Text(mutual.isEmpty
                         ? String(localized: "邀请一个朋友，看看你们的足迹在哪里交汇。", bundle: .appLanguage)
                         : String(localized: "和 \(ListFormatter.localizedString(byJoining: mutual.prefix(3).map(\.name))) 的足迹", bundle: .appLanguage))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .task { if ParallelSharing.shared.hasConsented { await sharing.refresh() } }
    }
}

/// Two paths, one warm and one cool, meeting in the middle.
private struct CrossingPaths: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            var mine = Path()
            mine.move(to: CGPoint(x: w * 0.15, y: h * 0.9))
            mine.addCurve(to: CGPoint(x: w * 0.85, y: h * 0.1), control1: CGPoint(x: w * 0.2, y: h * 0.4), control2: CGPoint(x: w * 0.7, y: h * 0.55))
            var theirs = Path()
            theirs.move(to: CGPoint(x: w * 0.85, y: h * 0.9))
            theirs.addCurve(to: CGPoint(x: w * 0.15, y: h * 0.1), control1: CGPoint(x: w * 0.8, y: h * 0.4), control2: CGPoint(x: w * 0.3, y: h * 0.55))
            context.stroke(mine, with: .color(.orange), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            context.stroke(theirs, with: .color(.teal), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 5]))
            let meet = CGRect(x: w / 2 - 5, y: h * 0.48 - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: meet.insetBy(dx: -4, dy: -4)), with: .color(.yellow.opacity(0.3)))
            context.fill(Path(ellipseIn: meet), with: .color(.yellow))
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(red: 0.1, green: 0.11, blue: 0.2)))
    }
}

// MARK: - Friends

/// Everyone the person shares footprints with, inviting more, and stopping.
struct ParallelView: View {
    @State private var sharing = ParallelSharing.shared
    @State private var askingConsent = false
    @State private var confirmingStopAll = false
    @State private var stopping: ParallelSharing.Friend?
    @State private var working = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    CrossingPaths().frame(width: 64, height: 80)
                    Text("平行足迹").font(.system(.title2, design: .serif, weight: .bold))
                    Text("和朋友互相共享足迹，看看你们哪天在同一座城市、在哪里擦肩而过、去过哪些同样的地方。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            if !sharing.friends.isEmpty {
                Section("朋友") {
                    ForEach(sharing.friends) { friend in
                        row(friend)
                            .swipeActions {
                                Button("停止共享", role: .destructive) { stopping = friend }
                            }
                    }
                }
            }

            Section {
                Button {
                    if sharing.hasConsented { invite() } else { askingConsent = true }
                } label: {
                    HStack {
                        Label("邀请朋友", systemImage: "person.badge.plus")
                        if working { Spacer(); ProgressView() }
                    }
                }
                .disabled(working)
            } footer: {
                Text("朋友就是你发出邀请、并且接受了的人。双方都共享之后，才能看到彼此的平行足迹。")
            }

            if let error = sharing.lastError {
                Section { Text(error).foregroundStyle(.red) }
            }

            Section {
                NavigationLink("共享了什么，没有共享什么") { ParallelPrivacyView() }
                if sharing.hasConsented && !sharing.friends.isEmpty {
                    Button("停止与所有人共享", role: .destructive) { confirmingStopAll = true }
                }
            }
        }
        .navigationTitle("平行足迹")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ParallelSharing.Friend.self) { FriendFootprintsView(friend: $0) }
        .refreshable { await sharing.refresh() }
        .task { await sharing.refresh() }
        .sheet(isPresented: $askingConsent) {
            ParallelConsentSheet {
                sharing.hasConsented = true
                askingConsent = false
                // Once the consent sheet has closed, or the sharing screen can't open.
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    invite()
                }
            }
        }
        .confirmationDialog("停止与所有人共享？", isPresented: $confirmingStopAll, titleVisibility: .visible) {
            Button("停止共享并删除", role: .destructive) { Task { await sharing.stopAll() } }
        } message: {
            Text("你共享在 iCloud 里的足迹摘要会被删除，朋友们也看不到了。你自己的记录不受影响。")
        }
        .confirmationDialog(stopping.map { String(localized: "停止与\($0.name)共享？", bundle: .appLanguage) } ?? "",
                            isPresented: Binding(get: { stopping != nil }, set: { if !$0 { stopping = nil } }),
                            titleVisibility: .visible) {
            Button("停止共享", role: .destructive) {
                if let friend = stopping { Task { await sharing.stop(friend) } }
            }
        } message: {
            Text("你们将互相看不到对方的足迹。")
        }
    }

    @ViewBuilder private func row(_ friend: ParallelSharing.Friend) -> some View {
        switch friend.state {
        case .mutual:
            NavigationLink(value: friend) {
                Label(friend.name, systemImage: "person.2.fill")
            }
        case .theyShared:
            HStack {
                Label(friend.name, systemImage: "person.fill.questionmark")
                Spacer()
                Button("共享回去") { invite() }.buttonStyle(.borderedProminent).controlSize(.small)
            }
        case .waitingForThem:
            LabeledContent { Text("等 Ta 共享回来").font(.footnote) } label: { Label(friend.name, systemImage: "hourglass") }
        case .invited:
            LabeledContent { Text("已邀请，等待接受").font(.footnote) } label: { Label(friend.name, systemImage: "envelope") }
        }
    }

    private func invite() {
        working = true
        Task {
            defer { working = false }
            do {
                let share = try await sharing.prepareShare()
                CloudSharing.present(share: share, container: sharing.container) { Task { await sharing.refresh() } }
            } catch {
                await sharing.refresh()
            }
        }
    }
}

/// Asked once, before the first invitation: what's shared and what isn't.
struct ParallelConsentSheet: View {
    let agree: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CrossingPaths().frame(width: 72, height: 90)
                    Text("和朋友共享你的足迹").font(.system(.title, design: .serif, weight: .bold))
                    ParallelPrivacyText()
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: agree) {
                    Text("同意并邀请朋友").font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", systemImage: "xmark") { dismiss() } }
            }
        }
    }
}

struct ParallelPrivacyView: View {
    var body: some View {
        ScrollView { ParallelPrivacyText().padding(24) }
            .navigationTitle("共享了什么")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ParallelPrivacyText: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            point("checkmark.circle.fill", .green, "会共享",
                  "每天到过哪些区域（约 20 公里的范围），以及每个小时所在的约 1 公里的方格。")
            point("xmark.circle.fill", .red, "不会共享",
                  "家、公司、学校附近 2 公里内的一切，隐私区域，地点名称，具体坐标，路线，照片和文字。朋友算不出你住在哪里。")
            point("iphone", .blue, "在哪里比对",
                  "摘要存在你自己的 iCloud 里，只给你邀请的人看。比对在各自的手机上进行，不经过我们的服务器。")
            point("hand.raised.fill", .orange, "随时停止",
                  "停止共享后，对方立刻看不到你的足迹，你也看不到对方的。")
        }
    }

    private func point(_ symbol: String, _ tint: Color, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Shown after accepting someone's invitation: share back, so both can see.
struct ShareBackSheet: View {
    let friend: ParallelSharing.Friend
    @State private var sharing = ParallelSharing.shared
    @State private var working = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            CrossingPaths().frame(width: 72, height: 90).padding(.top, 28)
            Text("\(friend.name)把足迹共享给了你").font(.system(.title2, design: .serif, weight: .bold))
                .multilineTextAlignment(.center)
            Text("你也共享给 Ta，你们就能看到彼此的平行足迹：哪天在同一座城市，在哪里擦肩而过。")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            if let error = sharing.lastError {
                Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Button {
                working = true
                Task {
                    defer { working = false }
                    sharing.hasConsented = true
                    guard let share = try? await sharing.prepareShare() else { return }
                    dismiss()
                    // iOS won't show the sharing screen while this sheet is still closing.
                    try? await Task.sleep(for: .milliseconds(700))
                    CloudSharing.present(share: share, container: sharing.container) { Task { await sharing.refresh() } }
                }
            } label: {
                Group { if working { ProgressView() } else { Text("共享我的足迹给 Ta") } }
                    .font(.headline).frame(maxWidth: .infinity).frame(height: 50)
            }
            .buttonStyle(.glassProminent)
            Button("以后再说") { dismiss() }
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}

/// Apple's own screen for inviting people to a share and managing who's on it.
@MainActor
enum CloudSharing {
    static func present(share: CKShare, container: CKContainer, onChange: @escaping () -> Void) {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadOnly]
        let delegate = Delegate(onChange: onChange)
        controller.delegate = delegate
        // The controller holds its delegate weakly.
        objc_setAssociatedObject(controller, &Delegate.key, delegate, .OBJC_ASSOCIATION_RETAIN)
        guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(controller, animated: true)
    }

    private final class Delegate: NSObject, UICloudSharingControllerDelegate {
        nonisolated(unsafe) static var key = 0
        let onChange: () -> Void
        init(onChange: @escaping () -> Void) { self.onChange = onChange }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            String(localized: "漫迹 · 平行足迹", bundle: .appLanguage)
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) { onChange() }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { onChange() }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { onChange() }
    }
}

// MARK: - One friend

/// Where your footprints and a friend's met: the hours you passed each other, the days in the
/// same city, and the places you both know at different times.
struct FriendFootprintsView: View {
    let friend: ParallelSharing.Friend
    @State private var result: ParallelResult?
    @State private var names = PlaceNamer(stays: [])
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let result {
                    header(result)
                    if result.isEmpty {
                        ContentUnavailableView("还没有交汇", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                               description: Text("你们的足迹还没有在同一个地方出现过。下次一起出发吧。"))
                    }
                    if !result.passedBy.isEmpty { passedBy(result.passedBy) }
                    if !result.samePlaces.isEmpty { samePlaces(result.samePlaces) }
                    if !result.sameDays.isEmpty { sameDays(result.sameDays) }
                } else {
                    ProgressView("正在比对你们的足迹…").frame(maxWidth: .infinity).padding(.top, 80)
                }
            }
            .padding()
        }
        .navigationTitle(friend.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        names = PlaceNamer(stays: PlaceSummaries.shared.stays)
        let theirs = await ParallelSharing.shared.days(of: friend)
        guard let container = PlaceSummaries.shared.stays.first?.modelContext?.container else {
            result = ParallelResult()
            return
        }
        let hidden = PrivacyZones.shared.zones.map(\.location)
        let computed = await Task.detached(priority: .userInitiated) {
            ParallelMatch.compare(mine: Array(ParallelSharing.myDays(in: container, hiddenZones: hidden).values), theirs: theirs)
        }.value
        withAnimation(.smooth) { result = computed }
    }

    // MARK: Sections

    private func header(_ result: ParallelResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Circle().fill(.orange).frame(width: 10, height: 10)
                Text("你").font(.subheadline.weight(.semibold))
                Image(systemName: "arrow.left.and.right").font(.caption).foregroundStyle(.white.opacity(0.5))
                Circle().fill(.teal).frame(width: 10, height: 10)
                Text(friend.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(.white)
            HStack(alignment: .firstTextBaseline, spacing: 22) {
                figure(result.passedBy.count, "次擦肩而过")
                figure(result.sameDays.count, "天在同一座城市")
                figure(result.samePlaces.count, "个共同的地方")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(red: 0.12, green: 0.12, blue: 0.24), Color(red: 0.08, green: 0.25, blue: 0.3)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 26, style: .continuous)
        )
    }

    private func figure(_ value: Int, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(value)").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.7))
        }
    }

    private func passedBy(_ moments: [ParallelResult.Moment]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "擦肩而过")
            Text("同一个小时，相距约 1 公里以内。").font(.footnote).foregroundStyle(.secondary)
            ForEach(Array(moments.prefix(30).enumerated()), id: \.element.id) { index, moment in
                Button { navigator.show(day: moment.date) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        // Maps for the latest few; a list of dozens of maps is heavy.
                        if index < 5 {
                            Map(initialPosition: .region(MKCoordinateRegion(center: moment.coordinate, latitudinalMeters: 3500, longitudinalMeters: 3500))) {
                                MapCircle(center: moment.coordinate, radius: 700)
                                    .foregroundStyle(.yellow.opacity(0.25))
                                    .stroke(.yellow, lineWidth: 2)
                            }
                            .allowsHitTesting(false)
                            .frame(height: 130)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(moment.date.formatted(.dateTime.year().month().day().hour().locale(appLocale)))
                                .font(.headline).foregroundStyle(.primary)
                            Text("你们都在\(names.place(near: moment.coordinate))附近")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(.background.secondary)
                    .clipShape(.rect(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private func samePlaces(_ echoes: [ParallelResult.Echo]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "同一个地方，不同的时光")
            Text("你们去过同一个地方，只是不在同一个时候。").font(.footnote).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(echoes.prefix(40).enumerated()), id: \.element.id) { index, echo in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(names.place(near: echo.coordinate)).font(.headline)
                        HStack(spacing: 14) {
                            when(echo.mine, tint: .orange, who: String(localized: "你", bundle: .appLanguage))
                            when(echo.theirs, tint: .teal, who: friend.name)
                        }
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if index < min(echoes.count, 40) - 1 { Divider() }
                }
            }
            .padding(.horizontal, 16)
            .background(.background.secondary, in: .rect(cornerRadius: 20, style: .continuous))
        }
    }

    private func when(_ date: Date, tint: Color, who: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text("\(who) · \(date.formatted(.dateTime.year().month().locale(appLocale)))")
                .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func sameDays(_ days: [ParallelResult.SameDay]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "同一天，同一座城市")
            VStack(spacing: 0) {
                ForEach(Array(days.prefix(60).enumerated()), id: \.element.id) { index, day in
                    Button { if let date = day.date { navigator.show(day: date) } } label: {
                        HStack {
                            Text(day.date?.formatted(.dateTime.year().month().day().weekday(.abbreviated).locale(appLocale)) ?? day.day)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(names.city(in: day.area)).foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 12)
                    }
                    if index < min(days.count, 60) - 1 { Divider() }
                }
            }
            .padding(.horizontal, 16)
            .background(.background.secondary, in: .rect(cornerRadius: 20, style: .continuous))
        }
    }
}

/// Names a shared cell or area from the person's own places: their friend's data has no names.
struct PlaceNamer {
    private let stays: [(location: CLLocation, name: String, city: String?)]

    init(stays: [Stay]) {
        self.stays = stays.map { ($0.location, $0.customName ?? $0.placeName ?? $0.street ?? $0.city ?? "", $0.city) }
    }

    func place(near coordinate: CLLocationCoordinate2D) -> String {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let nearest = stays.filter { !$0.name.isEmpty }.min { $0.location.distance(from: here) < $1.location.distance(from: here) }
        if let nearest, nearest.location.distance(from: here) < 1_500 { return nearest.name }
        return city(near: here) ?? String(localized: "同一个地方", bundle: .appLanguage)
    }

    func city(in area: FootprintDay.Area) -> String {
        let center = FootprintDigest.center(of: area)
        return city(near: CLLocation(latitude: center.latitude, longitude: center.longitude)) ?? ""
    }

    private func city(near here: CLLocation) -> String? {
        stays.filter { $0.city != nil }
            .min { $0.location.distance(from: here) < $1.location.distance(from: here) }
            .flatMap { $0.location.distance(from: here) < 30_000 ? $0.city : nil }
    }
}
