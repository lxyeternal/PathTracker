import SwiftUI
import SwiftData
import Photos

/// The onboarding step that gives a new passport its history: the places in the photo
/// library are found, and the passport opens with their stamps landing one by one as the
/// places are named.
struct PhotosStep: View {
    var onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.placeTagger) private var tagger
    @AppStorage("photoImport.lastRun") private var lastRun: Double = 0
    private var summaries = PlaceSummaries.shared

    @State private var phase = Phase.intro
    @State private var scanned = 0
    @State private var total = 0
    @State private var found = 0
    @State private var open = false
    @State private var landed: [Stamp] = []
    @State private var float = false

    enum Phase { case intro, scanning, reveal, denied }

    init(onDone: @escaping () -> Void) { self.onDone = onDone }

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            book
                .frame(width: 210, height: 290)
            text
            Spacer(minLength: 0)
            buttons
        }
        .animation(.smooth, value: phase)
        .onAppear { withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { float = true } }
        .onChange(of: summaries.stamps.cities.count + summaries.stamps.provinces.count + summaries.stamps.passport.count) { land() }
    }

    // MARK: The passport

    /// Closed and floating while waiting; it opens like a book once the places are in.
    private var book: some View {
        ZStack {
            page
            PassportCover(compact: phase != .intro)
                .rotation3DEffect(.degrees(open ? -172 : 0), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.45)
                .opacity(open ? 0 : 1)
                .animation(.easeInOut(duration: 1.1), value: open)
                .overlay {
                    if phase == .scanning {
                        ZStack {
                            Circle().stroke(.white.opacity(0.2), lineWidth: 5)
                            Circle()
                                .trim(from: 0, to: total > 0 ? CGFloat(scanned) / CGFloat(total) : 0.05)
                                .stroke(PassportCover.gold, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 74, height: 74)
                        .offset(y: 8)
                        .transition(.opacity)
                    }
                }
        }
        .rotationEffect(.degrees(open ? 0 : -4))
        .offset(y: phase == .intro && float ? -6 : 0)
        .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
    }

    /// The first page, stamps landing on it as they're found.
    private var page: some View {
        GeometryReader { geo in
            ZStack {
                StampPaper(style: .passport)
                ForEach(Array(landed.enumerated()), id: \.element.id) { index, stamp in
                    let side = geo.size.width * (stamp.kind == .province ? 0.27 : 0.38)
                    LandingStamp(stamp: stamp)
                        .frame(width: side, height: side)
                        .position(x: Self.slots[index].x * geo.size.width, y: Self.slots[index].y * geo.size.height)
                }
            }
        }
        .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 3, bottomLeading: 3, bottomTrailing: 14, topTrailing: 14)))
    }

    private static let slots: [CGPoint] = [
        CGPoint(x: 0.3, y: 0.17), CGPoint(x: 0.72, y: 0.24), CGPoint(x: 0.28, y: 0.44),
        CGPoint(x: 0.7, y: 0.52), CGPoint(x: 0.32, y: 0.72), CGPoint(x: 0.72, y: 0.82),
    ]

    /// New stamps take the next free spot: countries first, then provinces, then cities.
    private func land() {
        guard phase == .reveal else { return }
        let book = summaries.stamps
        let candidates = book.passport.filter { $0.kind == .entry } + book.provinces + book.cities
        let have = Set(landed.map(\.id))
        for stamp in candidates where !have.contains(stamp.id) && landed.count < Self.slots.count {
            landed.append(stamp)
        }
    }

    // MARK: Words

    @ViewBuilder
    private var text: some View {
        VStack(spacing: 10) {
            switch phase {
            case .intro:
                Text("找回这些年去过的地方").font(.title.bold()).multilineTextAlignment(.center)
                Text("漫迹可以从照片的拍摄地点，找出你去过的国家和城市，为它们一一盖上印章。只读取时间和地点，照片不会被上传。")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            case .scanning:
                Text("正在翻看相册…").font(.title2.bold())
                if total > 0 {
                    Text("\(scanned.formatted()) / \(total.formatted())")
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        .contentTransition(.numericText())
                }
            case .reveal:
                Text(found > 0 ? "你的护照" : "没找到带地点的照片").font(.title.bold())
                if found > 0 {
                    HStack(spacing: 18) {
                        count(summaries.lightUp.countries.count, "国家和地区")
                        count(summaries.stamps.provinces.count, "省份")
                        count(summaries.stamps.cities.count, "城市")
                    }
                    Text("地点还在陆续识别，几分钟内会全部盖上。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("以后去过的地方，会在你到达时盖上。").foregroundStyle(.secondary)
                }
            case .denied:
                Text("没有照片权限").font(.title.bold())
                Text("以后可以在“足迹”页随时从相册找回。").foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .transition(.opacity)
    }

    private func count(_ value: Int, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 0) {
            Text("\(value)").font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy, value: value)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 12) {
            switch phase {
            case .intro:
                PrimaryButton(title: "从相册找回", action: start)
                SecondaryButton(title: "以后再说", action: onDone)
            case .scanning:
                PrimaryButton(title: "正在查找…") {}.disabled(true)
            case .reveal, .denied:
                PrimaryButton(title: "继续", action: onDone)
            }
        }
    }

    // MARK: Importing

    private func start() {
        Task {
            var status = PhotoFootprints.authorization
            if status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
            guard status == .authorized || status == .limited else {
                phase = .denied
                return
            }
            phase = .scanning
            let summary = await PhotoFootprints.importLibrary(into: context) { done, all in
                Task { @MainActor in withAnimation { scanned = done; total = all } }
            } adding: { done, all in
                withAnimation { scanned = done; total = all }
            }
            lastRun = Date().timeIntervalSince1970
            found = summary.visits
            tagger?.enqueue()
            summaries.setNeedsRefresh()
            phase = .reveal
            try? await Task.sleep(for: .seconds(0.3))
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            open = true
            try? await Task.sleep(for: .seconds(1.0))
            land()
        }
    }
}

/// A stamp arriving on the page: lifted, then pressed down with a thump.
private struct LandingStamp: View {
    let stamp: Stamp
    @State private var down = false

    var body: some View {
        StampWithRoute(stamp: stamp)
            .rotationEffect(.degrees(stamp.tilt + (down ? 0 : -8)))
            .scaleEffect(down ? 1 : 1.5)
            .opacity(down ? 1 : 0)
            .task {
                // Several can arrive together: stagger them a little.
                try? await Task.sleep(for: .seconds(Double(stamp.seed % 5) * 0.12))
                withAnimation(.spring(response: 0.26, dampingFraction: 0.58)) { down = true }
                try? await Task.sleep(for: .seconds(0.12))
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.85)
                SeenStamps.insert(stamp.id)
            }
    }
}
