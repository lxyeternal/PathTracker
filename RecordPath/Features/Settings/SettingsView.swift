import SwiftUI
import SwiftData
import AuthenticationServices
import CoreLocation

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.placeTagger) private var tagger
    @Environment(LocationEngine.self) private var engine
    @Environment(ActivityProvider.self) private var activity
    @Environment(AccountManager.self) private var account
    @Environment(Notifier.self) private var notifier
    @AppStorage(Notifier.Setting.arrivals.rawValue) private var notifyArrivals = true
    @AppStorage(Notifier.Setting.milestones.rawValue) private var notifyMilestones = true
    @AppStorage(Notifier.Setting.weekly.rawValue) private var notifyWeekly = true

    @State private var syncStatus: SyncStatus = .checking
    private var cloud = CloudSync.shared
    @State private var confirmingDeleteAll = false
    @State private var stats: (chunks: Int, stays: Int, trips: Int) = (0, 0, 0)
    @State private var retagged = false
    @State private var importing = false
    @State private var importingPhotos = false
    @AppStorage("photoImport.lastRun") private var photoImportRun: Double = 0
    @State private var importMessage: String?
    private var zones = PrivacyZones.shared

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                languageSection
                trackingSection
                notificationsSection
                permissionsSection
                privacySection
                dataSection
                aboutSection
                #if DEBUG
                developerSection
                #endif
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", systemImage: "checkmark") { dismiss() }
                }
            }
            .task {
                syncStatus = await SyncStatus.current()
                refreshCounts()
            }
            .sheet(isPresented: $importingPhotos) { PhotoImportSheet() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.gpx, .xml], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                var tracks = 0, places = 0, duplicates = 0
                var failures: [String] = []
                for url in urls {
                    do {
                        let r = try GPXImporter.importFile(at: url, into: context)
                        tracks += r.tracks; places += r.places; duplicates += r.skippedDuplicates + r.skippedPlaces
                    } catch {
                        failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
                    }
                }
                tagger?.enqueue()
                refreshCounts()
                var message = String(localized: "导入了 \(tracks) 段轨迹、\(places) 个地点。", bundle: .appLanguage)
                if duplicates > 0 {
                    let skipped = String(localized: "跳过了 \(duplicates) 条已经存在的记录。", bundle: .appLanguage)
                    message += (message.last.map { "。！？".contains($0) } == true ? "" : " ") + skipped
                }
                if !failures.isEmpty { message += "\n" + failures.joined(separator: "\n") }
                importMessage = message
            }
            .alert("导入完成", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }
            .confirmationDialog("删除所有数据？", isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
                Button("删除所有数据", role: .destructive, action: deleteEverything)
            } message: {
                Text("所有轨迹、地点、旅程和照片都会从这台设备和你的 iCloud 中永久删除，且无法恢复。")
            }
        }
    }

    // MARK: Sections

    private var accountSection: some View {
        Section {
            NavigationLink {
                ProfileEditView()
            } label: {
                HStack(spacing: 14) {
                    Avatar(size: 60)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account.displayName).font(.title3.weight(.semibold))
                        Text(account.profile.bio ?? account.profile.email
                             ?? String(localized: "设置头像、名字和个人信息", bundle: .appLanguage))
                            .font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(2)
                        if account.isSignedIn {
                            Label("已通过 Apple 登录", systemImage: "apple.logo")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var languageSection: some View {
        Section {
            Picker(selection: Binding(get: { LanguageSettings.shared.language },
                                      set: { newValue in withAnimation(.smooth) { LanguageSettings.shared.set(newValue) } })) {
                ForEach(AppLanguage.allCases) { language in
                    Text(verbatim: language.nativeName).tag(language)
                }
            } label: {
                Label("语言", systemImage: "globe")
            }
        } footer: {
            Text("系统权限弹窗的语言会在下次打开 App 时更新。")
        }
    }

    private var trackingSection: some View {
        Section {
            @Bindable var engine = engine
            Picker(selection: $engine.isEnabled) {
                Text("全天自动").tag(true)
                Text("仅手动").tag(false)
            } label: {
                Label("记录方式", systemImage: "location.fill")
            }
            LabeledContent {
                Text(statusText).foregroundStyle(.secondary)
            } label: {
                Label("当前状态", systemImage: "waveform.path.ecg")
            }
            if engine.isEnabled {
                Picker(selection: $engine.precision) {
                    Text("省电").tag(LocationEngine.Precision.battery)
                    Text("均衡").tag(LocationEngine.Precision.balanced)
                    Text("精细").tag(LocationEngine.Precision.precise)
                } label: {
                    Label("记录精度", systemImage: "scope")
                }
            }
            if engine.isPaused, let until = engine.pausedUntil {
                Button("恢复记录（原定 \(Format.time(until))）", systemImage: "play.circle") { engine.resume() }
            }
            if engine.activeTripID != nil {
                Label("手动记录进行中，使用高精度定位", systemImage: "record.circle").foregroundStyle(.orange)
            }
        } header: {
            Text("记录")
        } footer: {
            Text(precisionFooter)
        }
    }

    @ViewBuilder
    private var notificationsSection: some View {
        Section {
            switch notifier.authorization {
            case .authorized, .provisional, .ephemeral:
                Toggle(isOn: $notifyArrivals) { Label("第一次到达新地方", systemImage: "mappin.and.ellipse") }
                Toggle(isOn: $notifyMilestones) { Label("达成里程碑", systemImage: "flag.checkered") }
                Toggle(isOn: $notifyWeekly) { Label("每周一回顾上周", systemImage: "calendar") }
            case .denied:
                Button("在“设置”中打开通知", systemImage: "bell.slash") { openSettings() }
            default:
                Button("打开通知", systemImage: "bell.badge") { Task { await notifier.requestAuthorization() } }
            }
        } header: {
            Text("通知")
        } footer: {
            Text("第一次到达新的国家、省份或城市，达成里程碑，以及每周一早上回顾上周。通知在手机上生成，不经过任何服务器。")
        }
    }

    private var permissionsSection: some View {
        Section("权限") {
            permissionRow(title: "位置", symbol: "location.circle.fill", tint: .blue,
                          value: locationText,
                          needsAction: !engine.hasAnyPermission || (engine.isEnabled && !engine.hasAlwaysPermission) || !engine.isPreciseLocation) {
                switch engine.authorization {
                case .notDetermined: engine.requestWhenInUse()
                case .authorizedWhenInUse: engine.requestAlways()
                default: openSettings()
                }
            }
            permissionRow(title: "健康（步数）", symbol: "heart.circle.fill", tint: .pink,
                          value: activity.isAuthorizationRequested ? String(localized: "已请求", bundle: .appLanguage) : String(localized: "未开启", bundle: .appLanguage),
                          needsAction: !activity.isAuthorizationRequested) {
                if activity.isAuthorizationRequested {
                    // Health permissions can only be changed in the Health app afterwards.
                    if let url = URL(string: "x-apple-health://") { UIApplication.shared.open(url) }
                } else {
                    Task { await activity.requestAuthorization() }
                }
            }
            permissionRow(title: "照片（时间线）", symbol: "photo.circle.fill", tint: .orange,
                          value: photosText, needsAction: false) {
                if DayPhotos.status == .notDetermined {
                    Task { _ = await DayPhotos.requestAccess() }
                } else {
                    openSettings()
                }
            }
            LabeledContent {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(syncStatus == .available ? String(localized: "自动同步", bundle: .appLanguage) : syncStatus.title)
                        .foregroundStyle(syncStatus == .available ? .green : .secondary)
                    if syncStatus == .available, let last = cloud.lastSync {
                        Text("上次 \(last.formatted(.relative(presentation: .named).locale(appLocale)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } label: {
                Label("iCloud 同步", systemImage: "icloud.fill")
            }
            if syncStatus == .available {
                Button {
                    cloud.syncNow { try context.save() }
                } label: {
                    HStack {
                        Label("立即同步", systemImage: "arrow.triangle.2.circlepath.icloud")
                        Spacer()
                        if cloud.isSyncing { ProgressView() }
                    }
                }
                .disabled(cloud.isSyncing)
            }
        }
    }

    private var photosText: String {
        switch DayPhotos.status {
        case .authorized: String(localized: "全部照片", bundle: .appLanguage)
        case .limited: String(localized: "部分照片", bundle: .appLanguage)
        case .denied, .restricted: String(localized: "未允许", bundle: .appLanguage)
        default: String(localized: "未开启", bundle: .appLanguage)
        }
    }

    private var dataSection: some View {
        Section {
            LabeledContent("轨迹片段", value: "\(stats.chunks)")
            LabeledContent("到访记录", value: "\(stats.stays)")
            LabeledContent("旅程与记录", value: "\(stats.trips)")
            ShareLink(item: AllTracksExport(container: context.container), preview: SharePreview(AppInfo.exportFileName)) {
                Label("导出全部轨迹（GPX）", systemImage: "square.and.arrow.up")
            }
            .disabled(stats.chunks == 0)
            Button("导入 GPX 文件", systemImage: "square.and.arrow.down") { importing = true }
            Button(photoImportRun > 0 ? LocalizedStringKey("重新从相册导入") : "从相册导入足迹", systemImage: "photo.stack") { importingPhotos = true }
            Button("重新显示引导", systemImage: "arrow.uturn.backward") {
                UserDefaults.standard.set(false, forKey: "onboarding.completed")
                dismiss()
            }
            Button(retagged ? "已开始重新识别" : "重新识别未命名的地点", systemImage: "arrow.clockwise") {
                tagger?.retryFailed()
                withAnimation { retagged = true }
            }
            .disabled(retagged)
            Button("删除所有数据", systemImage: "trash", role: .destructive) { confirmingDeleteAll = true }
        } header: {
            Text("数据")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if photoImportRun > 0 {
                    Text("上次从相册导入：\(Date(timeIntervalSince1970: photoImportRun).formatted(date: .abbreviated, time: .omitted))。重新导入只会补上新的地方，不会重复。")
                }
                if PhotoFootprints.authorization == .limited {
                    Text("漫迹目前只能访问部分照片，导入可能不完整。可在系统设置里改为“完全访问”后重新导入。")
                        .foregroundStyle(.orange)
                }
                Text("GPX 可以导入 AllTrails、Strava、Google Earth 等应用。")
            }
        }
    }

    private var privacySection: some View {
        Section {
            if zones.zones.isEmpty {
                Text("还没有隐私区域").foregroundStyle(.secondary)
            }
            ForEach(zones.zones) { zone in
                Label(zone.name, systemImage: "eye.slash")
            }
            .onDelete { offsets in
                for index in offsets { zones.remove(zones.zones[index]) }
            }
        } header: {
            Text("隐私区域")
        } footer: {
            Text("在地点详情里打开“分享和导出时隐藏这里”即可添加，左滑可以删除。隐私区域内的轨迹不会出现在分享图片和 GPX 文件里。")
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            ShareLink(item: Diagnostics.fileURL, preview: SharePreview("Waytrace-diagnostics.log")) {
                Label("导出诊断日志", systemImage: "doc.text.magnifyingglass")
            }
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label("隐私政策", systemImage: "hand.raised.fill")
            }
            Link(destination: AppInfo.supportURL) {
                Label("联系我们", systemImage: "envelope.fill")
            }
            LabeledContent("版本", value: Bundle.main.versionString)
        }
    }

    #if DEBUG
    private var developerSection: some View {
        Section("开发者") {
            Button("生成演示数据", systemImage: "wand.and.stars") {
                DemoData.generate(in: context)
                engine.reloadAfterDataChange(discardPending: true)
                refreshCounts()
            }
            Button("生成 6000 个照片地点", systemImage: "photo.stack") {
                DemoData.photoStress(in: context)
                refreshCounts()
            }
            Button("预览庆祝动画", systemImage: "sparkles") {
                Celebrations.shared.addSamples()
                dismiss()
            }
        }
    }
    #endif

    // MARK: Helpers

    private func permissionRow(title: LocalizedStringKey, symbol: String, tint: Color, value: String,
                               needsAction: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label { Text(title).foregroundStyle(.primary) } icon: { Image(systemName: symbol).foregroundStyle(tint) }
                Spacer()
                Text(value).foregroundStyle(needsAction ? .orange : .secondary)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .tint(.primary)
    }

    private var precisionFooter: String {
        guard engine.isEnabled else {
            return String(localized: "仅手动：只在你从“今天”页开始记录时使用位置，结束后完全不定位。不需要“始终允许”位置权限。", bundle: .appLanguage)
        }
        let mode: String
        switch engine.precision {
        case .battery: mode = String(localized: "省电：只记录到过的地点和大致路线，几乎不耗电。", bundle: .appLanguage)
        case .balanced: mode = String(localized: "均衡：移动时记录完整路线，静止时自动暂停定位。适合大多数人。", bundle: .appLanguage)
        case .precise: mode = String(localized: "精细：路线最贴合街道，耗电更多，适合徒步和骑行爱好者。", bundle: .appLanguage)
        }
        let manual = String(localized: "也可以随时在“今天”页右上角手动记录一段。", bundle: .appLanguage)
        // Chinese sentences sit side by side; languages with spaces need one between them.
        let separator = mode.last.map { "。！？".contains($0) } == true ? "" : " "
        return mode + separator + manual
    }

    private var locationText: String {
        switch engine.authorization {
        case .authorizedAlways: engine.isPreciseLocation ? String(localized: "始终允许", bundle: .appLanguage) : String(localized: "精确位置已关闭", bundle: .appLanguage)
        case .authorizedWhenInUse: String(localized: "使用期间", bundle: .appLanguage)
        case .denied: String(localized: "已拒绝", bundle: .appLanguage)
        case .restricted: String(localized: "受限制", bundle: .appLanguage)
        default: String(localized: "未设置", bundle: .appLanguage)
        }
    }

    private var statusText: String {
        if engine.isPaused, engine.activeTripID == nil { return String(localized: "已暂停", bundle: .appLanguage) }
        guard engine.isRecording else { return String(localized: "未在记录", bundle: .appLanguage) }
        switch engine.activity {
        case .moving: return String(localized: "移动中", bundle: .appLanguage)
        case .stationary: return String(localized: "静止", bundle: .appLanguage)
        case .starting: return String(localized: "启动中", bundle: .appLanguage)
        case .unavailable: return String(localized: "无法定位", bundle: .appLanguage)
        case .off: return String(localized: "等待权限", bundle: .appLanguage)
        }
    }

    private func refreshCounts() {
        stats = ((try? context.fetchCount(FetchDescriptor<TrackChunk>())) ?? 0,
                 (try? context.fetchCount(FetchDescriptor<Stay>())) ?? 0,
                 (try? context.fetchCount(FetchDescriptor<Trip>())) ?? 0)
    }

    private func deleteEverything() {
        if engine.activeTripID != nil,
           let trip = (try? context.fetch(FetchDescriptor<Trip>()))?.first(where: \.isActive) {
            engine.endTrip(trip)
        }
        try? context.delete(model: TrackChunk.self)
        try? context.delete(model: Stay.self)
        try? context.delete(model: TripPhoto.self)
        try? context.delete(model: Trip.self)
        try? context.save()
        engine.reloadAfterDataChange(discardPending: true)
        #if DEBUG
        UserDefaults.standard.removeObject(forKey: "debug.demoSteps")
        #endif
        account.reset()
        refreshCounts()
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

/// The app's public name and contact details.
enum AppInfo {
    /// "漫迹" in Chinese, "Waytrace" in English.
    static var name: String { String(localized: "漫迹", bundle: .appLanguage) }
    static var exportFileName: String { "Waytrace.gpx" }
    static let supportEmail = "honywendev@gmail.com"
    static var supportURL: URL {
        URL(string: "mailto:\(supportEmail)?subject=Waytrace%20\(Bundle.main.versionString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
    }
}

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
