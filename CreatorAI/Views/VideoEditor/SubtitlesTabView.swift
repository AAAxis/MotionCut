import SwiftUI

struct SubtitlesTabView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme
    private let subtitleFonts = ["System", "Rounded", "Serif", "Avenir Next", "Helvetica Neue", "Georgia"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Subtitles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(theme.text)

            Text("Edit the text for each clip. Subtitles can be burned into the video on export.")
                .font(.system(size: 13))
                .foregroundColor(theme.textSecondary)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Burn subtitles")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(theme.text)
                    Text("Add captions overlay when exporting")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textSecondary)
                }

                HStack(spacing: 8) {
                    captionChip("Off", isSelected: !viewModel.addCaptionsViaCloud) {
                        viewModel.setCaptionsViaCloud(false)
                    }
                    captionChip("On", isSelected: viewModel.addCaptionsViaCloud) {
                        viewModel.setCaptionsViaCloud(true)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 8)

            if viewModel.clips.isEmpty {
                Text("No clips.")
                    .font(.system(size: 14))
                    .foregroundColor(theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(Array(viewModel.clips.enumerated()), id: \.element.id) { index, clip in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .top, spacing: 12) {
                                        Text("\(index + 1)")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(theme.primary)
                                            .frame(width: 24, height: 24)
                                            .background(Circle().fill(theme.primary.opacity(0.12)))

                                        TextField("Subtitle text...", text: Binding(
                                            get: { viewModel.clips[index].text ?? "" },
                                            set: { viewModel.updateText(for: index, text: $0) }
                                        ), axis: .vertical)
                                        .font(editorFont(for: clip.textFontName, size: 15))
                                        .foregroundColor(theme.text)
                                        .lineLimit(1...4)

                                        Spacer(minLength: 0)
                                    }

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(subtitleFonts, id: \.self) { font in
                                                fontChip(font, isSelected: clip.textFontName == font) {
                                                    viewModel.updateTextFont(for: index, fontName: font)
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(theme.surfaceElevated)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(index == viewModel.activeClipIndex ? theme.primary : theme.border, lineWidth: index == viewModel.activeClipIndex ? 1.5 : 1)
                                        )
                                )
                                .id(clip.id)
                            }
                        }
                    }
                    .onAppear {
                        if viewModel.clips.indices.contains(viewModel.activeClipIndex) {
                            proxy.scrollTo(viewModel.clips[viewModel.activeClipIndex].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func captionChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? .white : theme.text)
                .frame(minWidth: 58)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? theme.primary : theme.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? theme.primary : theme.border, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func fontChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(editorFont(for: title, size: 12).weight(.semibold))
                .foregroundColor(isSelected ? .white : theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? theme.primary : theme.surface)
                        .overlay(Capsule().stroke(isSelected ? theme.primary : theme.border, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    private func editorFont(for name: String, size: CGFloat) -> Font {
        switch name {
        case "Rounded":
            return .system(size: size, weight: .semibold, design: .rounded)
        case "Serif":
            return .system(size: size, weight: .semibold, design: .serif)
        case "Avenir Next":
            return .custom("AvenirNext-DemiBold", size: size)
        case "Helvetica Neue":
            return .custom("HelveticaNeue-Bold", size: size)
        case "Georgia":
            return .custom("Georgia-Bold", size: size)
        default:
            return .system(size: size, weight: .semibold)
        }
    }
}
