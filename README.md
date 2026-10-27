<p align="center">
  <img src="docs/images/icon.png" width="120" alt="漫迹 Waytrace 图标">
</p>

<h1 align="center">漫迹 · Waytrace</h1>

<p align="center">
  <b>不用打开，不用记得按开始。你走过的路，它都替你记着。</b><br>
  全天自动记录足迹的 iPhone 和 Apple Watch App：轨迹、停留的地点、去过的城市和国家，一年一年攒成你自己的地图。
</p>

<p align="center">
  <img alt="iOS 26+" src="https://img.shields.io/badge/iOS-26%2B-black?logo=apple">
  <img alt="watchOS 26+" src="https://img.shields.io/badge/watchOS-26%2B-black?logo=apple">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI%20%C2%B7%20SwiftData-F05138?logo=swift&logoColor=white">
  <img alt="No third-party dependencies" src="https://img.shields.io/badge/依赖-零第三方库-34C759">
  <img alt="License" src="https://img.shields.io/badge/许可-非商业使用-orange">
</p>

<p align="center">
  简体中文 · <a href="README_en.md">English</a>
</p>

<p align="center">
  <img src="docs/images/today.jpg" width="200" alt="今天">
  <img src="docs/images/country.jpg" width="200" alt="国家页">
  <img src="docs/images/year.jpg" width="200" alt="年度足迹">
  <img src="docs/images/milestones.jpg" width="200" alt="里程碑">
</p>

---

## 它能做什么

### 🗺️ 自动记录，什么都不用管
- **全天后台记录**：口袋里的手机就够了。走路、骑车、开车、坐飞机，自动分辨出行方式，用不同颜色画在地图上。
- **自动认出地点**：在一个地方停留几分钟，就记成一次“停留”，并认出它是哪家店、哪个景点、哪座城市、哪个国家。
- **时间线**：一天按“停留 → 路上 → 停留”排开，每个地点带上你在那里拍的照片；点照片直接看大图，点地点先看再改。
- **省电**：三档精度可选，静止时自动降频，在国内地图上自动纠正坐标偏移。

### 📸 一键从相册点亮过去
- 扫描相册里上万张照片和视频的拍摄地点，**补上 App 出现之前你去过的所有地方**，点亮城市、省份和国家。
- 同一天同一座城市的照片合成一次到访；已经记录过的不会重复。
- 所有读取都在手机上完成，照片不会被上传或复制。

### 🌏 你去过的世界
- **点亮地图**：中国 34 个省级行政区的方块地图，世界各大洲的国旗墙；点进去就是那个省或国家的全部足迹。
- **国家页**：描出国境的地图（中国大陆、港澳台不由 App 绘制边界），每座去过的城市一团光，标着天数。
- **一段段行程**：成百上千条到访按“同一城市的连续几天”自动归成一段，按年份排开；每段有地图、照片拼贴和每一天的轨迹。

<p align="center">
  <img src="docs/images/places.jpg" width="200" alt="足迹">
  <img src="docs/images/lightup.jpg" width="200" alt="点亮地图">
  <img src="docs/images/country.jpg" width="200" alt="国家页">
</p>

### 🧳 旅程，自动整理
- 从足迹里**自动找出过去的旅行**：离开常住地 80 公里以上的连续日子，一键收进旅程。
- 旅程汇总这几天的路线、地点和照片，可以写备注、导出 GPX、生成分享图。
- 徒步、跑步、骑行可以单独用高精度记录，Apple Watch 一起记录心率并存为体能训练。

### ✨ 有仪式感的时刻
- **点亮仪式**：第一次到新的国家或省份，地图从灰色亮起来，国旗落下，撒下彩纸；按住才会点亮。
- **插画奖牌**：23 枚里程碑，每一枚是一幅小画，铜、银、金、铂金分级。
- **年度足迹**：故事一样一页页翻：发光的城市地图、转动的点阵地球、走过的脚印、落在地图上的国旗、最远那天的路线、一墙拍立得照片，最后是一张可以分享的海报。

<p align="center">
  <img src="docs/images/year.jpg" width="200" alt="年度足迹封面">
  <img src="docs/images/globe.jpg" width="200" alt="移动距离">
  <img src="docs/images/milestones.jpg" width="200" alt="里程碑">
</p>

### ⌚ Apple Watch
- 打开就是地图：你的位置、今天的路线、所在的地点。
- 不带手机也能记录徒步、跑步、骑行；在 iPhone 上开始记录时，手表自动跟着一起记录。
- 表盘复杂功能：今天走了多远、现在在哪。

---

## 隐私

漫迹**没有自己的服务器**。轨迹、地点、旅程和照片只存在你的设备和你自己的 iCloud 里，开发者看不到。地点名称通过 Apple 地图服务识别；照片只在手机上读取。详见 [PRIVACY.md](PRIVACY.md)。

## 技术

| | |
|---|---|
| 界面 | SwiftUI、MapKit、Swift Charts，iOS 26 Liquid Glass |
| 存储与同步 | SwiftData + CloudKit 私有数据库，自动同步 |
| 后台定位 | `CLLocationUpdate.liveUpdates` + `CLBackgroundActivitySession`，被系统终止后由显著位置变化唤醒 |
| 地点 | `MKReverseGeocodingRequest`、`MKLocalPointsOfInterestRequest`；国内地图 WGS-84 → GCJ-02 转换 |
| 运动与健康 | CoreMotion 识别出行方式，HealthKit 步数 |
| Apple Watch | watchOS SwiftUI App、WidgetKit 复杂功能、`HKWorkoutSession`、WatchConnectivity |
| 实时活动 | ActivityKit：锁屏、灵动岛、手表智能叠放 |
| 多语言 | String Catalog，简体中文和英文，App 内切换 |

轨迹点按段压缩（LZFSE）成 `TrackChunk`，一天只有几十条 CloudKit 记录。所有汇总（国家、城市、点亮地图、里程碑、旅程发现）在后台线程计算，几千个地点也不卡。没有任何第三方依赖。

<details>
<summary>项目结构</summary>

```
RecordPath/
├── App/            入口、Tab 结构
├── Persistence/    SwiftData 模型、轨迹编码、iCloud 同步
├── Location/       后台定位引擎、出行方式识别
├── Places/         地点识别、常去地点
├── Health/         步数
├── Account/        Apple 登录
├── Features/       今天 / 足迹 / 旅程 / 统计 / 庆祝 / 设置 / 引导
├── Watch/          和手表的同步
└── Shared/         地图、统计、相册导入、旅程发现、GPX
Common/             iPhone、手表、复杂功能共用的代码
WaytraceWatch/      Apple Watch App
WaytraceWidgets/    表盘复杂功能
WaytraceLiveActivity/  实时活动
```
</details>

## 运行

- Xcode 26 或更高版本；iOS 26+（iPhone），watchOS 26+。
- 打开 `RecordPath.xcodeproj`，选择 RecordPath scheme 运行即可，不需要安装任何依赖。
- 在真机上运行需要把 Signing 里的 Team 换成你自己的。
- 调试版的“设置 › 开发者”可以生成演示数据，方便在模拟器里看效果。

```bash
# 单元测试
xcodebuild test -project RecordPath.xcodeproj -scheme RecordPath \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RecordPathTests

# 在模拟器里模拟一段移动
xcrun simctl location booted start --speed=12 31.2245,121.4466 31.2310,121.4650 31.2400,121.4900
```

每一轮的设计取舍和实测记录在 [PRODUCT_REVIEW.md](PRODUCT_REVIEW.md)，上架前的事项在 [LAUNCH_CHECKLIST.md](LAUNCH_CHECKLIST.md)。

## 许可

本项目采用 **[PolyForm Noncommercial 1.0.0](LICENSE)** 许可。

- ✅ 个人学习、研究、自用、修改，以及非营利组织、教育机构使用：可以。
- ❌ 任何商业用途（包括上架收费或带广告的 App、用于公司产品或服务）：不可以。
- 如需商业授权，请通过 GitHub 联系作者。

Copyright © 2026 lxyeternal
