import SwiftUI
import AVFoundation
import AVKit

// MARK: - Reels-style Catalog Feed

struct CatalogView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @StateObject private var viewModel = CatalogViewModel()

    var body: some View {
        GeometryReader { geo in
            let pageSize = CGSize(
                width: geo.size.width,
                height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            )

            ZStack {
                Color.black

                if viewModel.generations.isEmpty && !viewModel.isLoading {
                    VStack(spacing: 16) {
                        Image(systemName: "play.rectangle.on.rectangle")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No videos yet")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                } else {
                    if #available(iOS 17.0, *) {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(viewModel.generations.enumerated()), id: \.element.id) { index, item in
                                    reelCardView(item: item, index: index, size: pageSize)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.paging)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(viewModel.generations.enumerated()), id: \.element.id) { index, item in
                                    reelCardView(item: item, index: index, size: pageSize)
                                }
                            }
                        }
                    }
                }

                if viewModel.isLoading && viewModel.generations.isEmpty {
                    ProgressView().scaleEffect(1.2).tint(.white)
                }
            }
        }
        .ignoresSafeArea()
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { viewModel.userId = appState.userId }
        .task {
            viewModel.userId = appState.userId
            if viewModel.generations.isEmpty {
                await viewModel.loadGenerations()
            }
        }
    }
}

extension CatalogView {
    func reelCardView(item: CatalogItem, index: Int, size: CGSize) -> some View {
        ReelCard(
            item: item,
            isVisible: viewModel.currentIndex == index,
            onUsePrompt: {
                NotificationCenter.default.post(name: .catalogUsePrompt, object: item.prompt)
            },
            viewModel: viewModel,
            index: index
        )
        .frame(width: size.width, height: size.height)
        .id(index)
        .onAppear {
            // Only update if this card is closer to what the user scrolled to
            // (prevents adjacent preloaded cards from stealing focus)
            if abs(index - viewModel.currentIndex) <= 1 {
                viewModel.currentIndex = index
            }
            if index >= viewModel.generations.count - 3 {
                Task { await viewModel.loadMore() }
            }
        }
    }
}

// MARK: - Single Reel Card

struct ReelCard: View {
    let item: CatalogItem
    let isVisible: Bool
    let onUsePrompt: () -> Void
    @ObservedObject var viewModel: CatalogViewModel
    let index: Int

    @StateObject private var playerVM = ReelPlayerViewModel()
    @State private var isMuted = false
    @State private var showShareSheet = false
    @State private var showComments = false

    var body: some View {
        ZStack {
            // Full-screen video — no overlays, no gradients
            if let player = playerVM.player {
                VideoPlayerLayer(player: player)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if player.timeControlStatus == .playing {
                            player.pause()
                        } else {
                            player.play()
                        }
                    }
            } else {
                Color.black
            }

            // Buffering
            if playerVM.isBuffering && isVisible {
                ProgressView().scaleEffect(1.3).tint(.white)
            }

            // Right side buttons
            VStack(spacing: 22) {
                Spacer()

                // Profile avatar
                VStack(spacing: 4) {
                    if let avatarUrl = item.creator.avatarUrl, let url = URL(string: avatarUrl) {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                avatarPlaceholder
                            }
                        }
                        .frame(width: 46, height: 46)
                        .clipShape(Circle())
                    } else {
                        avatarPlaceholder
                    }
                    Text(item.creator.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 2)
                        .lineLimit(1)
                        .frame(width: 60)
                }

                // Like
                sideButton(
                    icon: item.isLiked ? "heart.fill" : "heart",
                    label: "\(item.likesCount)",
                    color: item.isLiked ? .red : .white
                ) {
                    viewModel.toggleLike(at: index)
                }

                // Comments
                sideButton(icon: "bubble.right", label: "\(item.commentsCount)", color: .white) {
                    showComments = true
                }

                // Share
                sideButton(icon: "arrowshape.turn.up.right", label: "Share", color: .white) {
                    showShareSheet = true
                }

                // Mute
                Button {
                    isMuted.toggle()
                    playerVM.player?.isMuted = isMuted
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 2)
                        .padding(10)
                }

                Spacer().frame(height: 80)
            }
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .trailing)

            // Bottom text — no gradient, just shadows
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                        Text(item.model)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .shadow(color: .black, radius: 3)

                    Text(item.prompt)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .shadow(color: .black, radius: 3)

                    Button(action: onUsePrompt) {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Edit Prompt")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.black.opacity(0.3)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.trailing, 56)
                .padding(.bottom, 90)
            }
        }
        .onChange(of: isVisible) { visible in
            if visible {
                playerVM.setup(url: item.videoUrl, muted: isMuted)
                playerVM.play()
            } else {
                playerVM.pause()
            }
        }
        .onAppear {
            playerVM.setup(url: item.videoUrl, muted: isMuted)
            if isVisible {
                playerVM.play()
            }
        }
        .task(id: isVisible) {
            // Ensure play starts when visibility changes (covers first card)
            if isVisible {
                playerVM.setup(url: item.videoUrl, muted: isMuted)
                playerVM.play()
            }
        }
        .onDisappear {
            playerVM.tearDown()
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = URL(string: item.videoUrl) {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showComments) {
            CommentsSheet(item: item, userId: viewModel.userId)
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 46, height: 46)
            .overlay(
                Text(String(item.creator.displayName.prefix(1)).uppercased())
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            )
    }

    private func sideButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundColor(color)
                    .shadow(color: .black, radius: 2)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .shadow(color: .black, radius: 2)
            }
        }
    }
}

// MARK: - Reel Player ViewModel

@MainActor
class ReelPlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isBuffering = true

    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var currentURL: String?

    func setup(url: String, muted: Bool) {
        guard currentURL != url else { return }
        tearDown()
        currentURL = url

        guard let videoURL = URL(string: url) else { return }
        let item = AVPlayerItem(asset: AVURLAsset(url: videoURL))
        item.preferredForwardBufferDuration = 8

        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.isMuted = muted
        avPlayer.automaticallyWaitsToMinimizeStalling = true

        statusObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                self?.isBuffering = !item.isPlaybackLikelyToKeepUp
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak avPlayer] _ in
            avPlayer?.seek(to: .zero)
            avPlayer?.play()
        }

        player = avPlayer
    }

    func play() { player?.play() }
    func pause() { player?.pause() }

    func tearDown() {
        player?.pause()
        statusObservation?.invalidate()
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player = nil
        currentURL = nil
        isBuffering = true
    }
}

// MARK: - Comments Sheet

struct CommentData: Identifiable {
    let id: String
    let text: String
    let createdAt: String
    let userName: String
    let userAvatar: String?
}

struct CommentsSheet: View {
    let item: CatalogItem
    let userId: String?
    @Environment(\.dismiss) var dismiss

    @State private var comments: [CommentData] = []
    @State private var isLoading = true
    @State private var newComment = ""
    @State private var isSending = false

    private let baseURL = "https://www.creatorai.art/api/catalog/comments"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        // Original post
                        HStack(alignment: .top, spacing: 10) {
                            commentAvatar(name: item.creator.displayName, url: item.creator.avatarUrl)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.creator.displayName)
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(item.model)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Text(item.prompt)
                                    .font(.system(size: 14))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)

                        Divider().padding(.horizontal)

                        if isLoading {
                            HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 20)
                        } else if comments.isEmpty {
                            VStack(spacing: 6) {
                                Text("No comments yet")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("Be the first to comment")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                        } else {
                            ForEach(comments) { comment in
                                HStack(alignment: .top, spacing: 10) {
                                    commentAvatar(name: comment.userName, url: comment.userAvatar)
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(comment.userName)
                                                .font(.system(size: 13, weight: .semibold))
                                            Text(timeAgo(comment.createdAt))
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                        Text(comment.text)
                                            .font(.system(size: 14))
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }

                Divider()

                if userId != nil {
                    HStack(spacing: 10) {
                        TextField("Add a comment...", text: $newComment)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.systemGray6)))

                        Button {
                            Task { await sendComment() }
                        } label: {
                            if isSending {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(newComment.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .blue)
                            }
                        }
                        .disabled(newComment.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("\(comments.count) Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await loadComments() }
    }

    private func commentAvatar(name: String, url: String?) -> some View {
        Group {
            if let urlStr = url, let imgUrl = URL(string: urlStr) {
                AsyncImage(url: imgUrl) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        avatarFallback(name: name)
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            } else {
                avatarFallback(name: name)
            }
        }
    }

    private func avatarFallback(name: String) -> some View {
        Circle()
            .fill(LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 32, height: 32)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            )
    }

    private func timeAgo(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateString) else { return "" }
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "now" }
        if diff < 3600 { return "\(Int(diff / 60))m" }
        if diff < 86400 { return "\(Int(diff / 3600))h" }
        return "\(Int(diff / 86400))d"
    }

    private func loadComments() async {
        guard let url = URL(string: "\(baseURL)?generationId=\(item.id)") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(CommentsResponse.self, from: data)
            comments = decoded.comments.map {
                CommentData(id: $0.id, text: $0.text, createdAt: $0.createdAt, userName: $0.user.displayName, userAvatar: $0.user.avatarUrl)
            }
        } catch {
            print("[Comments] Load failed: \(error)")
        }
        isLoading = false
    }

    private func sendComment() async {
        guard let userId, !newComment.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSending = true
        defer { isSending = false }

        guard let url = URL(string: baseURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["generationId": item.id, "userId": userId, "text": newComment.trimmingCharacters(in: .whitespaces)]
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(SingleCommentResponse.self, from: data)
            let c = decoded.comment
            comments.insert(CommentData(id: c.id, text: c.text, createdAt: c.createdAt, userName: c.user.displayName, userAvatar: c.user.avatarUrl), at: 0)
            newComment = ""
        } catch {
            print("[Comments] Send failed: \(error)")
        }
    }
}

private struct CommentsResponse: Decodable {
    let comments: [CommentDTO]
}

private struct SingleCommentResponse: Decodable {
    let comment: CommentDTO
}

private struct CommentDTO: Decodable {
    let id: String
    let text: String
    let createdAt: String
    let user: CommentUserDTO
}

private struct CommentUserDTO: Decodable {
    let id: String?
    let displayName: String
    let avatarUrl: String?
}

// MARK: - Full-screen AVPlayerLayer

struct VideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = PlayerFillView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? PlayerFillView)?.player = player
    }
}

private final class PlayerFillView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspectFill
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
