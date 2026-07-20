import UIKit

enum FitnessCardKind: String, CaseIterable, WellnessCardKind, Sendable {
    case weeklySummary
    case weeklyActivity
    case recentWorkouts

    static let storageNamespace = "fitness"

    @MainActor
    var title: String {
        switch self {
        case .weeklySummary: L10n.text("fitness.cards.weekly_summary")
        case .weeklyActivity: L10n.text("fitness.week.title")
        case .recentWorkouts: L10n.text("fitness.recent.title")
        }
    }

    var symbolName: String {
        switch self {
        case .weeklySummary: "chart.bar.fill"
        case .weeklyActivity: "calendar"
        case .recentWorkouts: "figure.run"
        }
    }
}

typealias FitnessCardLayoutPreferences = WellnessCardLayoutPreferences<FitnessCardKind>

@MainActor
final class FitnessViewController: WellnessScrollViewController {
    var onStartWorkout: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    private let appleHealthService: AppleHealthSyncing
    private let cardLayoutPreferences: FitnessCardLayoutPreferences
    private lazy var syncIndicator = AppleHealthSyncNavigationIndicator(service: appleHealthService)

    init(appleHealthService: AppleHealthSyncing, defaults: UserDefaults = .standard) {
        self.appleHealthService = appleHealthService
        cardLayoutPreferences = FitnessCardLayoutPreferences(defaults: defaults)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("fitness.title")
        navigationItem.largeTitleDisplayMode = .never
        view.accessibilityIdentifier = "fitness.root"
        let settingsButton = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(openSettings)
        )
        settingsButton.accessibilityLabel = L10n.Settings.title
        settingsButton.accessibilityIdentifier = "fitness.settings"
        let editCardsButton = UIBarButtonItem(
            image: UIImage(systemName: "square.grid.2x2"),
            style: .plain,
            target: self,
            action: #selector(openCardEditor)
        )
        editCardsButton.tintColor = WellnarioPalette.fuchsia
        editCardsButton.accessibilityLabel = L10n.text("fitness.cards.edit")
        editCardsButton.accessibilityIdentifier = "fitness.cards.edit"
        navigationItem.rightBarButtonItems = [settingsButton, editCardsButton]
        syncIndicator.install(
            on: navigationItem,
            baseItems: navigationItem.rightBarButtonItems ?? []
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appleHealthDidChange),
            name: .appleHealthSyncDidChange,
            object: appleHealthService
        )
        buildContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never
        syncIndicator.refresh()
        buildContent()
    }

    private func buildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let visibleCards = cardLayoutPreferences.orderedCards.filter(cardLayoutPreferences.isVisible)
        if visibleCards.isEmpty {
            contentStack.addArrangedSubview(makeNoVisibleCardsView())
            contentStack.addArrangedSubview(makeStartButton())
            return
        }

        for (index, card) in visibleCards.enumerated() {
            let section = makeCardSection(card)
            contentStack.addArrangedSubview(section)
            if index == 0 {
                let startButton = makeStartButton()
                contentStack.addArrangedSubview(startButton)
                if visibleCards.count > 1 {
                    contentStack.setCustomSpacing(WellnarioSpacing.large, after: startButton)
                }
            } else if index < visibleCards.count - 1 {
                contentStack.setCustomSpacing(WellnarioSpacing.large, after: section)
            }
        }
    }

    private func makeStartButton() -> PrimaryButton {
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
        return startButton
    }

    private func makeCardSection(_ card: FitnessCardKind) -> UIView {
        let views: [UIView]
        switch card {
        case .weeklySummary:
            views = [makeWeeklyHero()]
        case .weeklyActivity:
            views = [
                makeSectionTitle(
                    L10n.text("fitness.week.title"),
                    detail: L10n.text("fitness.week.detail")
                ),
                makeWeekCard()
            ]
        case .recentWorkouts:
            views = [makeSectionTitle(L10n.text("fitness.recent.title")), makeRecentCard()]
        }
        let section = UIStackView(
            arrangedSubviews: views,
            axis: .vertical,
            spacing: WellnarioSpacing.cardGap
        )
        section.accessibilityIdentifier = "fitness.card.section.\(card.rawValue)"
        return section
    }

    private func makeNoVisibleCardsView() -> EmptyStateView {
        let emptyState = EmptyStateView()
        emptyState.accessibilityIdentifier = "fitness.cards.empty"
        emptyState.configure(
            kind: .other,
            title: L10n.text("fitness.cards.empty.title"),
            message: L10n.text("fitness.cards.empty.body"),
            actionTitle: L10n.text("fitness.cards.edit")
        )
        emptyState.onAction = { [weak self] in self?.openCardEditor() }
        emptyState.heightAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        return emptyState
    }

    private func makeWeeklyHero() -> PremiumCardView {
        let eyebrow = UILabel()
        eyebrow.applyWellnarioStyle(.caption, color: WellnarioPalette.magenta)
        eyebrow.text = L10n.text("fitness.this_week")

        let valueLabel = UILabel()
        valueLabel.applyWellnarioStyle(.metric, color: WellnarioPalette.textPrimary)
        valueLabel.text = "\(appleHealthService.snapshot.workoutsThisWeek.count)"
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
        detail.text = weeklyDetail()
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
        card.isAccessibilityElement = true
        card.accessibilityLabel = L10n.text("fitness.this_week")
        card.accessibilityValue = "\(valueLabel.text ?? "0") \(L10n.text("fitness.workouts")), \(detail.text ?? "")"
        return card
    }

    private func weeklyDetail() -> String {
        let snapshot = appleHealthService.snapshot
        var details: [String] = []
        if let steps = snapshot.stepsToday {
            details.append(L10n.text(
                "apple_health.steps_today",
                AppleHealthUIFormatting.number(steps)
            ))
        }
        if let energy = snapshot.activeEnergyKilocaloriesToday {
            details.append(L10n.text(
                "apple_health.active_energy_today",
                AppleHealthUIFormatting.number(energy)
            ))
        }
        return details.isEmpty ? L10n.text("fitness.hero.empty") : details.joined(separator: " · ")
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
        let workoutDays = Set(appleHealthService.snapshot.workoutsThisWeek.map {
            Calendar.autoupdatingCurrent.startOfDay(for: $0.startDate)
        })
        let days = currentWeekDates
        for (index, symbol) in daySymbols.enumerated() {
            let label = UILabel()
            label.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
            label.text = symbol
            label.textAlignment = .center

            let circle = UIView()
            let hasWorkout = days.indices.contains(index) && workoutDays.contains(days[index])
            circle.backgroundColor = hasWorkout
                ? WellnarioPalette.magenta.withAlphaComponent(0.18)
                : WellnarioPalette.surfaceElevated
            circle.layer.borderWidth = 1
            circle.layer.borderColor = (hasWorkout
                ? WellnarioPalette.magenta.withAlphaComponent(0.55)
                : WellnarioPalette.hairline).cgColor
            circle.applyContinuousCorners(18)
            circle.heightAnchor.constraint(equalToConstant: 36).isActive = true
            let dot = UIView()
            dot.backgroundColor = hasWorkout
                ? WellnarioPalette.magenta
                : (index == currentWeekdayIndex ? WellnarioPalette.textSecondary : WellnarioPalette.textDisabled)
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

    private func makeRecentCard() -> PremiumCardView {
        let workouts = appleHealthService.snapshot.workoutsThisWeek
        guard !workouts.isEmpty else { return makeEmptyRecentCard() }

        let stack = UIStackView(arrangedSubviews: [], axis: .vertical, spacing: WellnarioSpacing.xSmall)
        for (index, workout) in workouts.prefix(5).enumerated() {
            if index > 0 {
                let separator = UIView()
                separator.backgroundColor = WellnarioPalette.hairline
                separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
                stack.addArrangedSubview(separator)
            }
            stack.addArrangedSubview(makeWorkoutRow(workout))
        }
        return makeCard(containing: stack, identifier: "fitness.recent.card")
    }

    private func makeWorkoutRow(_ workout: AppleHealthWorkout) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: AppleHealthUIFormatting.workoutSymbol(workout.kind)))
        icon.tintColor = WellnarioPalette.magenta
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        titleLabel.text = AppleHealthUIFormatting.workoutTitle(workout.kind)
        let detailLabel = UILabel()
        detailLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        var details = [
            WellnarioFormatters.relativeDay(workout.startDate),
            AppleHealthUIFormatting.duration(workout.durationSeconds)
        ]
        if let energy = workout.activeEnergyKilocalories {
            details.append(L10n.text("apple_health.energy_kcal", AppleHealthUIFormatting.number(energy)))
        }
        detailLabel.text = details.joined(separator: " · ")
        detailLabel.numberOfLines = 2
        let labels = UIStackView(arrangedSubviews: [titleLabel, detailLabel], axis: .vertical, spacing: 3)
        let row = UIStackView(
            arrangedSubviews: [icon, labels],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        row.isAccessibilityElement = true
        row.accessibilityLabel = [titleLabel.text, detailLabel.text].compactMap { $0 }.joined(separator: ", ")
        return row
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

    private var currentWeekDates: [Date] {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let interval = calendar.dateInterval(of: .weekOfYear, for: now)
        let start = interval?.start ?? calendar.startOfDay(for: now)
        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start).map(calendar.startOfDay)
        }
    }

    private func localizedWeekdayInitials() -> [String] {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        let symbols = formatter.veryShortWeekdaySymbols ?? []
        guard symbols.count == 7 else { return ["L", "M", "X", "J", "V", "S", "D"] }
        return Array(symbols[1...]) + [symbols[0]]
    }

    @objc private func startWorkout() { onStartWorkout?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func openCardEditor() {
        let editor = WellnessCardEditorViewController(
            preferences: cardLayoutPreferences,
            configuration: WellnessCardEditorConfiguration(
                title: L10n.text("fitness.cards.editor.title"),
                sectionTitle: L10n.text("fitness.cards.editor.section"),
                footer: L10n.text("fitness.cards.editor.footer"),
                visibleText: L10n.text("fitness.cards.visible"),
                hiddenText: L10n.text("fitness.cards.hidden"),
                visibilityAccessibilityFormatKey: "fitness.cards.visibility.accessibility",
                accessibilityPrefix: "fitness.cards"
            )
        )
        editor.onLayoutChange = { [weak self] in self?.buildContent() }
        navigationController?.pushViewController(editor, animated: true)
    }
    @objc private func appleHealthDidChange() { buildContent() }
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
