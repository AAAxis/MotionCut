import SwiftUI
import PhotosUI

struct ReelCreatorView: View {
    @ObservedObject var viewModel: CreateViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Describe a concept -> get a viral POV reel in seconds.")
                .font(.system(size: 16))
                .foregroundColor(theme.textSecondary)
                .padding(.bottom, 24)

            // Topic Input
            SectionLabel("TOPIC / CONCEPT")
            TextEditor(text: $viewModel.reelTopic)
                .frame(minHeight: 80)
                .font(.system(size: 16))
                .foregroundColor(theme.text)
                .scrollContentBackground(.hidden)
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
                .overlay(alignment: .topLeading) {
                    if viewModel.reelTopic.isEmpty {
                        Text("e.g. traveling without eSIM, hustle culture, Monday motivation...")
                            .font(.system(size: 16))
                            .foregroundColor(theme.textTertiary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.bottom, 20)

            // Influencer / Avatar
            SectionLabel("INFLUENCER / AVATAR")
            AvatarPickerView(viewModel: viewModel)
                .padding(.bottom, 20)

            // Reference video (for movement)
            SectionLabel("REFERENCE VIDEO (copy movement)")
            ReferenceVideoPickerView(referenceVideoURL: $viewModel.reelReferenceVideoURL)
                .padding(.bottom, 20)



            // Progress Steps
            if viewModel.isLoading, let progress = viewModel.genProgress {
                VStack(spacing: 0) {
                    ForEach(ReelStep.allCases, id: \.rawValue) { step in
                        let currentIdx = ReelStep.allCases.firstIndex(of: currentReelStep(progress.step)) ?? 0
                        let thisIdx = ReelStep.allCases.firstIndex(of: step) ?? 0
                        let isActive = step.rawValue == progress.step
                        let isDone = thisIdx < currentIdx || progress.step == "done"
                        let isPending = thisIdx > currentIdx

                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(isDone ? theme.success.opacity(0.12) : isActive ? theme.primary.opacity(0.12) : theme.border.opacity(0.4))
                                    .frame(width: 32, height: 32)

                                if isDone {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(theme.success)
                                } else if isActive {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(theme.primary)
                                } else {
                                    Image(systemName: step.icon)
                                        .font(.system(size: 14))
                                        .foregroundColor(theme.textTertiary)
                                }
                            }

                            Text(isActive && step == .rendering ? progress.message : step.label)
                                .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                                .foregroundColor(isDone ? theme.success : isActive ? theme.text : theme.textTertiary)

                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .opacity(isPending ? 0.35 : 1)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(theme.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(theme.border, lineWidth: 1)
                        )
                )
                .padding(.bottom, 16)
            }

            // Generate Button
            Button {
                dismissKeyboard()
                Task {
                    if let params = await viewModel.generateReel(appState: appState) {
                        NotificationService.shared.requestPermissionIfNeeded()
                        _ = await BackgroundRenderService.shared.startExport(fromReelParams: params)
                        NotificationCenter.default.post(name: .switchToLibraryTab, object: nil)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                        Text(viewModel.genProgress?.message ?? "Generating...")
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
            }
            .disabled(viewModel.isLoading)
        }
    }

    private func currentReelStep(_ stepString: String) -> ReelStep {
        ReelStep(rawValue: stepString) ?? .scenario
    }
}

// MARK: - Reference Video Picker (for movement copy)

struct ReferenceVideoPickerView: View {
    @Binding var referenceVideoURL: URL?
    @Environment(\.theme) var theme
    @State private var selectedItem: PhotosPickerItem?
    @State private var thumbnailImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let url = referenceVideoURL {
                HStack(spacing: 12) {
                    if let img = thumbnailImage {
                        Image(uiImage: img)
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
                        selectedItem = nil
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
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
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
            }
        }
        .onChange(of: referenceVideoURL) { url in
            if let url = url, thumbnailImage == nil {
                loadThumbnail(for: url)
            }
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
}
