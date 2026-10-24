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

    @State private var syncStatus: SyncStatus = .checking
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var confirmingSignOut = false
    @State private var confirmingDeleteAll = false
    @State private var stats: (chunks: Int, stays: Int, trips: Int) = (0, 0, 0)
    @State private var retagged = false
    @State private var importing = false
    @State private var importMessage: String?
    private var zones = PrivacyZones.shared

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                trackingSection
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
                var message = String(localized: "导入了 \(tracks) 段轨迹、\(places) 个地点。")
                if duplicates > 0 { message += String(localized: "跳过了 \(duplicates) 条已经存在的记录。") }
                if !failures.isEmpty { message += "\n" + failures.joined(separator: "\n") }
                importMessage = message
            }
            .alert("导入完成", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }
            .alert("修改名字", isPresented: $editingName) {
                TextField("名字", text: $nameDraft)
                Button("取消", role: .cancel) {}
                Button("保存") { account.updateDisplayName(nameDraft) }
            }
            .confirmationDialog("退出登录？", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) { account.signOut() }
            } message: {
                Text("你的轨迹和地点仍然保留在这台设备和 iCloud 中。")
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
            if let profile = account.profile {
                HStack(spacing: 14) {
                    Avatar(name: profile.displayName, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName ?? String(localized: "旅行者")).font(.headline)
                        Text(profile.email ?? String(localized: "已通过 Apple 登录"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Button("修改名字", systemImage: "pencil") {
                    nameDraft = profile.displayName ?? ""
                    editingName = true
                }
                Button("退出登录", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    confirmingSignOut = true
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("登录后，你的名字会在所有设备上同步。").font(.subheadline).foregroundStyle(.secondary)
                    SignInWithAppleButton(.signIn, onRequest: account.configure, onCompletion: account.handle)
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 46)
                        .clipShape(.capsule)
                }
                .padding(.vertical, 6)
                if let error = account.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
        } header: {
            Text("账户")
        }
    }

    private var trackingSection: some View {
        Section {
            @Bindable var engine = engine
            Toggle(isOn: $engine.isEnabled) {
                Label("全天自动记录", systemImage: "location.fill")
            }
            LabeledContent {
                Text(statusText).foregroundStyle(.secondary)
            } label: {
                Label("当前状态", systemImage: "waveform.path.ecg")
            }
            Picker(selection: $engine.precision) {
                Text("省电").tag(LocationEngine.Precision.battery)
                Text("均衡").tag(LocationEngine.Precision.balanced)
                Text("精细").tag(LocationEngine.Precision.precise)
            } label: {
                Label("记录精度", systemImage: "scope")
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

    private var permissionsSection: some View {
        Section("权限") {
            permissionRow(title: "位置", symbol: "location.circle.fill", tint: .blue,
                          value: locationText, needsAction: !engine.hasAlwaysPermission || !engine.isPreciseLocation) {
                switch engine.authorization {
                case .notDetermined: engine.requestWhenInUse()
                case .authorizedWhenInUse: engine.requestAlways()
                default: openSettings()
                }
            }
            permissionRow(title: "健康（步数）", symbol: "heart.circle.fill", tint: .pink,
                          value: activity.isAuthorizationRequested ? String(localized: "已请求") : String(localized: "未开启"),
                          needsAction: !activity.isAuthorizationRequested) {
                if activity.isAuthorizationRequested {
                    // Health permissions can only be changed in the Health app afterwards.
                    if let url = URL(string: "x-apple-health://") { UIApplication.shared.open(url) }
                } else {
                    Task { await activity.requestAuthorization() }
                }
            }
            LabeledContent {
                Text(syncStatus.title).foregroundStyle(syncStatus == .available ? .green : .secondary)
            } label: {
                Label("iCloud 同步", systemImage: "icloud.fill")
            }
        }
    }

    private var dataSection: some View {
        Section {
            LabeledContent("轨迹片段", value: "\(stats.chunks)")
            LabeledContent("到访记录", value: "\(stats.stays)")
            LabeledContent("旅程", value: "\(stats.trips)")
            ShareLink(item: AllTracksExport(container: context.container), preview: SharePreview("PathTracker.gpx")) {
                Label("导出全部轨迹（GPX）", systemImage: "square.and.arrow.up")
            }
            .disabled(stats.chunks == 0)
            Button("导入 GPX 文件", systemImage: "square.and.arrow.down") { importing = true }
            Button(retagged ? "已开始重新识别" : "重新识别未命名的地点", systemImage: "arrow.clockwise") {
                tagger?.retryFailed()
                withAnimation { retagged = true }
            }
            .disabled(retagged)
            Button("删除所有数据", systemImage: "trash", role: .destructive) { confirmingDeleteAll = true }
        } header: {
            Text("数据")
        } footer: {
            Text("GPX 可以导入 AllTrails、Strava、Google Earth 等应用。")
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
            Button("重新显示引导", systemImage: "arrow.uturn.backward") {
                UserDefaults.standard.set(false, forKey: "onboarding.completed")
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
        let mode: String
        switch engine.precision {
        case .battery: mode = String(localized: "省电：只记录到过的地点和大致路线，几乎不耗电。")
        case .balanced: mode = String(localized: "均衡：移动时记录完整路线，静止时自动暂停定位。适合大多数人。")
        case .precise: mode = String(localized: "精细：路线最贴合街道，耗电更多，适合徒步和骑行爱好者。")
        }
        return mode + String(localized: "关闭全天记录后，仍可以在“今天”页右上角手动记录一段。")
    }

    private var locationText: String {
        switch engine.authorization {
        case .authorizedAlways: engine.isPreciseLocation ? String(localized: "始终允许") : String(localized: "精确位置已关闭")
        case .authorizedWhenInUse: String(localized: "使用期间")
        case .denied: String(localized: "已拒绝")
        case .restricted: String(localized: "受限制")
        default: String(localized: "未设置")
        }
    }

    private var statusText: String {
        if engine.isPaused, engine.activeTripID == nil { return String(localized: "已暂停") }
        guard engine.isRecording else { return String(localized: "已关闭") }
        switch engine.activity {
        case .moving: return String(localized: "移动中")
        case .stationary: return String(localized: "静止")
        case .starting: return String(localized: "启动中")
        case .unavailable: return String(localized: "无法定位")
        case .off: return String(localized: "等待权限")
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
        account.signOut()
        refreshCounts()
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

/// Public contact details. Replace the support address before submitting to the App Store.
enum AppInfo {
    static let supportEmail = "support@pathtracker.app"
    static var supportURL: URL {
        URL(string: "mailto:\(supportEmail)?subject=PathTracker%20\(Bundle.main.versionString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
    }
}

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
