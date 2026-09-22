#if os(macOS)
import SwiftUI
import AppKit

/// ARCHITER design language (0.3.0): dark tabletop theme, 4pt spacing grid,
/// serif display type, brass accent. Semantic tokens only - views never
/// hardcode colors or sizes.

public enum Theme {

    // MARK: - Color palette (dark "ink and brass" tabletop theme)

    public static let ink = Color(red: 0.93, green: 0.90, blue: 0.84)          // parchment text
    public static let inkMuted = Color(red: 0.62, green: 0.60, blue: 0.56)
    public static let inkFaint = Color(red: 0.45, green: 0.44, blue: 0.41)
    public static let surface = Color(red: 0.11, green: 0.10, blue: 0.13)      // app background
    public static let surfaceRaised = Color(red: 0.16, green: 0.15, blue: 0.19) // cards
    public static let surfaceInset = Color(red: 0.08, green: 0.075, blue: 0.10) // wells/fields
    public static let edge = Color(red: 0.28, green: 0.26, blue: 0.31)          // hairline borders
    public static let accent = Color(red: 0.83, green: 0.62, blue: 0.28)        // brass
    public static let accentSoft = Color(red: 0.83, green: 0.62, blue: 0.28).opacity(0.18)
    public static let danger = Color(red: 0.85, green: 0.36, blue: 0.32)
    public static let success = Color(red: 0.48, green: 0.75, blue: 0.44)
    public static let arcana = Color(red: 0.62, green: 0.52, blue: 0.87)        // spellcasting violet

    // MARK: - Type scale

    public enum Typeface {
        public static let display = Font.system(size: 30, weight: .semibold, design: .serif)
        public static let title = Font.system(size: 20, weight: .semibold, design: .serif)
        public static let headline = Font.system(size: 13, weight: .semibold, design: .default)
        public static let body = Font.system(size: 12, weight: .regular, design: .default)
        public static let caption = Font.system(size: 10.5, weight: .regular, design: .default)
        public static let captionSmall = Font.system(size: 9.5, weight: .regular, design: .default)
        public static let statBig = Font.system(size: 24, weight: .bold, design: .rounded)
        public static let statLabel = Font.system(size: 9.5, weight: .semibold, design: .default)
    }

    // MARK: - Spacing (4pt grid)

    public enum Gap {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
    }

    public enum Radius {
        public static let sm: CGFloat = 5
        public static let md: CGFloat = 8
        public static let lg: CGFloat = 12
    }
}
#endif
