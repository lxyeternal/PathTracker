# PathTracker 🗺️

[![iOS](https://img.shields.io/badge/iOS-14.0+-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.0+-orange.svg)](https://swift.org/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-2.0+-green.svg)](https://developer.apple.com/xcode/swiftui/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> A modern GPS journey tracking app built with SwiftUI for recording and visualizing your travel paths

[中文文档](README_cn.md) | [English](README.md)

## 📱 Overview

PathTracker is an elegant iOS application designed to help travelers record, visualize, and manage their journeys. Built with SwiftUI and leveraging Apple's native CoreLocation framework, it provides a seamless experience for tracking your adventures around the world.

## ✨ Key Features

### 🏠 Dashboard & Home
- **Beautiful Overview**: Elegant gradient-based interface with travel statistics
- **Quick Stats**: Real-time display of visited locations, countries, and cities
- **Recent Journeys**: Quick access to your latest travel experiences
- **World Map Preview**: Visual representation of your global adventures
- **Countries Collection**: Organized view of all countries you've visited

### 🗺️ Interactive Map
- **Real-time Tracking**: Live GPS tracking with Apple's CoreLocation
- **Visual Journey Paths**: See your travel routes displayed on the map
- **Location Pins**: Color-coded pins representing different countries
- **Map Controls**: Switch between standard, satellite, and hybrid views
- **Journey Filtering**: Filter journeys by time periods
- **Location Details**: Tap pins to view detailed visit information

### 📍 Journey Recording
- **Smart Tracking**: Intelligent path recording with configurable parameters
- **Journey Management**: Start, pause, resume, and stop tracking
- **Photo Integration**: Capture and attach photos to your journeys
- **Location Naming**: Automatic location detection with manual override
- **Real-time Status**: Live tracking status with current location display

### 📅 Timeline View
- **Chronological Display**: View all your journeys in chronological order
- **Time Filtering**: Filter by this month, last month, or custom date ranges
- **Search Functionality**: Search through your journey history
- **Statistics Summary**: Quick stats for the selected time period
- **Journey Details**: Detailed view of each journey with photos and notes

### 👤 Profile & Settings
- **User Management**: Profile editing with photo upload
- **Travel Statistics**: Comprehensive travel analytics
- **Privacy Controls**: Granular privacy settings for location sharing
- **Data Export**: Export your travel data in multiple formats (JSON, CSV, GPX)
- **Notification Settings**: Customize app notifications
- **Help & Support**: Built-in help system and support options

### 🔐 Authentication & Security
- **Secure Login**: Email-based authentication system
- **User Registration**: Simple signup process with validation
- **Data Persistence**: Secure local data storage
- **Privacy First**: Location data stays on your device

## 🏗️ Technical Architecture

### Core Technologies
- **SwiftUI**: Modern declarative UI framework
- **CoreLocation**: Apple's native location services
- **Combine**: Reactive programming for data flow
- **PhotosUI**: Native photo selection and management
- **MapKit**: Advanced mapping capabilities

### Project Structure
```
RecordPath/
├── RecordPathApp.swift          # App entry point
├── ContentView.swift            # Main app coordinator
├── Managers/
│   ├── AuthenticationManager.swift    # User authentication
│   └── PathTrackingManager.swift     # GPS tracking logic
├── Models/
│   ├── PathTrackingModels.swift      # Core data models
│   └── SimpleModels.swift            # Legacy compatibility models
├── Services/
│   └── CoreLocationService.swift     # Location service wrapper
└── Views/
    ├── Authentication/           # Login/signup screens
    ├── Dashboard/               # Home dashboard
    ├── Map/                     # Map interface
    ├── Recording/               # Journey recording
    ├── Timeline/                # Journey history
    ├── Profile/                 # User profile & settings
    ├── Country/                 # Country-specific views
    └── Journey/                 # Journey detail views
```

### Key Components

#### PathTrackingManager
- Manages GPS tracking lifecycle
- Handles location permissions
- Processes and filters location data
- Creates journey segments and paths

#### AuthenticationManager
- User session management
- Sample data generation for demo
- Secure data persistence
- User profile management

#### CoreLocationService
- Native iOS location services
- Permission handling
- Real-time location updates
- Battery-optimized tracking

## 🚀 Getting Started

### Prerequisites
- Xcode 14.0 or later
- iOS 14.0 or later
- Apple Developer account (for device testing)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/PathTracker.git
   cd PathTracker
   ```

2. **Open in Xcode**
   ```bash
   open RecordPath.xcodeproj
   ```

3. **Configure signing**
   - Select your development team in project settings
   - Update bundle identifier if needed

4. **Build and run**
   - Select your target device or simulator
   - Press `Cmd + R` to build and run

### Configuration

#### Location Permissions
The app requires location permissions to function. These are configured in `Info.plist`:
- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`

#### Privacy Settings
- Location data is processed locally
- No external APIs required for basic functionality
- Optional: Configure AMap SDK for enhanced China support

## 📊 Features Deep Dive

### Journey Tracking
- **Minimum Distance**: 5 meters between recorded points
- **Time Interval**: 10 seconds minimum between recordings
- **Battery Optimization**: Intelligent location sampling
- **Segment Management**: Automatic path segmentation

### Data Models
- **Journey**: Complete travel experience with multiple segments
- **PathSegment**: Individual tracking sessions within a journey
- **LocationPoint**: GPS coordinates with timestamp and metadata
- **Visit**: Significant locations with user annotations

### Export Capabilities
- **JSON Format**: Complete data with metadata
- **CSV Format**: Spreadsheet-compatible format
- **GPX Format**: GPS exchange format for third-party apps
- **Photo Inclusion**: Optional photo export with data

## 🛠️ Development

### Building from Source
```bash
# Clone the repository
git clone https://github.com/yourusername/PathTracker.git

# Navigate to project directory
cd PathTracker

# Open in Xcode
open RecordPath.xcodeproj
```

### Testing
- Unit tests available in `RecordPathTests/`
- UI tests in `RecordPathUITests/`
- Run tests with `Cmd + U`

### Contributing
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📱 Screenshots

| Dashboard | Map View | Recording | Timeline |
|-----------|----------|-----------|----------|
| ![Dashboard](screenshots/dashboard.png) | ![Map](screenshots/map.png) | ![Recording](screenshots/recording.png) | ![Timeline](screenshots/timeline.png) |

## 🔧 Customization

### Tracking Parameters
Modify tracking sensitivity in `PathTrackingManager.swift`:
```swift
private let minimumDistance: Double = 5.0 // meters
private let minimumTimeInterval: TimeInterval = 10.0 // seconds
```

### UI Themes
Customize colors and styling in individual view files or create a theme system.

### Location Services
Switch between Apple CoreLocation and AMap SDK by modifying service implementations.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/PathTracker/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/PathTracker/discussions)
- **Email**: support@pathtracker.app

## 🗺️ Roadmap

- [ ] Cloud sync capabilities
- [ ] Social sharing features
- [ ] Advanced analytics
- [ ] Apple Watch companion app
- [ ] Offline map support
- [ ] Journey sharing with friends
- [ ] AI-powered travel insights

## 🙏 Acknowledgments

- Apple for CoreLocation and MapKit frameworks
- SwiftUI community for inspiration and best practices
- Open source contributors and testers

---

**Made with ❤️ for travelers around the world**

*Start tracking your adventures today!* 🌍✈️