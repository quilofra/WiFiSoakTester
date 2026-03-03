import SwiftUI

enum ThemePreset: String, CaseIterable, Identifiable, Codable {
    case ocean = "Ocean"
    case sunset = "Sunset"
    case studio = "Studio"

    var id: String { rawValue }
}

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case enhanced = "Ahora (Color)"
    case classic = "Antes (Sin color)"

    var id: String { rawValue }
}

struct ThemePalette: Sendable {
    let cyan: Color
    let sky: Color
    let mint: Color
    let amber: Color
    let coral: Color
    let indigo: Color
}

enum VisualTheme {
    static let monochrome = ThemePalette(
        cyan: Color(white: 0.68),
        sky: Color(white: 0.62),
        mint: Color(white: 0.56),
        amber: Color(white: 0.50),
        coral: Color(white: 0.45),
        indigo: Color(white: 0.40)
    )

    static let ocean = ThemePalette(
        cyan: Color(red: 0.14, green: 0.74, blue: 0.94),
        sky: Color(red: 0.28, green: 0.56, blue: 0.97),
        mint: Color(red: 0.19, green: 0.80, blue: 0.66),
        amber: Color(red: 0.96, green: 0.67, blue: 0.24),
        coral: Color(red: 0.94, green: 0.39, blue: 0.34),
        indigo: Color(red: 0.33, green: 0.45, blue: 0.90)
    )

    static let sunset = ThemePalette(
        cyan: Color(red: 0.95, green: 0.47, blue: 0.42),
        sky: Color(red: 0.95, green: 0.61, blue: 0.31),
        mint: Color(red: 0.75, green: 0.44, blue: 0.96),
        amber: Color(red: 0.99, green: 0.78, blue: 0.35),
        coral: Color(red: 0.98, green: 0.35, blue: 0.46),
        indigo: Color(red: 0.45, green: 0.37, blue: 0.97)
    )

    static let studio = ThemePalette(
        cyan: Color(red: 0.34, green: 0.60, blue: 0.90),
        sky: Color(red: 0.41, green: 0.52, blue: 0.72),
        mint: Color(red: 0.33, green: 0.66, blue: 0.66),
        amber: Color(red: 0.73, green: 0.62, blue: 0.43),
        coral: Color(red: 0.72, green: 0.45, blue: 0.46),
        indigo: Color(red: 0.37, green: 0.45, blue: 0.65)
    )

    static func palette(for preset: ThemePreset) -> ThemePalette {
        switch preset {
        case .ocean:
            return ocean
        case .sunset:
            return sunset
        case .studio:
            return studio
        }
    }
}
