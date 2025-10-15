# PathTracker 路径追踪器 🗺️

[![iOS](https://img.shields.io/badge/iOS-14.0+-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.0+-orange.svg)](https://swift.org/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-2.0+-green.svg)](https://developer.apple.com/xcode/swiftui/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> 一款使用SwiftUI构建的现代GPS旅程追踪应用，用于记录和可视化您的旅行路径

[中文文档](README_cn.md) | [English](README.md)

## 📱 应用概述

PathTracker是一款优雅的iOS应用程序，旨在帮助旅行者记录、可视化和管理他们的旅程。采用SwiftUI构建，利用苹果原生CoreLocation框架，为追踪您的全球冒险提供无缝体验。

## ✨ 核心功能

### 🏠 仪表盘与主页
- **精美概览**：基于渐变的优雅界面，显示旅行统计数据
- **快速统计**：实时显示已访问的地点、国家和城市数量
- **最近旅程**：快速访问您最新的旅行体验
- **世界地图预览**：您全球冒险的可视化展示
- **国家收藏**：您访问过的所有国家的有序视图

### 🗺️ 交互式地图
- **实时追踪**：使用苹果CoreLocation的实时GPS追踪
- **可视化旅程路径**：在地图上显示您的旅行路线
- **位置标记**：代表不同国家的彩色标记
- **地图控制**：在标准、卫星和混合视图之间切换
- **旅程筛选**：按时间段筛选旅程
- **位置详情**：点击标记查看详细的访问信息

### 📍 旅程记录
- **智能追踪**：具有可配置参数的智能路径记录
- **旅程管理**：开始、暂停、恢复和停止追踪
- **照片集成**：为您的旅程拍摄和附加照片
- **位置命名**：自动位置检测，支持手动覆盖
- **实时状态**：带有当前位置显示的实时追踪状态

### 📅 时间线视图
- **按时间顺序显示**：按时间顺序查看所有旅程
- **时间筛选**：按本月、上月或自定义日期范围筛选
- **搜索功能**：搜索您的旅程历史
- **统计摘要**：所选时间段的快速统计
- **旅程详情**：每个旅程的详细视图，包含照片和笔记

### 👤 个人资料与设置
- **用户管理**：支持照片上传的个人资料编辑
- **旅行统计**：全面的旅行分析数据
- **隐私控制**：位置共享的细粒度隐私设置
- **数据导出**：以多种格式导出旅行数据（JSON、CSV、GPX）
- **通知设置**：自定义应用通知
- **帮助与支持**：内置帮助系统和支持选项

### 🔐 身份验证与安全
- **安全登录**：基于邮箱的身份验证系统
- **用户注册**：带验证的简单注册流程
- **数据持久化**：安全的本地数据存储
- **隐私优先**：位置数据保存在您的设备上

## 🏗️ 技术架构

### 核心技术
- **SwiftUI**：现代声明式UI框架
- **CoreLocation**：苹果原生位置服务
- **Combine**：数据流的响应式编程
- **PhotosUI**：原生照片选择和管理
- **MapKit**：高级地图功能

### 项目结构
```
RecordPath/
├── RecordPathApp.swift          # 应用入口点
├── ContentView.swift            # 主应用协调器
├── Managers/
│   ├── AuthenticationManager.swift    # 用户身份验证
│   └── PathTrackingManager.swift     # GPS追踪逻辑
├── Models/
│   ├── PathTrackingModels.swift      # 核心数据模型
│   └── SimpleModels.swift            # 兼容性模型
├── Services/
│   └── CoreLocationService.swift     # 位置服务包装器
└── Views/
    ├── Authentication/           # 登录/注册界面
    ├── Dashboard/               # 主页仪表盘
    ├── Map/                     # 地图界面
    ├── Recording/               # 旅程记录
    ├── Timeline/                # 旅程历史
    ├── Profile/                 # 用户资料与设置
    ├── Country/                 # 国家特定视图
    └── Journey/                 # 旅程详情视图
```

### 关键组件

#### PathTrackingManager（路径追踪管理器）
- 管理GPS追踪生命周期
- 处理位置权限
- 处理和过滤位置数据
- 创建旅程段和路径

#### AuthenticationManager（身份验证管理器）
- 用户会话管理
- 演示用示例数据生成
- 安全数据持久化
- 用户资料管理

#### CoreLocationService（核心位置服务）
- 原生iOS位置服务
- 权限处理
- 实时位置更新
- 电池优化追踪

## 🚀 快速开始

### 前置要求
- Xcode 14.0或更高版本
- iOS 14.0或更高版本
- Apple开发者账户（用于设备测试）

### 安装步骤

1. **克隆仓库**
   ```bash
   git clone https://github.com/yourusername/PathTracker.git
   cd PathTracker
   ```

2. **在Xcode中打开**
   ```bash
   open RecordPath.xcodeproj
   ```

3. **配置签名**
   - 在项目设置中选择您的开发团队
   - 如需要，更新Bundle Identifier

4. **构建并运行**
   - 选择您的目标设备或模拟器
   - 按`Cmd + R`构建并运行

### 配置说明

#### 位置权限
应用需要位置权限才能正常工作。这些在`Info.plist`中配置：
- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`

#### 隐私设置
- 位置数据在本地处理
- 基本功能无需外部API
- 可选：配置高德地图SDK以增强中国地区支持

## 📊 功能深度解析

### 旅程追踪
- **最小距离**：记录点之间5米的最小距离
- **时间间隔**：记录之间最少10秒间隔
- **电池优化**：智能位置采样
- **段管理**：自动路径分段

### 数据模型
- **Journey（旅程）**：包含多个段的完整旅行体验
- **PathSegment（路径段）**：旅程中的单个追踪会话
- **LocationPoint（位置点）**：带时间戳和元数据的GPS坐标
- **Visit（访问）**：带用户注释的重要位置

### 导出功能
- **JSON格式**：包含元数据的完整数据
- **CSV格式**：电子表格兼容格式
- **GPX格式**：用于第三方应用的GPS交换格式
- **照片包含**：可选的照片与数据一起导出

## 🛠️ 开发指南

### 从源码构建
```bash
# 克隆仓库
git clone https://github.com/yourusername/PathTracker.git

# 导航到项目目录
cd PathTracker

# 在Xcode中打开
open RecordPath.xcodeproj
```

### 测试
- 单元测试位于`RecordPathTests/`
- UI测试位于`RecordPathUITests/`
- 使用`Cmd + U`运行测试

### 贡献代码
1. Fork仓库
2. 创建功能分支
3. 进行更改
4. 如适用，添加测试
5. 提交Pull Request

## 📱 应用截图

| 仪表盘 | 地图视图 | 记录界面 | 时间线 |
|--------|----------|----------|--------|
| ![仪表盘](screenshots/dashboard.png) | ![地图](screenshots/map.png) | ![记录](screenshots/recording.png) | ![时间线](screenshots/timeline.png) |

## 🔧 自定义配置

### 追踪参数
在`PathTrackingManager.swift`中修改追踪敏感度：
```swift
private let minimumDistance: Double = 5.0 // 米
private let minimumTimeInterval: TimeInterval = 10.0 // 秒
```

### UI主题
在各个视图文件中自定义颜色和样式，或创建主题系统。

### 位置服务
通过修改服务实现在Apple CoreLocation和高德地图SDK之间切换。

## 📄 许可证

本项目采用MIT许可证 - 详见[LICENSE](LICENSE)文件。

## 🤝 支持

- **问题反馈**：[GitHub Issues](https://github.com/yourusername/PathTracker/issues)
- **讨论**：[GitHub Discussions](https://github.com/yourusername/PathTracker/discussions)
- **邮箱**：support@pathtracker.app

## 🗺️ 开发路线图

- [ ] 云同步功能
- [ ] 社交分享功能
- [ ] 高级分析
- [ ] Apple Watch配套应用
- [ ] 离线地图支持
- [ ] 与朋友分享旅程
- [ ] AI驱动的旅行洞察

## 🙏 致谢

- 感谢Apple提供CoreLocation和MapKit框架
- 感谢SwiftUI社区的灵感和最佳实践
- 感谢开源贡献者和测试人员

---

**为全世界的旅行者用❤️制作**

*今天就开始追踪您的冒险之旅！* 🌍✈️

## 🌟 主要特色功能详解

### 智能位置追踪
- **自适应精度**：根据移动速度自动调整GPS精度
- **电池优化**：智能降频以延长电池寿命
- **后台追踪**：支持后台持续位置记录
- **网络优化**：在网络条件差时优雅降级

### 数据可视化
- **热力图**：显示您最常访问的区域
- **路径动画**：动态播放您的旅行路线
- **统计图表**：美观的图表展示旅行数据
- **地理标签**：智能识别和标记重要地点

### 用户体验
- **直观导航**：简洁明了的标签式导航
- **手势支持**：丰富的手势操作支持
- **无障碍**：完整的VoiceOver和动态字体支持
- **国际化**：支持多语言界面

### 数据安全
- **本地存储**：所有数据存储在设备本地
- **加密保护**：敏感数据采用加密存储
- **隐私控制**：用户完全控制数据共享
- **GDPR合规**：符合欧盟数据保护法规

这款应用完美结合了功能性和美观性，为旅行爱好者提供了一个全面的旅程记录解决方案。无论您是偶尔旅行还是经常出差，PathTracker都能帮您完整记录和回顾每一次珍贵的旅程。
