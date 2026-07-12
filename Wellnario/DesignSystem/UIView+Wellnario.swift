import UIKit

extension UIView {
    @discardableResult
    func preparedForAutoLayout() -> Self {
        translatesAutoresizingMaskIntoConstraints = false
        return self
    }

    func addForAutoLayout(_ subview: UIView) {
        addSubview(subview)
        subview.translatesAutoresizingMaskIntoConstraints = false
    }

    @discardableResult
    func pinEdges(
        to guide: UILayoutGuide,
        insets: NSDirectionalEdgeInsets = .zero
    ) -> [NSLayoutConstraint] {
        let constraints = [
            leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: insets.leading),
            trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -insets.trailing),
            topAnchor.constraint(equalTo: guide.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -insets.bottom)
        ]
        NSLayoutConstraint.activate(constraints)
        return constraints
    }

    @discardableResult
    func pinEdges(
        to view: UIView,
        insets: NSDirectionalEdgeInsets = .zero
    ) -> [NSLayoutConstraint] {
        let constraints = [
            leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: insets.leading),
            trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -insets.trailing),
            topAnchor.constraint(equalTo: view.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -insets.bottom)
        ]
        NSLayoutConstraint.activate(constraints)
        return constraints
    }

    func applyContinuousCorners(_ radius: CGFloat) {
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
    }

    func applyPremiumShadow(opacity: Float = 0.30) {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = opacity
        layer.shadowOffset = CGSize(width: 0, height: 8)
        layer.shadowRadius = 24
    }
}

extension NSDirectionalEdgeInsets {
    static func all(_ value: CGFloat) -> NSDirectionalEdgeInsets {
        NSDirectionalEdgeInsets(top: value, leading: value, bottom: value, trailing: value)
    }
}

extension UIStackView {
    convenience init(
        arrangedSubviews: [UIView],
        axis: NSLayoutConstraint.Axis,
        spacing: CGFloat,
        alignment: UIStackView.Alignment = .fill,
        distribution: UIStackView.Distribution = .fill
    ) {
        self.init(arrangedSubviews: arrangedSubviews)
        self.axis = axis
        self.spacing = spacing
        self.alignment = alignment
        self.distribution = distribution
    }
}
