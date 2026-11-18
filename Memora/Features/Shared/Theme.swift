//
//  Theme.swift
//  Memora
//
//  The visual identity: a dark, elegant palette (blue-black background,
//  comfortable card contrast, soft accents) with the rounded system font for
//  long, comfortable study sessions.
//

import SwiftUI

public extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum Theme {
    // Surfaces
    static let background = Color(hex: 0x0E1117)     // negro azulado
    static let surface = Color(hex: 0x161B22)
    static let surfaceElevated = Color(hex: 0x1D2430)
    static let stroke = Color(hex: 0x2A3340)

    // Text
    static let textPrimary = Color(hex: 0xF2F4F8)
    static let textSecondary = Color(hex: 0x98A2B3)
    static let textTertiary = Color(hex: 0x6B7685)

    // Accent
    static let accent = Color(hex: 0x7C88FF)
    static let accentSoft = Color(hex: 0x7C88FF, alpha: 0.18)

    // Ratings
    static let again = Color(hex: 0xFF6B6B)
    static let hard = Color(hex: 0xFFB454)
    static let good = Color(hex: 0x51CF66)
    static let easy = Color(hex: 0x4DABF7)

    // States
    static let newCard = Color(hex: 0x4DABF7)
    static let learnCard = Color(hex: 0xFF8787)
    static let reviewCard = Color(hex: 0x51CF66)

    static let cornerRadius: CGFloat = 16
    static let smallRadius: CGFloat = 10

    static func ratingColor(_ rating: Rating) -> Color {
        switch rating {
        case .again: return again
        case .hard: return hard
        case .good: return good
        case .easy: return easy
        }
    }
}

/// A rounded card container used across the app.
struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
    }
}

extension View {
    /// Apply the Memora look: rounded font + dark scheme.
    func memoraStyle() -> some View {
        self.fontDesign(.rounded)
            .tint(Theme.accent)
            .preferredColorScheme(.dark)
    }
}
