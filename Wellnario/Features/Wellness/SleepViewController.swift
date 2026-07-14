import UIKit

@MainActor
final class SleepViewController: WellnessScrollViewController {
    var onOpenSettings: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("sleep.title")
        view.accessibilityIdentifier = "sleep.root"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(openSettings)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = L10n.Settings.title
        buildContent()
    }

    private func buildContent() {
        let sourceBanner = FeedbackBannerView()
        sourceBanner.configure(
            message: L10n.text("sleep.source.empty"),
            tone: .information,
            actionTitle: L10n.text("integrations.connect")
        )
        sourceBanner.onAction = { [weak self] in self?.onOpenSettings?() }
        contentStack.addArrangedSubview(sourceBanner)

        contentStack.addArrangedSubview(makeSectionTitle(
            L10n.text("sleep.latest.title"),
            detail: L10n.text("sleep.latest.detail")
        ))

        let hero = makeLatestSessionCard()
        contentStack.addArrangedSubview(hero)

        let metrics = [
            makeMiniMetric(
                title: L10n.text("sleep.duration"),
                value: "—",
                detail: L10n.text("sleep.no_data"),
                symbol: "bed.double.fill",
                tone: WellnarioPalette.violet
            ),
            makeMiniMetric(
                title: L10n.text("sleep.score"),
                value: "—",
                detail: L10n.text("sleep.no_data"),
                symbol: "sparkles",
                tone: WellnarioPalette.magenta
            )
        ]
        let metricRow = UIStackView(
            arrangedSubviews: metrics,
            axis: .horizontal,
            spacing: WellnarioSpacing.cardGap,
            alignment: .fill,
            distribution: .fillEqually
        )
        metrics[0].widthAnchor.constraint(equalTo: metrics[1].widthAnchor).isActive = true
        contentStack.addArrangedSubview(metricRow)

        contentStack.setCustomSpacing(WellnarioSpacing.large, after: metricRow)
        contentStack.addArrangedSubview(makeSectionTitle(
            L10n.text("sleep.trend.title"),
            detail: L10n.text("sleep.trend.period")
        ))

        let chart = WellnessTrendChartView()
        chart.values = Array(repeating: nil, count: 7)
        chart.labels = localizedWeekdayInitials()
        chart.lineColor = WellnarioPalette.violet
        chart.emptyText = L10n.text("sleep.trend.empty")
        chart.accessibilityIdentifier = "sleep.trend.chart"
        let chartCard = makeCard(containing: chart, identifier: "sleep.trend.card")
        contentStack.addArrangedSubview(chartCard)

        contentStack.setCustomSpacing(WellnarioSpacing.large, after: chartCard)
        contentStack.addArrangedSubview(makeSectionTitle(L10n.text("sleep.factors.title")))
        contentStack.addArrangedSubview(makeFactorCard())
    }

    private func makeLatestSessionCard() -> PremiumCardView {
        let moon = UIImageView(image: UIImage(systemName: "moon.stars.fill"))
        moon.tintColor = WellnarioPalette.violet
        moon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 29, weight: .semibold)

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = L10n.text("sleep.latest.empty.title")
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        bodyLabel.text = L10n.text("sleep.latest.empty.body")
        bodyLabel.numberOfLines = 0

        let iconContainer = UIView()
        iconContainer.backgroundColor = WellnarioPalette.violet.withAlphaComponent(0.14)
        iconContainer.applyContinuousCorners(22)
        iconContainer.addForAutoLayout(moon)
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 64),
            iconContainer.heightAnchor.constraint(equalTo: iconContainer.widthAnchor),
            moon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            moon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor)
        ])

        let text = UIStackView(arrangedSubviews: [titleLabel, bodyLabel], axis: .vertical, spacing: 6)
        let content = UIStackView(
            arrangedSubviews: [iconContainer, text],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
        let card = makeCard(containing: content, identifier: "sleep.latest.card")
        card.showsAccent = true
        card.isAccessibilityElement = true
        card.accessibilityLabel = [titleLabel.text, bodyLabel.text].compactMap { $0 }.joined(separator: ". ")
        return card
    }

    private func makeMiniMetric(
        title: String,
        value: String,
        detail: String,
        symbol: String,
        tone: UIColor
    ) -> PremiumCardView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = tone
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        titleLabel.text = title
        titleLabel.numberOfLines = 2

        let valueLabel = UILabel()
        valueLabel.applyWellnarioStyle(.metric, color: WellnarioPalette.textPrimary)
        valueLabel.text = value
        let detailLabel = UILabel()
        detailLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        detailLabel.text = detail
        detailLabel.numberOfLines = 2

        let heading = UIStackView(
            arrangedSubviews: [titleLabel, UIView(), icon],
            axis: .horizontal,
            spacing: 6,
            alignment: .top
        )
        let stack = UIStackView(arrangedSubviews: [heading, valueLabel, detailLabel], axis: .vertical, spacing: 6)
        let card = makeCard(containing: stack)
        card.isAccessibilityElement = true
        card.accessibilityLabel = title
        card.accessibilityValue = [value, detail].joined(separator: ", ")
        return card
    }

    private func makeFactorCard() -> PremiumCardView {
        let lastFactor = WellnessLocalStore.lastSleepFactor
        let icon = UIImageView(image: UIImage(systemName: "text.badge.plus"))
        icon.tintColor = WellnarioPalette.cyan
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        titleLabel.text = lastFactor ?? L10n.text("sleep.factors.empty.title")
        let detailLabel = UILabel()
        detailLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        detailLabel.text = lastFactor == nil
            ? L10n.text("sleep.factors.empty.body")
            : L10n.text("sleep.factors.last_logged")
        detailLabel.numberOfLines = 0

        let labels = UIStackView(arrangedSubviews: [titleLabel, detailLabel], axis: .vertical, spacing: 4)
        let stack = UIStackView(
            arrangedSubviews: [icon, labels],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        let card = makeCard(containing: stack, identifier: "sleep.factor.summary")
        card.isAccessibilityElement = true
        card.accessibilityLabel = [titleLabel.text, detailLabel.text].compactMap { $0 }.joined(separator: ". ")
        return card
    }

    private func localizedWeekdayInitials() -> [String] {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        return Array(formatter.veryShortWeekdaySymbols.prefix(7))
    }

    @objc private func openSettings() { onOpenSettings?() }
}
