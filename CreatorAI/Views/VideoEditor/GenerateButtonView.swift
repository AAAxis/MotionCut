import SwiftUI

struct GenerateButtonView: View {
    let label: String
    let isGenerating: Bool
    let isSaved: Bool
    let action: () -> Void

    @Environment(\.theme) var theme

    init(label: String, isGenerating: Bool, isSaved: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.isGenerating = isGenerating
        self.isSaved = isSaved
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView()
                        .tint(.white)
                    Text("Saving...")
                        .font(.system(size: 17, weight: .semibold))
                } else if isSaved {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                    Text("Saved!")
                        .font(.system(size: 17, weight: .semibold))
                } else {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 18))
                    Text(label)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSaved ? theme.success : theme.primary)
            )
            .opacity(isGenerating ? 0.7 : 1)
        }
        .disabled(isGenerating || isSaved)
    }
}
