# 上线清单

> 上 TestFlight 的具体步骤见 [AppStore/TESTFLIGHT.md](AppStore/TESTFLIGHT.md)，商店文案和截图在 [AppStore/](AppStore/)。

代码已经可以在模拟器里完整运行。以下事项需要开发者账号或你本人来完成，完成后才能上真机测试和提交 App Store。

## 1. 账号与标识（需要你来做）

- [x] 加入 Apple Developer Program，Team ID `46CMLTF7SR`。
- [x] **Bundle ID**：`com.honywen.waytrace`（已写入工程；上架后不能再改）。在开发者网站 Identifiers 里注册同名 App ID。
- [x] **App 名称**：中文“漫迹”，英文“Waytrace”（主屏幕名称随语言切换）。
- [ ] 在 App Store Connect 中新建 App：主要语言简体中文，名称“漫迹”；再添加英文本地化，名称“Waytrace”。

## 2. Xcode 签名与能力（我可以帮你改，需要先有 Team ID）

在 Signing & Capabilities 里选择你的 Team 之后，确认以下能力都已开启（`RecordPath.entitlements` 已经写好）：

- [ ] iCloud › CloudKit，容器为 `iCloud.com.honywen.waytrace`
- [ ] Sign in with Apple
- [ ] HealthKit
- [ ] Background Modes › Location updates、Remote notifications
- [ ] Push Notifications（CloudKit 同步需要）

Apple Watch（自动签名会一起创建，确认一下即可）：

- [ ] 手表 App `com.honywen.waytrace.watchkitapp`：HealthKit、App Groups（`group.com.honywen.waytrace`）、Background Modes › Workout processing
- [ ] 复杂功能 `com.honywen.waytrace.watchkitapp.widgets`：App Groups（同一个组）

## 3. CloudKit

- [ ] 在真机上运行一次，让 SwiftData 在开发环境自动创建 CloudKit 架构。
- [ ] 打开 CloudKit Console，把架构 **Deploy Schema Changes 到 Production**。不做这一步，App Store 版本将无法同步。

## 4. 真机测试（需要一台 iPhone）

- [ ] 授予“始终允许”定位后，锁屏带手机出门 1 小时，回来检查轨迹是否完整。
- [ ] 在设置里把 App 从后台划掉，然后出门，检查是否会被系统重新唤醒并继续记录。
- [ ] 观察全天耗电（设置 › 电池）。
- [ ] 在中国大陆检查地图上的轨迹是否与道路对齐（已加入 GCJ-02 转换，单元测试覆盖了 30 个边境和沿海城市，仍需真机确认；也看看深圳—香港、珠海—澳门过境时轨迹是否连贯）。
- [ ] 第一次到达新城市、新省份时是否收到通知；每周一早上是否收到上周回顾。
- [ ] 两台设备登录同一个 Apple ID，检查 iCloud 同步。
- [ ] Apple Watch：不带手机出门用手表记录一段徒步，回来后检查是否出现在 iPhone 的“旅程”和“健身”App 里。模拟器里文件传输不可用，这条只能在真机上验证。
- [ ] Apple Watch：放下手腕 30 分钟，记录是否持续、耗电多少。
- [ ] Apple Watch：表盘复杂功能是否随 iPhone 更新。
- [ ] 联动：在 iPhone 上开始手动记录（打开“在 Apple Watch 上同时记录”），手表 App 是否自动打开并开始记录。模拟器里 HealthKit 无法把这个请求送到手表，只能在真机上验证（调试版可以用 `-simulateWorkoutLaunch hiking` 启动参数模拟）。
- [ ] 联动：手表智能叠放里是否出现实时活动，锁屏和灵动岛显示是否正常。
- [ ] 测试通过 Apple 登录、退出登录，以及在 iOS 设置里停止使用 Apple ID 登录后 App 的表现。

## 5. 审核材料

- [x] **隐私政策网址**：https://lxyeternal.github.io/PathTracker/privacy.html（需要在 GitHub 打开 Pages，见 TESTFLIGHT.md 第 1 步）。
- [x] **客服邮箱**：honywendev@gmail.com（已写入 `AppInfo.supportEmail`，App Store Connect 的“技术支持网址”也可以填这个邮箱所在页面）。
- [x] 中英文商店描述、关键词和 iPhone 截图：`AppStore/`。
- [ ] **App 隐私标签**：位置（精确位置）、健康与健身、照片；全部选择“不用于追踪、不与身份关联”，并勾选数据不会被开发者收集。
- [ ] **后台定位说明**：审核会询问为什么需要“始终允许”定位。可以这样回答：用于全天自动记录用户的出行轨迹，这是 App 的核心功能；数据只存在用户自己的 iCloud 中。最好附上一段演示视频。
- [ ] 截图：6.9 英寸和 6.5 英寸 iPhone 截图，另需 Apple Watch 截图（任一尺寸）。可以在调试版里用“生成演示数据”后截图。
- [ ] 如果要在中国大陆上架：完成 **ICP 备案**并在 App Store Connect 中填写备案号。

## 6. 已知的后续工作（不影响第一版）

- 灵动岛与锁屏的实时活动（Live Activity），用于显示旅程记录状态。
- 桌面小组件：今日步数和距离。
- 使用 Apple 登录时撤销令牌需要一个服务器端接口，目前 App 内的“删除所有数据”会清除本地和 iCloud 数据并退出登录。
