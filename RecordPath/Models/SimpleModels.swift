import Foundation
import CoreLocation
import SwiftUI

// Legacy data models (kept for compatibility with existing views)

struct Location: Identifiable {
    let id = UUID()
    var name: String
    var address: String?
    var city: String?
    var country: String?
    var latitude: Double
    var longitude: Double
    var category: String?
    
    var coordinate: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    var clLocation: CLLocation {
        return CLLocation(latitude: latitude, longitude: longitude)
    }
    
    var displayName: String {
        return name
    }
    
    var fullAddress: String {
        var components: [String] = []
        
        if let address = address, !address.isEmpty {
            components.append(address)
        }
        
        if let city = city, !city.isEmpty {
            components.append(city)
        }
        
        if let country = country, !country.isEmpty {
            components.append(country)
        }
        
        return components.joined(separator: ", ")
    }
}

struct Visit: Identifiable {
    let id = UUID()
    var visitDate: Date
    var comment: String?
    var rating: Int
    var weather: String?
    var createdAt: Date
    var location: Location
    var photos: [Photo] = []
    
    var displayComment: String {
        return comment ?? "No comment"
    }
    
    var hasComment: Bool {
        return comment != nil && !comment!.isEmpty
    }
    
    var hasPhotos: Bool {
        return photos.count > 0
    }
    
    var locationName: String {
        return location.displayName
    }
    
    var locationAddress: String {
        return location.fullAddress
    }
    
    var daysSinceVisit: Int {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.day], from: visitDate, to: now)
        return components.day ?? 0
    }
    
    var isToday: Bool {
        return Calendar.current.isDateInToday(visitDate)
    }
    
    var isYesterday: Bool {
        return Calendar.current.isDateInYesterday(visitDate)
    }
    
    var formattedVisitDate: String {
        let formatter = DateFormatter()
        
        if isToday {
            return "Today"
        } else if isYesterday {
            return "Yesterday"
        } else if daysSinceVisit < 7 {
            formatter.dateFormat = "EEEE"
            return formatter.string(from: visitDate)
        } else {
            formatter.dateStyle = .medium
            return formatter.string(from: visitDate)
        }
    }
    
    var ratingStars: String {
        return String(repeating: "⭐", count: rating)
    }
}

struct Photo: Identifiable {
    let id = UUID()
    var imageData: Data
    var caption: String?
    var takenAt: Date
    var isProfilePicture: Bool = false
    
    var image: UIImage? {
        return UIImage(data: imageData)
    }
    
    var displayCaption: String {
        return caption ?? "No caption"
    }
    
    var hasCaption: Bool {
        return caption != nil && !caption!.isEmpty
    }
    
    var formattedTakenAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: takenAt)
    }
}