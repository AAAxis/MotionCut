import SwiftUI

// MARK: - Fox / Firefox-inspired palette
struct AppColors {
    let isDark: Bool

    // Fox dark: #1C1B22, #2B2A33; light: white / off-white
    var background: Color { isDark ? Color(hex: "#1C1B22") : Color.white }
    var surface: Color { isDark ? Color(hex: "#2B2A33") : Color.white }
    var surfaceElevated: Color { isDark ? Color(hex: "#38383D") : Color(hex: "#F5F5F7") }

    var text: Color { isDark ? Color.white : Color(hex: "#0C0C0D") }
    var textSecondary: Color { isDark ? Color.white.opacity(0.75) : Color(hex: "#4E4E52") }
    var textTertiary: Color { isDark ? Color.white.opacity(0.55) : Color(hex: "#737373") }

    // Fox orange (primary)
    var primary: Color { Color(hex: "#FF7139") }
    var primaryDark: Color { isDark ? Color(hex: "#FF8A5C") : Color(hex: "#FF7139") }

    // Fox blue (accent)
    var foxBlue: Color { Color(hex: "#0060DF") }

    var border: Color { isDark ? Color(hex: "#38383D") : Color(hex: "#D7D7DB") }
    var borderLight: Color { isDark ? Color(hex: "#2B2A33") : Color(hex: "#EDEDF0") }
    var separator: Color { isDark ? Color(hex: "#38383D") : Color(hex: "#D7D7DB") }

    var inputBackground: Color { isDark ? Color(hex: "#38383D") : Color(hex: "#F0F0F4") }
    var inputBackgroundFocused: Color { isDark ? Color(hex: "#42424D") : Color(hex: "#E8E8EC") }
    var placeholder: Color { isDark ? Color.white.opacity(0.4) : Color(hex: "#737373") }

    var cardBackground: Color { isDark ? Color(hex: "#2B2A33") : Color.white }
    var cardBorder: Color { isDark ? Color(hex: "#38383D") : Color(hex: "#EDEDF0") }

    var buttonSecondary: Color { isDark ? Color(hex: "#38383D") : Color(hex: "#FFF4EE") }
    var buttonSecondaryText: Color { isDark ? Color.white : Color(hex: "#FF7139") }

    var success: Color { Color(hex: "#12BC00") }
    var warning: Color { Color(hex: "#FFBF00") }
    var error: Color { Color(hex: "#D70022") }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct ThemeKey: EnvironmentKey {
    static let defaultValue = AppColors(isDark: false)
}

extension EnvironmentValues {
    var theme: AppColors {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
