import UIKit

/// Semantic color roles used throughout Wellnario's dark, Peakwatch-inspired UI.
///
/// Feature code should use these roles instead of literal colors so increased
/// contrast and reduced-transparency behavior remains consistent.
@MainActor
enum WellnarioPalette {
    static let background = UIColor(hex: 0x050507)
    static let surface = UIColor(hex: 0x19191D)
    static let surfaceElevated = UIColor(hex: 0x222229)
    static let surfacePressed = UIColor(hex: 0x2A2A32)
    static let fieldBackground = UIColor(hex: 0x222229)

    static let textPrimary = UIColor(hex: 0xF7F7FA)
    static let textSecondary = UIColor(hex: 0xB0B0BA)
    static let textTertiary = UIColor(hex: 0x8B8B95)
    static let textDisabled = UIColor(hex: 0x5D5D66)

    static let cyan = UIColor(hex: 0x40DCE6)
    static let violet = UIColor(hex: 0x806CFF)
    static let magenta = UIColor(hex: 0xD94EEC)
    static let pink = UIColor(hex: 0xFF3E7D)

    static let success = UIColor(hex: 0x66E26F)
    static let warning = UIColor(hex: 0xFFB44D)
    static let danger = UIColor(hex: 0xFF5C72)
    static let information = UIColor(hex: 0x5BA7FF)

    static var hairline: UIColor {
        UIColor.white.withAlphaComponent(UIAccessibility.isDarkerSystemColorsEnabled ? 0.18 : 0.08)
    }

    static var cardTopHighlight: UIColor {
        UIColor.white.withAlphaComponent(UIAccessibility.isDarkerSystemColorsEnabled ? 0.14 : 0.06)
    }

    static var glassSurface: UIColor {
        UIAccessibility.isReduceTransparencyEnabled
            ? UIColor(hex: 0x202025)
            : UIColor(hex: 0x202025, alpha: 0.86)
    }

    static let signatureGradient = [cyan, violet, magenta, pink]
    static let surfaceGradient = [UIColor(hex: 0x202024), surface]

    static func color(for tone: WellnarioTone) -> UIColor {
        switch tone {
        case .neutral: textSecondary
        case .accent: cyan
        case .success: success
        case .warning: warning
        case .danger: danger
        case .information: information
        }
    }
}

/// A semantic tone shared by badges, metric cards and feedback components.
enum WellnarioTone: Sendable {
    case neutral
    case accent
    case success
    case warning
    case danger
    case information
}

/// Spacing values follow a four-point rhythm.
enum WellnarioSpacing {
    static let xxxSmall: CGFloat = 4
    static let xxSmall: CGFloat = 8
    static let xSmall: CGFloat = 12
    static let small: CGFloat = 16
    static let medium: CGFloat = 20
    static let large: CGFloat = 24
    static let xLarge: CGFloat = 32
    static let xxLarge: CGFloat = 40

    static let screenHorizontal: CGFloat = 20
    static let cardPadding: CGFloat = 20
    static let cardGap: CGFloat = 14
    static let bottomNavigationInset: CGFloat = 104
}

enum WellnarioRadius {
    static let small: CGFloat = 10
    static let control: CGFloat = 14
    static let button: CGFloat = 16
    static let card: CGFloat = 24
    static let floatingBar: CGFloat = 36
}

enum WellnarioLayout {
    static let minimumTouchTarget: CGFloat = 44
    static let fieldMinimumHeight: CGFloat = 56
    static let primaryButtonHeight: CGFloat = 52
    static let floatingTabBarHeight: CGFloat = 72
    static let metricCardMinimumHeight: CGFloat = 172
    static let insightCardMinimumHeight: CGFloat = 138
}

/// Motion constants and helpers that automatically honor Reduce Motion.
@MainActor
enum WellnarioMotion {
    static let quick: TimeInterval = 0.12
    static let standard: TimeInterval = 0.28
    static let emphasized: TimeInterval = 0.42

    static var animationsEnabled: Bool { !UIAccessibility.isReduceMotionEnabled }

    static func animate(
        duration: TimeInterval = standard,
        delay: TimeInterval = 0,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard animationsEnabled else {
            UIView.performWithoutAnimation(animations)
            completion?(true)
            return
        }

        UIView.animate(
            withDuration: duration,
            delay: delay,
            options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState],
            animations: animations,
            completion: completion
        )
    }

    static func spring(
        duration: TimeInterval = standard,
        delay: TimeInterval = 0,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard animationsEnabled else {
            UIView.performWithoutAnimation(animations)
            completion?(true)
            return
        }

        UIView.animate(
            withDuration: duration,
            delay: delay,
            usingSpringWithDamping: 0.82,
            initialSpringVelocity: 0.35,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: animations,
            completion: completion
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
