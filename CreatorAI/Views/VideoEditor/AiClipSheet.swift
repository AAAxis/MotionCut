import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
#if os(iOS)
import RevenueCatUI
import PhotosUI
#endif

// MARK: - AI Model definitions (matches web pricing)

struct AIVideoModel: Identifiable {
    let id: String
    let name: String
    let tier: String // "budget", "standard", "premium"
    let creditsPerSec: Int
    let hasAudio: Bool
    let supportsFirstFrameReference: Bool
    let supportsMotionReference: Bool

    var isNoAI: Bool { id == "noai" }
}

private let AI_VIDEO_MODELS: [AIVideoModel] = [
    AIVideoModel(id: "noai", name: "Pexels", tier: "free", creditsPerSec: 0, hasAudio: false, supportsFirstFrameReference: false, supportsMotionReference: false),
    // fal.ai video generation models
    AIVideoModel(id: "fal-ai/kling-video/v2.6/pro/text-to-video", name: "Kling 2.6 Pro", tier: "premium", creditsPerSec: 5, hasAudio: true, supportsFirstFrameReference: false, supportsMotionReference: false),
    AIVideoModel(id: "fal-ai/kling-video/v2.5-turbo/pro/text-to-video", name: "Kling 2.5 Turbo Pro", tier: "standard", creditsPerSec: 3, hasAudio: false, supportsFirstFrameReference: false, supportsMotionReference: false),
    AIVideoModel(id: "fal-ai/kling-video/v2.1/master/text-to-video", name: "Kling 2.1 Master", tier: "premium", creditsPerSec: 5, hasAudio: true, supportsFirstFrameReference: true, supportsMotionReference: true),
    AIVideoModel(id: "fal-ai/bytedance/seedance/v1/pro/text-to-video", name: "Seedance Pro", tier: "standard", creditsPerSec: 3, hasAudio: true, supportsFirstFrameReference: true, supportsMotionReference: false),
    AIVideoModel(id: "fal-ai/bytedance/seedance/v1/lite/text-to-video", name: "Seedance Lite", tier: "budget", creditsPerSec: 1, hasAudio: true, supportsFirstFrameReference: true, supportsMotionReference: false),
    AIVideoModel(id: "fal-ai/veo3/fast", name: "Veo 3 Fast", tier: "premium", creditsPerSec: 5, hasAudio: true, supportsFirstFrameReference: true, supportsMotionReference: false),
    AIVideoModel(id: "fal-ai/minimax/hailuo-02/standard/text-to-video", name: "Hailuo 02", tier: "standard", creditsPerSec: 3, hasAudio: false, supportsFirstFrameReference: true, supportsMotionReference: false),
]

struct AiClipSheet: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @Environment(\.dismiss) var dismiss
    @State private var showPaywall = false
    @AppStorage("FAL_API_KEY") private var falAPIKey = ""
    @AppStorage("OPENAI_API_KEY") private var openAIAPIKey = ""
    @State private var showSettings = false
    @State private var selectedModelId = "noai"
    @State private var availableVideoModels = AI_VIDEO_MODELS
    @State private var isLoadingModels = false
    @State private var audioMode = "none"
    @State private var elevenLabsVoices: [ElevenLabsVoice] = []
    @State private var selectedElevenLabsVoiceId = ""
    @State private var isLoadingElevenLabsVoices = false
    @State private var voicePreviewPlayer: AVPlayer?
    @State private var previewingVoiceId: String?
    @State private var loadingVoicePreviewId: String?
    @State private var language = "en"
    @State private var referenceImageData: Data?
    @State private var referenceVideoURL: URL?
    @State private var referenceAttachmentName = ""
    @State private var referenceAttachmentKind = ""
    @State private var isUploadingReference = false
    @State private var showReferenceFilePicker = false
    @State private var continueGenerationAfterPaywall = false
    #if os(iOS)
    @State private var selectedReferenceItem: PhotosPickerItem?
    #endif

    private var selectedModel: AIVideoModel {
        availableVideoModels.first { $0.id == selectedModelId } ?? availableVideoModels[0]
    }

    private var selectedModelSupportsReference: Bool {
        selectedModel.supportsFirstFrameReference || selectedModel.supportsMotionReference
    }

    private var sortedVideoModels: [AIVideoModel] {
        availableVideoModels.sorted { lhs, rhs in
            let leftScore = modelSortScore(lhs)
            let rightScore = modelSortScore(rhs)
            if leftScore != rightScore { return leftScore > rightScore }
            if lhs.creditsPerSec != rhs.creditsPerSec { return lhs.creditsPerSec < rhs.creditsPerSec }
            return lhs.name < rhs.name
        }
    }

    private func modelSortScore(_ model: AIVideoModel) -> Int {
        let id = model.id.lowercased()
        let name = model.name.lowercased()
        if model.isNoAI { return 100 }
        if id.contains("openai") || name.contains("sora") { return 95 }
        if id.contains("kling") || name.contains("kling") { return 90 }
        if id.contains("seedance") || name.contains("seedance") { return 80 }
        if id.contains("veo") || name.contains("veo") { return 70 }
        if id.contains("hailuo") || name.contains("hailuo") { return 60 }
        return 10
    }

    private var scenarioMode: String {
        if let saved = UserDefaults.standard.string(forKey: "AI_SCENARIO_MODE") {
            return saved == "apple" ? "apple" : "openrouter"
        }
        return "apple"
    }

    private var selectedModelNeedsFalKey: Bool {
        selectedModel.id.hasPrefix("fal-ai/")
    }

    private var selectedModelNeedsOpenAIKey: Bool {
        selectedModel.id.hasPrefix("openai/")
    }

    private var requiresSubscription: Bool {
        selectedModelNeedsOpenAIKey || audioMode == "elevenlabs"
    }

    private var missingSubscription: Bool {
        requiresSubscription && !appState.hasUnlimitedAPIUsage
    }

    private var hasFalKey: Bool {
        !falAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasOpenAIKey: Bool {
        !openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ad maker")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(theme.text)

            // Prompt
            TextEditor(text: $viewModel.aiPrompt)
                .frame(minHeight: 70)
                .font(.system(size: 15))
                .foregroundColor(theme.text)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.surfaceElevated)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border, lineWidth: 1))
                )
                .overlay(alignment: .topLeading) {
                    if viewModel.aiPrompt.isEmpty {
                        Text("Describe the ad you want...")
                            .font(.system(size: 15))
                            .foregroundColor(theme.textTertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
            }

            modelPicker
            if selectedModelNeedsFalKey && !hasFalKey {
                falSetupBanner
            }
            if selectedModelNeedsOpenAIKey && !hasOpenAIKey {
                providerSetupBanner(provider: "OpenAI", modelName: selectedModel.name)
            }
            if selectedModelSupportsReference {
                referenceAttachmentPicker
            }
            optionPicker(title: "Audio", selection: $audioMode, options: [
                ("none", "No audio"),
                ("music", "Music"),
                ("elevenlabs", "Voice")
            ])
            if audioMode == "elevenlabs" {
                elevenLabsVoicePicker
            }
            optionPicker(title: "Language", selection: $language, options: LANGUAGES.map { ($0.id, $0.label) })

            captionsPicker

            // Status banner
            if viewModel.aiGenerating {
                HStack(spacing: 8) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text(viewModel.aiStatus.replacingOccurrences(of: "...", with: ""))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme.primary.opacity(0.8)))
            }

            // Access
            HStack {
                Image(systemName: requiresSubscription ? "crown.fill" : "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(requiresSubscription ? theme.primary : theme.success)
                Text(accessSummary)
                    .font(.system(size: 12))
                    .foregroundColor(theme.textTertiary)
                Spacer()
            }

            // Generate button
            HStack(spacing: 8) {
                if viewModel.aiGenerating {
                    Image(systemName: "film.stack")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Generating")
                        .font(.system(size: 15, weight: .semibold))
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                    Text(actionTitle)
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(viewModel.aiGenerating ? theme.primary.opacity(0.7) : theme.primary))
            .opacity(viewModel.aiPrompt.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                let prompt = viewModel.aiPrompt.trimmingCharacters(in: .whitespaces)
                guard !prompt.isEmpty, !viewModel.aiGenerating else { return }
                if selectedModelNeedsFalKey && !hasFalKey {
                    viewModel.processingError = "Connect fal.ai in Settings before using this model."
                    showSettings = true
                } else if selectedModelNeedsOpenAIKey && !hasOpenAIKey {
                    viewModel.processingError = "Connect OpenAI in Settings before using Sora."
                    showSettings = true
                } else if missingSubscription {
                    continueGenerationAfterPaywall = true
                    showPaywall = true
                } else {
                    startGeneration(prompt: prompt)
                }
            }

            // Error
            if let error = viewModel.processingError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(theme.error)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(theme.error)
                }
            }

            Spacer()
        }
        .padding(16)
        .onAppear {
            if audioMode == "elevenlabs" {
                Task { await fetchElevenLabsVoices() }
            }
        }
        .onChange(of: audioMode) { mode in
            if mode == "elevenlabs" {
                Task { await fetchElevenLabsVoices() }
            }
        }
        .onChange(of: selectedModelId) { _ in
            if !selectedModelSupportsReference {
                clearReferenceAttachment()
            } else if referenceAttachmentKind == "photo", !selectedModel.supportsFirstFrameReference {
                clearReferenceAttachment()
            } else if referenceAttachmentKind == "video", !selectedModel.supportsMotionReference {
                clearReferenceAttachment()
            }
        }
        #if os(iOS)
        .onChange(of: selectedReferenceItem) { item in
            guard let item else { return }
            Task { await loadReferenceItem(item) }
        }
        #endif
        .onChange(of: viewModel.aiGenerating) { generating in
            if !generating && viewModel.aiStatus.isEmpty {
                dismiss()
            }
        }
        .onChange(of: showPaywall) { isPresented in
            guard !isPresented, continueGenerationAfterPaywall else { return }
            continueGenerationAfterPaywall = false
            let prompt = viewModel.aiPrompt.trimmingCharacters(in: .whitespaces)
            guard !prompt.isEmpty, !viewModel.aiGenerating else { return }
            startGeneration(prompt: prompt)
        }
        .onDisappear {
            voicePreviewPlayer?.pause()
            voicePreviewPlayer = nil
            previewingVoiceId = nil
            loadingVoicePreviewId = nil
        }
        .sheet(isPresented: $showPaywall) {
            #if os(iOS)
            PaywallView()
                .onPurchaseCompleted { customerInfo in
                    Task { await PurchaseService.shared.handlePurchaseCompleted(customerInfo: customerInfo, appState: appState) }
                    showPaywall = false
                }
            #else
            MacBuyCreditsPlaceholder(dismiss: { showPaywall = false })
                .frame(minWidth: 400, minHeight: 300)
            #endif
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(showCloseButton: true, userId: appState.userId ?? "demo-user")
                .environmentObject(appState)
        }
        .fileImporter(
            isPresented: $showReferenceFilePicker,
            allowedContentTypes: [.image, .movie, .video],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            loadReferenceFile(url)
        }
    }

    private var actionTitle: String {
        if isUploadingReference { return "Uploading reference..." }
        if missingSubscription { return "Start trial" }
        return "Build ad"
    }

    private var accessSummary: String {
        if selectedModel.isNoAI && audioMode != "elevenlabs" {
            return "Pexels stock mode"
        }
        if appState.hasUnlimitedAPIUsage {
            return "Subscription active"
        }
        if selectedModelNeedsFalKey {
            return "Uses your fal.ai key"
        }
        return "Pro unlocks Voice and watermark removal"
    }

    private func startGeneration(prompt: String) {
        viewModel.processingError = nil
        Task {
            isUploadingReference = true
            let reference = selectedModelSupportsReference
                ? await uploadReferenceAttachment()
                : (imageUrl: nil as String?, videoUrl: nil as String?, promptNote: nil as String?)
            isUploadingReference = false
            dismiss()
            let editPrompt = audioMode == "music"
                ? "\(prompt)\nAudio direction: use music only, choose a matching music bed, no voiceover."
                : prompt
            let builtAd = await viewModel.generateAiAd(
                aiModelId: selectedModelId,
                sourceMode: selectedModel.isNoAI ? "stock" : "ai",
                scenarioMode: scenarioMode,
                voiceoverMode: audioMode,
                elevenLabsVoiceId: audioMode == "elevenlabs" ? selectedElevenLabsVoiceId : nil,
                referenceImageUrl: reference.imageUrl,
                referenceVideoUrl: reference.videoUrl,
                referencePromptNote: reference.promptNote,
                language: language,
                clipCount: 4
            )
            if builtAd {
                await viewModel.runAiTimelineEdit(
                    scenarioMode: scenarioMode,
                    language: language,
                    requestOverride: editPrompt
                )
            }
        }
    }

    private var referenceAttachmentPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reference")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.textTertiary)

            if referenceAttachmentKind.isEmpty {
                HStack(spacing: 8) {
                    #if os(iOS)
                    PhotosPicker(selection: $selectedReferenceItem, matching: .any(of: [.images, .videos])) {
                        referenceButtonLabel(icon: "paperclip", title: "Attach photo/video")
                    }
                    #else
                    Button {
                        showReferenceFilePicker = true
                    } label: {
                        referenceButtonLabel(icon: "paperclip", title: "Attach photo/video")
                    }
                    #endif
                }
            } else {
                HStack(spacing: 9) {
                    Image(systemName: referenceAttachmentKind == "photo" ? "photo" : "video")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.primary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(theme.primary.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(referenceAttachmentKind == "photo" ? "First frame" : "Motion control")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(theme.text)
                        Text(referenceAttachmentName)
                            .font(.system(size: 11))
                            .foregroundColor(theme.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if isUploadingReference {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    Button {
                        clearReferenceAttachment()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(theme.textTertiary)
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.surfaceElevated)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border, lineWidth: 1))
                )
            }
        }
    }

    private var falSetupBanner: some View {
        providerSetupBanner(provider: "fal.ai", modelName: selectedModel.name)
    }

    private func providerSetupBanner(provider: String, modelName: String) -> some View {
        Button {
            showSettings = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "key.fill")
                    .font(.system(size: 13, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect \(provider)")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Add your API key in Settings to use \(modelName).")
                        .font(.system(size: 11))
                        .foregroundColor(theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(theme.text)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.surfaceElevated)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.primary.opacity(0.35), lineWidth: 1))
            )
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }

    private func referenceButtonLabel(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .foregroundColor(theme.primary)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.primary.opacity(0.09))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.primary.opacity(0.25), lineWidth: 1))
        )
    }

    private var elevenLabsVoicePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Voice style")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.textTertiary)
                Spacer()
                if isLoadingElevenLabsVoices {
                    ProgressView()
                        .scaleEffect(0.65)
                }
            }

            if !ElevenLabsTTSService.shared.isConfigured {
                Text("Premium voice is unavailable. Built-in voice will be used.")
                    .font(.system(size: 12))
                    .foregroundColor(theme.textTertiary)
                    .padding(.vertical, 8)
            } else if elevenLabsVoices.isEmpty && !isLoadingElevenLabsVoices {
                Text("No voices loaded yet.")
                    .font(.system(size: 12))
                    .foregroundColor(theme.textTertiary)
                    .padding(.vertical, 8)
                    .onTapGesture {
                        Task { await fetchElevenLabsVoices() }
                    }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(elevenLabsVoices) { voice in
                            let isSelected = selectedElevenLabsVoiceId == voice.id
                            HStack(spacing: 7) {
                                Button {
                                    toggleVoicePreview(voice)
                                } label: {
                                    Group {
                                        if loadingVoicePreviewId == voice.id {
                                            ProgressView()
                                                .scaleEffect(0.55)
                                                .tint(isSelected ? .white : theme.primary)
                                        } else {
                                            Image(systemName: previewingVoiceId == voice.id ? "stop.fill" : "play.fill")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(isSelected ? .white : theme.primary)
                                        }
                                    }
                                    .frame(width: 14, height: 14)
                                }
                                #if os(macOS)
                                .buttonStyle(.plain)
                                #endif
                                .disabled(voice.previewURL == nil)

                                Text(voice.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundColor(isSelected ? .white : theme.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? theme.primary : theme.surfaceElevated))
                            .onTapGesture {
                                selectedElevenLabsVoiceId = voice.id
                            }
                        }
                    }
                }
            }
        }
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Model")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.textTertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sortedVideoModels) { model in
                        let isSelected = selectedModelId == model.id
                        VStack(spacing: 2) {
                            Text(model.name)
                                .font(.system(size: 11, weight: .semibold))
                            Group {
                                if model.hasAudio {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.system(size: 8))
                                        .frame(height: 10)
                                } else {
                                    Color.clear
                                        .frame(height: 10)
                                }
                            }
                            .foregroundColor(isSelected ? .white.opacity(0.7) : theme.textTertiary)
                        }
                        .foregroundColor(isSelected ? .white : theme.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? theme.primary : theme.surfaceElevated)
                        )
                        .onTapGesture { selectedModelId = model.id }
                    }
                    if isLoadingModels {
                        ProgressView()
                            .scaleEffect(0.7)
                            .padding(.horizontal, 8)
                    }
                }
            }
        }
    }

    private func toggleVoicePreview(_ voice: ElevenLabsVoice) {
        if previewingVoiceId == voice.id {
            voicePreviewPlayer?.pause()
            voicePreviewPlayer = nil
            previewingVoiceId = nil
            loadingVoicePreviewId = nil
            return
        }

        guard let previewURL = voice.previewURL, let url = URL(string: previewURL) else { return }
        voicePreviewPlayer?.pause()
        loadingVoicePreviewId = voice.id
        let player = AVPlayer(url: url)
        voicePreviewPlayer = player
        previewingVoiceId = voice.id
        player.play()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if previewingVoiceId == voice.id {
                loadingVoicePreviewId = nil
            }
        }
    }

    #if os(iOS)
    @MainActor
    private func loadReferenceItem(_ item: PhotosPickerItem) async {
        defer { selectedReferenceItem = nil }

        guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else {
            viewModel.processingError = "Could not read the selected reference."
            return
        }

        let supportedTypes = item.supportedContentTypes
        let isVideo = supportedTypes.contains { $0.conforms(to: .movie) || $0.conforms(to: .video) }

        if isVideo {
            guard selectedModel.supportsMotionReference else {
                viewModel.processingError = "\(selectedModel.name) does not support motion-control video references."
                return
            }
            let ext = supportedTypes.first(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) })?.preferredFilenameExtension ?? "mov"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("reference-\(UUID().uuidString)")
                .appendingPathExtension(ext)
            do {
                try data.write(to: url, options: .atomic)
                referenceVideoURL = url
                referenceImageData = nil
                referenceAttachmentKind = "video"
                referenceAttachmentName = "Reference video"
            } catch {
                viewModel.processingError = error.localizedDescription
            }
        } else {
            guard selectedModel.supportsFirstFrameReference else {
                viewModel.processingError = "\(selectedModel.name) does not support first-frame image references."
                return
            }
            referenceImageData = data
            referenceVideoURL = nil
            referenceAttachmentKind = "photo"
            referenceAttachmentName = "Reference photo"
        }
    }
    #endif

    private func loadReferenceFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let ext = url.pathExtension.isEmpty ? "ref" : url.pathExtension
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("reference-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            if UTType(filenameExtension: ext)?.conforms(to: .image) == true {
                guard selectedModel.supportsFirstFrameReference else {
                    viewModel.processingError = "\(selectedModel.name) does not support first-frame image references."
                    return
                }
                referenceImageData = try Data(contentsOf: dest)
                referenceVideoURL = nil
                referenceAttachmentKind = "photo"
                referenceAttachmentName = url.lastPathComponent
            } else {
                guard selectedModel.supportsMotionReference else {
                    viewModel.processingError = "\(selectedModel.name) does not support motion-control video references."
                    return
                }
                referenceVideoURL = dest
                referenceImageData = nil
                referenceAttachmentKind = "video"
                referenceAttachmentName = url.lastPathComponent
            }
        } catch {
            viewModel.processingError = error.localizedDescription
        }
    }

    private func clearReferenceAttachment() {
        referenceImageData = nil
        referenceVideoURL = nil
        referenceAttachmentName = ""
        referenceAttachmentKind = ""
    }

    @MainActor
    private func uploadReferenceAttachment() async -> (imageUrl: String?, videoUrl: String?, promptNote: String?) {
        let userId = appState.userId ?? "demo-user"
        do {
            if let imageData = referenceImageData, selectedModel.supportsFirstFrameReference {
                let uploaded = try await GenerationService.shared.uploadReferenceImage(
                    imageData: imageData,
                    filename: "reference-\(UUID().uuidString).jpg",
                    userId: userId
                )
                let url = absoluteAPIURL(uploaded.url)
                return (
                    imageUrl: url,
                    videoUrl: nil,
                    promptNote: "Use the attached image as the first frame reference."
                )
            }

            if let videoURL = referenceVideoURL, selectedModel.supportsMotionReference {
                let uploaded = try await GenerationService.shared.uploadReferenceVideo(
                    fileURL: videoURL,
                    userId: userId
                )
                let url = absoluteAPIURL(uploaded.url)
                return (
                    imageUrl: nil,
                    videoUrl: url,
                    promptNote: "Use the attached video only for motion control."
                )
            }
        } catch {
            let fallbackNote = referenceAttachmentKind == "video"
                ? "Reference video was attached but upload is unavailable. Use motion control only if the generation model receives a valid reference."
                : "Reference photo was attached but upload is unavailable. Use first-frame reference only if the generation model receives a valid reference."
            viewModel.processingMessage = "Reference upload unavailable. Continuing without uploaded reference."
            return (nil, nil, fallbackNote)
        }

        return (nil, nil, nil)
    }

    private func absoluteAPIURL(_ path: String) -> String {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return path
        }
        return "\(APIService.shared.syncBaseURL)\(path)"
    }

    @MainActor
    private func fetchElevenLabsVoices() async {
        guard !isLoadingElevenLabsVoices else { return }
        guard ElevenLabsTTSService.shared.isConfigured else { return }

        isLoadingElevenLabsVoices = true
        defer { isLoadingElevenLabsVoices = false }

        do {
            let voices = try await ElevenLabsTTSService.shared.fetchVoices()
            elevenLabsVoices = voices
            loadingVoicePreviewId = nil
            if !voices.contains(where: { $0.id == selectedElevenLabsVoiceId }) {
                selectedElevenLabsVoiceId = voices.first?.id ?? ""
            }
        } catch {
            viewModel.processingError = error.localizedDescription
            print("[ElevenLabs] Voice fetch failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func fetchOpenRouterVideoModels() async {
        guard !isLoadingModels else { return }
        isLoadingModels = true
        defer { isLoadingModels = false }

        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = root["data"] as? [[String: Any]] else { return }

            let fetched = items.compactMap(openRouterVideoModel(from:))
            guard !fetched.isEmpty else { return }
            var seen: Set<String> = ["noai"]
            let merged = [AI_VIDEO_MODELS[0]] + (fetched + AI_VIDEO_MODELS.dropFirst()).filter { model in
                if seen.contains(model.id) { return false }
                seen.insert(model.id)
                return true
            }
            availableVideoModels = merged
            if !availableVideoModels.contains(where: { $0.id == selectedModelId }) {
                selectedModelId = "noai"
            }
        } catch {
            print("[OpenRouter] Model fetch failed: \(error.localizedDescription)")
        }
    }

    private func openRouterVideoModel(from item: [String: Any]) -> AIVideoModel? {
        guard let id = item["id"] as? String else { return nil }
        let architecture = item["architecture"] as? [String: Any]
        let outputModalities = architecture?["output_modalities"] as? [String] ?? []
        let inputModalities = architecture?["input_modalities"] as? [String] ?? []
        let modality = architecture?["modality"] as? String ?? ""
        let searchable = ([id, modality] + outputModalities + inputModalities).joined(separator: " ").lowercased()
        let looksVideo = searchable.contains("video")
            || id.lowercased().contains("veo")
            || id.lowercased().contains("kling")
            || id.lowercased().contains("seedance")
            || id.lowercased().contains("hailuo")
        guard looksVideo else { return nil }

        let name = (item["name"] as? String) ?? id.split(separator: "/").last.map(String.init) ?? id
        let supportsAudio = outputModalities.contains { $0.lowercased().contains("audio") }
        let lowerId = id.lowercased()
        let supportsFirstFrame = lowerId.contains("veo")
            || lowerId.contains("kling")
            || lowerId.contains("seedance")
            || lowerId.contains("hailuo")
        let supportsMotion = lowerId.contains("kling")
        return AIVideoModel(
            id: id,
            name: shortModelName(name),
            tier: "openrouter",
            creditsPerSec: estimatedCredits(for: id),
            hasAudio: supportsAudio,
            supportsFirstFrameReference: supportsFirstFrame,
            supportsMotionReference: supportsMotion
        )
    }

    private func shortModelName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "Google: ", with: "")
            .replacingOccurrences(of: "Kwaivgi: ", with: "")
            .replacingOccurrences(of: "Bytedance: ", with: "")
            .replacingOccurrences(of: "MiniMax: ", with: "")
        return String(cleaned.prefix(18))
    }

    private func estimatedCredits(for id: String) -> Int {
        let lower = id.lowercased()
        if lower.contains("lite") || lower.contains("fast") { return 1 }
        if lower.contains("pro") || lower.contains("veo-3.1") { return 5 }
        return 3
    }

    private var captionsPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Captions")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.textTertiary)
            HStack(spacing: 6) {
                captionChip("Off", isSelected: !viewModel.addCaptionsViaCloud) {
                    viewModel.setCaptionsViaCloud(false)
                }
                captionChip("On", isSelected: viewModel.addCaptionsViaCloud) {
                    viewModel.setCaptionsViaCloud(true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func captionChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(isSelected ? .white : theme.text)
            .frame(minWidth: 58)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? theme.primary : theme.surfaceElevated))
            .onTapGesture(perform: action)
    }

    private func optionPicker(title: String, selection: Binding<String>, options: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(options, id: \.0) { id, label in
                        let isSelected = selection.wrappedValue == id
                        Text(label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isSelected ? .white : theme.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? theme.primary : theme.surfaceElevated))
                            .onTapGesture { selection.wrappedValue = id }
                    }
                }
            }
        }
    }
}
