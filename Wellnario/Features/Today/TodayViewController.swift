import UIKit

@MainActor
final class TodayViewController: FeatureViewController {
    var onOpenSettings: (() -> Void)?
    var onShowSupplements: (() -> Void)?
    var onShowTrends: (() -> Void)?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let dateButton = UIButton(type: .system)
    private let profileButton = UIButton(type: .system)
    private let insightCard = PremiumCardView()
    private let insightTitle = UILabel()
    private let insightMessage = UILabel()
    private let metricStack = UIStackView()
    private let dayCard = PremiumCardView()
    private let dayContent = UIStackView()
    private let activeCard = PremiumCardView()
    private let activeContent = UIStackView()

    private var summary: DashboardSummary?
    private var selectedDate = Date()

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpView()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: TodayViewController, _) in
            if let summary = self.summary { self.rebuildMetrics(summary) }
        }
        applyLocalizedCopy()
        reloadContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reloadContent()
    }

    override func applyLocalizedCopy() {
        navigationItem.accessibilityLabel = L10n.Tab.today
        dateButton.setTitle(WellnarioFormatters.dateHeader(selectedDate), for: .normal)
        profileButton.accessibilityLabel = L10n.More.settings
        insightTitle.text = L10n.Today.suggestion
    }

    override func reloadContent() {
        do {
            let summary = try repository.dashboard(
                on: LocalDay(containing: selectedDate, in: .current),
                expiringWithinDays: 30
            )
            self.summary = summary
            render(summary)
        } catch {
            showInlineError(error)
        }
    }

    private func setUpView() {
        navigationController?.setNavigationBarHidden(true, animated: false)

        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .always
        scrollView.showsVerticalScrollIndicator = false
        view.addForAutoLayout(scrollView)
        scrollView.pinEdges(to: view)

        contentStack.axis = .vertical
        contentStack.spacing = WellnarioSpacing.cardGap
        scrollView.addForAutoLayout(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: WellnarioSpacing.screenHorizontal),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -WellnarioSpacing.screenHorizontal),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: WellnarioSpacing.medium),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -WellnarioSpacing.bottomNavigationInset),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -(WellnarioSpacing.screenHorizontal * 2))
        ])

        let header = makeHeader()
        contentStack.addArrangedSubview(header)
        contentStack.setCustomSpacing(WellnarioSpacing.xLarge, after: header)

        setUpInsightCard()
        contentStack.addArrangedSubview(insightCard)

        metricStack.axis = .vertical
        metricStack.spacing = WellnarioSpacing.cardGap
        contentStack.addArrangedSubview(metricStack)

        setUpWideCard(dayCard, stack: dayContent)
        contentStack.addArrangedSubview(dayCard)

        setUpWideCard(activeCard, stack: activeContent)
        contentStack.addArrangedSubview(activeCard)
    }

    private func makeHeader() -> UIView {
        dateButton.titleLabel?.font = WellnarioTypography.font(for: .pageTitle)
        dateButton.titleLabel?.adjustsFontForContentSizeCategory = true
        dateButton.setTitleColor(WellnarioPalette.textPrimary, for: .normal)
        dateButton.contentHorizontalAlignment = .left
        dateButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        dateButton.tintColor = WellnarioPalette.textSecondary
        dateButton.semanticContentAttribute = .forceRightToLeft
        dateButton.addTarget(self, action: #selector(selectDate), for: .touchUpInside)

        let configuration = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        profileButton.setImage(UIImage(systemName: "person.fill", withConfiguration: configuration), for: .normal)
        profileButton.tintColor = WellnarioPalette.textPrimary
        profileButton.backgroundColor = WellnarioPalette.surfaceElevated
        profileButton.applyContinuousCorners(26)
        profileButton.layer.borderWidth = 1
        profileButton.layer.borderColor = WellnarioPalette.hairline.cgColor
        profileButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        NSLayoutConstraint.activate([
            profileButton.widthAnchor.constraint(equalToConstant: 52),
            profileButton.heightAnchor.constraint(equalTo: profileButton.widthAnchor)
        ])

        return UIStackView(
            arrangedSubviews: [dateButton, profileButton],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center,
            distribution: .fill
        )
    }

    private func setUpInsightCard() {
        insightCard.showsAccent = true
        insightCard.isPressable = true
        insightCard.addTarget(self, action: #selector(insightTapped), for: .touchUpInside)
        insightCard.heightAnchor.constraint(greaterThanOrEqualToConstant: WellnarioLayout.insightCardMinimumHeight).isActive = true

        let icon = UIImageView(image: UIImage(systemName: "sparkles"))
        icon.tintColor = WellnarioPalette.cyan
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)

        insightTitle.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.magenta)
        let top = UIStackView(
            arrangedSubviews: [icon, insightTitle, UIView()],
            axis: .horizontal,
            spacing: WellnarioSpacing.xxSmall,
            alignment: .center
        )

        insightMessage.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        insightMessage.numberOfLines = 3

        let stack = UIStackView(
            arrangedSubviews: [top, insightMessage],
            axis: .vertical,
            spacing: WellnarioSpacing.small
        )
        insightCard.contentView.addForAutoLayout(stack)
        stack.pinEdges(to: insightCard.contentView, insets: .all(WellnarioSpacing.cardPadding))
    }

    private func setUpWideCard(_ card: PremiumCardView, stack: UIStackView) {
        stack.axis = .vertical
        stack.spacing = WellnarioSpacing.xSmall
        card.contentView.addForAutoLayout(stack)
        stack.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.cardPadding))
    }

    private func render(_ summary: DashboardSummary) {
        insightMessage.text = suggestion(for: summary)
        rebuildMetrics(summary)
        rebuildDayCard(summary)
        rebuildActiveCard(summary)
    }

    private func rebuildMetrics(_ summary: DashboardSummary) {
        metricStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let inTarget = summary.activeProgress.filter { $0.status == .within }.count
        let configuredTargets = summary.activeProgress.filter { $0.targetLower != nil }.count
        let expiryTone: WellnarioTone = summary.expiredCount > 0 ? .danger : (summary.expiringSoonCount > 0 ? .warning : .success)

        let intake = makeMetric(
            title: L10n.text("today.intakes"),
            symbol: "checkmark.circle",
            value: "\(summary.consumptionCount)",
            status: summary.consumptionCount == 0 ? L10n.text("today.none_yet") : L10n.text("today.logged"),
            tone: summary.consumptionCount == 0 ? .neutral : .success,
            values: recentCounts()
        )
        let targets = makeMetric(
            title: L10n.Today.actives,
            symbol: "scope",
            value: configuredTargets == 0 ? "—" : "\(inTarget)/\(configuredTargets)",
            status: configuredTargets == 0 ? L10n.text("today.configure_targets") : L10n.text("today.in_target"),
            tone: inTarget == configuredTargets && configuredTargets > 0 ? .success : .accent,
            values: summary.activeProgress.prefix(7).map { FeatureFormatting.double($0.consumedAmount) }
        )
        let inventory = makeMetric(
            title: L10n.Today.inventory,
            symbol: "shippingbox",
            value: "\(summary.instanceCount)",
            status: L10n.text("today.available_batches"),
            tone: summary.instanceCount == 0 ? .neutral : .information,
            values: [Double(summary.instanceCount), Double(summary.supplementCount)]
        )
        let expiry = makeMetric(
            title: L10n.Today.expiry,
            symbol: "calendar.badge.exclamationmark",
            value: "\(summary.expiringSoonCount + summary.expiredCount)",
            status: expiryStatus(summary),
            tone: expiryTone,
            values: [Double(summary.expiringSoonCount), Double(summary.expiredCount), 0]
        )

        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            [intake, targets, inventory, expiry].forEach(metricStack.addArrangedSubview)
        } else {
            metricStack.addArrangedSubview(makeMetricRow(intake, targets))
            metricStack.addArrangedSubview(makeMetricRow(inventory, expiry))
        }
    }

    private func makeMetric(
        title: String,
        symbol: String,
        value: String,
        status: String,
        tone: WellnarioTone,
        values: [Double]
    ) -> MetricCardView {
        let card = MetricCardView()
        card.configure(title: title, symbolName: symbol, value: value, status: status, tone: tone)
        let sparkline = SparklineView()
        sparkline.values = values.isEmpty ? [0, 0] : (values.count == 1 ? [0, values[0]] : values)
        sparkline.lineColor = WellnarioPalette.color(for: tone)
        card.setVisualization(sparkline)
        return card
    }

    private func makeMetricRow(_ first: UIView, _ second: UIView) -> UIStackView {
        let stack = UIStackView(
            arrangedSubviews: [first, second],
            axis: .horizontal,
            spacing: WellnarioSpacing.cardGap,
            alignment: .fill,
            distribution: .fillEqually
        )
        first.widthAnchor.constraint(equalTo: second.widthAnchor).isActive = true
        return stack
    }

    private func rebuildDayCard(_ summary: DashboardSummary) {
        dayContent.arrangedSubviews.forEach { $0.removeFromSuperview() }

        dayContent.addArrangedSubview(sectionHeader(title: L10n.Today.summary, symbol: "clock.fill"))
        if summary.recentConsumptions.isEmpty {
            let label = UILabel()
            label.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
            label.text = L10n.Diary.noEntriesMessage
            label.numberOfLines = 0
            dayContent.addArrangedSubview(label)
        } else {
            summary.recentConsumptions.prefix(4).forEach { consumption in
                dayContent.addArrangedSubview(consumptionRow(consumption))
            }
        }
        let button = PrimaryButton(title: L10n.Today.logIntake)
        button.addTarget(self, action: #selector(logIntake), for: .touchUpInside)
        dayContent.setCustomSpacing(WellnarioSpacing.medium, after: dayContent.arrangedSubviews.last!)
        dayContent.addArrangedSubview(button)
    }

    private func rebuildActiveCard(_ summary: DashboardSummary) {
        activeContent.arrangedSubviews.forEach { $0.removeFromSuperview() }
        activeContent.addArrangedSubview(sectionHeader(title: L10n.Today.intakeByActive, symbol: "chart.bar.fill"))

        if summary.activeProgress.isEmpty {
            let label = UILabel()
            label.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
            label.text = L10n.text("today.active_progress.empty")
            label.numberOfLines = 0
            activeContent.addArrangedSubview(label)
        } else {
            summary.activeProgress.prefix(5).forEach { progress in
                activeContent.addArrangedSubview(activeProgressRow(progress))
            }
        }

        let button = PrimaryButton(title: L10n.Tab.trends, style: .secondary)
        button.addTarget(self, action: #selector(openTrends), for: .touchUpInside)
        activeContent.setCustomSpacing(WellnarioSpacing.medium, after: activeContent.arrangedSubviews.last!)
        activeContent.addArrangedSubview(button)
    }

    private func sectionHeader(title: String, symbol: String) -> UIView {
        let label = UILabel()
        label.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        label.text = title
        let image = UIImageView(image: UIImage(systemName: symbol))
        image.tintColor = WellnarioPalette.textTertiary
        return UIStackView(
            arrangedSubviews: [label, UIView(), image],
            axis: .horizontal,
            spacing: WellnarioSpacing.xxSmall,
            alignment: .center
        )
    }

    private func consumptionRow(_ consumption: Consumption) -> UIView {
        let artwork = PresentationArtworkView(kind: .capsule)
        artwork.showsBackground = true
        NSLayoutConstraint.activate([
            artwork.widthAnchor.constraint(equalToConstant: 48),
            artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor)
        ])

        let title = UILabel()
        title.applyWellnarioStyle(.body, color: WellnarioPalette.textPrimary)
        title.text = consumption.supplementNameSnapshot
        let detail = UILabel()
        detail.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        detail.text = "\(FeatureFormatting.decimal(consumption.quantity)) \(consumption.unit.symbol(languageCode: catalogLanguage.rawValue)) · \(WellnarioFormatters.time(consumption.consumedAt, timeZoneID: consumption.timeZoneID))"
        let labels = UIStackView(arrangedSubviews: [title, detail], axis: .vertical, spacing: 2)
        return UIStackView(arrangedSubviews: [artwork, labels], axis: .horizontal, spacing: WellnarioSpacing.xSmall, alignment: .center)
    }

    private func activeProgressRow(_ progress: ActiveDailyProgress) -> UIView {
        let name = UILabel()
        name.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        name.text = progress.active.localizedName(language: catalogLanguage)

        let amount = UILabel()
        amount.applyWellnarioStyle(.caption, color: statusColor(progress.status))
        amount.text = "\(FeatureFormatting.decimal(progress.consumedAmount)) \(progress.unit.symbol(languageCode: catalogLanguage.rawValue))"
        amount.setContentHuggingPriority(.required, for: .horizontal)

        let header = UIStackView(arrangedSubviews: [name, amount], axis: .horizontal, spacing: 8, alignment: .firstBaseline)
        let progressView = TargetProgressView()
        if let lower = progress.targetLower, let upper = progress.targetUpper {
            let upperDouble = max(FeatureFormatting.double(upper), 0.001)
            progressView.set(
                value: FeatureFormatting.double(progress.consumedAmount),
                targetRange: FeatureFormatting.double(lower)...upperDouble,
                domain: 0...max(upperDouble * 1.35, FeatureFormatting.double(progress.consumedAmount)),
                unit: progress.unit.symbol(languageCode: catalogLanguage.rawValue),
                animated: view.window != nil
            )
        } else {
            progressView.set(value: 0, targetRange: 0...0, domain: 0...1, unit: "", animated: false)
        }
        return UIStackView(arrangedSubviews: [header, progressView], axis: .vertical, spacing: 6)
    }

    private func statusColor(_ status: TargetProgressStatus) -> UIColor {
        switch status {
        case .within: WellnarioPalette.success
        case .above: WellnarioPalette.warning
        case .below: WellnarioPalette.cyan
        case .noTarget: WellnarioPalette.textSecondary
        }
    }

    private func suggestion(for summary: DashboardSummary) -> String {
        if summary.supplementCount == 0 { return L10n.text("today.suggestion.first_supplement") }
        if summary.expiredCount > 0 { return L10n.text("today.suggestion.expired", summary.expiredCount) }
        if summary.consumptionCount == 0 { return L10n.text("today.suggestion.log_first") }
        let inTarget = summary.activeProgress.filter { $0.status == .within }.count
        if inTarget > 0 { return L10n.text("today.suggestion.in_target", inTarget) }
        return L10n.text("today.suggestion.review")
    }

    private func expiryStatus(_ summary: DashboardSummary) -> String {
        if summary.expiredCount > 0 { return L10n.text("expiry.expired_count", summary.expiredCount) }
        if summary.expiringSoonCount > 0 { return L10n.text("expiry.soon_count", summary.expiringSoonCount) }
        return L10n.text("expiry.all_good")
    }

    private func recentCounts() -> [Double] {
        let today = LocalDay(containing: selectedDate, in: .current)
        guard let from = try? today.adding(days: -6),
              let days = try? repository.diary(from: from, through: today) else {
            return [0, 0]
        }
        let counts = Dictionary(uniqueKeysWithValues: days.map { ($0.day, $0.consumptions.count) })
        return (0..<7).compactMap { offset in
            (try? from.adding(days: offset)).map { Double(counts[$0] ?? 0) }
        }
    }

    private func showInlineError(_ error: Error) {
        metricStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let empty = EmptyStateView()
        empty.configure(kind: .other, title: L10n.Common.error, message: error.localizedDescription, actionTitle: L10n.Common.retry)
        empty.onAction = { [weak self] in self?.reloadContent() }
        empty.heightAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        metricStack.addArrangedSubview(empty)
    }

    @objc private func selectDate() {
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .inline
        picker.maximumDate = Date()
        picker.date = selectedDate

        let controller = UIViewController()
        controller.view.backgroundColor = WellnarioPalette.background
        controller.view.addForAutoLayout(picker)
        picker.pinEdges(to: controller.view.safeAreaLayoutGuide, insets: .all(WellnarioSpacing.small))
        controller.preferredContentSize = CGSize(width: 360, height: 420)
        picker.addAction(UIAction { [weak self, weak controller] action in
            guard let picker = action.sender as? UIDatePicker else { return }
            self?.selectedDate = picker.date
            self?.applyLocalizedCopy()
            self?.reloadContent()
            controller?.dismiss(animated: true)
        }, for: .valueChanged)
        presentSheet(controller)
    }

    @objc private func openSettings() { onOpenSettings?() }

    @objc private func insightTapped() {
        guard summary?.supplementCount ?? 0 > 0 else {
            addSupplement()
            return
        }
        logIntake()
    }

    @objc private func addSupplement() {
        if let onShowSupplements { onShowSupplements() }
        else { presentSheet(SupplementEditorViewController(repository: repository), largeOnly: true) }
    }

    @objc private func logIntake() {
        do {
            let instances = try repository.fetchInstances(supplementID: nil, includeArchived: false)
            guard !instances.isEmpty else {
                let alert = UIAlertController(
                    title: L10n.Inventory.noItemsTitle,
                    message: L10n.text("intake.requires_batch"),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
                alert.addAction(UIAlertAction(title: L10n.Today.addFirstSupplement, style: .default) { [weak self] _ in
                    self?.addSupplement()
                })
                present(alert, animated: true)
                return
            }
            presentSheet(IntakeEditorViewController(repository: repository), largeOnly: true)
        } catch { showError(error) }
    }

    @objc private func openTrends() { onShowTrends?() }

}
