import UIKit

enum WellnarioAppearanceMode: String, CaseIterable, Sendable {
    case dark
    case light
    case system

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: .unspecified
        }
    }
}

@MainActor
final class WellnarioAppearanceManager {
    static let shared = WellnarioAppearanceManager()
    static let didChangeNotification = Notification.Name("wellnario.appearance.didChange")

    private static let preferenceKey = "wellnario.appearance.mode"
    private let defaults: UserDefaults
    private(set) var mode: WellnarioAppearanceMode

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Self.preferenceKey)
            .flatMap(WellnarioAppearanceMode.init(rawValue:))
            ?? .dark
    }

    func setMode(_ mode: WellnarioAppearanceMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        defaults.set(mode.rawValue, forKey: Self.preferenceKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    func apply(to window: UIWindow) {
        window.overrideUserInterfaceStyle = mode.interfaceStyle
    }
}

/// Semantic color roles used throughout Wellnario in light and dark appearances.
///
/// Feature code should use these roles instead of literal colors so increased
/// contrast and reduced-transparency behavior remains consistent.
@MainActor
enum WellnarioPalette {
    static let background = adaptive(light: 0xF6F6FA, dark: 0x050507)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x19191D)
    static let surfaceElevated = adaptive(light: 0xEEEEF4, dark: 0x222229)
    static let surfacePressed = adaptive(light: 0xE3E3EB, dark: 0x2A2A32)
    static let fieldBackground = adaptive(light: 0xF0F0F5, dark: 0x222229)

    static let textPrimary = adaptive(light: 0x17171D, dark: 0xF7F7FA)
    static let textSecondary = adaptive(light: 0x555560, dark: 0xB0B0BA)
    static let textTertiary = adaptive(light: 0x73737F, dark: 0x8B8B95)
    static let textDisabled = adaptive(light: 0xA0A0AA, dark: 0x5D5D66)
    static let onAccent = UIColor.white

    static let cyan = adaptive(light: 0x007F8C, dark: 0x40DCE6)
    static let violet = adaptive(light: 0x6852E5, dark: 0x806CFF)
    static let fuchsia = adaptive(light: 0xB72BC9, dark: 0xD94EEC)
    static let magenta = fuchsia
    static let pink = adaptive(light: 0xD91F5C, dark: 0xFF3E7D)

    static let success = adaptive(light: 0x238A31, dark: 0x66E26F)
    static let warning = adaptive(light: 0xA85F00, dark: 0xFFB44D)
    static let yellow = adaptive(light: 0x8A6C00, dark: 0xFFD84D)
    static let orange = adaptive(light: 0xC45B00, dark: 0xFF8A3D)
    static let danger = adaptive(light: 0xC72F48, dark: 0xFF5C72)
    static let information = adaptive(light: 0x256EC4, dark: 0x5BA7FF)
    static let synchronizationBannerOpacity: CGFloat = 0.45

    static var hairline: UIColor {
        adaptive(
            light: 0x111118,
            dark: 0xFFFFFF,
            alpha: UIAccessibility.isDarkerSystemColorsEnabled ? 0.18 : 0.09
        )
    }

    static var cardTopHighlight: UIColor {
        adaptive(
            light: 0x111118,
            dark: 0xFFFFFF,
            alpha: UIAccessibility.isDarkerSystemColorsEnabled ? 0.16 : 0.07
        )
    }

    static var glassSurface: UIColor {
        adaptive(
            light: 0xFFFFFF,
            dark: 0x202025,
            lightAlpha: UIAccessibility.isReduceTransparencyEnabled ? 1 : 0.88,
            darkAlpha: UIAccessibility.isReduceTransparencyEnabled ? 1 : 0.86
        )
    }

    static let signatureGradient = [cyan, violet, magenta, pink]
    static let surfaceGradient = [
        adaptive(light: 0xFFFFFF, dark: 0x202024),
        adaptive(light: 0xF1F1F6, dark: 0x19191D)
    ]

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

    private static func adaptive(
        light: UInt32,
        dark: UInt32,
        alpha: CGFloat = 1
    ) -> UIColor {
        adaptive(
            light: light,
            dark: dark,
            lightAlpha: alpha,
            darkAlpha: alpha
        )
    }

    private static func adaptive(
        light: UInt32,
        dark: UInt32,
        lightAlpha: CGFloat,
        darkAlpha: CGFloat
    ) -> UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                UIColor(hex: dark, alpha: darkAlpha)
            } else {
                UIColor(hex: light, alpha: lightAlpha)
            }
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
