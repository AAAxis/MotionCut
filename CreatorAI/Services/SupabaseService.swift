import Foundation
import Supabase

final class SupabaseService {
    static let shared = SupabaseService()

    /// OAuth redirect URL. Add to Supabase Dashboard → Authentication → URL Configuration → Redirect URLs.
    static let authRedirectURL = URL(string: "creatorai://auth/callback")!

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: "https://uhpuqiptxcjluwsetoev.supabase.co")!,
            supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVocHVxaXB0eGNqbHV3c2V0b2V2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTcwOTE4OTYsImV4cCI6MjA3MjY2Nzg5Nn0.D_t-dyA4Z192kAU97Oi79At_IDT_5putusXrR0bQ6z8"
        )
    }

    // MARK: - Auth

    /// Sign in with Apple id_token from native Sign in with Apple.
    func signInWithApple(idToken: String, nonce: String) async throws -> Session {
        let credentials = OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        return try await client.auth.signInWithIdToken(credentials: credentials)
    }

    /// Sign in with Google via OAuth (opens in-app browser). Add `creatorai://auth/callback` to Supabase redirect URLs.
    func signInWithGoogle() async throws -> Session {
        try await client.auth.signInWithOAuth(
            provider: .google,
            redirectTo: Self.authRedirectURL
        )
    }

    /// Sign out from Supabase Auth.
    func signOut() async throws {
        try await client.auth.signOut()
    }

    // MARK: - Storage

    /// Upload video file to Supabase Storage. Returns the public URL.
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

    /// Delete video from Supabase Storage.
    func deleteVideo(generationId: String) async {
        let storagePath = "renders/\(generationId).mp4"
        do {
            try await client.storage.from("videos").remove(paths: [storagePath])
        } catch {
            print("[Supabase] Delete failed: \(error)")
        }
    }

    // MARK: - Database

    /// Row shape for the generations table (must match DB columns; omit any column not in schema).
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
        /// Present in fetch response only if your DB has this column; omitted from upsert to avoid PGRST204.
        let music_file: String?
    }

    /// Payload for upsert: only columns that exist in your Supabase generations table.
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

    /// True when PostgREST reports the table is not in the schema cache (e.g. table not created or not exposed).
    private func isTableNotFoundError(_ error: Error) -> Bool {
        let msg = "\(error)"
        return msg.contains("Could not find the table") || msg.contains("PGRST205")
    }
}
