import SwiftUI

/// The privacy policy shown in the app. Keep it in sync with the hosted copy that
/// App Store Connect links to (PRIVACY.md at the repository root).
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("更新日期：2026 年 10 月 24 日")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                section("我们不收集你的数据",
                        "漫迹没有自己的服务器。你的轨迹、到访地点、旅程、照片和备注只保存在你的设备上，并通过你自己的 iCloud 账户在你的设备之间同步。开发者无法看到、访问或导出这些数据。")

                section("位置信息",
                        "在你允许后，App 会在前台和后台读取你的位置，用来画出你走过的路线、识别你停留的地点。手机静止时系统会暂停定位以节省电量。你可以随时在“设置”中关闭自动记录，或在 iOS“设置”中修改定位权限。")

                section("地点识别",
                        "为了显示地点名称、城市和国家，App 会把停留地点的坐标发送给 Apple 地图服务进行反向地理编码和兴趣点查询。这一过程由 Apple 处理，受 Apple 隐私政策约束，不包含你的身份信息。查看一个地点“那天的天空”时，App 会把那里的大致坐标（约 1 公里精度）和日期发送给 Apple 天气服务，取回当天的天气，并只保存在你的设备上。")

                section("健康与运动数据",
                        "如果你允许，App 会读取“健康”中的步数和步行距离，以及设备的运动状态（步行、骑行、乘车），只用于在 App 内展示统计。这些数据不会被写入“健康”，也不会离开你的设备和 iCloud。")

                section("Apple 登录",
                        "登录是可选的。如果你使用“通过 Apple 登录”，App 只保存 Apple 提供的匿名用户标识、你选择分享的名字和邮箱，存放在你的 iCloud 键值存储中，用于在你的设备之间同步资料。")

                section("照片",
                        "你添加到旅程中的照片会被压缩后保存在 App 中并同步到你的 iCloud。App 只能访问你在系统照片选择器里选中的照片。")

                section("删除数据",
                        "你可以在“设置 › 删除所有数据”中永久删除所有轨迹、地点、旅程和照片，删除会同步到你的所有设备和 iCloud。卸载 App 会删除本机数据；iCloud 中的数据可以在 iOS“设置 › Apple 账户 › iCloud › 管理存储空间”中删除。")

                section("第三方",
                        "App 不包含广告、数据分析或第三方追踪 SDK，不会出售或共享你的任何数据。")

                section("联系我们",
                        "如果你对隐私有任何疑问，请通过 App 内“设置 › 联系我们”与我们联系。")
            }
            .padding()
        }
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(body).font(.body).foregroundStyle(.secondary)
        }
    }
}
