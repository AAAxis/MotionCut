import Foundation
import Supabase

/// Supabase client for database and storage.
/// Auth is handled by Firebase — Supabase stores data only (same as Android).
final class SupabaseService {
    static let shared = SupabaseService()

    private static let supabaseURL = "https://xxcllmzflnwzqiaslyou.supabase.co"
    private static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh4Y2xsbXpmbG53enFpYXNseW91Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQyMDM1NDcsImV4cCI6MjA4OTc3OTU0N30.VbAv5UEC6n1ZyXFvjLshVOp9ZKN5_Rq8fEznoEqFsKY"

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: Self.supabaseURL)!,
            supabaseKey: Self.supabaseAnonKey
        )
    }

    // MARK: - App Users (Firebase UID + FCM token)

    private struct AppUserRow: Encodable {
        let id: String
        let email: String?
        let display_name: String?
        let avatar_url: String?
        let platform: String
    }

    func upsertUser(userId: String, email: String?, displayName: String? = nil, avatarUrl: String? = nil) async {
        let row = AppUserRow(
            id: userId,
            email: email,
            display_name: displayName,
            avatar_url: avatarUrl,
            platform: "ios"
        )
        do {
            try await client.from("app_users").upsert(row).execute()
            print("[Supabase] Upserted user \(userId) (\(email ?? "no email"))")
        } catch {
            print("[Supabase] Upsert user failed: \(error)")
        }
    }

    func saveFCMToken(userId: String, token: String) async {
        do {
            try await client.from("app_users")
                .update(["fcm_token": token, "platform": "ios"])
                .eq("id", value: userId)
                .execute()
            print("[Supabase] Saved FCM token for user \(userId)")
        } catch {
            print("[Supabase] Save FCM token failed: \(error)")
        }
    }

    // MARK: - Storage

    func uploadVideo(fileURL: URL, generationId: String) async -> String? {
        let storagePath = "renders/\(generationId).mp4"
        do {
            let fileData = try Data(contentsOf: fileURL)
            try await client.storage.from("videos").upload(
                storagePath,
                data: fileData,
                options: .init(contentType: "video/mp4", upsert: true)
            )
            let publicURL = try client.storage.from("videos").getPublicURL(path: storagePath)
            print("[Supabase] Uploaded video: \(publicURL.absoluteString)")
            return publicURL.absoluteString
        } catch {
            print("[Supabase] Upload failed: \(error)")
            return nil
        }
    }

    func deleteVideo(generationId: String) async {
        let storagePath = "renders/\(generationId).mp4"
        do {
            try await client.storage.from("videos").remove(paths: [storagePath])
        } catch {
            print("[Supabase] Delete failed: \(error)")
        }
    }

    // MARK: - Database (generations table)

    struct GenerationRow: Codable {
        let id: String
        let video_name: String
        let video_storage_path: String?
        let status: String
        let created_at: String
        let user_id: String?
        let music_id: String?
        let music_name: String?
        let music_volume: Double?
        let takes_json: String?
        let music_file: String?
    }

    private struct UpsertGenerationRow: Encodable {
        let id: String
        let video_name: String
        let video_storage_path: String?
        let status: String
        let created_at: String
        let user_id: String?
        let music_id: String?
        let music_name: String?
        let music_volume: Double?
        let takes_json: String?
    }

    func upsertGeneration(_ gen: Generation, remoteVideoUrl: String? = nil) async {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let row = UpsertGenerationRow(
            id: gen.id,
            video_name: gen.videoName,
            video_storage_path: remoteVideoUrl,
            status: gen.status.rawValue,
            created_at: iso.string(from: gen.createdAt),
            user_id: gen.userId,
            music_id: gen.musicId,
            music_name: gen.musicName,
            music_volume: gen.musicVolume,
            takes_json: gen.takesJson
        )
        do {
            try await client.from("generations").upsert(row).execute()
            print("[Supabase] Upserted generation \(gen.id)")
        } catch {
            if isTableNotFoundError(error) {
                print("[Supabase] Generations table not in schema (PGRST205); skipping sync.")
            } else {
                print("[Supabase] Upsert failed: \(error)")
            }
        }
    }

    func fetchGenerations(userId: String) async -> [Generation] {
        do {
            let rows: [GenerationRow] = try await client.from("generations")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .execute()
                .value
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return rows.map { row in
                Generation(
                    id: row.id,
                    videoName: row.video_name,
                    videoUri: nil,
                    resultVideoUrl: row.video_storage_path,
                    status: GenerationStatus(rawValue: row.status) ?? .saved,
                    createdAt: iso.date(from: row.created_at) ?? Date(),
                    userId: row.user_id,
                    musicId: row.music_id,
                    musicName: row.music_name,
                    musicFile: row.music_file,
                    musicVolume: row.music_volume,
                    takesJson: row.takes_json
                )
            }
        } catch {
            if isTableNotFoundError(error) {
                print("[Supabase] Generations table not in schema (PGRST205); using local data only.")
            } else {
                print("[Supabase] Fetch failed: \(error)")
            }
            return []
        }
    }

    func deleteGeneration(id: String) async {
        do {
            try await client.from("generations").delete().eq("id", value: id).execute()
        } catch {
            if !isTableNotFoundError(error) {
                print("[Supabase] Delete row failed: \(error)")
            }
        }
    }

    private func isTableNotFoundError(_ error: Error) -> Bool {
        let msg = "\(error)"
        return msg.contains("Could not find the table") || msg.contains("PGRST205")
    }
}
