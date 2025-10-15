//
//  FirebaseService.swift
//  RecordPath
//
//  Created by Assistant on 2024/10/15.
//

import Foundation
import Firebase
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

class FirebaseService: ObservableObject {
    static let shared = FirebaseService()
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    
    private init() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.currentUser = user
                self?.isAuthenticated = user != nil
            }
        }
    }
    
    // MARK: - Authentication
    
    func signInAnonymously() async throws {
        let result = try await Auth.auth().signInAnonymously()
        print("Anonymous user signed in: \(result.user.uid)")
    }
    
    func signUp(email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        print("User signed up: \(result.user.uid)")
    }
    
    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        print("User signed in: \(result.user.uid)")
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
        print("User signed out")
    }
    
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "没有当前用户"])
        }
        
        try await deleteUserData(userId: user.uid)
        try await user.delete()
        print("Account deleted")
    }
    
    // MARK: - Firestore Operations
    
    func savePath(_ path: PathData) async throws {
        guard let userId = currentUser?.uid else {
            throw NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "用户未登录"])
        }
        
        let pathDict: [String: Any] = [
            "id": path.id.uuidString,
            "name": path.name,
            "startTime": Timestamp(date: path.startTime),
            "endTime": path.endTime.map { Timestamp(date: $0) } as Any,
            "coordinates": path.coordinates.map { coord in
                [
                    "latitude": coord.latitude,
                    "longitude": coord.longitude,
                    "timestamp": Timestamp(date: coord.timestamp),
                    "altitude": coord.altitude,
                    "speed": coord.speed,
                    "accuracy": coord.accuracy
                ]
            },
            "totalDistance": path.totalDistance,
            "isRecording": path.isRecording,
            "createdAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ]
        
        try await db.collection("users").document(userId).collection("paths").document(path.id.uuidString).setData(pathDict)
        print("Path data saved: \(path.name)")
    }
    
    func fetchUserPaths() async throws -> [PathData] {
        guard let userId = currentUser?.uid else {
            throw NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "用户未登录"])
        }
        
        let snapshot = try await db.collection("users").document(userId).collection("paths")
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { document in
            let data = document.data()
            
            guard let idString = data["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let name = data["name"] as? String,
                  let startTimeTimestamp = data["startTime"] as? Timestamp,
                  let coordinatesData = data["coordinates"] as? [[String: Any]],
                  let totalDistance = data["totalDistance"] as? Double,
                  let isRecording = data["isRecording"] as? Bool else {
                return nil
            }
            
            let coordinates = coordinatesData.compactMap { coordData -> LocationCoordinate? in
                guard let latitude = coordData["latitude"] as? Double,
                      let longitude = coordData["longitude"] as? Double,
                      let timestamp = coordData["timestamp"] as? Timestamp,
                      let altitude = coordData["altitude"] as? Double,
                      let speed = coordData["speed"] as? Double,
                      let accuracy = coordData["accuracy"] as? Double else {
                    return nil
                }
                
                return LocationCoordinate(
                    latitude: latitude,
                    longitude: longitude,
                    timestamp: timestamp.dateValue(),
                    altitude: altitude,
                    speed: speed,
                    accuracy: accuracy
                )
            }
            
            let endTime = (data["endTime"] as? Timestamp)?.dateValue()
            
            return PathData(
                id: id,
                name: name,
                startTime: startTimeTimestamp.dateValue(),
                endTime: endTime,
                coordinates: coordinates,
                totalDistance: totalDistance,
                isRecording: isRecording
            )
        }
    }
    
    func deletePath(pathId: UUID) async throws {
        guard let userId = currentUser?.uid else {
            throw NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "用户未登录"])
        }
        
        try await db.collection("users").document(userId).collection("paths").document(pathId.uuidString).delete()
        print("Path deleted: \(pathId)")
    }
    
    private func deleteUserData(userId: String) async throws {
        let pathsSnapshot = try await db.collection("users").document(userId).collection("paths").getDocuments()
        
        let batch = db.batch()
        for document in pathsSnapshot.documents {
            batch.deleteDocument(document.reference)
        }
        
        batch.deleteDocument(db.collection("users").document(userId))
        
        try await batch.commit()
        print("User data deleted: \(userId)")
    }
    
    // MARK: - Storage Operations
    
    func uploadPathFile(pathId: UUID, data: Data, fileName: String) async throws -> String {
        guard let userId = currentUser?.uid else {
            throw NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "用户未登录"])
        }
        
        let storageRef = storage.reference().child("users/\(userId)/paths/\(pathId.uuidString)/\(fileName)")
        
        let metadata = StorageMetadata()
        metadata.contentType = "application/json"
        
        let _ = try await storageRef.putDataAsync(data, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        
        return downloadURL.absoluteString
    }
    
    func downloadPathFile(pathId: UUID, fileName: String) async throws -> Data {
        guard let userId = currentUser?.uid else {
            throw NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "用户未登录"])
        }
        
        let storageRef = storage.reference().child("users/\(userId)/paths/\(pathId.uuidString)/\(fileName)")
        let data = try await storageRef.data(maxSize: 10 * 1024 * 1024)
        
        return data
    }
}

// MARK: - Error Handling Extension
extension FirebaseService {
    func handleAuthError(_ error: Error) -> String {
        guard let authError = error as NSError? else {
            return "未知错误"
        }
        
        switch AuthErrorCode(rawValue: authError.code) {
        case .emailAlreadyInUse:
            return "该邮箱已被使用"
        case .weakPassword:
            return "密码强度不够"
        case .invalidEmail:
            return "邮箱格式无效"
        case .userNotFound:
            return "用户不存在"
        case .wrongPassword:
            return "密码错误"
        case .networkError:
            return "网络连接错误"
        default:
            return authError.localizedDescription
        }
    }
}