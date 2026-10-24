# 漫迹 · Waytrace

全天自动记录足迹的 iOS App（Bundle ID `com.honywen.waytrace`）：在后台记录你走过的每一条路，自动识别停留的地点、城市、国家和知名景点，并统计每天的步数和移动距离。数据只保存在用户自己的设备和 iCloud 中。

## 功能

- **今天**：当天轨迹地图（按步行、骑行、乘车、飞行着色，可全屏放大、切换卫星图、生成分享图片），步数、步行距离、移动距离，以及“停留 → 路上 → 停留”的时间线。左右滑动或用带记录标记的日历切换日期。
  - 点一段“路上”：起终点、用时、速度，改正出行方式，删除 GPS 乱线，并列出同一条路线的所有历史记录（平均用时、最快一次）。
  - 点一个地点：改名（家、学校、公司，自动应用到附近所有到访）、备注、设为隐私区域、跳到那一天。
  - 记录状态：暂停 1 小时 / 3 小时 / 到明天早上；在外地时提示“要把这次出行记成一段旅程吗？”。
  - 右上角一键手动开始记录，和全天自动记录互不影响。
- **足迹**：去过的国家和地区（停留天数、城市、景点）、城市数、景点、常去的地方、全部足迹地图；全局搜索地点、城市、国家；每个地点都有完整的到访历史。
- **旅程**：开始一段旅程（高精度），或为过去的日期补建；按天分组、照片（读取 EXIF 时间和位置）、备注、分享图片、导出 GPX。
- **统计**：周、月、年的步数和移动距离（点柱子看某一天），出行方式占比，累计国家、城市、记录天数。
- **个人资料**：设置和更换头像（从相册选取，自动裁成方形）、名字、邮箱、一句话简介；Apple 登录可选，退出登录不会丢失资料。
- **语言**：App 内可在“跟随系统 / 简体中文 / English”之间切换，立即生效；系统权限弹窗在下次打开时切换。
- **设置**：全天记录开关、记录精度（省电 / 均衡 / 精细）、权限与 iCloud 状态、隐私区域、导入和导出 GPX、删除所有数据、隐私政策。

迭代过程和每一轮的实测记录见 [PRODUCT_REVIEW.md](PRODUCT_REVIEW.md)。

## 技术架构

| 层 | 实现 |
|---|---|
| 存储与同步 | SwiftData + CloudKit 私有数据库（无需服务器） |
| 后台定位 | `CLLocationUpdate.liveUpdates` + `CLBackgroundActivitySession`，并用显著位置变化在被系统终止后重新唤醒 |
| 停留识别 | 自研停留检测：在 120 米范围内停留超过 5 分钟（或系统判定静止），即记为一次停留 |
| 地点标注 | `MKReverseGeocodingRequest`（国家、城市）+ `MKLocalPointsOfInterestRequest`（地点名称、景点） |
| 出行方式 | CoreMotion 运动识别，无法获取时按速度推断 |
| 步数 | HealthKit 每日统计，“健康”不可用时退回 CMPedometer |
| 登录与资料 | Sign in with Apple（可选）；名字、简介和头像（≤400px JPEG）存放在 iCloud 键值存储 |
| 多语言 | String Catalog（`Localizable.xcstrings`、`InfoPlist.xcstrings`），源语言简体中文，另有英文；App 内切换通过 `AppLanguage.swift` |
| UI | SwiftUI、MapKit、Swift Charts，iOS 26 Liquid Glass |

轨迹点按段压缩成 `TrackChunk`（每段最多约 400 个点，用 LZFSE 压缩），一天只有几十条 CloudKit 记录，同步快，也节省用户的 iCloud 空间。

```
RecordPath/
├── App/            入口、Tab 结构
├── Persistence/    SwiftData 模型、轨迹编码、容器
├── Location/       后台定位引擎、出行方式识别
├── Places/         地点标注、常去地点
├── Health/         步数
├── Account/        Apple 登录
├── Features/       今天 / 足迹 / 旅程 / 统计 / 设置 / 引导
└── Shared/         通用组件、地图、统计计算、GPX 导出、演示数据
```

## 开发

- Xcode 26 或更高版本，iOS 26 及以上，仅支持 iPhone。
- 直接打开 `RecordPath.xcodeproj` 运行，不依赖任何第三方库。
- 调试版的“设置 › 开发者”里可以生成演示数据（两周的上下班通勤，加一次东京、京都旅行）。
- 单元测试：`⌘U`，或者在命令行运行

```bash
xcodebuild test -project RecordPath.xcodeproj -scheme RecordPath -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RecordPathTests
```

- 在模拟器里测试后台记录：

```bash
xcrun simctl location booted start --speed=12 31.2245,121.4466 31.2310,121.4650 31.2400,121.4900
```

上线前需要完成的事项见 [LAUNCH_CHECKLIST.md](LAUNCH_CHECKLIST.md)。
