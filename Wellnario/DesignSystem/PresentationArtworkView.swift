import UIKit

/// Common supplement presentation types used by bundled vector artwork.
enum PresentationKind: String, CaseIterable, Sendable {
    case capsule
    case tablet
    case powder
    case liquid
    case gummy
    case sachet
    case other

    init(name: String) {
        let normalized = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        if normalized.contains("caps") { self = .capsule }
        else if normalized.contains("past") || normalized.contains("tabl") || normalized.contains("compr") { self = .tablet }
        else if normalized.contains("polv") || normalized.contains("powd") { self = .powder }
        else if normalized.contains("liq") || normalized.contains("got") || normalized.contains("drop") { self = .liquid }
        else if normalized.contains("gom") || normalized.contains("gumm") { self = .gummy }
        else if normalized.contains("sob") || normalized.contains("sach") { self = .sachet }
        else { self = .other }
    }

    var symbolName: String {
        switch self {
        case .capsule: "capsule.portrait.fill"
        case .tablet: "pills.fill"
        case .powder: "takeoutbag.and.cup.and.straw.fill"
        case .liquid: "drop.fill"
        case .gummy: "seal.fill"
        case .sachet: "shippingbox.fill"
        case .other: "sparkles"
        }
    }

    @MainActor var localizedName: String {
        L10n.text("presentation.\(rawValue)")
    }
}

/// Offline presentation artwork drawn entirely with Core Graphics. The view is
/// useful as a product placeholder, empty-state illustration or compact avatar.
final class PresentationArtworkView: UIView {
    var kind: PresentationKind = .capsule {
        didSet {
            accessibilityLabel = kind.localizedName
            setNeedsDisplay()
        }
    }

    var showsBackground = true {
        didSet { setNeedsDisplay() }
    }

    var primaryColor: UIColor = WellnarioPalette.cyan {
        didSet { setNeedsDisplay() }
    }

    var secondaryColor: UIColor = WellnarioPalette.violet {
        didSet { setNeedsDisplay() }
    }

    init(kind: PresentationKind = .capsule) {
        self.kind = kind
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 96, height: 96)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), !rect.isEmpty else { return }

        context.saveGState()
        if showsBackground { drawBackground(in: rect, context: context) }

        let artworkRect = rect.insetBy(dx: rect.width * 0.20, dy: rect.height * 0.20)
        switch kind {
        case .capsule: drawCapsule(in: artworkRect, context: context)
        case .tablet: drawTablet(in: artworkRect, context: context)
        case .powder: drawPowder(in: artworkRect, context: context)
        case .liquid: drawLiquid(in: artworkRect, context: context)
        case .gummy: drawGummy(in: artworkRect, context: context)
        case .sachet: drawSachet(in: artworkRect, context: context)
        case .other: drawSymbol(in: artworkRect)
        }
        context.restoreGState()
    }

    private func setUp() {
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityTraits = [.image]
        accessibilityLabel = kind.localizedName
    }

    private func drawBackground(in rect: CGRect, context: CGContext) {
        let insetRect = rect.insetBy(dx: 1, dy: 1)
        let path = UIBezierPath(roundedRect: insetRect, cornerRadius: min(rect.width, rect.height) * 0.28)
        context.saveGState()
        path.addClip()

        let colors = [
            primaryColor.withAlphaComponent(0.25).cgColor,
            secondaryColor.withAlphaComponent(0.10).cgColor,
            WellnarioPalette.surfaceElevated.cgColor
        ] as CFArray
        let locations: [CGFloat] = [0, 0.52, 1]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
            context.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: rect.width * 0.30, y: rect.height * 0.22),
                startRadius: 0,
                endCenter: CGPoint(x: rect.midX, y: rect.midY),
                endRadius: rect.width * 0.78,
                options: [.drawsAfterEndLocation]
            )
        }
        context.restoreGState()

        WellnarioPalette.hairline.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawCapsule(in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: -.pi / 4)
        let capsuleRect = CGRect(
            x: -rect.width * 0.19,
            y: -rect.height * 0.44,
            width: rect.width * 0.38,
            height: rect.height * 0.88
        )
        let capsulePath = UIBezierPath(roundedRect: capsuleRect, cornerRadius: capsuleRect.width / 2)
        capsulePath.addClip()

        primaryColor.setFill()
        UIRectFill(capsuleRect)
        secondaryColor.setFill()
        UIRectFill(CGRect(x: capsuleRect.minX, y: capsuleRect.midY, width: capsuleRect.width, height: capsuleRect.height / 2))

        UIColor.white.withAlphaComponent(0.34).setStroke()
        capsulePath.lineWidth = max(1, rect.width * 0.025)
        capsulePath.stroke()
        let seam = UIBezierPath()
        seam.move(to: CGPoint(x: capsuleRect.minX, y: capsuleRect.midY))
        seam.addLine(to: CGPoint(x: capsuleRect.maxX, y: capsuleRect.midY))
        seam.stroke()
        context.restoreGState()
    }

    private func drawTablet(in rect: CGRect, context: CGContext) {
        let diameter = min(rect.width, rect.height) * 0.72
        let circleRect = CGRect(
            x: rect.midX - diameter / 2,
            y: rect.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
        let circle = UIBezierPath(ovalIn: circleRect)
        secondaryColor.setFill()
        circle.fill()
        UIColor.white.withAlphaComponent(0.28).setStroke()
        circle.lineWidth = max(1, rect.width * 0.025)
        circle.stroke()

        let score = UIBezierPath()
        score.move(to: CGPoint(x: circleRect.minX + diameter * 0.18, y: circleRect.midY))
        score.addLine(to: CGPoint(x: circleRect.maxX - diameter * 0.18, y: circleRect.midY))
        score.lineWidth = max(2, rect.height * 0.045)
        score.lineCapStyle = .round
        UIColor.white.withAlphaComponent(0.66).setStroke()
        score.stroke()

        context.setShadow(offset: CGSize(width: 0, height: 4), blur: 8, color: UIColor.black.withAlphaComponent(0.25).cgColor)
    }

    private func drawPowder(in rect: CGRect, context: CGContext) {
        let bowlRect = CGRect(
            x: rect.minX + rect.width * 0.10,
            y: rect.midY,
            width: rect.width * 0.80,
            height: rect.height * 0.34
        )
        let bowl = UIBezierPath()
        bowl.move(to: bowlRect.origin)
        bowl.addQuadCurve(
            to: CGPoint(x: bowlRect.maxX, y: bowlRect.minY),
            controlPoint: CGPoint(x: bowlRect.midX, y: bowlRect.maxY + bowlRect.height * 0.25)
        )
        bowl.close()
        secondaryColor.setFill()
        bowl.fill()

        primaryColor.setStroke()
        bowl.lineWidth = max(2, rect.height * 0.05)
        bowl.lineCapStyle = .round
        bowl.stroke()

        let particleCenters = [
            CGPoint(x: rect.midX - rect.width * 0.22, y: rect.midY - rect.height * 0.17),
            CGPoint(x: rect.midX, y: rect.midY - rect.height * 0.25),
            CGPoint(x: rect.midX + rect.width * 0.22, y: rect.midY - rect.height * 0.12),
            CGPoint(x: rect.midX + rect.width * 0.07, y: rect.midY - rect.height * 0.04)
        ]
        for (index, center) in particleCenters.enumerated() {
            let size = rect.width * (index.isMultiple(of: 2) ? 0.09 : 0.07)
            let particle = UIBezierPath(ovalIn: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size))
            (index.isMultiple(of: 2) ? primaryColor : WellnarioPalette.magenta).setFill()
            particle.fill()
        }
    }

    private func drawLiquid(in rect: CGRect, context: CGContext) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.06))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.06),
            controlPoint1: CGPoint(x: rect.midX - rect.width * 0.54, y: rect.midY + rect.height * 0.18),
            controlPoint2: CGPoint(x: rect.midX - rect.width * 0.28, y: rect.maxY - rect.height * 0.02)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.06),
            controlPoint1: CGPoint(x: rect.midX + rect.width * 0.28, y: rect.maxY - rect.height * 0.02),
            controlPoint2: CGPoint(x: rect.midX + rect.width * 0.54, y: rect.midY + rect.height * 0.18)
        )
        path.close()
        primaryColor.setFill()
        path.fill()
        UIColor.white.withAlphaComponent(0.34).setStroke()
        path.lineWidth = max(1, rect.width * 0.025)
        path.stroke()

        let highlight = UIBezierPath(ovalIn: CGRect(
            x: rect.midX - rect.width * 0.19,
            y: rect.midY - rect.height * 0.05,
            width: rect.width * 0.12,
            height: rect.height * 0.22
        ))
        UIColor.white.withAlphaComponent(0.40).setFill()
        highlight.fill()
        _ = context
    }

    private func drawGummy(in rect: CGRect, context: CGContext) {
        let gummyRect = rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.15)
        let gummy = UIBezierPath(roundedRect: gummyRect, cornerRadius: gummyRect.width * 0.30)
        WellnarioPalette.magenta.setFill()
        gummy.fill()
        UIColor.white.withAlphaComponent(0.30).setStroke()
        gummy.lineWidth = max(1, rect.width * 0.025)
        gummy.stroke()

        let shine = UIBezierPath(roundedRect: CGRect(
            x: gummyRect.minX + gummyRect.width * 0.17,
            y: gummyRect.minY + gummyRect.height * 0.14,
            width: gummyRect.width * 0.22,
            height: gummyRect.height * 0.14
        ), cornerRadius: gummyRect.height * 0.07)
        UIColor.white.withAlphaComponent(0.42).setFill()
        shine.fill()
        _ = context
    }

    private func drawSachet(in rect: CGRect, context: CGContext) {
        let sachetRect = rect.insetBy(dx: rect.width * 0.14, dy: rect.height * 0.05)
        let sachet = UIBezierPath(roundedRect: sachetRect, cornerRadius: rect.width * 0.08)
        secondaryColor.setFill()
        sachet.fill()
        UIColor.white.withAlphaComponent(0.30).setStroke()
        sachet.lineWidth = max(1, rect.width * 0.025)
        sachet.stroke()

        primaryColor.setStroke()
        let band = UIBezierPath()
        band.move(to: CGPoint(x: sachetRect.minX, y: sachetRect.midY))
        band.addLine(to: CGPoint(x: sachetRect.maxX, y: sachetRect.midY))
        band.lineWidth = rect.height * 0.16
        band.stroke()

        for fraction in stride(from: CGFloat(0.12), through: 0.88, by: 0.12) {
            let x = sachetRect.minX + sachetRect.width * fraction
            let notch = UIBezierPath()
            notch.move(to: CGPoint(x: x, y: sachetRect.minY))
            notch.addLine(to: CGPoint(x: x, y: sachetRect.minY + rect.height * 0.05))
            notch.lineWidth = 1
            UIColor.white.withAlphaComponent(0.46).setStroke()
            notch.stroke()
        }
        _ = context
    }

    private func drawSymbol(in rect: CGRect) {
        let configuration = UIImage.SymbolConfiguration(pointSize: min(rect.width, rect.height) * 0.58, weight: .semibold)
        let image = UIImage(systemName: kind.symbolName, withConfiguration: configuration)?
            .withTintColor(primaryColor, renderingMode: .alwaysOriginal)
        let size = image?.size ?? .zero
        image?.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }
}
