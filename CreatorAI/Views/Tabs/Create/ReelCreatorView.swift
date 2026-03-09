import SwiftUI

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

            // Language
            SectionLabel("LANGUAGE")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(LANGUAGES) { lang in
                        Button {
                            viewModel.reelLang = lang.id
                        } label: {
                            HStack(spacing: 6) {
                                Text(flagEmoji(lang.flag))
                                    .font(.system(size: 16))
                                Text(lang.label)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(viewModel.reelLang == lang.id ? theme.primary.opacity(0.08) : theme.surfaceElevated)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(viewModel.reelLang == lang.id ? theme.primary : theme.border, lineWidth: 1.5)
                                    )
                            )
                            .foregroundColor(viewModel.reelLang == lang.id ? theme.primary : theme.text)
                        }
                    }
                }
            }
            .padding(.bottom, 20)

            // Duration
            SectionLabel("DURATION")
            HStack(spacing: 10) {
                ForEach(REEL_DURATIONS) { d in
                    Button {
                        viewModel.reelDuration = d.value
                    } label: {
                        VStack(spacing: 2) {
                            Text(d.label)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(viewModel.reelDuration == d.value ? theme.primary : theme.text)
                            Text(d.desc)
                                .font(.system(size: 12))
                                .foregroundColor(theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(viewModel.reelDuration == d.value ? theme.primary.opacity(0.08) : theme.surfaceElevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(viewModel.reelDuration == d.value ? theme.primary : theme.border, lineWidth: 1.5)
                                )
                        )
                    }
                }
            }
            .padding(.bottom, 24)

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

    private func flagEmoji(_ code: String) -> String {
        let base: UInt32 = 127397
        return code.unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }.map { String($0) }.joined()
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
