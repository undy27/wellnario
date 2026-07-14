import UIKit

@MainActor
final class FitnessViewController: WellnessScrollViewController {
    var onStartWorkout: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("fitness.title")
        view.accessibilityIdentifier = "fitness.root"
        buildContent()
    }

    private func buildContent() {
        contentStack.addArrangedSubview(makeWeeklyHero())

        let startButton = PrimaryButton()
        var startConfiguration = UIButton.Configuration.plain()
        startConfiguration.title = L10n.text("fitness.start_workout")
        startConfiguration.image = UIImage(systemName: "play.fill")
        startConfiguration.imagePadding = 8
        startConfiguration.baseForegroundColor = WellnarioPalette.textPrimary
        startConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = WellnarioTypography.font(for: .button)
            return outgoing
        }
        startButton.configuration = startConfiguration
        startButton.style = .primary
        startButton.accessibilityIdentifier = "fitness.start"
        startButton.addTarget(self, action: #selector(startWorkout), for: .touchUpInside)
        contentStack.addArrangedSubview(startButton)

        contentStack.setCustomSpacing(WellnarioSpacing.large, after: startButton)
        contentStack.addArrangedSubview(makeSectionTitle(
            L10n.text("fitness.week.title"),
            detail: L10n.text("fitness.week.detail")
        ))
        contentStack.addArrangedSubview(makeWeekCard())

        contentStack.setCustomSpacing(WellnarioSpacing.large, after: contentStack.arrangedSubviews.last!)
        contentStack.addArrangedSubview(makeSectionTitle(L10n.text("fitness.recent.title")))
        contentStack.addArrangedSubview(makeEmptyRecentCard())
    }

    private func makeWeeklyHero() -> PremiumCardView {
        let eyebrow = UILabel()
        eyebrow.applyWellnarioStyle(.caption, color: WellnarioPalette.magenta)
        eyebrow.text = L10n.text("fitness.this_week")

        let valueLabel = UILabel()
        valueLabel.applyWellnarioStyle(.metric, color: WellnarioPalette.textPrimary)
        valueLabel.text = "0"
        let unitLabel = UILabel()
        unitLabel.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textSecondary)
        unitLabel.text = L10n.text("fitness.workouts")
        let valueRow = UIStackView(
            arrangedSubviews: [valueLabel, unitLabel, UIView()],
            axis: .horizontal,
            spacing: WellnarioSpacing.xxSmall,
            alignment: .lastBaseline
        )

        let detail = UILabel()
        detail.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        detail.text = L10n.text("fitness.hero.empty")
        detail.numberOfLines = 0

        let artwork = FitnessArtworkView()
        artwork.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            artwork.widthAnchor.constraint(equalToConstant: 108),
            artwork.heightAnchor.constraint(equalToConstant: 98)
        ])

        let labels = UIStackView(arrangedSubviews: [eyebrow, valueRow, detail], axis: .vertical, spacing: 8)
        let content = UIStackView(
            arrangedSubviews: [labels, artwork],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        let card = makeCard(containing: content, identifier: "fitness.weekly.summary")
        card.showsAccent = true
        card.isAccessibilityElement = true
        card.accessibilityLabel = L10n.text("fitness.this_week")
        card.accessibilityValue = L10n.text("fitness.hero.empty")
        return card
    }

    private func makeWeekCard() -> PremiumCardView {
        let daySymbols = localizedWeekdayInitials()
        let stack = UIStackView(
            arrangedSubviews: [],
            axis: .horizontal,
            spacing: 6,
            alignment: .fill,
            distribution: .fillEqually
        )
        for (index, symbol) in daySymbols.enumerated() {
            let label = UILabel()
            label.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
            label.text = symbol
            label.textAlignment = .center

            let circle = UIView()
            circle.backgroundColor = index == currentWeekdayIndex
                ? WellnarioPalette.magenta.withAlphaComponent(0.18)
                : WellnarioPalette.surfaceElevated
            circle.layer.borderWidth = 1
            circle.layer.borderColor = (index == currentWeekdayIndex
                ? WellnarioPalette.magenta.withAlphaComponent(0.55)
                : WellnarioPalette.hairline).cgColor
            circle.applyContinuousCorners(18)
            circle.heightAnchor.constraint(equalToConstant: 36).isActive = true
            let dot = UIView()
            dot.backgroundColor = index == currentWeekdayIndex ? WellnarioPalette.magenta : WellnarioPalette.textDisabled
            dot.applyContinuousCorners(3)
            circle.addForAutoLayout(dot)
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 6),
                dot.heightAnchor.constraint(equalTo: dot.widthAnchor),
                dot.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
                dot.centerYAnchor.constraint(equalTo: circle.centerYAnchor)
            ])
            stack.addArrangedSubview(UIStackView(arrangedSubviews: [label, circle], axis: .vertical, spacing: 8))
        }
        return makeCard(containing: stack, identifier: "fitness.week.card")
    }

    private func makeEmptyRecentCard() -> PremiumCardView {
        let icon = UIImageView(image: UIImage(systemName: "figure.strengthtraining.traditional"))
        icon.tintColor = WellnarioPalette.magenta
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = L10n.text("fitness.recent.empty.title")
        let bodyLabel = UILabel()
        bodyLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        bodyLabel.text = L10n.text("fitness.recent.empty.body")
        bodyLabel.numberOfLines = 0
        let labels = UIStackView(arrangedSubviews: [titleLabel, bodyLabel], axis: .vertical, spacing: 5)
        let content = UIStackView(
            arrangedSubviews: [icon, labels],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
        return makeCard(containing: content, identifier: "fitness.recent.empty")
    }

    private var currentWeekdayIndex: Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return (weekday + 5) % 7
    }

    private func localizedWeekdayInitials() -> [String] {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        let symbols = formatter.veryShortWeekdaySymbols ?? []
        guard symbols.count == 7 else { return ["L", "M", "X", "J", "V", "S", "D"] }
        return Array(symbols[1...]) + [symbols[0]]
    }

    @objc private func startWorkout() { onStartWorkout?() }
}

@MainActor
private final class FitnessArtworkView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }

    override func draw(_ rect: CGRect) {
        let bars: [(height: CGFloat, color: UIColor)] = [
            (38, WellnarioPalette.violet),
            (62, WellnarioPalette.magenta),
            (82, WellnarioPalette.pink),
            (54, WellnarioPalette.cyan)
        ]
        let width: CGFloat = 12
        let gap: CGFloat = 9
        let total = width * CGFloat(bars.count) + gap * CGFloat(bars.count - 1)
        var x = rect.midX - total / 2
        for bar in bars {
            let frame = CGRect(x: x, y: rect.maxY - bar.height - 7, width: width, height: bar.height)
            let path = UIBezierPath(roundedRect: frame, cornerRadius: width / 2)
            bar.color.withAlphaComponent(0.82).setFill()
            path.fill()
            x += width + gap
        }
    }
}
