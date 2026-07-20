import UIKit
@preconcurrency import UserNotifications

@MainActor
final class SupplementDetailViewController: FeatureViewController {
    private let supplementID: UUID
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    private var supplement: Supplement?
    private var presentations: [PresentationType] = []
    private var actives: [Active] = []
    private var instances: [SupplementInstance] = []
    private var recentConsumptions: [Consumption] = []
    private let reminderStore = SupplementProductReminderStore()

    init(repository: WellnarioRepositoryProtocol, supplementID: UUID) {
        self.supplementID = supplementID
        super.init(repository: repository)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.Common.edit,
            style: .plain,
            target: self,
            action: #selector(editTapped)
        )
        setUpView()
        reloadContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if isViewLoaded { reloadContent() }
    }

    override func reloadContent() {
        do {
            guard let supplement = try repository.supplement(id: supplementID) else {
                navigationController?.popViewController(animated: true)
                return
            }
            self.supplement = supplement
            presentations = try repository.fetchPresentationTypes()
            actives = try repository.fetchActives(includeArchived: true)
            instances = try repository.fetchInstances(supplementID: supplementID, includeArchived: true)
            let instanceIDs = Set(instances.map(\.id))
            recentConsumptions = try repository.fetchConsumptions(from: nil, through: nil, limit: nil)
                .filter { instanceIDs.contains($0.instanceID) }
            title = supplement.name
            rebuild()
        } catch { showError(error) }
    }

    private func setUpView() {
        view.addForAutoLayout(scrollView)
        scrollView.pinEdges(to: view)
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false

        stackView.axis = .vertical
        stackView.spacing = WellnarioSpacing.cardGap
        scrollView.addForAutoLayout(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: WellnarioSpacing.screenHorizontal),
            stackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -WellnarioSpacing.screenHorizontal),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: WellnarioSpacing.medium),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -WellnarioSpacing.bottomNavigationInset),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -(WellnarioSpacing.screenHorizontal * 2))
        ])
    }

    private func rebuild() {
        guard let supplement else { return }
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stackView.addArrangedSubview(makeHero(supplement))

        let batchButton = PrimaryButton(title: L10n.Inventory.add, style: .secondary)
        batchButton.addTarget(self, action: #selector(addInstance), for: .touchUpInside)
        stackView.addArrangedSubview(batchButton)

        stackView.addArrangedSubview(makeCompositionCard(supplement))
        stackView.addArrangedSubview(makeReminderCard(supplement))
        stackView.addArrangedSubview(makeInventoryCard())
        stackView.addArrangedSubview(makeHistoryCard())

        let archive = PrimaryButton(title: L10n.text("supplements.archive"), style: .destructive)
        archive.addTarget(self, action: #selector(archiveTapped), for: .touchUpInside)
        stackView.addArrangedSubview(archive)
    }

    private func makeHero(_ supplement: Supplement) -> PremiumCardView {
        let card = PremiumCardView()
        let kind = presentation.map { PresentationKind(name: $0.localizedName(language: catalogLanguage)) } ?? .other
        let artwork: UIView
        if let photo = SupplementPhotoStore.image(
            reference: supplement.imageReference,
            databaseURL: repository.databaseURL
        ) {
            let imageView = UIImageView(image: photo)
            imageView.contentMode = .scaleAspectFit
            imageView.applyContinuousCorners(WellnarioRadius.control)
            imageView.clipsToBounds = true
            artwork = imageView
        } else {
            let presentationArtwork = PresentationArtworkView(kind: kind)
            presentationArtwork.primaryColor = WellnarioPalette.cyan
            presentationArtwork.secondaryColor = WellnarioPalette.magenta
            artwork = presentationArtwork
        }
        NSLayoutConstraint.activate([
            artwork.widthAnchor.constraint(equalToConstant: 176),
            artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor)
        ])

        let name = UILabel()
        name.applyWellnarioStyle(.pageTitle, color: WellnarioPalette.textPrimary)
        name.text = supplement.name
        name.textAlignment = .center
        name.numberOfLines = 0
        let brand = UILabel()
        brand.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        brand.text = [supplement.brand, presentation?.localizedName(language: catalogLanguage)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        brand.textAlignment = .center
        brand.numberOfLines = 0
        let details = UILabel()
        details.applyWellnarioStyle(.secondary, color: WellnarioPalette.textTertiary)
        details.text = supplement.details
        details.textAlignment = .center
        details.numberOfLines = 0
        details.isHidden = supplement.details?.isEmpty != false

        let stack = UIStackView(arrangedSubviews: [artwork, name, brand, details], axis: .vertical, spacing: 8, alignment: .center)
        card.contentView.addForAutoLayout(stack)
        stack.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.cardPadding))
        return card
    }

    private var presentation: PresentationType? {
        guard let supplement else { return nil }
        return presentations.first { $0.id == supplement.presentationTypeID }
    }

    private func makeCompositionCard(_ supplement: Supplement) -> PremiumCardView {
        let card = PremiumCardView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.addArrangedSubview(sectionHeader(L10n.Supplements.composition, symbol: "atom"))

        let basisLabel = UILabel()
        basisLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        basisLabel.text = L10n.text(
            "supplements.composition.basis",
            FeatureFormatting.decimal(supplement.basisQuantity),
            supplement.basisUnit.symbol(languageCode: catalogLanguage.rawValue)
        )
        basisLabel.numberOfLines = 0
        stack.addArrangedSubview(basisLabel)

        for component in supplement.components {
            let active = actives.first { $0.id == component.activeID }
            let row = valueRow(
                title: active?.localizedName(language: catalogLanguage) ?? L10n.Form.active,
                value: "\(FeatureFormatting.decimal(component.amount)) \(component.unit.symbol(languageCode: catalogLanguage.rawValue))",
                symbol: "sparkle"
            )
            stack.addArrangedSubview(row)
        }
        card.contentView.addForAutoLayout(stack)
        stack.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.cardPadding))
        return card
    }

    private func makeInventoryCard() -> PremiumCardView {
        let card = PremiumCardView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.addArrangedSubview(sectionHeader(L10n.Inventory.title, symbol: "shippingbox.fill"))
        if instances.isEmpty {
            let label = bodyLabel(L10n.Inventory.noItemsMessage)
            stack.addArrangedSubview(label)
        } else {
            for instance in instances {
                let button = UIButton(type: .system)
                var config = UIButton.Configuration.plain()
                config.title = instance.label.isEmpty ? nil : instance.label
                let remainingContent = instance.totalQuantity.flatMap { quantity in
                    instance.totalUnit.map {
                        L10n.text(
                            "inventory.remaining_content.value",
                            "\(FeatureFormatting.decimal(quantity)) \($0.symbol(languageCode: catalogLanguage.rawValue))"
                        )
                    }
                }
                config.subtitle = [remainingContent, FeatureFormatting.expirationText(instance.expirationDay)]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                config.image = UIImage(systemName: "shippingbox")
                config.imagePadding = 12
                config.baseForegroundColor = WellnarioPalette.textPrimary
                config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)
                button.configuration = config
                button.contentHorizontalAlignment = .leading
                button.accessibilityHint = L10n.Common.edit
                button.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    self.presentSheet(InstanceEditorViewController(repository: self.repository, instance: instance), largeOnly: true)
                }, for: .touchUpInside)
                stack.addArrangedSubview(button)
            }
        }
        let add = PrimaryButton(title: L10n.Inventory.add, style: .secondary)
        add.addTarget(self, action: #selector(addInstance), for: .touchUpInside)
        stack.addArrangedSubview(add)
        card.contentView.addForAutoLayout(stack)
        stack.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.cardPadding))
        return card
    }

    private func makeReminderCard(_ supplement: Supplement) -> PremiumCardView {
        let card = PremiumCardView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        let reminders = reminderStore.reminders(for: supplement.id)
        stack.addArrangedSubview(sectionHeader(L10n.text("supplements.reminders.title"), symbol: "bell.fill"))
        let summary = UILabel()
        summary.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        summary.numberOfLines = 0
        if reminders.isEmpty {
            summary.text = L10n.text("supplements.reminders.empty")
        } else {
            let formatter = DateFormatter()
            formatter.locale = LocalizationManager.shared.locale
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            let times = reminders
                .sorted { $0.timeMinutes < $1.timeMinutes }
                .map { reminder in
                    let date = Calendar.autoupdatingCurrent.date(bySettingHour: reminder.timeMinutes / 60, minute: reminder.timeMinutes % 60, second: 0, of: Date()) ?? Date()
                    return formatter.string(from: date)
                }
                .joined(separator: " · ")
            let schedule = reminders[0].recurrence == .weekdays
                ? L10n.text("supplements.reminders.schedule.weekdays")
                : L10n.text(
                    "supplements.reminders.schedule.every_n_days",
                    reminders[0].intervalDays
                )
            summary.text = "\(times)\n\(schedule)"
        }
        stack.addArrangedSubview(summary)
        let button = PrimaryButton(title: reminders.isEmpty ? L10n.text("supplements.reminders.add") : L10n.Common.edit, style: .secondary)
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.presentSheet(
                SupplementReminderEditorViewController(
                    repository: self.repository,
                    supplement: supplement,
                    store: self.reminderStore
                ),
                largeOnly: true
            )
        }, for: .touchUpInside)
        stack.addArrangedSubview(button)
        card.contentView.addForAutoLayout(stack)
        stack.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.cardPadding))
        return card
    }

    private func makeHistoryCard() -> PremiumCardView {
        let card = PremiumCardView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.addArrangedSubview(sectionHeader(L10n.Supplements.recentIntakes, symbol: "clock.arrow.circlepath"))
        if recentConsumptions.isEmpty {
            stack.addArrangedSubview(bodyLabel(L10n.Diary.noEntriesMessage))
        } else {
            for consumption in recentConsumptions.prefix(5) {
                let row = valueRow(
                    title: WellnarioFormatters.dateAndTime(
                        consumption.consumedAt,
                        timeZoneID: consumption.timeZoneID
                    ),
                    value: "\(FeatureFormatting.decimal(consumption.quantity)) \(consumption.unit.symbol(languageCode: catalogLanguage.rawValue))",
                    symbol: "checkmark.circle.fill"
                )
                stack.addArrangedSubview(row)
            }
        }
        card.contentView.addForAutoLayout(stack)
        stack.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.cardPadding))
        return card
    }

    private func sectionHeader(_ title: String, symbol: String) -> UIView {
        let label = UILabel()
        label.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        label.text = title
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = WellnarioPalette.textTertiary
        return UIStackView(arrangedSubviews: [label, UIView(), icon], axis: .horizontal, spacing: 8, alignment: .center)
    }

    private func valueRow(title: String, value: String, symbol: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = WellnarioPalette.cyan
        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textPrimary)
        titleLabel.text = title
        titleLabel.numberOfLines = 2
        let valueLabel = UILabel()
        valueLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        valueLabel.text = value
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        return UIStackView(arrangedSubviews: [icon, titleLabel, valueLabel], axis: .horizontal, spacing: 10, alignment: .center)
    }

    private func bodyLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        label.text = text
        label.numberOfLines = 0
        return label
    }

    @objc private func editTapped() {
        guard let supplement else { return }
        presentSheet(SupplementEditorViewController(repository: repository, supplement: supplement), largeOnly: true)
    }

    @objc private func addInstance() {
        presentSheet(InstanceEditorViewController(repository: repository, supplementID: supplementID), largeOnly: true)
    }

    @objc private func archiveTapped() {
        showConfirmation(title: L10n.text("supplements.archive"), message: L10n.text("supplements.archive.confirmation"), destructiveTitle: L10n.text("supplements.archive")) { [weak self] in
            guard let self else { return }
            do {
                _ = try self.repository.deleteSupplement(id: self.supplementID)
                self.reminderStore.remove(for: self.supplementID)
                SupplementReminderNotificationScheduler(repository: self.repository, store: self.reminderStore).reschedule()
                self.navigationController?.popViewController(animated: true)
            } catch { self.showError(error) }
        }
    }
}

@MainActor
final class SupplementReminderNotificationScheduler {
    private let repository: WellnarioRepositoryProtocol
    private let store: SupplementProductReminderStore
    private let center: UNUserNotificationCenter
    private let identifierPrefix = "wellnario.supplement.reminder."

    init(
        repository: WellnarioRepositoryProtocol,
        store: SupplementProductReminderStore = SupplementProductReminderStore(),
        center: UNUserNotificationCenter = .current()
    ) {
        self.repository = repository
        self.store = store
        self.center = center
    }

    func reschedule() {
        Task { @MainActor in
            _ = self.store.removeLegacyUnconfirmedSuggestions()
            if !self.store.all().isEmpty {
                guard (try? await self.center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            }
            await self.removeExisting()
            if !self.store.all().isEmpty { self.scheduleUpcoming() }
        }
    }

    private func removeExisting() async {
        let requests = await center.pendingNotificationRequests()
        let ids = requests.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        let delivered = await center.deliveredNotifications()
        let deliveredIDs = delivered.map { $0.request.identifier }.filter { $0.hasPrefix(identifierPrefix) }
        center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
    }

    private func scheduleUpcoming() {
        let supplements: [UUID: String]
        do {
            supplements = Dictionary(uniqueKeysWithValues: try repository.fetchSupplements(includeArchived: false).map { ($0.id, $0.name) })
        } catch { return }

        let reminders = store.all().filter { supplements[$0.supplementID] != nil }
        guard !reminders.isEmpty else { return }
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        let start = calendar.startOfDay(for: Date())
        var grouped: [String: (date: Date, names: Set<String>)] = [:]
        let horizon = 21 // iOS keeps a limited number of pending local notifications.
        for offset in 0..<horizon {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let localDay = LocalDay(containing: day, in: calendar.timeZone)
            let weekday = calendar.component(.weekday, from: day)
            for reminder in reminders where shouldFire(reminder, localDay: localDay, weekday: weekday, calendar: calendar) {
                guard let fireDate = calendar.date(bySettingHour: reminder.timeMinutes / 60, minute: reminder.timeMinutes % 60, second: 0, of: day), fireDate > Date() else { continue }
                let key = "\(localDay.iso8601)-\(reminder.timeMinutes)"
                grouped[key, default: (fireDate, [])].names.insert(supplements[reminder.supplementID]!)
            }
        }
        for (key, item) in grouped {
            let names = item.names.sorted().joined(separator: ", ")
            let content = UNMutableNotificationContent()
            content.title = L10n.text("supplements.reminders.notification.title")
            content.body = item.names.count == 1
                ? L10n.text("supplements.reminders.notification.single", names)
                : L10n.text("supplements.reminders.notification.multiple", names)
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let request = UNNotificationRequest(
                identifier: identifierPrefix + key,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            center.add(request)
        }
    }

    private func shouldFire(
        _ reminder: SupplementProductReminder,
        localDay: LocalDay,
        weekday: Int,
        calendar: Calendar
    ) -> Bool {
        switch reminder.recurrence {
        case .weekdays:
            return reminder.weekdaysMask & (1 << (weekday - 1)) != 0
        case .everyDays:
            guard let current = calendar.date(from: DateComponents(year: localDay.year, month: localDay.month, day: localDay.day)),
                  let anchor = calendar.date(from: DateComponents(year: reminder.anchorDay.year, month: reminder.anchorDay.month, day: reminder.anchorDay.day)) else { return false }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: anchor), to: calendar.startOfDay(for: current)).day ?? -1
            return days >= 0 && days % max(1, reminder.intervalDays) == 0
        }
    }
}

@MainActor
final class SupplementReminderEditorViewController: UIViewController {
    private let repository: WellnarioRepositoryProtocol
    private let supplement: Supplement
    private let store: SupplementProductReminderStore
    private let onSaveDraft: (([SupplementProductReminder]) -> Void)?
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let remindersStack = UIStackView()
    private let modeControl = UISegmentedControl()
    private let weekdaysStack = UIStackView()
    private let intervalField = FormFieldView()
    private var reminders: [SupplementProductReminder]
    private var recurrence: SupplementReminderRecurrence
    private var weekdaysMask: Int
    private var intervalDays: Int
    private var anchorDay: LocalDay
    private let suggestion: SupplementReminderSuggestion?
    private let addButton = PrimaryButton(style: .secondary)

    init(
        repository: WellnarioRepositoryProtocol,
        supplement: Supplement,
        store: SupplementProductReminderStore = SupplementProductReminderStore(),
        onSaveDraft: (([SupplementProductReminder]) -> Void)? = nil
    ) {
        self.repository = repository
        self.supplement = supplement
        self.store = store
        self.onSaveDraft = onSaveDraft
        _ = store.removeLegacyUnconfirmedSuggestions()
        let savedReminders = store.reminders(for: supplement.id)
        let proposedSuggestion = savedReminders.isEmpty && !store.hasUserConfiguration(for: supplement.id)
            ? try? SupplementDefaultReminderPlanner().suggestion(for: supplement, in: repository)
            : nil
        self.reminders = savedReminders
        self.suggestion = proposedSuggestion
        self.recurrence = savedReminders.first?.recurrence ?? proposedSuggestion?.recurrence ?? .weekdays
        self.weekdaysMask = savedReminders.first?.weekdaysMask ?? proposedSuggestion?.weekdaysMask ?? 127
        self.intervalDays = savedReminders.first?.intervalDays ?? proposedSuggestion?.intervalDays ?? 1
        self.anchorDay = savedReminders.first?.anchorDay ?? LocalDay(containing: Date(), in: .autoupdatingCurrent)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("supplements.reminders.title")
        view.backgroundColor = WellnarioPalette.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.text("supplements.reminders.save"),
            style: .done,
            target: self,
            action: #selector(saveTapped)
        )
        setUpView()
        rebuildRows()
    }

    private func setUpView() {
        view.addForAutoLayout(scrollView)
        scrollView.pinEdges(to: view)
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false

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

        let intro = PremiumCardView()
        let introStack = UIStackView()
        introStack.axis = .vertical
        introStack.spacing = 8
        let heading = UILabel()
        heading.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        heading.text = supplement.name
        heading.numberOfLines = 0
        let body = UILabel()
        body.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        body.text = L10n.text("supplements.reminders.body")
        body.numberOfLines = 0
        introStack.addArrangedSubview(heading)
        introStack.addArrangedSubview(body)
        intro.contentView.addForAutoLayout(introStack)
        introStack.pinEdges(to: intro.contentView, insets: .all(WellnarioSpacing.cardPadding))
        contentStack.addArrangedSubview(intro)

        buildSharedScheduleControls()

        remindersStack.axis = .vertical
        remindersStack.spacing = WellnarioSpacing.cardGap
        contentStack.addArrangedSubview(remindersStack)
        addButton.setTitle(L10n.text("supplements.reminders.add"), for: .normal)
        addButton.addTarget(self, action: #selector(addReminder), for: .touchUpInside)
        contentStack.addArrangedSubview(addButton)
    }

    private func buildSharedScheduleControls() {
        let card = PremiumCardView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        let title = UILabel()
        title.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        title.text = L10n.text("supplements.reminders.schedule.title")
        stack.addArrangedSubview(title)

        modeControl.insertSegment(withTitle: L10n.text("supplements.reminders.schedule.weekdays"), at: 0, animated: false)
        modeControl.insertSegment(withTitle: L10n.text("supplements.reminders.schedule.every_days"), at: 1, animated: false)
        modeControl.selectedSegmentIndex = recurrence == .weekdays ? 0 : 1
        modeControl.addTarget(self, action: #selector(scheduleModeChanged), for: .valueChanged)
        stack.addArrangedSubview(modeControl)

        weekdaysStack.axis = .horizontal
        weekdaysStack.distribution = .fillEqually
        weekdaysStack.spacing = 4
        let symbols = Calendar.autoupdatingCurrent.veryShortStandaloneWeekdaySymbols
        for weekday in [2, 3, 4, 5, 6, 7, 1] {
            let button = UIButton(type: .system)
            button.tag = weekday
            button.setTitle(symbols[weekday - 1], for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
            button.layer.cornerRadius = 8
            button.addTarget(self, action: #selector(scheduleWeekdayTapped(_:)), for: .touchUpInside)
            weekdaysStack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(weekdaysStack)

        intervalField.configure(
            title: L10n.text("supplements.reminders.interval"),
            placeholder: "2",
            text: intervalDays == 1 ? nil : "\(intervalDays)",
            keyboardType: .numberPad
        )
        intervalField.textField.addTarget(self, action: #selector(scheduleIntervalChanged), for: .editingDidEnd)
        stack.addArrangedSubview(intervalField)
        card.contentView.addForAutoLayout(stack)
        stack.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.cardPadding))
        contentStack.addArrangedSubview(card)
        updateSharedScheduleVisibility()
        updateSharedWeekdayAppearance()
    }

    private func rebuildRows() {
        remindersStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, reminder) in reminders.enumerated() {
            let row = SupplementReminderRowView(reminder: reminder, onChange: { [weak self] value in
                guard let self, self.reminders.indices.contains(index) else { return }
                self.reminders[index] = value
            }, onDelete: { [weak self] in
                guard let self, self.reminders.indices.contains(index) else { return }
                self.reminders.remove(at: index)
                self.rebuildRows()
            })
            remindersStack.addArrangedSubview(row)
        }
        addButton.isHidden = reminders.count >= 3
    }

    @objc private func addReminder() {
        guard reminders.count < 3 else { return }
        let suggestedTime = suggestion?.timeMinutes[
            min(reminders.count, max(0, (suggestion?.timeMinutes.count ?? 1) - 1))
        ] ?? SupplementReminderTemplate.anytime.defaultMinutes
        reminders.append(
            SupplementProductReminder(
                supplementID: supplement.id,
                timeMinutes: suggestedTime
            )
        )
        rebuildRows()
    }

    @objc private func cancelTapped() {
        if onSaveDraft != nil {
            navigationController?.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    @objc private func saveTapped() {
        if recurrence == .weekdays && weekdaysMask == 0 {
                showAlert(message: L10n.text("supplements.reminders.invalid_weekdays"))
                return
        }
        if recurrence == .everyDays && intervalDays < 1 {
                showAlert(message: L10n.text("supplements.reminders.invalid_interval"))
                return
        }
        let normalized = reminders.map {
            SupplementProductReminder(
                id: $0.id,
                supplementID: supplement.id,
                timeMinutes: $0.timeMinutes,
                recurrence: recurrence,
                weekdaysMask: weekdaysMask,
                intervalDays: intervalDays,
                anchorDay: anchorDay
            )
        }
        if let onSaveDraft {
            onSaveDraft(normalized)
            navigationController?.popViewController(animated: true)
        } else {
            store.set(normalized, for: supplement.id)
            SupplementReminderNotificationScheduler(repository: repository, store: store).reschedule()
            dismiss(animated: true)
        }
    }

    private func updateSharedScheduleVisibility() {
        weekdaysStack.isHidden = recurrence != .weekdays
        intervalField.isHidden = recurrence != .everyDays
    }

    private func updateSharedWeekdayAppearance() {
        for case let button as UIButton in weekdaysStack.arrangedSubviews {
            let selected = weekdaysMask & (1 << (button.tag - 1)) != 0
            button.backgroundColor = selected ? WellnarioPalette.fuchsia : WellnarioPalette.surfacePressed
            button.setTitleColor(selected ? .white : WellnarioPalette.textSecondary, for: .normal)
        }
    }

    @objc private func scheduleModeChanged() {
        recurrence = modeControl.selectedSegmentIndex == 0 ? .weekdays : .everyDays
        updateSharedScheduleVisibility()
    }

    @objc private func scheduleWeekdayTapped(_ sender: UIButton) {
        let bit = 1 << (sender.tag - 1)
        weekdaysMask = weekdaysMask & bit == 0 ? weekdaysMask | bit : weekdaysMask & ~bit
        updateSharedWeekdayAppearance()
    }

    @objc private func scheduleIntervalChanged() {
        if let value = Int(intervalField.textField.text ?? ""), value > 0 { intervalDays = value }
    }

    private func showAlert(message: String) {
        let alert = UIAlertController(title: L10n.Common.error, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.Common.done, style: .default))
        present(alert, animated: true)
    }
}

@MainActor
private final class SupplementReminderRowView: PremiumCardView {
    private var reminder: SupplementProductReminder
    private let onChange: (SupplementProductReminder) -> Void
    private let onDelete: () -> Void
    private let timePicker = UIDatePicker()
    private let templatesStack = UIStackView()

    init(
        reminder: SupplementProductReminder,
        onChange: @escaping (SupplementProductReminder) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.reminder = reminder
        self.onChange = onChange
        self.onDelete = onDelete
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8
        let title = UILabel()
        title.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        title.text = L10n.text("supplements.reminders.title")
        let delete = UIButton(type: .system)
        delete.setImage(UIImage(systemName: "trash"), for: .normal)
        delete.tintColor = WellnarioPalette.textTertiary
        delete.accessibilityLabel = L10n.Common.delete
        delete.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        header.addArrangedSubview(title)
        header.addArrangedSubview(UIView())
        header.addArrangedSubview(delete)
        stack.addArrangedSubview(header)

        timePicker.datePickerMode = .time
        timePicker.preferredDatePickerStyle = .compact
        timePicker.date = Calendar.autoupdatingCurrent.date(bySettingHour: reminder.timeMinutes / 60, minute: reminder.timeMinutes % 60, second: 0, of: Date()) ?? Date()
        timePicker.addTarget(self, action: #selector(timeChanged), for: .valueChanged)
        let timeRow = UIStackView(arrangedSubviews: [label(L10n.text("supplements.reminders.time")), UIView(), timePicker], axis: .horizontal, spacing: 8, alignment: .center)
        stack.addArrangedSubview(timeRow)
        let templateTitle = UILabel()
        templateTitle.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        templateTitle.text = L10n.text("supplements.reminders.template")
        stack.addArrangedSubview(templateTitle)
        templatesStack.axis = .vertical
        templatesStack.spacing = 6
        templatesStack.distribution = .fillEqually
        let templates = SupplementReminderTemplate.allCases
        for start in stride(from: 0, to: templates.count, by: 2) {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 6
            row.distribution = .fillEqually
            for template in templates[start..<min(start + 2, templates.count)] {
                row.addArrangedSubview(makeTemplateButton(template))
            }
            if row.arrangedSubviews.count == 1 { row.addArrangedSubview(UIView()) }
            templatesStack.addArrangedSubview(row)
        }
        stack.addArrangedSubview(templatesStack)
        contentView.addForAutoLayout(stack)
        stack.pinEdges(to: contentView, insets: .all(WellnarioSpacing.cardPadding))
    }

    private func label(_ text: String) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.body, color: WellnarioPalette.textPrimary)
        label.text = text
        return label
    }

    private func makeTemplateButton(_ template: SupplementReminderTemplate) -> ChipButton {
        let preferences = SupplementReminderSchedulePreferences()
        let button = ChipButton(title: L10n.text("settings.advanced.reminders.template.\(template.rawValue)"))
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.reminder.timeMinutes = preferences.minutes(for: template)
            self.timePicker.date = Calendar.autoupdatingCurrent.date(
                bySettingHour: self.reminder.timeMinutes / 60,
                minute: self.reminder.timeMinutes % 60,
                second: 0,
                of: Date()
            ) ?? Date()
            self.onChange(self.reminder)
        }, for: .touchUpInside)
        return button
    }

    @objc private func deleteTapped() { onDelete() }

    @objc private func timeChanged() {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: timePicker.date)
        if let hour = components.hour, let minute = components.minute { reminder.timeMinutes = hour * 60 + minute }
        onChange(reminder)
    }

}

@MainActor
final class SupplementReminderProductPickerViewController: FeatureViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var supplements: [Supplement] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("supplements.reminders.title")
        view.addForAutoLayout(tableView)
        tableView.pinEdges(to: view)
        tableView.backgroundColor = WellnarioPalette.background
        tableView.contentInset = UIEdgeInsets(
            top: 8,
            left: 0,
            bottom: WellnarioSpacing.bottomNavigationInset,
            right: 0
        )
        tableView.verticalScrollIndicatorInsets.bottom = WellnarioSpacing.bottomNavigationInset
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "supplement.reminder.product")
        reloadContent()
    }

    override func reloadContent() {
        do {
            _ = SupplementProductReminderStore().removeLegacyUnconfirmedSuggestions()
            supplements = try repository.fetchSupplements(includeArchived: false)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            tableView.reloadData()
        } catch { showError(error) }
    }
}

extension SupplementReminderProductPickerViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { supplements.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "supplement.reminder.product", for: indexPath)
        let supplement = supplements[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = supplement.name
        content.secondaryText = supplement.brand.isEmpty ? nil : supplement.brand
        if let photo = SupplementPhotoStore.image(
            reference: supplement.imageReference,
            databaseURL: repository.databaseURL
        ) {
            content.image = photo
            content.imageProperties.maximumSize = CGSize(width: 48, height: 48)
            content.imageProperties.reservedLayoutSize = CGSize(width: 48, height: 48)
        } else {
            content.image = UIImage(systemName: "pills.fill")
            content.imageProperties.tintColor = WellnarioPalette.fuchsia
            content.imageProperties.reservedLayoutSize = CGSize(width: 48, height: 48)
        }
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "supplements.reminder.product.\(supplement.id.uuidString)"
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        presentSheet(
            SupplementReminderEditorViewController(repository: repository, supplement: supplements[indexPath.row]),
            largeOnly: true
        )
    }
}
