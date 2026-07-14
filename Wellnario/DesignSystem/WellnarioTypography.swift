import UIKit

/// Named typography styles backed by Dynamic Type.
enum WellnarioTextStyle: Sendable {
    case date
    case pageTitle
    case cardTitle
    case metric
    case summaryTitle
    case summaryMetric
    case summaryDetail
    case sectionTitle
    case body
    case secondary
    case caption
    case tab
    case button
}

enum WellnarioTypography {
    static func font(for style: WellnarioTextStyle) -> UIFont {
        switch style {
        case .date:
            scaledFont(size: 34, weight: .semibold, textStyle: .largeTitle)
        case .pageTitle:
            scaledFont(size: 28, weight: .bold, textStyle: .title1)
        case .cardTitle:
            scaledFont(size: 20, weight: .semibold, textStyle: .title3)
        case .metric:
            scaledFont(size: 36, weight: .bold, textStyle: .largeTitle, design: .rounded, tabular: true)
        case .summaryTitle:
            scaledFont(size: 15, weight: .semibold, textStyle: .subheadline)
        case .summaryMetric:
            scaledFont(size: 26, weight: .bold, textStyle: .title2, design: .rounded, tabular: true)
        case .summaryDetail:
            scaledFont(size: 11, weight: .medium, textStyle: .caption2)
        case .sectionTitle:
            scaledFont(size: 18, weight: .semibold, textStyle: .headline)
        case .body:
            scaledFont(size: 16, weight: .regular, textStyle: .body)
        case .secondary:
            scaledFont(size: 15, weight: .regular, textStyle: .subheadline)
        case .caption:
            scaledFont(size: 13, weight: .medium, textStyle: .caption1)
        case .tab:
            scaledFont(size: 11, weight: .semibold, textStyle: .caption2)
        case .button:
            scaledFont(size: 16, weight: .semibold, textStyle: .headline)
        }
    }

    private static func scaledFont(
        size: CGFloat,
        weight: UIFont.Weight,
        textStyle: UIFont.TextStyle,
        design: UIFontDescriptor.SystemDesign = .default,
        tabular: Bool = false
    ) -> UIFont {
        let base: UIFont
        if tabular {
            base = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        } else {
            base = UIFont.systemFont(ofSize: size, weight: weight)
        }

        let descriptor = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
        let designedFont = UIFont(descriptor: descriptor, size: size)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: designedFont)
    }
}

extension UILabel {
    /// Applies a semantic Wellnario font and keeps it synchronized with Dynamic Type.
    func applyWellnarioStyle(_ style: WellnarioTextStyle, color: UIColor? = nil) {
        font = WellnarioTypography.font(for: style)
        adjustsFontForContentSizeCategory = true
        if let color {
            textColor = color
        }
    }
}
