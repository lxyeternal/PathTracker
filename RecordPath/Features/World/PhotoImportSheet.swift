import SwiftUI
import SwiftData
import Photos

/// Lighting up the map from the photo library: why, then a scan with progress, then what was found.
struct PhotoImportSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.placeTagger) private var tagger
    @AppStorage("photoImport.lastRun") private var lastRun: Double = 0

    @State private var phase = Phase.intro
    @State private var scanned = 0
    @State private var total = 0
    @State private var summary = PhotoFootprints.Summary()
    @State private var before = LightUpInsights()
    @State private var newCountries: [String] = []
    @State private var adding = 0
    @State private var toAdd = 0
    @State private var appeared = false
    @State private var access = PhotoFootprints.authorization

    enum Phase { case intro, denied, scanning, done }

    var body: some View {
        NavigationStack {
            ZStack {
                switch phase {
                case .intro: intro
                case .denied: denied
                case .scanning: scanning
                case .done: done
                }
            }
            .animation(.smooth, value: phase)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                        .disabled(phase == .scanning)
                }
            }
        }
        .interactiveDismissDisabled(phase == .scanning)
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.75).delay(0.1)) { appeared = true } }
        // Coming back from Settings with "All Photos" allowed.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            access = PhotoFootprints.authorization
        }
    }

    // MARK: Phases

    private var intro: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                ForEach(0..<3) { i in
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [[Color.orange, .pink, .purple][i].opacity(0.85), [Color.yellow, .orange, .blue][i].opacity(0.85)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 104, height: 128)
                        .overlay(Image(systemName: ["mountain.2.fill", "building.2.fill", "beach.umbrella.fill"][i])
                            .font(.system(size: 34, weight: .semibold)).foregroundStyle(.white.opacity(0.9)))
                        .rotationEffect(.degrees(appeared ? Double(i - 1) * 12 : 0))
                        .offset(x: appeared ? CGFloat(i - 1) * 62 : 0, y: appeared ? abs(CGFloat(i - 1)) * 12 : 0)
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 6)
                }
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                    .offset(y: appeared ? -82 : -40)
                    .opacity(appeared ? 1 : 0)
                    .shadow(radius: 4, y: 2)
            }
            .frame(height: 190)
            VStack(spacing: 10) {
                Text("从相册点亮足迹").font(.title2.bold())
                Text("你拍过的照片和视频里记着当时的地点。漫迹会找出这些地方，点亮去过的城市、省份和国家，并放进那一天的时间线。")
                    .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            Label("只读取时间和地点，照片不会被上传或复制", systemImage: "lock.fill")
                .font(.footnote).foregroundStyle(.secondary)
            if lastRun > 0 {
                Text("上次导入：\(Date(timeIntervalSince1970: lastRun).formatted(date: .abbreviated, time: .shortened))。再次扫描只会加入新的地方，不会重复。")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            Spacer()
            if access == .limited { LimitedAccessNotice().padding(.horizontal, 24) }
            Button(action: start) {
                Text(lastRun > 0 ? "再次扫描相册" : "开始扫描")
                    .font(.headline).frame(maxWidth: .infinity).frame(height: 52)
            }
            .buttonStyle(.glassProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    private var denied: some View {
        ContentUnavailableView {
            Label("需要访问照片", systemImage: "photo.badge.exclamationmark")
        } description: {
            Text("在“设置”里允许漫迹访问“所有照片”，才能从照片的拍摄地点点亮足迹。")
        } actions: {
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var scanning: some View {
        VStack(spacing: 20) {
            ProgressView(value: total > 0 ? Double(scanned) / Double(total) : 0)
                .progressViewStyle(.circular)
                .controlSize(.large)
            Text(toAdd > 0 ? "正在加入时间线…" : "正在查看照片…").font(.headline)
            if toAdd > 0 {
                Text("\(adding.formatted()) / \(toAdd.formatted())")
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    .contentTransition(.numericText())
            } else if total > 0 {
                Text("\(scanned.formatted()) / \(total.formatted())")
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
    }

    private var done: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: summary.visits > 0 ? "sparkles" : "checkmark.circle.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom))
                    .symbolEffect(.bounce, value: phase)
                    .padding(.top, 30)
                Text(summary.visits > 0 ? "找到了 \(summary.visits) 个去过的地方" : "没有找到新的地方")
                    .font(.title2.bold()).multilineTextAlignment(.center)
                HStack(spacing: 0) {
                    stat(summary.scanned.formatted(), "张照片和视频")
                    Divider().frame(height: 40)
                    stat(summary.withLocation.formatted(), "张带有地点")
                    Divider().frame(height: 40)
                    stat(summary.skippedAlreadyRecorded.formatted(), "处已经记录过")
                }
                .padding(.vertical, 14)
                .background(.background.secondary, in: .rect(cornerRadius: 20, style: .continuous))
                if !newCountries.isEmpty {
                    Text(newCountries.map { String.flag(for: $0) }.joined(separator: " "))
                        .font(.system(size: 34))
                }
                if access == .limited { LimitedAccessNotice() }
                if summary.visits > 0 {
                    Label("城市和国家正在后台识别，几分钟内会陆续点亮。", systemImage: "clock.arrow.circlepath")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Button { dismiss() } label: {
                    Text("完成").font(.headline).frame(maxWidth: .infinity).frame(height: 52)
                }
                .buttonStyle(.glassProminent)
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)
        }
    }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private func start() {
        Task {
            var status = PhotoFootprints.authorization
            if status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
            access = status
            guard status == .authorized || status == .limited else {
                phase = .denied
                return
            }
            before = LightUpInsights(stays: (try? context.fetch(FetchDescriptor<Stay>())) ?? [])
            phase = .scanning
            summary = await PhotoFootprints.importLibrary(into: context) { done, all in
                Task { @MainActor in
                    withAnimation { scanned = done; total = all }
                }
            } adding: { done, all in
                withAnimation { adding = done; toAdd = all }
            }
            lastRun = Date().timeIntervalSince1970
            tagger?.enqueue()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { phase = .done }
            // Most visits are named from their neighbours within seconds; show the new flags as they arrive.
            for delay in [1.5, 3.0, 6.0] {
                try? await Task.sleep(for: .seconds(delay))
                let after = LightUpInsights(stays: (try? context.fetch(FetchDescriptor<Stay>())) ?? [])
                let fresh = after.countries.subtracting(before.countries).sorted()
                if fresh != newCountries { withAnimation(.spring) { newCountries = fresh } }
            }
        }
    }
}

/// When only some photos are shared with the app, an import can only find the places in
/// those, which reads as "it didn't import everything". Say so, and how to share them all.
struct LimitedAccessNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("只允许访问了部分照片", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("漫迹只能看到你选中的照片，其他照片里的地方不会被找到。在“设置 › 隐私与安全性 › 照片”里把漫迹改成“完全访问”，回来再扫描一次即可补全。")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.orange.opacity(0.1), in: .rect(cornerRadius: 18, style: .continuous))
    }
}

/// The invitation to import, shown until the library has been scanned once.
struct PhotoImportCard: View {
    var title: LocalizedStringKey = "从相册点亮足迹"
    var subtitle: LocalizedStringKey = "用照片的拍摄地点，补上以前去过的地方"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "photo.stack.fill").font(.title2).foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}
