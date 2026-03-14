import SwiftUI
import AVFoundation
import Combine

@MainActor
class GenerationStatusViewModel: ObservableObject {
    @Published var status: String = "processing"
    @Published var videoUrl: String?
    @Published var error: String?
    @Published var currentStep: Int = 0
    @Published var resultPlayer: AVPlayer?

    let generationId: String
    let title: String
    let isLocalExport: Bool

    private var pollTimer: Timer?
    private var stepTimers: [Timer] = []

    enum GenerationType {
        case api      // Ad Maker
        case reel     // AI Influencer / Reel
        case export   // Local export
    }

    static let apiSteps: [(key: String, label: String, icon: String)] = [
        ("scraping", "Analyzing page...", "magnifyingglass"),
        ("scripting", "Writing script...", "pencil.line"),
        ("footage", "Finding footage...", "film"),
        ("rendering", "Rendering video...", "film.stack"),
        ("done", "Done!", "checkmark.circle.fill"),
    ]

    static let reelSteps: [(key: String, label: String, icon: String)] = [
        ("starting", "Starting AI model...", "cpu"),
        ("processing", "Generating video...", "wand.and.stars"),
        ("enhancing", "Enhancing quality...", "sparkles"),
        ("audio", "Mixing audio...", "waveform"),
        ("done", "Done!", "checkmark.circle.fill"),
    ]

    static let exportSteps: [(key: String, label: String, icon: String)] = [
        ("preparing", "Preparing clips...", "doc.on.doc"),
        ("rendering", "Rendering video...", "film.stack"),
        ("saving", "Saving...", "square.and.arrow.down"),
        ("done", "Done!", "checkmark.circle.fill"),
    ]

    let generationType: GenerationType

    var steps: [(key: String, label: String, icon: String)] {
        switch generationType {
        case .api: return Self.apiSteps
        case .reel: return Self.reelSteps
        case .export: return Self.exportSteps
        }
    }

    init(generationId: String, title: String, isLocalExport: Bool = false, generationType: GenerationType? = nil) {
        self.generationId = generationId
        self.title = title
        self.isLocalExport = isLocalExport
        self.generationType = generationType ?? (isLocalExport ? .export : .api)
    }

    func startPolling() {
        startStepProgression()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkStatus()
            }
        }

        Task { await checkStatus() }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        stepTimers.forEach { $0.invalidate() }
        stepTimers.removeAll()
    }

    private func checkStatus() async {
        let response: GenerationStatusResponse
        if isLocalExport || generationType == .reel {
            response = GenerationService.shared.getLocalGenerationStatus(id: generationId)
        } else {
            do {
                response = try await GenerationService.shared.getGenerationStatus(id: generationId)
            } catch {
                return // Keep polling
            }
        }

        if response.status == "completed", let url = response.resultVideoUrl {
            status = "completed"
            videoUrl = url
            currentStep = steps.count - 1
            stopPolling()
        } else if response.status == "failed" {
            status = "failed"
            error = response.error ?? "Export failed"
            stopPolling()
        }
    }

    func setupResultPlayer(url: URL) {
        guard resultPlayer == nil else { return }
        let player = AVPlayer(url: url)
        resultPlayer = player
        player.play()

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }

    private func startStepProgression() {
        guard status == "processing" else { return }

        let delays: [TimeInterval] = isLocalExport
            ? [2, 5, 12]
            : [3, 8, 15, 25]

        for (i, delay) in delays.enumerated() {
            let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    if self?.status == "processing" && (self?.currentStep ?? 0) <= i {
                        self?.currentStep = i + 1
                    }
                }
            }
            stepTimers.append(timer)
        }
    }
}
