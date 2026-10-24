import SwiftUI
import AuthenticationServices
import CoreLocation

/// Four short steps: what the app does, location (When In Use, then Always), steps, and an
/// optional Sign in with Apple. Every permission can be skipped and granted later.
struct OnboardingView: View {
    var onFinish: () -> Void

    @Environment(LocationEngine.self) private var engine
    @Environment(ActivityProvider.self) private var activity
    @Environment(AccountManager.self) private var account

    enum Step: Int, CaseIterable { case welcome, location, activity, account }
    @State private var step: Step = .welcome

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case .welcome: welcome
                case .location: location
                case .activity: activityStep
                case .account: accountStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)

            pageDots.padding(.top, 20).padding(.bottom, 8)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
        .background(alignment: .top) {
            LinearGradient(colors: [Color.accentColor.opacity(0.18), .clear], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: step)
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { finish(); return }
        withAnimation(.smooth(duration: 0.45)) { step = next }
    }

    private func finish() {
        if engine.hasAnyPermission { engine.isEnabled = true }
        onFinish()
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.self) { item in
                Capsule()
                    .fill(item == step ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: item == step ? 20 : 7, height: 7)
            }
        }
        .animation(.spring(duration: 0.4), value: step)
        .accessibilityHidden(true)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 28) {
            Spacer()
            HeroSymbol(systemName: "point.topright.filled.arrow.triangle.backward.to.point.bottomleft.scurvepath", tint: .accentColor)
            VStack(spacing: 10) {
                Text("走过的路，都会被记住")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("PathTracker 在后台安静地记录你每天的轨迹，自动整理去过的地方、城市和国家。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 22) {
                FeatureRow(symbol: "map.fill", tint: .blue, title: "全天自动记录",
                           detail: "不用每次手动开始，放大地图就能看到走过的每条街。")
                FeatureRow(symbol: "flag.2.crossed.fill", tint: .orange, title: "足迹自动标注",
                           detail: "国家、城市和知名景点会被自动识别。")
                FeatureRow(symbol: "lock.icloud.fill", tint: .green, title: "只属于你",
                           detail: "数据只保存在你的设备和你自己的 iCloud 中。")
            }
            .padding(.top, 8)
            Spacer()
            PrimaryButton(title: "开始使用", action: advance)
        }
    }

    private var location: some View {
        VStack(spacing: 28) {
            Spacer()
            HeroSymbol(systemName: engine.hasAlwaysPermission ? "location.fill.viewfinder" : "location.fill", tint: .blue)
            VStack(spacing: 10) {
                Text(engine.hasAnyPermission && !engine.hasAlwaysPermission ? "再多一步：始终允许" : "允许访问你的位置")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(locationExplanation)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if engine.hasAnyPermission && !engine.hasAlwaysPermission {
                PermissionHint(text: "在弹出的对话框里选择“更改为始终允许”。")
            }
            Spacer()
            VStack(spacing: 12) {
                switch engine.authorization {
                case .notDetermined:
                    PrimaryButton(title: "允许访问位置") { engine.requestWhenInUse() }
                case .authorizedWhenInUse:
                    PrimaryButton(title: "改为始终允许") { engine.requestAlways() }
                    SecondaryButton(title: "以后再说", action: advance)
                case .authorizedAlways:
                    PrimaryButton(title: "继续", action: advance)
                default:
                    PrimaryButton(title: "打开设置") { openSettings() }
                    SecondaryButton(title: "跳过", action: advance)
                }
            }
        }
        .onChange(of: engine.authorization) { _, status in
            if status == .authorizedAlways {
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    advance()
                }
            }
        }
    }

    private var locationExplanation: LocalizedStringKey {
        switch engine.authorization {
        case .authorizedWhenInUse:
            "选择“始终允许”后，即使你没有打开 App，轨迹也会被记录下来。系统会在手机静止时自动暂停定位，尽量省电。"
        case .denied, .restricted:
            "定位权限已关闭。你可以在“设置”里打开，PathTracker 才能记录轨迹。"
        default:
            "PathTracker 用你的位置来画出走过的路线、识别停留的地点。位置数据不会离开你的设备和 iCloud。"
        }
    }

    private var activityStep: some View {
        VStack(spacing: 28) {
            Spacer()
            HeroSymbol(systemName: "figure.walk.motion", tint: .green)
            VStack(spacing: 10) {
                Text("步数与运动方式")
                    .font(.title.bold())
                Text("读取“健康”里的步数和步行距离，并识别你是在步行、骑行还是乘车，让每天的记录更完整。")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            VStack(spacing: 12) {
                PrimaryButton(title: "允许读取") {
                    Task {
                        await activity.requestAuthorization()
                        _ = await activity.activity(from: Date(), days: 1)
                        advance()
                    }
                }
                SecondaryButton(title: "以后再说", action: advance)
            }
        }
    }

    private var accountStep: some View {
        VStack(spacing: 28) {
            Spacer()
            HeroSymbol(systemName: "person.crop.circle.badge.checkmark", tint: .indigo)
            VStack(spacing: 10) {
                Text("登录以同步资料")
                    .font(.title.bold())
                Text("使用 Apple 登录来保存你的名字，并在你的所有设备上保持一致。不登录也能使用全部功能。")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            VStack(spacing: 12) {
                if account.isSignedIn {
                    Label("已登录为 \(account.greetingName)", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                        .frame(height: 52)
                    PrimaryButton(title: "完成", action: finish)
                } else {
                    SignInWithAppleButton(.signIn, onRequest: account.configure) { result in
                        account.handle(result)
                        if account.isSignedIn { finish() }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .clipShape(.capsule)
                    SecondaryButton(title: "暂不登录", action: finish)
                }
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

// MARK: - Building blocks

private struct HeroSymbol: View {
    let systemName: String
    let tint: Color
    @State private var appeared = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 64, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 120, height: 120)
            .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(tint.gradient))
            .shadow(color: tint.opacity(0.35), radius: 20, y: 10)
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            .symbolEffect(.bounce, value: appeared)
            .onAppear {
                withAnimation(.spring(duration: 0.6, bounce: 0.4).delay(0.1)) { appeared = true }
            }
            .accessibilityHidden(true)
    }
}

private struct FeatureRow: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PermissionHint: View {
    let text: LocalizedStringKey

    var body: some View {
        Label(text, systemImage: "hand.tap.fill")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: .capsule)
    }
}

struct PrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
    }
}

struct SecondaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.body.weight(.medium))
            .frame(height: 44)
    }
}
