import SwiftUI
import UIKit

/// Dismisses the keyboard (resign first responder).
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

extension View {
    func cardStyle(_ theme: AppColors) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(theme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(theme.cardBorder, lineWidth: 1)
                    )
            )
    }

    func primaryButton(_ theme: AppColors) -> some View {
        self
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(theme.primary)
            )
    }
}
