# 🛠️ 高德地图SDK手动集成指南

您已下载了SDK文件：`/Users/blue/Downloads/AMap_iOS_Loc_Lib_V2.10.0.zip`

## 📦 第一步：解压和准备SDK

### 1. 解压SDK文件
```bash
cd /Users/blue/Downloads
unzip AMap_iOS_Loc_Lib_V2.10.0.zip
```

### 2. 查看解压内容
解压后应该有以下文件：
- `AMapFoundationKit.framework`
- `AMapLocationKit.framework`

## 🔗 第二步：将Framework添加到Xcode项目

### 1. 打开Xcode项目
```bash
cd /Users/blue/Documents/Github/PathTracker
open RecordPath.xcodeproj
```

### 2. 在Xcode中添加Framework

**2.1 创建Frameworks文件夹**
- 在项目导航器中右键点击 `RecordPath` 
- 选择 "New Group"
- 命名为 "Frameworks"

**2.2 拖拽Framework文件**
- 从Finder中将以下文件拖拽到Xcode的 "Frameworks" 文件夹：
  - `AMapFoundationKit.framework`
  - `AMapLocationKit.framework`
- 在弹出的对话框中：
  - ✅ 勾选 "Copy items if needed"
  - ✅ 勾选 "RecordPath" target
  - 点击 "Finish"

### 3. 配置Build Settings

**3.1 添加Framework Search Paths**
- 选择项目 "RecordPath"
- 选择 Target "RecordPath"
- 找到 "Build Settings" 标签
- 搜索 "Framework Search Paths"
- 添加：`$(PROJECT_DIR)/Frameworks`

**3.2 添加Other Linker Flags**
- 在同一个Build Settings页面
- 搜索 "Other Linker Flags"
- 添加：`-ObjC`

**3.3 配置Embedded Binaries**
- 选择 "General" 标签
- 在 "Frameworks, Libraries, and Embedded Content" 部分
- 确保两个framework的 "Embed" 设置为 "Embed & Sign"

## 💻 第三步：更新代码

### 1. 启用import语句

**在 `RecordPathApp.swift` 中：**
```swift
import SwiftUI
import AMapFoundationKit  // ← 取消注释

@main
struct RecordPathApp: App {
    // ...
}
```

**在 `AMapLocationService.swift` 中：**
```swift
import Foundation
import CoreLocation
import Combine
import AMapLocationKit  // ← 取消注释
```

### 2. 启用配置代码

**在 `RecordPathApp.swift` 的 `configureAMapServices()` 方法中：**
```swift
private func configureAMapServices() {
    // 取消注释这些行：
    AMapServices.shared().apiKey = "b8383a545b59835164229ea06feedf86"
    AMapServices.shared().enableHTTPS = true
    print("✅ 高德地图SDK配置完成")
}
```

### 3. 启用AMapLocationService中的高德地图代码

在 `AMapLocationService.swift` 中找到所有用 `/*` 和 `*/` 注释的代码块，将它们取消注释。

## 🧪 第四步：测试集成

### 1. 编译项目
- 按 `Cmd + B` 编译
- 确保没有编译错误

### 2. 运行应用
- 在真机上运行（模拟器定位功能有限）
- 检查控制台输出：
```
✅ 高德地图SDK配置完成
📍 位置更新：lat:xx.xxxx, lon:xx.xxxx, accuracy:x.xm
```

## ⚠️ 常见问题解决

### 问题1：找不到Framework
**解决方案：**
- 确保Framework文件已正确复制到项目
- 检查Framework Search Paths设置

### 问题2：编译错误 "Undefined symbols"
**解决方案：**
- 确保添加了 `-ObjC` 到Other Linker Flags
- 确保Framework的Embed设置为 "Embed & Sign"

### 问题3：运行时崩溃
**解决方案：**
- 检查API Key是否正确：`b8383a545b59835164229ea06feedf86`
- 确保Info.plist中有位置权限描述

## 🎯 集成完成检查清单

- [ ] SDK文件已解压
- [ ] Framework已添加到Xcode项目
- [ ] Build Settings已正确配置
- [ ] import语句已取消注释
- [ ] API Key配置已启用
- [ ] 项目编译成功
- [ ] 在真机上测试定位功能

## 📞 需要帮助？

如果遇到问题，请检查：
1. Xcode版本兼容性
2. iOS版本要求
3. 证书和配置文件
4. 网络连接

完成后您将获得更准确的中文地址解析和更好的定位体验！🎉