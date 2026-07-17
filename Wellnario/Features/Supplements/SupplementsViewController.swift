import UIKit

@MainActor
final class SupplementsViewController: FeatureViewController {
    private enum Mode: Int { case products, inventory, actives }
    private enum ActiveFilter: Equatable {
        case all
        case favorites
        case category(ActiveCategory)
    }

    var onOpenSettings: (() -> Void)?

    private let segmentedControl = UISegmentedControl(items: ["", "", ""])
    private let categoryFilterScrollView = UIScrollView()
    private let categoryFilterStack = UIStackView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchController = UISearchController(searchResultsController: nil)
    private let emptyState = EmptyStateView()
    private let addBarButtonItem = UIBarButtonItem()
    private let intakeBarButtonItem = UIBarButtonItem()
    private let moreBarButtonItem = UIBarButtonItem()
    private let trendsBarButtonItem = UIBarButtonItem()
    private let settingsBarButtonItem = UIBarButtonItem()

    private var mode: Mode = .products
    private var presentations: [PresentationType] = []
    private var supplements: [Supplement] = []
    private var instances: [SupplementInstance] = []
    private var actives: [Active] = []
    private var todayProgress: [UUID: ActiveDailyProgress] = [:]
    private var weeklyConsumption: [UUID: [Double]] = [:]
    private var query = ""
    private var selectedActiveFilter: ActiveFilter = .all
    private var activeFilterButtons: [(filter: ActiveFilter, button: ChipButton)] = []
    private var categoryFilterHeightConstraint: NSLayoutConstraint!

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpView()
        applyLocalizedCopy()
        reloadContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never
        reloadContent()
    }

    override func applyLocalizedCopy() {
        title = L10n.Supplements.title
        segmentedControl.setTitle(L10n.Supplements.products, forSegmentAt: 0)
        segmentedControl.setTitle(L10n.Supplements.inventory, forSegmentAt: 1)
        segmentedControl.setTitle(L10n.Supplements.actives, forSegmentAt: 2)
        updateSearchPlaceholder()
        addBarButtonItem.accessibilityLabel = addButtonTitle
        intakeBarButtonItem.accessibilityLabel = L10n.Today.logIntake
        moreBarButtonItem.accessibilityLabel = L10n.text("supplements.more.accessibility")
        trendsBarButtonItem.accessibilityLabel = L10n.Trends.title
        settingsBarButtonItem.accessibilityLabel = L10n.Settings.title
        moreBarButtonItem.menu = makeMoreMenu()
        updateTopBarButtons()
        categoryFilterScrollView.accessibilityLabel = L10n.text("actives.categories.filter.accessibility")
        rebuildCategoryFilterButtons()
        tableView.reloadData()
        updateEmptyState()
    }

    override func reloadContent() {
        do {
            presentations = try repository.fetchPresentationTypes()
            supplements = try repository.fetchSupplements(includeArchived: false)
            instances = try repository.fetchInstances(supplementID: nil, includeArchived: false)
            actives = try repository.fetchActives(includeArchived: false)
            let today = LocalDay(containing: Date(), in: .current)
            let weekStart = try today.adding(days: -6)
            let weekDays = try (0..<7).map { try weekStart.adding(days: $0) }
            let weekConsumptions = try repository.fetchConsumptions(
                from: weekStart,
                through: today,
                limit: nil
            )
            weeklyConsumption = try WeeklyConsumptionAggregator.values(
                actives: actives,
                consumptions: weekConsumptions,
                days: weekDays
            )
            let dashboard = try repository.dashboard(
                on: today,
                expiringWithinDays: 30
            )
            todayProgress = Dictionary(uniqueKeysWithValues: dashboard.activeProgress.map { ($0.id, $0) })
            tableView.reloadData()
            updateEmptyState()
        } catch {
            showError(error)
        }
    }

    private func setUpView() {
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.navigationBar.prefersLargeTitles = false
        addBarButtonItem.image = UIImage(systemName: "plus")
        addBarButtonItem.style = .plain
        addBarButtonItem.target = self
        addBarButtonItem.action = #selector(addTapped)
        addBarButtonItem.tintColor = WellnarioPalette.cyan
        addBarButtonItem.accessibilityIdentifier = "supplements.add"

        intakeBarButtonItem.image = makeEatingPersonIcon()
        intakeBarButtonItem.style = .plain
        intakeBarButtonItem.target = self
        intakeBarButtonItem.action = #selector(logIntakeFromInventory)
        intakeBarButtonItem.tintColor = WellnarioPalette.fuchsia
        intakeBarButtonItem.accessibilityIdentifier = "supplements.log_intake"

        moreBarButtonItem.image = UIImage(systemName: "ellipsis.circle")
        moreBarButtonItem.style = .plain
        moreBarButtonItem.tintColor = WellnarioPalette.textSecondary
        moreBarButtonItem.accessibilityIdentifier = "supplements.more"

        trendsBarButtonItem.image = UIImage(systemName: "chart.xyaxis.line")
        trendsBarButtonItem.style = .plain
        trendsBarButtonItem.target = self
        trendsBarButtonItem.action = #selector(openTrends)
        trendsBarButtonItem.tintColor = WellnarioPalette.fuchsia
        trendsBarButtonItem.accessibilityIdentifier = "supplements.trends"

        settingsBarButtonItem.image = UIImage(systemName: "gearshape")
        settingsBarButtonItem.style = .plain
        settingsBarButtonItem.target = self
        settingsBarButtonItem.action = #selector(openSettings)
        settingsBarButtonItem.accessibilityIdentifier = "supplements.settings"
        updateTopBarButtons()

        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        searchController.searchBar.searchTextField.backgroundColor = WellnarioPalette.surfaceElevated
        searchController.searchBar.searchTextField.textColor = WellnarioPalette.textPrimary
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = true
        definesPresentationContext = true

        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.selectedSegmentTintColor = WellnarioPalette.fuchsia
        segmentedControl.backgroundColor = WellnarioPalette.surface
        segmentedControl.setTitleTextAttributes([
            .foregroundColor: WellnarioPalette.textSecondary,
            .font: WellnarioTypography.font(for: .caption)
        ], for: .normal)
        segmentedControl.setTitleTextAttributes([
            .foregroundColor: UIColor.white,
            .font: WellnarioTypography.font(for: .caption)
        ], for: .selected)
        segmentedControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        view.addForAutoLayout(segmentedControl)

        categoryFilterScrollView.showsHorizontalScrollIndicator = false
        categoryFilterScrollView.alwaysBounceHorizontal = true
        categoryFilterScrollView.isHidden = true
        categoryFilterStack.axis = .horizontal
        categoryFilterStack.alignment = .center
        categoryFilterStack.spacing = WellnarioSpacing.xSmall
        categoryFilterScrollView.addForAutoLayout(categoryFilterStack)
        view.addForAutoLayout(categoryFilterScrollView)
        categoryFilterHeightConstraint = categoryFilterScrollView.heightAnchor.constraint(equalToConstant: 0)

        tableView.backgroundColor = WellnarioPalette.background
        tableView.isOpaque = true
        let tableBackgroundView = UIView()
        tableBackgroundView.backgroundColor = WellnarioPalette.background
        tableBackgroundView.isOpaque = true
        tableView.backgroundView = tableBackgroundView
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: WellnarioSpacing.bottomNavigationInset, right: 0)
        tableView.verticalScrollIndicatorInsets.bottom = WellnarioSpacing.bottomNavigationInset
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(CatalogListCell.self, forCellReuseIdentifier: CatalogListCell.reuseIdentifier)
        view.addForAutoLayout(tableView)

        emptyState.onAction = { [weak self] in self?.addTapped() }
        view.addForAutoLayout(emptyState)

        NSLayoutConstraint.activate([
            segmentedControl.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: WellnarioSpacing.screenHorizontal),
            segmentedControl.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -WellnarioSpacing.screenHorizontal),
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: WellnarioSpacing.xSmall),
            segmentedControl.heightAnchor.constraint(equalToConstant: 40),

            categoryFilterScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            categoryFilterScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            categoryFilterScrollView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: WellnarioSpacing.xxSmall),
            categoryFilterHeightConstraint,

            categoryFilterStack.leadingAnchor.constraint(equalTo: categoryFilterScrollView.contentLayoutGuide.leadingAnchor, constant: WellnarioSpacing.screenHorizontal),
            categoryFilterStack.trailingAnchor.constraint(equalTo: categoryFilterScrollView.contentLayoutGuide.trailingAnchor, constant: -WellnarioSpacing.screenHorizontal),
            categoryFilterStack.topAnchor.constraint(equalTo: categoryFilterScrollView.contentLayoutGuide.topAnchor),
            categoryFilterStack.bottomAnchor.constraint(equalTo: categoryFilterScrollView.contentLayoutGuide.bottomAnchor),
            categoryFilterStack.heightAnchor.constraint(equalTo: categoryFilterScrollView.frameLayoutGuide.heightAnchor),

            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: categoryFilterScrollView.bottomAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyState.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: WellnarioSpacing.screenHorizontal),
            emptyState.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -WellnarioSpacing.screenHorizontal),
            emptyState.topAnchor.constraint(equalTo: categoryFilterScrollView.bottomAnchor),
            emptyState.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -WellnarioSpacing.bottomNavigationInset)
        ])
    }

    private var addButtonTitle: String {
        switch mode {
        case .products: L10n.Supplements.addSupplement
        case .inventory: L10n.Inventory.add
        case .actives: L10n.Actives.add
        }
    }

    private func makeMoreMenu() -> UIMenu {
        let archived = UIAction(
            title: L10n.text("archive.title"),
            image: UIImage(systemName: "archivebox")
        ) { [weak self] _ in
            guard let self else { return }
            self.navigationController?.pushViewController(
                ArchivedItemsViewController(repository: self.repository),
                animated: true
            )
        }
        return UIMenu(children: [archived])
    }

    private var filteredSupplements: [Supplement] {
        guard !query.isEmpty else { return supplements }
        return supplements.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.brand.localizedCaseInsensitiveContains(query)
                || ($0.category?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var filteredInstances: [SupplementInstance] {
        guard !query.isEmpty else { return instances }
        return instances.filter { instance in
            instance.label.localizedCaseInsensitiveContains(query)
                || supplement(for: instance)?.name.localizedCaseInsensitiveContains(query) == true
                || supplement(for: instance)?.brand.localizedCaseInsensitiveContains(query) == true
        }
    }

    private var filteredActives: [Active] {
        let filterMatches: [Active]
        switch selectedActiveFilter {
        case .all:
            filterMatches = actives
        case .favorites:
            filterMatches = actives.filter(\.isFavorite)
        case let .category(category):
            filterMatches = actives.filter { $0.categories.contains(category) }
        }
        guard !query.isEmpty else { return filterMatches }
        return filterMatches.filter {
            $0.localizedName(language: catalogLanguage).localizedCaseInsensitiveContains(query)
        }
    }

    private var visibleCount: Int {
        switch mode {
        case .products: filteredSupplements.count
        case .inventory: filteredInstances.count
        case .actives: filteredActives.count
        }
    }

    private func updateEmptyState() {
        let isEmpty = visibleCount == 0
        emptyState.isHidden = !isEmpty
        tableView.isHidden = isEmpty
        guard isEmpty else { return }

        if !query.isEmpty {
            emptyState.configure(
                kind: .other,
                title: L10n.text("search.empty.title"),
                message: L10n.text("search.empty.message"),
                actionTitle: nil
            )
            return
        }
        if mode == .actives {
            switch selectedActiveFilter {
            case .all:
                break
            case .favorites:
                emptyState.configure(
                    kind: .other,
                    title: L10n.text("actives.favorites.empty.title"),
                    message: L10n.text("actives.favorites.empty.message"),
                    actionTitle: nil
                )
                return
            case .category:
                emptyState.configure(
                    kind: .other,
                    title: L10n.text("actives.categories.empty.title"),
                    message: L10n.text("actives.categories.empty.message"),
                    actionTitle: nil
                )
                return
            }
        }
        switch mode {
        case .products:
            emptyState.configure(kind: .capsule, title: L10n.Supplements.noProductsTitle, message: L10n.Supplements.noProductsMessage, actionTitle: addButtonTitle)
        case .inventory:
            emptyState.configure(kind: .sachet, title: L10n.Inventory.noItemsTitle, message: L10n.Inventory.noItemsMessage, actionTitle: addButtonTitle)
        case .actives:
            emptyState.configure(kind: .other, title: L10n.Actives.noItemsTitle, message: L10n.Actives.noItemsMessage, actionTitle: addButtonTitle)
        }
    }

    private func supplement(for instance: SupplementInstance) -> Supplement? {
        supplements.first { $0.id == instance.supplementID }
    }

    private func presentation(for supplement: Supplement) -> PresentationType? {
        presentations.first { $0.id == supplement.presentationTypeID }
    }

    private func presentationKind(for supplement: Supplement) -> PresentationKind {
        guard let presentation = presentation(for: supplement) else { return .other }
        return PresentationKind(name: presentation.localizedName(language: catalogLanguage))
    }

    private func configureProduct(_ cell: CatalogListCell, supplement: Supplement) {
        let presentation = presentation(for: supplement)
        let count = instances.filter { $0.supplementID == supplement.id }.count
        let showsComponentAmounts = supplement.basisUnit.family == .discrete
        let componentSummary = supplement.components.prefix(2).compactMap { component in
            actives.first(where: { $0.id == component.activeID }).map {
                if showsComponentAmounts {
                    return "\($0.localizedName(language: catalogLanguage)) \(FeatureFormatting.decimal(component.amount)) \(component.unit.symbol(languageCode: catalogLanguage.rawValue))"
                }
                return $0.localizedName(language: catalogLanguage)
            }
        }.joined(separator: " · ")
        let subtitle = [supplement.brand, presentation?.localizedName(language: catalogLanguage)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        cell.configure(
            kind: presentationKind(for: supplement),
            image: SupplementPhotoStore.image(
                reference: supplement.imageReference,
                databaseURL: repository.databaseURL
            ),
            title: supplement.name,
            subtitle: subtitle,
            detail: componentSummary.isEmpty ? L10n.text("supplements.no_components") : componentSummary,
            badge: L10n.text("inventory.count", count),
            tone: count == 0 ? .warning : .success
        )
    }

    private func configureInstance(_ cell: CatalogListCell, instance: SupplementInstance) {
        let supplement = supplement(for: instance)
        let remainingLevel = inventoryLevel(for: instance)
        let remainingContent = instance.totalQuantity.flatMap { quantity in
            instance.totalUnit.map {
                L10n.text(
                    "inventory.remaining_content.value",
                    "\(FeatureFormatting.decimal(quantity)) \($0.symbol(languageCode: catalogLanguage.rawValue))"
                )
            }
        }
        let expirationText = FeatureFormatting.expirationText(instance.expirationDay)
        cell.configure(
            kind: supplement.map(presentationKind(for:)) ?? .other,
            image: supplement.flatMap {
                SupplementPhotoStore.image(reference: $0.imageReference, databaseURL: repository.databaseURL)
            },
            title: supplement?.name ?? instance.label,
            subtitle: instance.label,
            scrollsSubtitle: true,
            detail: [remainingContent, expirationText]
                .compactMap { $0 }
                .joined(separator: " · "),
            highlightedDetail: instance.expirationDay.map { (expirationText, expirationTone($0)) },
            inventoryLevel: remainingLevel,
            badge: nil,
            tone: .neutral
        )
    }

    private func inventoryLevel(for instance: SupplementInstance) -> Double? {
        guard let remainingQuantity = instance.totalQuantity,
              let remainingUnit = instance.totalUnit,
              let initialQuantity = instance.initialQuantity,
              let initialUnit = instance.initialUnit,
              initialQuantity > 0,
              remainingUnit.isCompatible(with: initialUnit),
              let normalizedRemaining = try? remainingUnit.convert(remainingQuantity, to: initialUnit),
              let quotient = try? DecimalMath.divide(normalizedRemaining, initialQuantity) else {
            return nil
        }
        return min(1, max(0, NSDecimalNumber(decimal: quotient).doubleValue))
    }

    private func configureActive(_ cell: CatalogListCell, active: Active) {
        let progress = todayProgress[active.id]
        let weeklyValues = weeklyConsumption[active.id] ?? Array(repeating: 0, count: 7)
        let weeklyTotal = weeklyValues.reduce(0, +)
        let unit = active.baseUnit.symbol(languageCode: catalogLanguage.rawValue)
        let target = active.currentTarget.map {
            let amount = $0.lowerBound == $0.upperBound
                ? FeatureFormatting.decimal($0.lowerBound)
                : "\(FeatureFormatting.decimal($0.lowerBound))–\(FeatureFormatting.decimal($0.upperBound))"
            return "\(amount) \($0.unit.symbol(languageCode: catalogLanguage.rawValue))"
        } ?? L10n.text("actives.target.not_set.short")
        let consumed = progress.map {
            "\(FeatureFormatting.decimal($0.consumedAmount)) \($0.unit.symbol(languageCode: catalogLanguage.rawValue))"
        } ?? "—"
        cell.configure(
            kind: .other,
            imageKey: active.imageKey,
            compact: true,
            title: active.localizedName(language: catalogLanguage),
            subtitle: L10n.text("actives.today", consumed),
            detail: L10n.text("actives.target.value", target),
            favoriteStatus: active.isFavorite,
            weeklyValues: weeklyValues,
            weeklySummary: L10n.text(
                "actives.weekly_consumption.summary",
                "\(WellnarioFormatters.number(weeklyTotal, maximumFractionDigits: 2)) \(unit)"
            ),
            badge: nil,
            tone: .neutral
        )
    }

    private func expirationTone(_ day: LocalDay) -> WellnarioTone {
        let today = LocalDay(containing: Date(), in: .current)
        if day < today { return .danger }
        if let warning = try? today.adding(days: 30), day <= warning {
            return .warning
        }
        return .success
    }

    @objc private func modeChanged() {
        mode = Mode(rawValue: segmentedControl.selectedSegmentIndex) ?? .products
        addBarButtonItem.accessibilityLabel = addButtonTitle
        updateTopBarButtons()
        updateSearchPlaceholder()
        updateCategoryFilterVisibility()
        updateEmptyState()
        tableView.layer.removeAllAnimations()
        UIView.performWithoutAnimation {
            tableView.reloadData()
            tableView.layoutIfNeeded()
        }
    }

    private func updateSearchPlaceholder() {
        searchController.searchBar.placeholder = mode == .actives
            ? L10n.text("actives.search.placeholder")
            : L10n.Common.search
    }

    private func rebuildCategoryFilterButtons() {
        categoryFilterStack.arrangedSubviews.forEach { view in
            categoryFilterStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        activeFilterButtons.removeAll()

        addActiveFilterButton(
            title: L10n.text("actives.categories.all"),
            filter: .all,
            accessibilityIdentifier: "actives.category.all"
        )
        addActiveFilterButton(
            title: L10n.text("actives.favorites"),
            filter: .favorites,
            accessibilityIdentifier: "actives.category.favorites"
        )
        for category in ActiveCategory.allCases {
            addActiveFilterButton(
                title: category.localizedName(language: catalogLanguage),
                filter: .category(category),
                accessibilityIdentifier: "actives.category.\(category.rawValue)"
            )
        }
        updateActiveFilterButtonSelection()
    }

    private func addActiveFilterButton(
        title: String,
        filter: ActiveFilter,
        accessibilityIdentifier: String
    ) {
        let button = ChipButton(title: title)
        button.accessibilityIdentifier = accessibilityIdentifier
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let button else { return }
            self?.selectActiveFilter(filter, button: button)
        }, for: .touchUpInside)
        activeFilterButtons.append((filter, button))
        categoryFilterStack.addArrangedSubview(button)
    }

    private func selectActiveFilter(_ filter: ActiveFilter, button: ChipButton) {
        guard selectedActiveFilter != filter else { return }
        selectedActiveFilter = filter
        updateActiveFilterButtonSelection()
        tableView.setContentOffset(
            CGPoint(x: 0, y: -tableView.adjustedContentInset.top),
            animated: false
        )
        tableView.reloadData()
        updateEmptyState()
        let visibleRect = button.convert(button.bounds, to: categoryFilterScrollView)
            .insetBy(dx: -WellnarioSpacing.small, dy: 0)
        categoryFilterScrollView.scrollRectToVisible(visibleRect, animated: true)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func updateActiveFilterButtonSelection() {
        for item in activeFilterButtons {
            item.button.isSelected = item.filter == selectedActiveFilter
        }
    }

    private func updateCategoryFilterVisibility() {
        let shouldShow = mode == .actives
        categoryFilterScrollView.isHidden = !shouldShow
        categoryFilterHeightConstraint.constant = shouldShow ? 52 : 0
        view.setNeedsLayout()
    }

    @objc private func openSettings() { onOpenSettings?() }

    @objc private func openTrends() {
        guard mode == .actives, let navigationController else { return }
        searchController.isActive = false
        view.endEditing(true)
        navigationController.pushViewController(
            TrendsViewController(repository: repository),
            animated: true
        )
    }

    private func updateTopBarButtons() {
        var items = [settingsBarButtonItem, addBarButtonItem]
        if mode == .inventory { items.append(intakeBarButtonItem) }
        if mode == .actives { items.append(trendsBarButtonItem) }
        items.append(moreBarButtonItem)
        navigationItem.rightBarButtonItems = items
    }

    private func makeEatingPersonIcon() -> UIImage? {
        let faceConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        let utensilConfiguration = UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        guard let face = UIImage(systemName: "face.smiling", withConfiguration: faceConfiguration),
              let utensil = UIImage(systemName: "fork.knife", withConfiguration: utensilConfiguration) else {
            return UIImage(systemName: "fork.knife.circle")
        }

        let size = CGSize(width: 27, height: 22)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.black.setFill()
            face.withTintColor(.black, renderingMode: .alwaysOriginal).draw(
                in: CGRect(x: 0, y: 1, width: 20, height: 20)
            )
            utensil.withTintColor(.black, renderingMode: .alwaysOriginal).draw(
                in: CGRect(x: 18, y: 11, width: 9, height: 9)
            )
        }.withRenderingMode(.alwaysTemplate)
    }

    @objc private func logIntakeFromInventory() {
        guard mode == .inventory else { return }
        do {
            guard !(try repository.fetchInstances(
                supplementID: nil,
                includeArchived: false
            )).isEmpty else {
                let alert = UIAlertController(
                    title: L10n.Inventory.noItemsTitle,
                    message: L10n.text("intake.requires_batch"),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
                alert.addAction(UIAlertAction(title: L10n.Inventory.add, style: .default) { [weak self] _ in
                    self?.addTapped()
                })
                present(alert, animated: true)
                return
            }
            searchController.isActive = false
            view.endEditing(true)
            presentSheet(IntakeEditorViewController(repository: repository), largeOnly: true)
        } catch {
            showError(error)
        }
    }

    @objc private func addTapped() {
        switch mode {
        case .products:
            presentSheet(ProductPackageWizardViewController(repository: repository), largeOnly: true)
        case .inventory:
            guard !supplements.isEmpty else {
                let alert = UIAlertController(title: L10n.Inventory.noItemsTitle, message: L10n.text("inventory.requires_supplement"), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
                alert.addAction(UIAlertAction(title: L10n.Supplements.addSupplement, style: .default) { [weak self] _ in
                    guard let self else { return }
                    self.presentSheet(ProductPackageWizardViewController(repository: self.repository), largeOnly: true)
                })
                present(alert, animated: true)
                return
            }
            presentSheet(InstanceEditorViewController(repository: repository), largeOnly: true)
        case .actives:
            presentSheet(ActiveEditorViewController(repository: repository), largeOnly: true)
        }
    }

    private func edit(at indexPath: IndexPath) {
        switch mode {
        case .products:
            presentSheet(SupplementEditorViewController(repository: repository, supplement: filteredSupplements[indexPath.row]), largeOnly: true)
        case .inventory:
            presentSheet(InstanceEditorViewController(repository: repository, instance: filteredInstances[indexPath.row]), largeOnly: true)
        case .actives:
            presentSheet(ActiveEditorViewController(repository: repository, active: filteredActives[indexPath.row]), largeOnly: true)
        }
    }

    private func delete(at indexPath: IndexPath) {
        let confirmationMessage = mode == .products
            ? L10n.text("supplements.delete.message")
            : L10n.text("delete.confirmation")
        showConfirmation(title: L10n.Common.delete, message: confirmationMessage) { [weak self] in
            guard let self else { return }
            do {
                switch self.mode {
                case .products: _ = try self.repository.deleteSupplement(id: self.filteredSupplements[indexPath.row].id)
                case .inventory: _ = try self.repository.deleteInstance(id: self.filteredInstances[indexPath.row].id)
                case .actives: _ = try self.repository.deleteActive(id: self.filteredActives[indexPath.row].id)
                }
                UIImpactFeedbackGenerator.wellnarioSuccess()
            } catch { self.showError(error) }
        }
    }
}

extension SupplementsViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        tableView.reloadData()
        updateEmptyState()
    }
}

extension SupplementsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { visibleCount }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: CatalogListCell.reuseIdentifier, for: indexPath) as! CatalogListCell
        switch mode {
        case .products: configureProduct(cell, supplement: filteredSupplements[indexPath.row])
        case .inventory: configureInstance(cell, instance: filteredInstances[indexPath.row])
        case .actives: configureActive(cell, active: filteredActives[indexPath.row])
        }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        mode == .actives ? 108 : 132
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch mode {
        case .products:
            navigationController?.pushViewController(
                SupplementDetailViewController(repository: repository, supplementID: filteredSupplements[indexPath.row].id),
                animated: true
            )
        case .inventory:
            presentSheet(InstanceEditorViewController(repository: repository, instance: filteredInstances[indexPath.row]), largeOnly: true)
        case .actives:
            showActiveDetail(for: filteredActives[indexPath.row])
        }
    }

    private func showActiveDetail(for active: Active) {
        guard let navigationController else { return }
        let detail = ActiveDetailViewController(repository: repository, activeID: active.id)

        guard WellnarioMotion.animationsEnabled else {
            navigationController.pushViewController(detail, animated: false)
            return
        }

        UIView.transition(
            with: navigationController.view,
            duration: WellnarioMotion.standard,
            options: [.transitionCrossDissolve, .allowAnimatedContent, .beginFromCurrentState]
        ) {
            navigationController.pushViewController(detail, animated: false)
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: L10n.Common.delete) { [weak self] _, _, completion in
            self?.delete(at: indexPath)
            completion(true)
        }
        delete.image = UIImage(systemName: "archivebox")
        let edit = UIContextualAction(style: .normal, title: L10n.Common.edit) { [weak self] _, _, completion in
            self?.edit(at: indexPath)
            completion(true)
        }
        edit.backgroundColor = WellnarioPalette.violet
        edit.image = UIImage(systemName: "pencil")
        let configuration = UISwipeActionsConfiguration(actions: [delete, edit])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
}

enum WeeklyConsumptionAggregator {
    static func values(
        actives: [Active],
        consumptions: [Consumption],
        days: [LocalDay]
    ) throws -> [UUID: [Double]] {
        let activeByID = Dictionary(uniqueKeysWithValues: actives.map { ($0.id, $0) })
        var totals: [UUID: [LocalDay: Decimal]] = [:]

        for consumption in consumptions where days.contains(consumption.localDay) {
            for snapshot in consumption.activeSnapshots {
                guard let active = activeByID[snapshot.activeID] else { continue }
                let normalizedAmount = try snapshot.unit.convert(
                    snapshot.amount,
                    to: active.baseUnit
                )
                let currentAmount = totals[snapshot.activeID]?[consumption.localDay] ?? 0
                totals[snapshot.activeID, default: [:]][consumption.localDay] = try DecimalMath.add(
                    currentAmount,
                    normalizedAmount
                )
            }
        }

        return Dictionary(uniqueKeysWithValues: actives.map { active in
            let dailyTotals = totals[active.id] ?? [:]
            let values = days.map { day in
                NSDecimalNumber(decimal: dailyTotals[day] ?? 0).doubleValue
            }
            return (active.id, values)
        })
    }
}

@MainActor
private final class InventoryLevelBar: UIView {
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private var normalizedLevel: CGFloat?

    var level: Double? {
        didSet {
            normalizedLevel = level.map { min(1, max(0, CGFloat($0))) }
            isHidden = normalizedLevel == nil
            setNeedsLayout()
            updateAccessibility()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityIdentifier = "inventory.level.bar"
        layer.addSublayer(trackLayer)
        layer.addSublayer(fillLayer)
        trackLayer.backgroundColor = WellnarioPalette.textPrimary.withAlphaComponent(0.14).cgColor
        fillLayer.backgroundColor = WellnarioPalette.fuchsia.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let cornerRadius = bounds.height / 2
        trackLayer.frame = bounds
        trackLayer.cornerRadius = cornerRadius
        let width = bounds.width * (normalizedLevel ?? 0)
        fillLayer.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        fillLayer.cornerRadius = cornerRadius
    }

    private func updateAccessibility() {
        guard let normalizedLevel else {
            accessibilityLabel = nil
            accessibilityValue = nil
            return
        }
        let percentage = Int((normalizedLevel * 100).rounded())
        accessibilityLabel = L10n.text("inventory.remaining_progress.accessibility")
        accessibilityValue = "\(percentage)%"
    }
}

private final class CatalogListCell: UITableViewCell {
    static let reuseIdentifier = "CatalogListCell"

    private let card = PremiumCardView()
    private let artwork = PresentationArtworkView(kind: .capsule)
    private let artworkContainer = UIView()
    private let artworkStack = UIStackView()
    private let inventoryLevelBar = InventoryLevelBar()
    private let activeIconView = UIImageView()
    private let titleLabel = UILabel()
    private let favoriteImageView = UIImageView()
    private let subtitleLabel = ContinuousMarqueeLabel()
    private let detailLabel = UILabel()
    private let badgeLabel = UILabel()
    private let weeklyChartLabel = UILabel()
    private let weeklyChartView = SparklineView()
    private let weeklyChartStack = UIStackView()
    private var artworkSizeConstraint: NSLayoutConstraint!
    private var rowEdgeConstraints: [NSLayoutConstraint] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(
        kind: PresentationKind,
        imageKey: String? = nil,
        image: UIImage? = nil,
        compact: Bool = false,
        title: String,
        subtitle: String,
        scrollsSubtitle: Bool = false,
        detail: String,
        highlightedDetail: (text: String, tone: WellnarioTone)? = nil,
        favoriteStatus: Bool? = nil,
        weeklyValues: [Double]? = nil,
        weeklySummary: String? = nil,
        inventoryLevel: Double? = nil,
        badge: String?,
        tone: WellnarioTone
    ) {
        artwork.kind = kind
        artworkSizeConstraint.constant = compact ? 62 : 78
        let contentInset: CGFloat = compact ? 10 : 14
        rowEdgeConstraints.forEach { $0.constant = contentInset }
        let activeIcon = image ?? imageKey.flatMap { UIImage(named: $0) }
        activeIconView.image = activeIcon
        activeIconView.isHidden = activeIcon == nil
        artwork.isHidden = activeIcon != nil
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle.isEmpty
        subtitleLabel.isMarqueeEnabled = scrollsSubtitle
        inventoryLevelBar.level = inventoryLevel
        let attributedDetail = NSMutableAttributedString(
            string: detail,
            attributes: [.foregroundColor: WellnarioPalette.textTertiary]
        )
        if let highlightedDetail {
            let range = (detail as NSString).range(of: highlightedDetail.text)
            if range.location != NSNotFound {
                attributedDetail.addAttribute(
                    .foregroundColor,
                    value: WellnarioPalette.color(for: highlightedDetail.tone),
                    range: range
                )
            }
        }
        detailLabel.attributedText = attributedDetail
        if let favoriteStatus {
            favoriteImageView.image = UIImage(
                systemName: favoriteStatus ? "star.fill" : "star"
            )
            favoriteImageView.tintColor = favoriteStatus
                ? WellnarioPalette.fuchsia
                : WellnarioPalette.textTertiary
            favoriteImageView.isHidden = false
        } else {
            favoriteImageView.image = nil
            favoriteImageView.isHidden = true
        }
        if let weeklyValues {
            weeklyChartLabel.text = L10n.Trends.sevenDays
            weeklyChartView.values = weeklyValues
            weeklyChartView.accessibilityLabel = L10n.text("actives.weekly_consumption")
            weeklyChartView.accessibilityValue = weeklySummary
            weeklyChartStack.isHidden = false
        } else {
            weeklyChartView.values = []
            weeklyChartView.accessibilityLabel = nil
            weeklyChartView.accessibilityValue = nil
            weeklyChartStack.isHidden = true
        }
        badgeLabel.text = badge
        badgeLabel.isHidden = badge == nil
        badgeLabel.textColor = WellnarioPalette.color(for: tone)
        badgeLabel.backgroundColor = WellnarioPalette.color(for: tone).withAlphaComponent(0.12)
        let favoriteDescription = favoriteStatus.map {
            L10n.text(
                $0
                    ? "actives.favorite.accessibility.on"
                    : "actives.favorite.accessibility.off"
            )
        }
        accessibilityLabel = [title, favoriteDescription, subtitle, detail, weeklySummary, badge]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func setUp() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
        contentView.addForAutoLayout(card)
        card.pinEdges(to: contentView, insets: NSDirectionalEdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
        card.isUserInteractionEnabled = false

        artworkContainer.addForAutoLayout(artwork)
        artworkContainer.addForAutoLayout(activeIconView)
        artwork.pinEdges(to: artworkContainer)
        activeIconView.pinEdges(to: artworkContainer)
        activeIconView.contentMode = .scaleAspectFit
        activeIconView.isHidden = true
        activeIconView.isAccessibilityElement = false

        artworkSizeConstraint = artworkContainer.widthAnchor.constraint(equalToConstant: 78)
        NSLayoutConstraint.activate([
            artworkSizeConstraint,
            artworkContainer.heightAnchor.constraint(equalTo: artworkContainer.widthAnchor)
        ])

        artworkStack.axis = .vertical
        artworkStack.spacing = 6
        artworkStack.alignment = .fill
        artworkStack.addArrangedSubview(artworkContainer)
        artworkStack.addArrangedSubview(inventoryLevelBar)
        inventoryLevelBar.isHidden = true
        NSLayoutConstraint.activate([
            artworkStack.widthAnchor.constraint(equalTo: artworkContainer.widthAnchor),
            inventoryLevelBar.heightAnchor.constraint(equalToConstant: 5)
        ])

        titleLabel.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byWordWrapping
        favoriteImageView.contentMode = .scaleAspectFit
        favoriteImageView.isHidden = true
        favoriteImageView.isAccessibilityElement = false
        favoriteImageView.setContentHuggingPriority(.required, for: .horizontal)
        favoriteImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            favoriteImageView.widthAnchor.constraint(equalToConstant: 19),
            favoriteImageView.heightAnchor.constraint(equalToConstant: 19)
        ])
        detailLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        detailLabel.numberOfLines = 2

        badgeLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.cyan)
        badgeLabel.textAlignment = .center
        badgeLabel.applyContinuousCorners(9)
        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        badgeLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true

        weeklyChartLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        weeklyChartLabel.text = L10n.Trends.sevenDays
        weeklyChartLabel.textAlignment = .right
        weeklyChartView.lineColor = WellnarioPalette.fuchsia
        weeklyChartView.showsEndMarker = true
        weeklyChartView.includesZeroBaseline = true
        weeklyChartView.accessibilityIdentifier = "active.weekly.chart"
        weeklyChartStack.axis = .vertical
        weeklyChartStack.spacing = 0
        weeklyChartStack.alignment = .fill
        weeklyChartStack.addArrangedSubview(weeklyChartLabel)
        weeklyChartStack.addArrangedSubview(weeklyChartView)
        weeklyChartStack.isHidden = true
        weeklyChartStack.setContentHuggingPriority(.required, for: .horizontal)
        weeklyChartStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            weeklyChartStack.widthAnchor.constraint(equalToConstant: 66),
            weeklyChartView.heightAnchor.constraint(equalToConstant: 42)
        ])

        let titleRow = UIStackView(
            arrangedSubviews: [titleLabel, favoriteImageView, badgeLabel],
            axis: .horizontal,
            spacing: 8,
            alignment: .center
        )
        let labels = UIStackView(arrangedSubviews: [titleRow, subtitleLabel, detailLabel], axis: .vertical, spacing: 4)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = UIStackView(
            arrangedSubviews: [artworkStack, labels, weeklyChartStack],
            axis: .horizontal,
            spacing: 8,
            alignment: .center
        )
        row.setCustomSpacing(14, after: artworkStack)
        card.contentView.addForAutoLayout(row)
        rowEdgeConstraints = [
            row.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 14),
            row.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 14),
            card.contentView.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: 14),
            card.contentView.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: 14)
        ]
        NSLayoutConstraint.activate(rowEdgeConstraints)
    }
}
