# 上 TestFlight 的步骤

照着从上往下做。标着 **你** 的需要用你的 Apple 账号操作；其余的已经准备好。

## 1. 打开网页（**你**，一次，约 2 分钟）

GitHub 仓库 › Settings › Pages › Build and deployment：Source 选 **Deploy from a branch**，Branch 选 **main**，文件夹选 **/docs**，保存。

一两分钟后这两个网址可以打开（App Store Connect 要填）：

- 隐私政策：https://lxyeternal.github.io/PathTracker/privacy.html
- 技术支持：https://lxyeternal.github.io/PathTracker/#support

## 2. 在 App Store Connect 新建 App（**你**，约 5 分钟）

[appstoreconnect.apple.com](https://appstoreconnect.apple.com) › App › “+” › 新建 App：

| 栏目 | 填写 |
|---|---|
| 平台 | iOS |
| 名称 | 漫迹（如果被占用，可以用“漫迹 - 足迹记录”这类） |
| 主要语言 | 简体中文 |
| 套装 ID | com.honywen.waytrace |
| SKU | waytrace |
| 用户访问权限 | 完全访问权限 |

建好后在“App 信息”里添加英文（美国）本地化，名称填 Waytrace。

## 3. 把 iCloud 结构发布到生产环境（**你**，约 2 分钟，必须做）

1. 打开 [CloudKit Console](https://icloud.developer.apple.com) › 选择容器 `iCloud.com.honywen.waytrace`。
2. 左侧 Schema：确认 Development 环境里已经有 `CD_Stay`、`CD_TrackChunk`、`CD_Trip`、`CD_TripPhoto` 这些记录类型（手机上用过 App 就会有）。
3. 点 **Deploy Schema Changes…** › Deploy。

不做这一步，TestFlight 和 App Store 版本无法同步 iCloud。以后改了数据模型（新增字段）要再部署一次。

## 4. 上传（我可以做，也可以你在 Xcode 里做）

命令行（在仓库根目录）：

```bash
zsh AppStore/upload.sh
```

或者在 Xcode 里：顶部设备选 **Any iOS Device (arm64)** › Product › Archive › 完成后在 Organizer 里点 **Distribute App** › **App Store Connect** › Upload。

每次上传的构建号会自动用当时的时间，不会重复。本地已经试过打包（包含 Apple Watch App、表盘复杂功能和实时活动），可以通过。

## 5. 在手机和手表上安装（**你**）

1. 上传后 10–30 分钟，App Store Connect › TestFlight 里会出现这个构建。第一次会问“出口合规”：选 **不使用加密**（App 只用了系统自带的 HTTPS）。
2. TestFlight › 内部测试 › 新建群组，把你自己的 Apple ID 加进去。
3. iPhone 上安装 **TestFlight** App，用同一个 Apple ID 登录，安装漫迹。
4. Apple Watch 会自动装上手表 App（如果没有：手表上打开 App Store 或 iPhone 的 Watch App › 漫迹 › 安装）。TestFlight 安装不需要开发者模式，之前手表连不上 Xcode 的问题不影响这里。

## 6. 测一周，再提交审核

要特别看的：

- 锁屏带手机出门、把 App 从后台划掉之后，轨迹是否完整；一整天耗电多少。
- 手表：不带手机记录一次徒步，回来是否出现在 iPhone 的“旅程”和“健身”里；表盘复杂功能是否更新。
- 两台设备（或卸载重装）检查 iCloud 同步。

有问题时在 设置 › 导出诊断日志，发给我。

## 7. 提交审核时还需要

- 文案、关键词、审核备注：`AppStore/metadata.md`（`python3 AppStore/check.py` 检查字数）。
- iPhone 截图（6.9 英寸，1320 × 2868）：`AppStore/screenshots/zh-Hans/` 和 `AppStore/screenshots/en/`，按 1–6 的顺序上传。重新生成：`python3 AppStore/tools/frame.py <原始截图目录> <输出目录> zh|en`。
- **Apple Watch 截图**：带手表 App 时必须有。装上 TestFlight 版本后，在手表上同时按侧边按钮和数码表冠截屏（照片会出现在 iPhone 的相册里），挑 2–3 张：地图首页、记录中、今天。
- 一段后台记录的演示视频（30 秒左右，录屏即可），附在审核备注里，说明为什么需要“始终”定位。
- 中国大陆：App 备案通过后，在 App Store Connect › App 信息 › 中国大陆 里填写备案号；在此之前可以先在“价格与销售范围”里不勾选中国大陆。
