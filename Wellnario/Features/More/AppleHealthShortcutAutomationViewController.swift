import AppIntents
import SwiftUI
import UIKit

/// Sets up the user's preferred cadence before handing off to the official
/// Shortcuts interface. Personal automations cannot be created or inspected
/// by third-party apps, so this screen is intentionally explicit about the
/// final Shortcuts steps that iOS keeps under the user's control.
@MainActor
final class AppleHealthShortcutAutomationViewController: WellnessScrollViewController {
    private let appleHealthService: AppleHealthSyncing
    private let preferences: AppleHealthShortcutAutomationPreferences
    private let cadenceControl = UISegmentedControl()
    private let timePicker = UIDatePicker()
    private let timeRow = UIStackView()
    private let weekdaysRow = UIStackView()
    private let scheduleDetailLabel = UILabel()
    private let triggerInstructionLabel = UILabel()
    private var weekdayButtons: [Int: UIButton] = [:]

    init(
        appleHealthService: AppleHealthSyncing,
        preferences: AppleHealthShortcutAutomationPreferences = AppleHealthShortcutAutomationPreferences()
    ) {
        self.appleHealthService = appleHealthService
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("apple_health.shortcut.automation.title")
        navigationItem.largeTitleDisplayMode = .never
        view.accessibilityIdentifier = "settings.integration.apple_health.automation"
        buildContent()
        refreshControls()
    }

    private func buildContent() {
        let iconContainer = UIView()
        iconContainer.backgroundColor = WellnarioPalette.pink.withAlphaComponent(0.14)
        iconContainer.applyContinuousCorners(28)
        let icon = UIImageView(
            image: UIImage(systemName: "arrow.triangle.2.circlepath.heart.fill")
        )
        icon.tintColor = WellnarioPalette.pink
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
        iconContainer.addForAutoLayout(icon)
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 68),
            iconContainer.heightAnchor.constraint(equalTo: iconContainer.widthAnchor),
            icon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor)
        ])

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.pageTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = L10n.text("apple_health.shortcut.automation.title")
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        bodyLabel.text = L10n.text("apple_health.shortcut.automation.description")
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0

        let hero = UIStackView(
            arrangedSubviews: [iconContainer, titleLabel, bodyLabel],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        contentStack.addArrangedSubview(makeCard(containing: hero))

        let availability = FeedbackBannerView()
        availability.configure(
            message: L10n.text(
                appleHealthService.isConfigured
                    ? "apple_health.shortcut.automation.ready"
                    : "apple_health.shortcut.automation.requires_connection"
            ),
            tone: appleHealthService.isConfigured ? .information : .warning
        )
        contentStack.addArrangedSubview(availability)

        contentStack.addArrangedSubview(
            makeSectionTitle(L10n.text("apple_health.shortcut.automation.schedule.title"))
        )
        contentStack.addArrangedSubview(makeCard(containing: makeScheduleContent()))

        contentStack.addArrangedSubview(
            makeSectionTitle(L10n.text("apple_health.shortcut.automation.create.title"))
        )
        contentStack.addArrangedSubview(makeCard(containing: makeShortcutCreationContent()))
    }

    private func makeScheduleContent() -> UIView {
        cadenceControl.insertSegment(
            withTitle: L10n.text("apple_health.shortcut.automation.cadence.waking"),
            at: AppleHealthShortcutAutomationCadence.wakingUp.index,
            animated: false
        )
        cadenceControl.insertSegment(
            withTitle: L10n.text("apple_health.shortcut.automation.cadence.daily"),
            at: AppleHealthShortcutAutomationCadence.daily.index,
            animated: false
        )
        cadenceControl.insertSegment(
            withTitle: L10n.text("apple_health.shortcut.automation.cadence.weekly"),
            at: AppleHealthShortcutAutomationCadence.weekly.index,
            animated: false
        )
        cadenceControl.selectedSegmentIndex = preferences.cadence.index
        cadenceControl.selectedSegmentTintColor = WellnarioPalette.violet
        cadenceControl.setTitleTextAttributes(
            [.foregroundColor: WellnarioPalette.textPrimary],
            for: .normal
        )
        cadenceControl.setTitleTextAttributes(
            [.foregroundColor: WellnarioPalette.onAccent],
            for: .selected
        )
        cadenceControl.accessibilityIdentifier = "settings.integration.apple_health.automation.cadence"
        cadenceControl.addTarget(self, action: #selector(cadenceChanged), for: .valueChanged)

        let cadenceLabel = UILabel()
        cadenceLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        cadenceLabel.text = L10n.text("apple_health.shortcut.automation.cadence.title")

        let timeLabel = UILabel()
        timeLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        timeLabel.text = L10n.text("apple_health.shortcut.automation.time.title")
        timePicker.datePickerMode = .time
        timePicker.preferredDatePickerStyle = .compact
        timePicker.locale = LocalizationManager.shared.locale
        timePicker.calendar = .autoupdatingCurrent
        timePicker.date = preferences.time
        timePicker.tintColor = WellnarioPalette.violet
        timePicker.accessibilityIdentifier = "settings.integration.apple_health.automation.time"
        timePicker.addTarget(self, action: #selector(timeChanged), for: .valueChanged)
        timePicker.setContentHuggingPriority(.required, for: .horizontal)
        timeRow.axis = .horizontal
        timeRow.alignment = .center
        timeRow.spacing = WellnarioSpacing.small
        timeRow.addArrangedSubview(timeLabel)
        timeRow.addArrangedSubview(UIView())
        timeRow.addArrangedSubview(timePicker)

        let weekdaysLabel = UILabel()
        weekdaysLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        weekdaysLabel.text = L10n.text("apple_health.shortcut.automation.weekdays.title")
        let weekdayButtonsStack = UIStackView()
        weekdayButtonsStack.axis = .horizontal
        weekdayButtonsStack.spacing = WellnarioSpacing.xxxSmall
        weekdayButtonsStack.distribution = .fillEqually
        for weekday in Self.weekdayDisplayOrder {
            let button = makeWeekdayButton(weekday: weekday)
            weekdayButtons[weekday] = button
            weekdayButtonsStack.addArrangedSubview(button)
        }
        weekdaysRow.axis = .vertical
        weekdaysRow.spacing = WellnarioSpacing.xSmall
        weekdaysRow.addArrangedSubview(weekdaysLabel)
        weekdaysRow.addArrangedSubview(weekdayButtonsStack)

        scheduleDetailLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        scheduleDetailLabel.numberOfLines = 0
        scheduleDetailLabel.accessibilityIdentifier = "settings.integration.apple_health.automation.summary"

        return UIStackView(
            arrangedSubviews: [cadenceLabel, cadenceControl, timeRow, weekdaysRow, scheduleDetailLabel],
            axis: .vertical,
            spacing: WellnarioSpacing.small
        )
    }

    private func makeShortcutCreationContent() -> UIView {
        let explanation = UILabel()
        explanation.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        explanation.text = L10n.text("apple_health.shortcut.automation.limit")
        explanation.numberOfLines = 0

        let stepsTitle = UILabel()
        stepsTitle.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        stepsTitle.text = L10n.text("apple_health.shortcut.automation.steps.title")

        let addShortcutStep = makeStepLabel(
            number: 1,
            text: L10n.text("apple_health.shortcut.automation.steps.add_shortcut")
        )
        let createAutomationStep = makeStepLabel(
            number: 2,
            text: L10n.text("apple_health.shortcut.automation.steps.create_automation")
        )
        triggerInstructionLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        triggerInstructionLabel.numberOfLines = 0
        let runImmediatelyStep = makeStepLabel(
            number: 4,
            text: L10n.text("apple_health.shortcut.automation.steps.run_immediately")
        )

        let stack = UIStackView(
            arrangedSubviews: [
                explanation,
                makeShortcutsLink(),
                stepsTitle,
                addShortcutStep,
                createAutomationStep,
                triggerInstructionLabel,
                runImmediatelyStep
            ],
            axis: .vertical,
            spacing: WellnarioSpacing.small
        )
        return stack
    }

    private func makeShortcutsLink() -> UIView {
        let container = UIView()
        container.accessibilityIdentifier = "settings.integration.apple_health.automation.add_shortcut"
        let hostingController = UIHostingController(
            rootView: ShortcutsLink { [weak self] in
                self?.shortcutLinkTapped()
            }
            .shortcutsLinkStyle(.automatic)
        )
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        container.addForAutoLayout(hostingController.view)
        hostingController.view.pinEdges(to: container)
        hostingController.didMove(toParent: self)
        container.heightAnchor.constraint(greaterThanOrEqualToConstant: WellnarioLayout.primaryButtonHeight)
            .isActive = true
        return container
    }

    private func makeStepLabel(number: Int, text: String) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        label.text = "\(number). \(text)"
        label.numberOfLines = 0
        return label
    }

    private func makeWeekdayButton(weekday: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = weekday
        button.titleLabel?.font = WellnarioTypography.font(for: .caption)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.setTitle(weekdaySymbol(for: weekday), for: .normal)
        button.applyContinuousCorners(WellnarioRadius.control)
        button.layer.borderWidth = 1
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: WellnarioLayout.minimumTouchTarget)
            .isActive = true
        button.accessibilityIdentifier = "settings.integration.apple_health.automation.weekday.\(weekday)"
        button.addTarget(self, action: #selector(weekdayTapped), for: .touchUpInside)
        return button
    }

    @objc private func cadenceChanged() {
        guard let cadence = AppleHealthShortcutAutomationCadence(
            index: cadenceControl.selectedSegmentIndex
        ) else { return }
        preferences.cadence = cadence
        refreshControls()
    }

    @objc private func timeChanged() {
        preferences.time = timePicker.date
        refreshControls()
    }

    @objc private func weekdayTapped(_ sender: UIButton) {
        var weekdays = preferences.weekdays
        if weekdays.contains(sender.tag) {
            guard weekdays.count > 1 else { return }
            weekdays.remove(sender.tag)
        } else {
            weekdays.insert(sender.tag)
        }
        preferences.weekdays = weekdays
        refreshControls()
    }

    private func shortcutLinkTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func refreshControls() {
        let cadence = preferences.cadence
        cadenceControl.selectedSegmentIndex = cadence.index
        timePicker.date = preferences.time
        timeRow.isHidden = cadence == .wakingUp
        weekdaysRow.isHidden = cadence != .weekly
        let selectedWeekdays = preferences.weekdays
        for (weekday, button) in weekdayButtons {
            let isSelected = selectedWeekdays.contains(weekday)
            button.backgroundColor = isSelected
                ? WellnarioPalette.violet
                : WellnarioPalette.surfaceElevated
            button.setTitleColor(
                isSelected ? WellnarioPalette.onAccent : WellnarioPalette.textSecondary,
                for: .normal
            )
            button.layer.borderColor = (isSelected ? WellnarioPalette.violet : WellnarioPalette.hairline)
                .cgColor
            button.accessibilityValue = L10n.text(isSelected ? "common.yes" : "common.no")
        }
        scheduleDetailLabel.text = scheduleSummary
        triggerInstructionLabel.text = "3. \(triggerInstruction)"
    }

    private var scheduleSummary: String {
        switch preferences.cadence {
        case .wakingUp:
            return L10n.text("apple_health.shortcut.automation.summary.waking")
        case .daily:
            return L10n.text(
                "apple_health.shortcut.automation.summary.daily",
                formattedTime(preferences.time)
            )
        case .weekly:
            return L10n.text(
                "apple_health.shortcut.automation.summary.weekly",
                formattedWeekdays(preferences.weekdays),
                formattedTime(preferences.time)
            )
        }
    }

    private var triggerInstruction: String {
        switch preferences.cadence {
        case .wakingUp:
            return L10n.text("apple_health.shortcut.automation.trigger.waking")
        case .daily:
            return L10n.text(
                "apple_health.shortcut.automation.trigger.daily",
                formattedTime(preferences.time)
            )
        case .weekly:
            return L10n.text(
                "apple_health.shortcut.automation.trigger.weekly",
                formattedWeekdays(preferences.weekdays),
                formattedTime(preferences.time)
            )
        }
    }

    private func weekdaySymbol(for weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        return formatter.veryShortWeekdaySymbols[weekday - 1]
    }

    private func formattedWeekdays(_ weekdays: Set<Int>) -> String {
        Self.weekdayDisplayOrder
            .filter(weekdays.contains)
            .map(weekdaySymbol(for:))
            .joined(separator: ", ")
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private static let weekdayDisplayOrder = [2, 3, 4, 5, 6, 7, 1]
}

private extension AppleHealthShortcutAutomationCadence {
    var index: Int {
        switch self {
        case .wakingUp: 0
        case .daily: 1
        case .weekly: 2
        }
    }

    init?(index: Int) {
        switch index {
        case 0: self = .wakingUp
        case 1: self = .daily
        case 2: self = .weekly
        default: return nil
        }
    }
}
