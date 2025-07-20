# 高德地图SDK集成指南

## 🚀 快速开始

您的高德地图API Key: `b8383a545b59835164229ea06feedf86`

### 1. 安装高德地图SDK

在项目根目录运行以下命令：

```bash
cd /Users/blue/Documents/Github/PathTracker
pod install
```

如果没有安装CocoaPods，请先安装：
```bash
sudo gem install cocoapods
```

### 2. 打开工作空间

安装完成后，请使用以下命令打开项目：
```bash
open RecordPath.xcworkspace
```

⚠️ **重要：从现在开始请使用 `.xcworkspace` 文件而不是 `.xcodeproj` 文件**

### 3. 启用高德地图功能

安装SDK后，请按以下步骤启用高德地图功能：

#### 3.1 更新 RecordPathApp.swift

在 `RecordPathApp.swift` 文件顶部添加：
```swift
import AMapFoundationKit
```

然后在 `configureAMapServices()` 方法中取消注释：
```swift
private func configureAMapServices() {
    AMapServices.shared().apiKey = "b8383a545b59835164229ea06feedf86"
    AMapServices.shared().enableHTTPS = true
    print("✅ 高德地图SDK配置完成")
}
```

#### 3.2 更新 AMapLocationService.swift

在 `AMapLocationService.swift` 文件顶部添加：
```swift
import AMapLocationKit
```

然后取消注释所有标记为 `// TODO: 安装高德地图SDK后启用` 的代码段。

### 4. 验证集成

运行应用后，您应该在控制台看到：
```
✅ 高德地图SDK配置完成
📍 位置更新：lat:xx.xxxx, lon:xx.xxxx, accuracy:x.xm
```

## 🔧 高级配置

### 地图功能（可选）

如果需要显示地图，请在 Podfile 中添加：
```ruby
pod 'AMap3DMap'
```

### 搜索功能（可选）

如果需要地点搜索功能，请在 Podfile 中添加：
```ruby
pod 'AMapSearch'
```

## ⚠️ 常见问题

### 1. 编译错误 "Module 'AMapLocationKit' not found"
- 确保已运行 `pod install`
- 确保使用 `.xcworkspace` 而不是 `.xcodeproj`

### 2. 定位不准确
- 检查权限是否正确授予
- 确保在真机上测试（模拟器定位功能有限）

### 3. API Key无效
- 确认 API Key: `b8383a545b59835164229ea06feedf86`
- 检查高德开放平台控制台中的配置

## 📱 当前功能状态

✅ **已完成的功能：**
- 位置权限管理
- GPS轨迹记录
- 智能旅程命名（时间+地点）
- 照片添加功能
- 暂停/恢复/停止功能
- 中文界面

🔄 **高德地图增强功能：**
- 更准确的中文地址解析
- 更好的国内定位精度
- 丰富的POI信息

## 🎯 下一步

1. 运行 `pod install`
2. 打开 `RecordPath.xcworkspace`
3. 取消注释高德地图相关代码
4. 编译运行
5. 在真机上测试定位功能

## 📞 技术支持

如果遇到问题，请检查：
1. 网络连接
2. 位置权限
3. API Key配置
4. SDK版本兼容性

祝您使用愉快！🎉