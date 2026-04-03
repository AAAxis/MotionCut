import Foundation

struct CatalogCreator {
    let displayName: String
    let avatarUrl: String?
}

struct CatalogItem: Identifiable {
    let id: String
    let prompt: String
    let mode: String
    let model: String
    let videoUrl: String
    let thumbnailUrl: String?
    let createdAt: String
    let creator: CatalogCreator
    var likesCount: Int
    var commentsCount: Int
    var isLiked: Bool
}

@MainActor
class CatalogViewModel: ObservableObject {
    @Published var generations: [CatalogItem] = []
    @Published var isLoading = false
    @Published var currentIndex: Int = 0
    @Published var hasMore = true

    private var currentPage = 1
    private let limit = 24
    private let catalogURL = "https://www.creatorai.art/api/catalog"

    var userId: String?

    func loadGenerations() async {
        guard !isLoading else { return }
        isLoading = true
        currentPage = 1
        let items = await fetchCatalog(page: 1)
        generations = items
        hasMore = items.count >= limit
        isLoading = false
    }

    func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        currentPage += 1
        let items = await fetchCatalog(page: currentPage)
        generations.append(contentsOf: items)
        hasMore = items.count >= limit
        isLoading = false
    }

    func refresh() async {
        await loadGenerations()
    }

    func toggleLike(at index: Int) {
        guard generations.indices.contains(index) else { return }
        let item = generations[index]
        let genId = item.id
        guard let userId else { return }

        // Optimistic update
        generations[index].isLiked.toggle()
        generations[index].likesCount += generations[index].isLiked ? 1 : -1

        // API call
        Task {
            await postLike(generationId: genId, userId: userId)
        }
    }

    // MARK: - API

    private func fetchCatalog(page: Int) async -> [CatalogItem] {
        var urlString = "\(catalogURL)?page=\(page)&limit=\(limit)"
        if let userId { urlString += "&userId=\(userId)" }
        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return [] }

            let decoded = try JSONDecoder().decode(CatalogResponse.self, from: data)
            return decoded.items.map { row in
                CatalogItem(
                    id: row.id,
                    prompt: row.prompt,
                    mode: row.mode,
                    model: row.model,
                    videoUrl: row.videoUrl,
                    thumbnailUrl: row.thumbnailUrl,
                    createdAt: row.createdAt,
                    creator: CatalogCreator(
                        displayName: row.creator?.displayName ?? "Creator",
                        avatarUrl: row.creator?.avatarUrl
                    ),
                    likesCount: row.likesCount ?? 0,
                    commentsCount: row.commentsCount ?? 0,
                    isLiked: row.isLiked ?? false
                )
            }
        } catch {
            print("[Catalog] Fetch failed: \(error)")
            return []
        }
    }

    private func postLike(generationId: String, userId: String) async {
        guard let url = URL(string: catalogURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["generationId": generationId, "userId": userId])
        _ = try? await URLSession.shared.data(for: request)
    }
}

private struct CatalogResponse: Decodable {
    let items: [CatalogRowDTO]
    let total: Int
}

private struct CatalogCreatorDTO: Decodable {
    let displayName: String?
    let avatarUrl: String?
}

private struct CatalogRowDTO: Decodable {
    let id: String
    let prompt: String
    let mode: String
    let model: String
    let videoUrl: String
    let thumbnailUrl: String?
    let createdAt: String
    let creator: CatalogCreatorDTO?
    let likesCount: Int?
    let commentsCount: Int?
    let isLiked: Bool?
}
