import SwiftUI
#if os(iOS)
import PhotosUI
#endif

struct ReelCreatorView: View {
    @ObservedObject var viewModel: CreateViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @State private var showLaunchCelebration = false
    @State private var reelPreview: PagePreview?
    @State private var lastScrapedURL: String?

    private var detectedURL: String? {
        let pattern = #"https?://[^\s]+"#
        guard let range = viewModel.reelTopic.range(of: pattern, options: .regularExpression) else { return nil }
        return String(viewModel.reelTopic[range])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Topic Input
            SectionLabel("TOPIC / CONCEPT")
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $viewModel.reelTopic)
                    .frame(minHeight: 80)
                    .font(.system(size: 16))
                    .foregroundColor(theme.text)
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .topLeading) {
                        if viewModel.reelTopic.isEmpty {
                            Text("e.g. traveling without eSIM, hustle culture, Monday motivation...")
                                .font(.system(size: 16))
                                .foregroundColor(theme.textTertiary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                    }

                ReferenceVideoPickerView(
                    referenceVideoURL: $viewModel.reelReferenceVideoURL,
                    style: .inlineAttachment
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(theme.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(theme.border, lineWidth: 1)
                    )
            )
            .onChange(of: viewModel.reelTopic) { _ in
                if let url = detectedURL, url != lastScrapedURL {
                    lastScrapedURL = url
                    Task {
                        reelPreview = await LocalScraperService.scrape(url: url)
                        if let p = reelPreview {
                            viewModel.reelScrapedContext = [p.title, p.description].compactMap { $0 }.joined(separator: ". ")
                        }
                    }
                } else if detectedURL == nil {
                    reelPreview = nil
                    lastScrapedURL = nil
                    viewModel.reelScrapedContext = nil
                }
            }
            .padding(.bottom, 12)

            // URL chip
            if let url = detectedURL {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                    Text(url)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundColor(theme.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(theme.primary.opacity(0.1)))
                .padding(.bottom, 8)
            }

            // Scraped preview card
            if let preview = reelPreview {
                VStack(alignment: .leading, spacing: 8) {
                    if let ogImage = preview.ogImage, !ogImage.isEmpty, let imgURL = URL(string: ogImage) {
                        AsyncImage(url: imgURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill).frame(height: 120).clipShape(RoundedRectangle(cornerRadius: 10))
                        } placeholder: { EmptyView() }
                    }
                    if let title = preview.title {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(theme.text)
                            .lineLimit(2)
                    }
                    if let desc = preview.description {
                        Text(desc)
                            .font(.system(size: 13))
                            .foregroundColor(theme.textSecondary)
                            .lineLimit(2)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(theme.surfaceElevated)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))
                )
                .padding(.bottom, 8)
            }

            Spacer().frame(height: 8)

            // AI Model Selection
            SectionLabel("AI MODEL")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(PRESET_AI_MODELS) { model in
                        Button {
                            viewModel.reelInfluencerId = model.id
                        } label: {
                            VStack(spacing: 8) {
                                CachedAsyncImage(url: model.imageURL, id: model.id)
                                    .frame(width: 64, height: 64)
                                    .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(viewModel.reelInfluencerId == model.id ? theme.primary : Color.clear, lineWidth: 3)
                                )

                                Text(model.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(viewModel.reelInfluencerId == model.id ? theme.primary : theme.text)
                                    .lineLimit(1)
                            }
                            .frame(width: 80)
                        }
                    }
                }
            }
            .padding(.bottom, 20)

            // Generate Button
            HStack(spacing: 8) {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                    Text("Generating...")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 20))
                    Text("Generate Reel")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(theme.primary)
            )
            .opacity(viewModel.isLoading ? 0.7 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !viewModel.isLoading else { return }
                dismissKeyboard()
                Task {
                    if await viewModel.generateReel(appState: appState) {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                            showLaunchCelebration = true
                        }
                        try? await Task.sleep(nanoseconds: 900_000_000)
                        withAnimation(.easeOut(duration: 0.2)) {
                            showLaunchCelebration = false
                        }
                        NotificationCenter.default.post(name: .switchToLibraryTab, object: nil)
                    }
                }
            }
        }
        .overlay {
            if showLaunchCelebration {
                ReelLaunchCelebrationView()
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }
}

private struct ReelLaunchCelebrationView: View {
    @State private var animate = false

    private let colors: [Color] = [
        .yellow, .orange, .red, .blue, .green, .pink
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<18, id: \.self) { index in
                    Circle()
                        .fill(colors[index % colors.count])
                        .frame(width: 10, height: 10)
                        .offset(y: animate ? -220 - CGFloat(index * 8) : 20)
                        .offset(x: animate ? horizontalOffset(for: index) : 0)
                        .opacity(animate ? 0 : 1)
                        .animation(
                            .easeOut(duration: 0.9).delay(Double(index) * 0.015),
                            value: animate
                        )
                }

                VStack(spacing: 12) {
                    Image(systemName: "rocket.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.white, .orange)
                        .rotationEffect(.degrees(animate ? 0 : -18))
                        .offset(y: animate ? -90 : 10)
                        .scaleEffect(animate ? 1.15 : 0.8)
                        .shadow(color: .orange.opacity(0.35), radius: 16, y: 10)

                    Text("Video Started")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .opacity(animate ? 1 : 0.4)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) {
                animate = true
            }
        }
    }

    private func horizontalOffset(for index: Int) -> CGFloat {
        let spread: [CGFloat] = [-120, -90, -70, -48, -24, 0, 24, 48, 70, 90, 120]
        return spread[index % spread.count]
    }
}

// MARK: - Reference Video Picker (for movement copy)

struct ReferenceVideoPickerView: View {
    enum Style {
        case fullWidth
        case inlineAttachment
    }

    @Binding var referenceVideoURL: URL?
    var style: Style = .fullWidth
    @Environment(\.theme) var theme
    #if os(iOS)
    @State private var selectedItem: PhotosPickerItem?
    #endif
    @State private var thumbnailImage: PlatformImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let url = referenceVideoURL {
                HStack(spacing: 12) {
                    if let img = thumbnailImage {
                        Image(platformImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(theme.surfaceElevated)
                            .frame(width: 80, height: 80)
                            .overlay(
                                Image(systemName: "video.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(theme.textTertiary)
                            )
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reference video selected")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(theme.text)
                        Text(url.lastPathComponent)
                            .font(.system(size: 12))
                            .foregroundColor(theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button {
                        referenceVideoURL = nil
                        #if os(iOS)
                        selectedItem = nil
                        #endif
                        thumbnailImage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(theme.textTertiary)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(theme.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(theme.border, lineWidth: 1)
                        )
                )
            } else {
                #if os(iOS)
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    attachmentButtonLabel
                }
                .onChange(of: selectedItem) { newItem in
                    Task {
                        guard let newItem = newItem else { return }
                        if let data = try? await newItem.loadTransferable(type: Data.self), !data.isEmpty {
                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
                            try? data.write(to: tempURL)
                            await MainActor.run {
                                referenceVideoURL = tempURL
                                loadThumbnail(for: tempURL)
                            }
                        }
                    }
                }
                #else
                // macOS: use file importer instead of PhotosPicker
                attachmentButtonLabel
                #endif
            }
        }
        .onChange(of: referenceVideoURL) { url in
            if let url = url, thumbnailImage == nil {
                loadThumbnail(for: url)
            }
        }
    }

    @ViewBuilder
    private var attachmentButtonLabel: some View {
        switch style {
        case .fullWidth:
            HStack(spacing: 10) {
                Image(systemName: "video.badge.plus")
                    .font(.system(size: 22))
                Text("Upload video to copy movement")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundColor(theme.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(theme.primary.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(theme.primary.opacity(0.5), lineWidth: 1.5)
                    )
            )
        case .inlineAttachment:
            HStack(spacing: 8) {
                Image(systemName: "paperclip")
                    .font(.system(size: 14, weight: .semibold))
                Text("Add movement video")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(theme.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(theme.primary.opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke(theme.primary.opacity(0.35), lineWidth: 1)
                    )
            )
        }
    }

    private func loadThumbnail(for url: URL) {
        Task {
            if let image = await ThumbnailService.shared.generateThumbnail(for: url) {
                await MainActor.run {
                    thumbnailImage = image
                }
            }
        }
    }
}

// MARK: - Section Label Helper

struct SectionLabel: View {
    let text: String
    @Environment(\.theme) var theme

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(theme.textSecondary)
            .tracking(0.5)
            .padding(.bottom, 8)
    }
}

// MARK: - Navigation Notification

extension Notification.Name {
    static let navigateToVideoEditor = Notification.Name("navigateToVideoEditor")
    static let navigateToGenerationStatus = Notification.Name("navigateToGenerationStatus")
    static let switchToLibraryTab = Notification.Name("switchToLibraryTab")
    static let startVideoImport = Notification.Name("startVideoImport")
    static let prefillPrompt = Notification.Name("prefillPrompt")
    static let applyEditorAIInstruction = Notification.Name("applyEditorAIInstruction")
}
