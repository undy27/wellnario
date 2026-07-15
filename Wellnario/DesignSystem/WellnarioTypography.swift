import UIKit

/// Named typography styles backed by Dynamic Type.
enum WellnarioTextStyle: Int, Sendable {
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
    static func font(
        for style: WellnarioTextStyle,
        compatibleWith traitCollection: UITraitCollection? = nil
    ) -> UIFont {
        switch style {
        case .date:
            scaledFont(size: 34, weight: .semibold, textStyle: .largeTitle, compatibleWith: traitCollection)
        case .pageTitle:
            scaledFont(size: 28, weight: .bold, textStyle: .title1, compatibleWith: traitCollection)
        case .cardTitle:
            scaledFont(size: 20, weight: .semibold, textStyle: .title3, compatibleWith: traitCollection)
        case .metric:
            scaledFont(
                size: 36,
                weight: .bold,
                textStyle: .largeTitle,
                design: .rounded,
                tabular: true,
                compatibleWith: traitCollection
            )
        case .summaryTitle:
            scaledFont(size: 15, weight: .semibold, textStyle: .subheadline, compatibleWith: traitCollection)
        case .summaryMetric:
            scaledFont(
                size: 26,
                weight: .bold,
                textStyle: .title2,
                design: .rounded,
                tabular: true,
                compatibleWith: traitCollection
            )
        case .summaryDetail:
            scaledFont(size: 11, weight: .medium, textStyle: .caption2, compatibleWith: traitCollection)
        case .sectionTitle:
            scaledFont(size: 18, weight: .semibold, textStyle: .headline, compatibleWith: traitCollection)
        case .body:
            scaledFont(size: 16, weight: .regular, textStyle: .body, compatibleWith: traitCollection)
        case .secondary:
            scaledFont(size: 15, weight: .regular, textStyle: .subheadline, compatibleWith: traitCollection)
        case .caption:
            scaledFont(size: 13, weight: .medium, textStyle: .caption1, compatibleWith: traitCollection)
        case .tab:
            scaledFont(size: 11, weight: .semibold, textStyle: .caption2, compatibleWith: traitCollection)
        case .button:
            scaledFont(size: 16, weight: .semibold, textStyle: .headline, compatibleWith: traitCollection)
        }
    }

    private static func scaledFont(
        size: CGFloat,
        weight: UIFont.Weight,
        textStyle: UIFont.TextStyle,
        design: UIFontDescriptor.SystemDesign = .default,
        tabular: Bool = false,
        compatibleWith traitCollection: UITraitCollection?
    ) -> UIFont {
        let base: UIFont
        if tabular {
            base = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        } else {
            base = UIFont.systemFont(ofSize: size, weight: weight)
        }

        let descriptor = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
        let designedFont = UIFont(descriptor: descriptor, size: size)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: designedFont,
            compatibleWith: traitCollection
        )
    }
}

@MainActor
private enum WellnarioTypographyRegistry {
    static let styles = NSMapTable<UILabel, NSNumber>(
        keyOptions: .weakMemory,
        valueOptions: .strongMemory
    )

    static func register(_ label: UILabel, style: WellnarioTextStyle) {
        styles.setObject(NSNumber(value: style.rawValue), forKey: label)
    }

    static func style(for label: UILabel) -> WellnarioTextStyle? {
        styles.object(forKey: label).flatMap { WellnarioTextStyle(rawValue: $0.intValue) }
    }
}

extension UILabel {
    /// Applies a semantic Wellnario font and keeps it synchronized with Dynamic Type.
    func applyWellnarioStyle(_ style: WellnarioTextStyle, color: UIColor? = nil) {
        WellnarioTypographyRegistry.register(self, style: style)
        font = WellnarioTypography.font(for: style, compatibleWith: traitCollection)
        adjustsFontForContentSizeCategory = true
        if let color {
            textColor = color
        }
    }

    fileprivate func refreshWellnarioStyle(compatibleWith traitCollection: UITraitCollection) {
        guard let style = WellnarioTypographyRegistry.style(for: self) else { return }
        font = WellnarioTypography.font(for: style, compatibleWith: traitCollection)
        invalidateIntrinsicContentSize()
    }
}

extension UIView {
    /// Reapplies semantic fonts in both Dynamic Type directions and redraws custom text views.
    func refreshWellnarioDynamicType(compatibleWith traitCollection: UITraitCollection? = nil) {
        let effectiveTraits = traitCollection ?? self.traitCollection
        (self as? UILabel)?.refreshWellnarioStyle(compatibleWith: effectiveTraits)
        setNeedsDisplay()
        invalidateIntrinsicContentSize()
        subviews.forEach { subview in
            subview.refreshWellnarioDynamicType(compatibleWith: traitCollection)
        }
        setNeedsLayout()
    }
}
