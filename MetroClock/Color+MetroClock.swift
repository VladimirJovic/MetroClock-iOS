import SwiftUI
import UIKit

// MARK: - Hex initializer (Color)
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red:     Double(r) / 255,
                  green:   Double(g) / 255,
                  blue:    Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: - Hex initializer (UIColor)
extension UIColor {
    convenience init(hex: String) {
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
        self.init(red:   CGFloat(r) / 255,
                  green: CGFloat(g) / 255,
                  blue:  CGFloat(b) / 255,
                  alpha: CGFloat(a) / 255)
    }
}

// MARK: - Adaptive Precision Design Tokens
//
//  Dark mode  →  existing Precision palette
//  Light mode →  clean, bright counterparts
//
extension Color {

    /// Backgrounds
    /// Dark:  #07070A  |  Light: #F2F2F7
    static var mcBackground: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "07070A")
                : UIColor(hex: "F2F2F7")
        })
    }

    /// Cards, chips, surface elements
    /// Dark:  #0D0D13  |  Light: #FFFFFF
    static var mcSurface: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "0D0D13")
                : UIColor(hex: "FFFFFF")
        })
    }

    /// Hairline borders
    /// Dark:  #181820  |  Light: #E5E5EA
    static var mcBorder: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "181820")
                : UIColor(hex: "E5E5EA")
        })
    }

    /// Primary accent — same in both modes
    static let mcOrange = Color(hex: "EA4500")

    /// Primary text (white on dark, near-black on light)
    /// Dark:  #FFFFFF  |  Light: #1C1C1E
    static var mcText: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "FFFFFF")
                : UIColor(hex: "1C1C1E")
        })
    }

    /// Secondary text
    /// Dark:  #888899  |  Light: #6E6E73
    static var mcTextSecondary: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "888899")
                : UIColor(hex: "6E6E73")
        })
    }

    /// Tertiary text / captions
    /// Dark:  #555566  |  Light: #8E8E93
    static var mcTextTertiary: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "555566")
                : UIColor(hex: "8E8E93")
        })
    }

    /// Faint text / dates
    /// Dark:  #3A3A4A  |  Light: #AEAEB2
    static var mcTextFaint: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "3A3A4A")
                : UIColor(hex: "AEAEB2")
        })
    }

    /// Tab bar top border
    /// Dark:  #101018  |  Light: #D1D1D6
    static var mcTabBorder: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "101018")
                : UIColor(hex: "D1D1D6")
        })
    }
}
