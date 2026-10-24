# 漫迹 · Waytrace

全天自动记录足迹的 iOS App（Bundle ID `com.honywen.waytrace`）：在后台记录你走过的每一条路，自动识别停留的地点、城市、国家和知名景点，并统计每天的步数和移动距离。数据只保存在用户自己的设备和 iCloud 中。

## 功能

- **今天**：当天轨迹地图（按步行、骑行、乘车、飞行着色，可全屏放大、切换卫星图、生成分享图片），步数、步行距离、移动距离，以及“停留 → 路上 → 停留”的时间线。左右滑动或用带记录标记的日历切换日期。
  - 点一段“路上”：起终点、用时、速度，改正出行方式，删除 GPS 乱线，并列出同一条路线的所有历史记录（平均用时、最快一次）。
  - 点一个地点：改名（家、学校、公司，自动应用到附近所有到访）、备注、设为隐私区域、跳到那一天。
  - 记录状态：暂停 1 小时 / 3 小时 / 到明天早上；在外地时提示“要把这次出行记成一段旅程吗？”。
  - 右上角一键手动开始记录，和全天自动记录互不影响。
- **记录**：一次徒步、步行、跑步或骑行，单独用高精度记录（可以让 Apple Watch 一起记录）；详情显示距离、用时、配速（骑行为均速）和爬升。
- **足迹**：去过的国家和地区（停留天数、城市、景点）、城市数、景点、常去的地方、全部足迹地图；全局搜索地点、城市、国家；每个地点都有完整的到访历史。
  - **点亮地图**：中国 34 个省级行政区（方块地图，按去过的天数由浅到深）和世界各大洲的国家，显示进度，可以分享成图片。
- **旅程**：出游或出差的几天，全天记录的轨迹和地点自动收进来；也可以为过去的日期补建；照片、备注、分享图片、导出 GPX。“旅程”和“记录”分成两个列表。
- **统计**：周、月、年的步数和移动距离（点柱子看某一天），出行方式占比，累计国家、城市、记录天数。
  - **年度足迹**：一页一页地看这一年：移动距离、步数、去过的国家城市省份（第一次去的单独列出）、移动最远的一天、除了家最常去的地方、离家最远的地方，最后一页可以分享。
  - **里程碑**：移动距离、国家、省份、城市、记录天数，已达成的带日期，下一个目标显示进度。
- **通知**（可分别关闭）：第一次到达新的国家、省份、城市；达成里程碑；每周一早上回顾上周。
- **照片**（可选）：时间线上每个地点下面显示在那里拍的照片，点开地点可以看全部。照片只在手机上读取。
- **个人资料**：设置和更换头像（从相册选取，自动裁成方形）、名字、邮箱、一句话简介；Apple 登录可选，退出登录不会丢失资料。
- **语言**：App 内可在“跟随系统 / 简体中文 / English”之间切换，立即生效；系统权限弹窗在下次打开时切换。
- **Apple Watch**：像地图和徒步 App 一样，打开就是地图：你现在的位置、今天走过的路线和所在地点名。
  - 一键开始记录（徒步 / 步行 / 跑步 / 骑行），不带手机也能记录。实时显示路线、用时、距离、配速和心率，可暂停、结束；结束后存为“健身”App 里的体能训练，并自动同步到 iPhone 的“旅程”。
  - “今天”里可以看步数、距离、地点，并在手表上暂停或恢复 iPhone 的全天记录。
  - 表盘复杂功能：今天的距离、现在所在的地点，轻点直接打开 App。
  - 跟随 iPhone App 里选的语言。
- **iPhone 和手表联动**：在 iPhone 上开始手动记录时，
  - 锁屏、灵动岛显示实时活动（名称、用时、距离），iOS 会自动把它放进手表的智能叠放，抬腕就能看到；
  - 打开“在 Apple Watch 上同时记录”（徒步、步行这类默认打开，开车、坐飞机、坐火车默认关闭），手表上的漫迹会自动打开并一起记录（心率、体能训练）；在任一设备上结束，两边一起结束，手表的记录并入同一段旅程。
- **设置**：全天记录开关、记录精度（省电 / 均衡 / 精细）、权限与 iCloud 状态、隐私区域、导入和导出 GPX、删除所有数据、隐私政策。

迭代过程和每一轮的实测记录见 [PRODUCT_REVIEW.md](PRODUCT_REVIEW.md)。

## 技术架构

| 层 | 实现 |
|---|---|
| 存储与同步 | SwiftData + CloudKit 私有数据库（无需服务器） |
| 后台定位 | `CLLocationUpdate.liveUpdates` + `CLBackgroundActivitySession`，并用显著位置变化在被系统终止后重新唤醒 |
| 停留识别 | 自研停留检测：在 120 米范围内停留超过 5 分钟（或系统判定静止），即记为一次停留 |
| 中国大陆地图偏移 | 记录的数据始终是 GPS 坐标（WGS-84）；在中国大陆画到 Apple 地图上时转换为 GCJ-02（`Common/ChinaCoordinates.swift`，港澳台和境外不转换） |
| 地点标注 | `MKReverseGeocodingRequest`（国家、城市）+ `MKLocalPointsOfInterestRequest`（地点名称、景点） |
| 出行方式 | CoreMotion 运动识别，无法获取时按速度推断 |
| 步数 | HealthKit 每日统计，“健康”不可用时退回 CMPedometer |
| 登录与资料 | Sign in with Apple（可选）；名字、简介和头像（≤400px JPEG）存放在 iCloud 键值存储 |
| 多语言 | String Catalog（`Localizable.xcstrings`、`InfoPlist.xcstrings`），源语言简体中文，另有英文；App 内切换通过 `AppLanguage.swift` |
| UI | SwiftUI、MapKit、Swift Charts，iOS 26 Liquid Glass |
| 实时活动 | ActivityKit（`WaytraceLiveActivity`），带手表智能叠放的小尺寸布局 |
| Apple Watch | watchOS 26 SwiftUI App + WidgetKit 复杂功能；`HKHealthStore.startWatchApp` 从 iPhone 打开手表 App；`HKWorkoutSession` 让记录在抬腕之外也持续进行；WatchConnectivity 同步 |

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
├── Watch/          和手表的同步（WatchBridge）、导入手表记录
└── Shared/         通用组件、地图、统计计算、GPX 导出、演示数据
Common/             iPhone、手表、复杂功能共用：轨迹编码、格式化、语言、同步消息
WaytraceWatch/      Apple Watch App：地图首页、记录（体能训练 + GPS）、今天
WaytraceWidgets/    表盘复杂功能
WaytraceLiveActivity/  iPhone 实时活动（锁屏、灵动岛、手表智能叠放）
```

### iPhone 和手表怎么配合

- iPhone 负责全天记录。手表不做全天 GPS（太耗电），只在你开始记录时用自己的 GPS。
- iPhone → 手表：今天的路线（抽稀到 600 个点以内）、地点、距离、步数、暂停状态和语言，变化时通过 application context 推送，最多 30 秒一次。
- 手表 → iPhone：暂停 / 恢复用消息发送（不在附近时排队）；记录用文件传输，iPhone 在附近且记录较小时同时直接发送。
- 手表上的记录要等 iPhone 确认收到（出现在 `receivedRecordings` 里）才删除，否则会自动重发；iPhone 按记录 ID 去重，重复收到也不会多出一条。
- 如果 iPhone 同时也在记录，同一段路不会重复：旅程的轨迹取时间范围内已有的记录，只有 iPhone 没录到时才用手表的轨迹。

## 开发

- Xcode 26 或更高版本，iOS 26 及以上（仅 iPhone），watchOS 26 及以上。
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
