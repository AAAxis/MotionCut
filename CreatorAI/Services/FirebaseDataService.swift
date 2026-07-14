import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

/// Firestore + Storage persistence. Firebase Auth owns identity.
final class FirebaseDataService {
    static let shared = FirebaseDataService()

    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    private init() {}

    private var platform: String {
        #if os(macOS)
        return "macos"
        #else
        return "ios"
        #endif
    }

    func upsertUser(userId: String, email: String?, displayName: String? = nil, avatarUrl: String? = nil) async {
        var data: [String: Any] = [
            "uid": userId,
            "platform": platform,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let email, !email.isEmpty { data["email"] = email }
        if let displayName, !displayName.isEmpty { data["displayName"] = displayName }
        if let avatarUrl, !avatarUrl.isEmpty { data["avatarUrl"] = avatarUrl }

        do {
            try await db.collection("users").document(userId).setData(data, merge: true)
            if let email, !email.isEmpty {
                try await db.collection("emails").document(email.lowercased()).setData([
                    "email": email.lowercased(),
                    "userId": userId,
                    "platform": platform,
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
            }
            await logUserAction(userId: userId, action: "user_upserted", data: ["email": email ?? ""])
            print("[FirebaseData] Upserted user \(userId)")
        } catch {
            print("[FirebaseData] Upsert user failed: \(error)")
        }
    }

    func saveFCMToken(userId: String, token: String) async {
        do {
            try await db.collection("users").document(userId).setData([
                "fcmToken": token,
                "platform": platform,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            await logUserAction(userId: userId, action: "fcm_token_saved", data: [:])
            print("[FirebaseData] Saved FCM token for user \(userId)")
        } catch {
            print("[FirebaseData] Save FCM token failed: \(error)")
        }
    }

    func logUserAction(userId: String, action: String, data: [String: Any]) async {
        var payload = data
        payload["action"] = action
        payload["platform"] = platform
        payload["createdAt"] = FieldValue.serverTimestamp()

        do {
            try await db.collection("users").document(userId)
                .collection("actions")
                .addDocument(data: payload)
        } catch {
            print("[FirebaseData] Log action failed: \(error)")
        }
    }

    @available(*, unavailable, message: "User-generated library videos are local-only. Do not upload them to Firebase.")
    func uploadVideo(fileURL: URL, generationId: String, userId explicitUserId: String? = nil) async -> String? {
        guard let userId = explicitUserId ?? Auth.auth().currentUser?.uid else {
            print("[FirebaseData] Upload skipped: no Firebase user")
            return nil
        }

        let storagePath = "users/\(userId)/videos/\(generationId).mp4"
        let ref = storage.reference(withPath: storagePath)
        do {
            let metadata = StorageMetadata()
            metadata.contentType = "video/mp4"
            _ = try await putFileAsync(ref: ref, fileURL: fileURL, metadata: metadata)
            let downloadURL = try await ref.downloadURL()
            let urlString = downloadURL.absoluteString

            try await db.collection("videos").document(generationId).setData([
                "id": generationId,
                "userId": userId,
                "storagePath": storagePath,
                "downloadUrl": urlString,
                "platform": platform,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            await logUserAction(userId: userId, action: "video_uploaded", data: [
                "generationId": generationId,
                "storagePath": storagePath
            ])
            print("[FirebaseData] Uploaded video: \(urlString)")
            return urlString
        } catch {
            print("[FirebaseData] Upload failed: \(error)")
            return nil
        }
    }

    @available(*, unavailable, message: "User-generated library videos are local-only. Do not delete remote Firebase video copies.")
    func deleteVideo(generationId: String, userId explicitUserId: String? = nil) async {
        guard let userId = explicitUserId ?? Auth.auth().currentUser?.uid else { return }
        let storagePath = "users/\(userId)/videos/\(generationId).mp4"
        do {
            try await storage.reference(withPath: storagePath).delete()
            try await db.collection("videos").document(generationId).delete()
            await logUserAction(userId: userId, action: "video_deleted", data: ["generationId": generationId])
        } catch {
            print("[FirebaseData] Delete video failed: \(error)")
        }
    }

    @available(*, unavailable, message: "User-generated library metadata is local-only. Do not sync generations to Firebase.")
    func upsertGeneration(_ gen: Generation, remoteVideoUrl: String? = nil) async {
        guard let userId = gen.userId ?? Auth.auth().currentUser?.uid else {
            print("[FirebaseData] Generation sync skipped: no Firebase user")
            return
        }

        var data: [String: Any] = [
            "id": gen.id,
            "videoName": gen.videoName,
            "status": gen.status.rawValue,
            "createdAtString": ISO8601DateFormatter().string(from: gen.createdAt),
            "createdAt": Timestamp(date: gen.createdAt),
            "userId": userId,
            "platform": platform,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let videoUri = gen.videoUri { data["videoUri"] = videoUri }
        if let resultVideoUrl = remoteVideoUrl ?? gen.resultVideoUrl { data["resultVideoUrl"] = resultVideoUrl }
        if let musicId = gen.musicId { data["musicId"] = musicId }
        if let musicName = gen.musicName { data["musicName"] = musicName }
        if let musicFile = gen.musicFile { data["musicFile"] = musicFile }
        if let musicVolume = gen.musicVolume { data["musicVolume"] = musicVolume }
        if let takesJson = gen.takesJson { data["takesJson"] = takesJson }

        do {
            try await db.collection("users").document(userId)
                .collection("generations").document(gen.id)
                .setData(data, merge: true)
            try await db.collection("videos").document(gen.id).setData(data, merge: true)
            await logUserAction(userId: userId, action: "generation_upserted", data: ["generationId": gen.id])
            print("[FirebaseData] Upserted generation \(gen.id)")
        } catch {
            print("[FirebaseData] Upsert generation failed: \(error)")
        }
    }

    @available(*, unavailable, message: "User-generated library metadata is local-only. Read GenerationService local storage instead.")
    func fetchGenerations(userId: String) async -> [Generation] {
        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("generations")
                .order(by: "createdAt", descending: true)
                .getDocuments()
            return snapshot.documents.compactMap { document in
                generation(from: document.data())
            }
        } catch {
            print("[FirebaseData] Fetch generations failed: \(error)")
            return []
        }
    }

    @available(*, unavailable, message: "User-generated library metadata is local-only. Delete local generation storage instead.")
    func deleteGeneration(id: String, userId explicitUserId: String? = nil) async {
        guard let userId = explicitUserId ?? Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(userId).collection("generations").document(id).delete()
            try? await db.collection("videos").document(id).delete()
            await logUserAction(userId: userId, action: "generation_deleted", data: ["generationId": id])
        } catch {
            print("[FirebaseData] Delete generation failed: \(error)")
        }
    }

    private func putFileAsync(ref: StorageReference, fileURL: URL, metadata: StorageMetadata) async throws -> StorageMetadata {
        try await withCheckedThrowingContinuation { continuation in
            ref.putFile(from: fileURL, metadata: metadata) { metadata, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let metadata {
                    continuation.resume(returning: metadata)
                } else {
                    continuation.resume(throwing: NSError(domain: "FirebaseDataService", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Firebase Storage upload returned no metadata"
                    ]))
                }
            }
        }
    }

    private func generation(from data: [String: Any]) -> Generation? {
        guard let id = data["id"] as? String else { return nil }
        let createdAt: Date
        if let timestamp = data["createdAt"] as? Timestamp {
            createdAt = timestamp.dateValue()
        } else if let raw = data["createdAtString"] as? String,
                  let date = ISO8601DateFormatter().date(from: raw) {
            createdAt = date
        } else {
            createdAt = Date()
        }

        return Generation(
            id: id,
            videoName: data["videoName"] as? String ?? "Video",
            videoUri: data["videoUri"] as? String,
            resultVideoUrl: data["resultVideoUrl"] as? String,
            status: GenerationStatus(rawValue: data["status"] as? String ?? "") ?? .saved,
            createdAt: createdAt,
            userId: data["userId"] as? String,
            musicId: data["musicId"] as? String,
            musicName: data["musicName"] as? String,
            musicFile: data["musicFile"] as? String,
            musicVolume: data["musicVolume"] as? Double,
            takesJson: data["takesJson"] as? String
        )
    }
}
