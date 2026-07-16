import UIKit

@MainActor
final class SupplementsViewController: FeatureViewController {
    private enum Mode: Int { case products, inventory, actives }

    var onOpenSettings: (() -> Void)?

    private let segmentedControl = UISegmentedControl(items: ["", "", ""])
    private let categoryFilterScrollView = UIScrollView()
    private let categoryFilterStack = UIStackView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchController = UISearchController(searchResultsController: nil)
    private let emptyState = EmptyStateView()
    private let addBarButtonItem = UIBarButtonItem()
    private let moreBarButtonItem = UIBarButtonItem()
    private let settingsBarButtonItem = UIBarButtonItem()

    private var mode: Mode = .products
    private var presentations: [PresentationType] = []
    private var supplements: [Supplement] = []
    private var instances: [SupplementInstance] = []
    private var actives: [Active] = []
    private var todayProgress: [UUID: ActiveDailyProgress] = [:]
    private var query = ""
    private var selectedCategory: ActiveCategory?
    private var categoryButtons: [(category: ActiveCategory?, button: ChipButton)] = []
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
        reloadContent()
    }

    override func applyLocalizedCopy() {
        title = L10n.Supplements.title
        segmentedControl.setTitle(L10n.Supplements.products, forSegmentAt: 0)
        segmentedControl.setTitle(L10n.Supplements.inventory, forSegmentAt: 1)
        segmentedControl.setTitle(L10n.Supplements.actives, forSegmentAt: 2)
        updateSearchPlaceholder()
        addBarButtonItem.accessibilityLabel = addButtonTitle
        moreBarButtonItem.accessibilityLabel = L10n.text("supplements.more.accessibility")
        settingsBarButtonItem.accessibilityLabel = L10n.Settings.title
        moreBarButtonItem.menu = makeMoreMenu()
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
            let dashboard = try repository.dashboard(
                on: LocalDay(containing: Date(), in: .current),
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
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true
        addBarButtonItem.image = UIImage(systemName: "plus")
        addBarButtonItem.style = .plain
        addBarButtonItem.target = self
        addBarButtonItem.action = #selector(addTapped)
        addBarButtonItem.tintColor = WellnarioPalette.cyan
        addBarButtonItem.accessibilityIdentifier = "supplements.add"

        moreBarButtonItem.image = UIImage(systemName: "ellipsis.circle")
        moreBarButtonItem.style = .plain
        moreBarButtonItem.tintColor = WellnarioPalette.textSecondary
        moreBarButtonItem.accessibilityIdentifier = "supplements.more"

        settingsBarButtonItem.image = UIImage(systemName: "gearshape")
        settingsBarButtonItem.style = .plain
        settingsBarButtonItem.target = self
        settingsBarButtonItem.action = #selector(openSettings)
        settingsBarButtonItem.accessibilityIdentifier = "supplements.settings"
        navigationItem.rightBarButtonItems = [
            settingsBarButtonItem,
            addBarButtonItem,
            moreBarButtonItem
        ]

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

        tableView.backgroundColor = .clear
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
        let categoryFiltered = selectedCategory.map { category in
            actives.filter { $0.categories.contains(category) }
        } ?? actives
        guard !query.isEmpty else { return categoryFiltered }
        return categoryFiltered.filter {
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
        if mode == .actives, selectedCategory != nil {
            emptyState.configure(
                kind: .other,
                title: L10n.text("actives.categories.empty.title"),
                message: L10n.text("actives.categories.empty.message"),
                actionTitle: nil
            )
            return
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
        let componentSummary = supplement.components.prefix(2).compactMap { component in
            actives.first(where: { $0.id == component.activeID }).map {
                "\($0.localizedName(language: catalogLanguage)) \(FeatureFormatting.decimal(component.amount)) \(component.unit.symbol(languageCode: catalogLanguage.rawValue))"
            }
        }.joined(separator: " · ")
        let subtitle = [supplement.brand, presentation?.localizedName(language: catalogLanguage)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        cell.configure(
            kind: presentationKind(for: supplement),
            title: supplement.name,
            subtitle: subtitle,
            detail: componentSummary.isEmpty ? L10n.text("supplements.no_components") : componentSummary,
            badge: L10n.text("inventory.count", count),
            tone: count == 0 ? .warning : .success
        )
    }

    private func configureInstance(_ cell: CatalogListCell, instance: SupplementInstance) {
        let supplement = supplement(for: instance)
        let state = expirationState(instance.expirationDay)
        cell.configure(
            kind: supplement.map(presentationKind(for:)) ?? .other,
            title: instance.label,
            subtitle: [supplement?.brand, supplement?.name].compactMap { $0 }.joined(separator: " · "),
            detail: FeatureFormatting.expirationText(instance.expirationDay),
            badge: state.label,
            tone: state.tone
        )
    }

    private func configureActive(_ cell: CatalogListCell, active: Active) {
        let progress = todayProgress[active.id]
        let target = active.currentTarget.map {
            "\(FeatureFormatting.decimal($0.lowerBound))–\(FeatureFormatting.decimal($0.upperBound)) \($0.unit.symbol(languageCode: catalogLanguage.rawValue))"
        } ?? L10n.text("actives.target.not_set")
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
            badge: progress.map { statusLabel($0.status) },
            tone: progress.map { tone($0.status) } ?? .neutral
        )
    }

    private func expirationState(_ day: LocalDay?) -> (label: String, tone: WellnarioTone) {
        guard let day else { return (L10n.Common.noDate, .neutral) }
        let today = LocalDay(containing: Date(), in: .current)
        if day < today { return (L10n.text("expiry.expired"), .danger) }
        if let warning = try? today.adding(days: 30), day <= warning {
            return (L10n.text("expiry.soon"), .warning)
        }
        return (L10n.text("expiry.ok"), .success)
    }

    private func statusLabel(_ status: TargetProgressStatus) -> String {
        switch status {
        case .noTarget: L10n.text("target.no_target")
        case .below: L10n.text("target.below")
        case .within: L10n.text("target.within")
        case .above: L10n.text("target.above")
        }
    }

    private func tone(_ status: TargetProgressStatus) -> WellnarioTone {
        switch status {
        case .noTarget: .neutral
        case .below: .information
        case .within: .success
        case .above: .warning
        }
    }

    @objc private func modeChanged() {
        mode = Mode(rawValue: segmentedControl.selectedSegmentIndex) ?? .products
        addBarButtonItem.accessibilityLabel = addButtonTitle
        updateSearchPlaceholder()
        updateCategoryFilterVisibility()
        tableView.reloadSections(IndexSet(integer: 0), with: .fade)
        updateEmptyState()
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
        categoryButtons.removeAll()

        addCategoryButton(
            title: L10n.text("actives.categories.all"),
            category: nil,
            accessibilityIdentifier: "actives.category.all"
        )
        for category in ActiveCategory.allCases {
            addCategoryButton(
                title: category.localizedName(language: catalogLanguage),
                category: category,
                accessibilityIdentifier: "actives.category.\(category.rawValue)"
            )
        }
        updateCategoryButtonSelection()
    }

    private func addCategoryButton(
        title: String,
        category: ActiveCategory?,
        accessibilityIdentifier: String
    ) {
        let button = ChipButton(title: title)
        button.accessibilityIdentifier = accessibilityIdentifier
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let button else { return }
            self?.selectCategory(category, button: button)
        }, for: .touchUpInside)
        categoryButtons.append((category, button))
        categoryFilterStack.addArrangedSubview(button)
    }

    private func selectCategory(_ category: ActiveCategory?, button: ChipButton) {
        guard selectedCategory != category else { return }
        selectedCategory = category
        updateCategoryButtonSelection()
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

    private func updateCategoryButtonSelection() {
        for item in categoryButtons {
            item.button.isSelected = item.category == selectedCategory
        }
    }

    private func updateCategoryFilterVisibility() {
        let shouldShow = mode == .actives
        categoryFilterScrollView.isHidden = !shouldShow
        categoryFilterHeightConstraint.constant = shouldShow ? 52 : 0
        view.setNeedsLayout()
    }

    @objc private func openSettings() { onOpenSettings?() }

    @objc private func addTapped() {
        switch mode {
        case .products:
            presentSheet(SupplementEditorViewController(repository: repository), largeOnly: true)
        case .inventory:
            guard !supplements.isEmpty else {
                let alert = UIAlertController(title: L10n.Inventory.noItemsTitle, message: L10n.text("inventory.requires_supplement"), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
                alert.addAction(UIAlertAction(title: L10n.Supplements.addSupplement, style: .default) { [weak self] _ in
                    guard let self else { return }
                    self.presentSheet(SupplementEditorViewController(repository: self.repository), largeOnly: true)
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
        showConfirmation(title: L10n.Common.delete, message: L10n.text("delete.confirmation")) { [weak self] in
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

@MainActor
private final class CatalogListCell: UITableViewCell {
    static let reuseIdentifier = "CatalogListCell"

    private let card = PremiumCardView()
    private let artwork = PresentationArtworkView(kind: .capsule)
    private let artworkContainer = UIView()
    private let activeIconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let detailLabel = UILabel()
    private let badgeLabel = UILabel()
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
        compact: Bool = false,
        title: String,
        subtitle: String,
        detail: String,
        badge: String?,
        tone: WellnarioTone
    ) {
        artwork.kind = kind
        artworkSizeConstraint.constant = compact ? 62 : 78
        let contentInset: CGFloat = compact ? 10 : 14
        rowEdgeConstraints.forEach { $0.constant = contentInset }
        let activeIcon = imageKey.flatMap { UIImage(named: $0) }
        activeIconView.image = activeIcon
        activeIconView.isHidden = activeIcon == nil
        artwork.isHidden = activeIcon != nil
        titleLabel.text = title
        subtitleLabel.text = subtitle
        detailLabel.text = detail
        badgeLabel.text = badge
        badgeLabel.isHidden = badge == nil
        badgeLabel.textColor = WellnarioPalette.color(for: tone)
        badgeLabel.backgroundColor = WellnarioPalette.color(for: tone).withAlphaComponent(0.12)
        accessibilityLabel = [title, subtitle, detail, badge].compactMap { $0 }.joined(separator: ", ")
    }

    private func setUp() {
        backgroundColor = .clear
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

        titleLabel.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        subtitleLabel.numberOfLines = 1
        detailLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        detailLabel.numberOfLines = 2

        badgeLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.cyan)
        badgeLabel.textAlignment = .center
        badgeLabel.applyContinuousCorners(9)
        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        badgeLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true

        let titleRow = UIStackView(arrangedSubviews: [titleLabel, badgeLabel], axis: .horizontal, spacing: 8, alignment: .center)
        let labels = UIStackView(arrangedSubviews: [titleRow, subtitleLabel, detailLabel], axis: .vertical, spacing: 4)
        let row = UIStackView(arrangedSubviews: [artworkContainer, labels], axis: .horizontal, spacing: 14, alignment: .center)
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
