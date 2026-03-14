import SwiftUI

struct Theme {
    // Scribe Color Palette
    static let obsidian = Color(red: 0.1, green: 0.1, blue: 0.11)
    static let cardBackgroundLight = Color.white
    static let cardBackgroundDark = Color(red: 0.15, green: 0.15, blue: 0.16)
    static let scribeRed = Color(red: 0.9, green: 0.2, blue: 0.2)
    static let accentGray = Color.gray.opacity(0.3)
    
    // Values
    static let cornerRadius: CGFloat = 20.0
    static let shadowRadius: CGFloat = 10.0
    static let shadowOpacityLight: Double = 0.05
    static let shadowOpacityDark: Double = 0.2
    
    // Helper to get card background based on scheme
    static func cardBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? cardBackgroundDark : cardBackgroundLight
    }
}

extension View {
    func scribeCardStyle(scheme: ColorScheme) -> some View {
        self
            .padding()
            .background(Theme.cardBackground(for: scheme))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(scheme == .dark ? Theme.shadowOpacityDark : Theme.shadowOpacityLight),
                    radius: Theme.shadowRadius,
                    x: 0,
                    y: 4)
    }
}
