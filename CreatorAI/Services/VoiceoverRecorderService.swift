import AVFoundation

/// Records voiceover audio from the microphone and saves to a local file.
final class VoiceoverRecorderService: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = VoiceoverRecorderService()

    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var recordedFileURL: URL?
    @Published var permissionDenied = false

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    private override init() {
        super.init()
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        #else
        // macOS: use AVCaptureDevice permission
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        #endif
    }

    // MARK: - Recording

    func startRecording() async -> Bool {
        let granted = await requestPermission()
        guard granted else {
            await MainActor.run { permissionDenied = true }
            return false
        }

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[Voiceover] Audio session setup failed: \(error)")
            return false
        }
        #endif

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voiceover-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            let audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder.delegate = self
            audioRecorder.record()
            self.recorder = audioRecorder

            await MainActor.run {
                self.isRecording = true
                self.recordingDuration = 0
                self.recordedFileURL = nil
            }

            await MainActor.run {
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    guard let self, let rec = self.recorder, rec.isRecording else { return }
                    self.recordingDuration = rec.currentTime
                }
            }

            return true
        } catch {
            print("[Voiceover] Recorder init failed: \(error)")
            return false
        }
    }

    func stopRecording() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()

        if let url = recorder?.url, FileManager.default.fileExists(atPath: url.path) {
            recordedFileURL = url
        }

        isRecording = false

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    func deleteRecording() {
        if let url = recordedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordedFileURL = nil
        recordingDuration = 0
    }

    // MARK: - AVAudioRecorderDelegate

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("[Voiceover] Recording finished unsuccessfully")
        }
    }
}
