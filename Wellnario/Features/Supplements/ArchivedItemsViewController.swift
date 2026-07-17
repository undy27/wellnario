import UIKit

/// Recovery center for records kept because they have historical references.
/// Restoring is always explicit and preserves the original identifiers so diary
/// and trend history remains connected to the recovered item.
@MainActor
final class ArchivedItemsViewController: FeatureViewController {
    private enum Mode: Int {
        case products
        case inventory
        case actives
    }

    private let descriptionLabel = UILabel()
    private let segmentedControl = UISegmentedControl(items: ["", "", ""])
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchController = UISearchController(searchResultsController: nil)
    private let emptyState = EmptyStateView()

    private var mode: Mode = .products
    private var presentations: [PresentationType] = []
    private var supplements: [Supplement] = []
    private var instances: [SupplementInstance] = []
    private var actives: [Active] = []
    private var query = ""
    private weak var feedbackBanner: FeedbackBannerView?

    private var archivedSupplements: [Supplement] {
        supplements.filter(\.isArchived)
    }

    private var archivedInstances: [SupplementInstance] {
        instances.filter(\.isArchived)
    }

    private var archivedActives: [Active] {
        actives.filter(\.isArchived)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        setUpView()
        applyLocalizedCopy()
        reloadContent()
    }

    override func applyLocalizedCopy() {
        title = L10n.text("archive.title")
        descriptionLabel.text = L10n.text("archive.description")
        segmentedControl.setTitle(L10n.Supplements.products, forSegmentAt: 0)
        segmentedControl.setTitle(L10n.Supplements.inventory, forSegmentAt: 1)
        segmentedControl.setTitle(L10n.Supplements.actives, forSegmentAt: 2)
        searchController.searchBar.placeholder = L10n.text("archive.search.placeholder")
        tableView.reloadData()
        updateEmptyState()
    }

    override func reloadContent() {
        do {
            presentations = try repository.fetchPresentationTypes()
            supplements = try repository.fetchSupplements(includeArchived: true)
            instances = try repository.fetchInstances(supplementID: nil, includeArchived: true)
            actives = try repository.fetchActives(includeArchived: true)
            tableView.reloadData()
            updateEmptyState()
        } catch {
            showError(error)
        }
    }

    private func setUpView() {
        view.accessibilityIdentifier = "supplements.archived.root"

        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        searchController.searchBar.searchTextField.backgroundColor = WellnarioPalette.surfaceElevated
        searchController.searchBar.searchTextField.textColor = WellnarioPalette.textPrimary
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        descriptionLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        descriptionLabel.numberOfLines = 0
        view.addForAutoLayout(descriptionLabel)

        segmentedControl.selectedSegmentIndex = mode.rawValue
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
        segmentedControl.accessibilityIdentifier = "archive.segments"
        segmentedControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        view.addForAutoLayout(segmentedControl)

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(
            top: WellnarioSpacing.xxSmall,
            left: 0,
            bottom: WellnarioSpacing.bottomNavigationInset,
            right: 0
        )
        tableView.verticalScrollIndicatorInsets.bottom = WellnarioSpacing.bottomNavigationInset
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ArchivedItemCell.self, forCellReuseIdentifier: ArchivedItemCell.reuseIdentifier)
        tableView.accessibilityIdentifier = "archive.list"
        view.addForAutoLayout(tableView)

        view.addForAutoLayout(emptyState)

        NSLayoutConstraint.activate([
            descriptionLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: WellnarioSpacing.screenHorizontal),
            descriptionLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -WellnarioSpacing.screenHorizontal),
            descriptionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: WellnarioSpacing.xSmall),

            segmentedControl.leadingAnchor.constraint(equalTo: descriptionLabel.leadingAnchor),
            segmentedControl.trailingAnchor.constraint(equalTo: descriptionLabel.trailingAnchor),
            segmentedControl.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: WellnarioSpacing.xSmall),
            segmentedControl.heightAnchor.constraint(equalToConstant: 40),

            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: WellnarioSpacing.xxSmall),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyState.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: WellnarioSpacing.screenHorizontal),
            emptyState.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -WellnarioSpacing.screenHorizontal),
            emptyState.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor),
            emptyState.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -WellnarioSpacing.bottomNavigationInset)
        ])
    }

    private var filteredSupplements: [Supplement] {
        guard !query.isEmpty else { return archivedSupplements }
        return archivedSupplements.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.brand.localizedCaseInsensitiveContains(query)
                || ($0.category?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var filteredInstances: [SupplementInstance] {
        guard !query.isEmpty else { return archivedInstances }
        return archivedInstances.filter { instance in
            instance.label.localizedCaseInsensitiveContains(query)
                || supplement(for: instance)?.name.localizedCaseInsensitiveContains(query) == true
                || supplement(for: instance)?.brand.localizedCaseInsensitiveContains(query) == true
        }
    }

    private var filteredActives: [Active] {
        guard !query.isEmpty else { return archivedActives }
        return archivedActives.filter {
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

        switch mode {
        case .products:
            emptyState.configure(
                kind: .capsule,
                title: L10n.text("archive.empty.products.title"),
                message: L10n.text("archive.empty.products.message"),
                actionTitle: nil
            )
        case .inventory:
            emptyState.configure(
                kind: .sachet,
                title: L10n.text("archive.empty.inventory.title"),
                message: L10n.text("archive.empty.inventory.message"),
                actionTitle: nil
            )
        case .actives:
            emptyState.configure(
                kind: .other,
                title: L10n.text("archive.empty.actives.title"),
                message: L10n.text("archive.empty.actives.message"),
                actionTitle: nil
            )
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

    private func archivedDateText(_ date: Date?) -> String {
        guard let date else { return L10n.text("archive.item.date.unknown") }
        return L10n.text("archive.item.date", WellnarioFormatters.dateAndTime(date))
    }

    private func configureProduct(_ cell: ArchivedItemCell, supplement: Supplement) {
        let presentation = presentation(for: supplement)?.localizedName(language: catalogLanguage)
        let subtitle = [supplement.brand, presentation]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        cell.configure(
            kind: presentationKind(for: supplement),
            title: supplement.name,
            subtitle: subtitle,
            detail: archivedDateText(supplement.archivedAt),
            restoreTitle: L10n.text("archive.restore"),
            identifier: "archive.restore.supplement.\(supplement.id.uuidString)"
        ) { [weak self] in
            self?.requestRestore(supplement)
        }
    }

    private func configureInstance(_ cell: ArchivedItemCell, instance: SupplementInstance) {
        let product = supplement(for: instance)
        let details = [
            L10n.text("archive.inventory.expiry", FeatureFormatting.expirationText(instance.expirationDay)),
            archivedDateText(instance.archivedAt)
        ].joined(separator: " · ")
        cell.configure(
            kind: product.map(presentationKind(for:)) ?? .other,
            title: product?.name ?? instance.label,
            subtitle: instance.label,
            detail: details,
            restoreTitle: L10n.text("archive.restore"),
            identifier: "archive.restore.instance.\(instance.id.uuidString)"
        ) { [weak self] in
            self?.requestRestore(instance)
        }
    }

    private func configureActive(_ cell: ArchivedItemCell, active: Active) {
        let unit = active.baseUnit.symbol(languageCode: catalogLanguage.rawValue)
        cell.configure(
            kind: .other,
            title: active.localizedName(language: catalogLanguage),
            subtitle: L10n.text("archive.active.unit", unit),
            detail: archivedDateText(active.archivedAt),
            restoreTitle: L10n.text("archive.restore"),
            identifier: "archive.restore.active.\(active.id.uuidString)"
        ) { [weak self] in
            self?.requestRestore(active)
        }
    }

    private func requestRestore(_ supplement: Supplement) {
        let blockers = archivedActives.filter { active in
            supplement.components.contains { $0.activeID == active.id }
        }
        guard blockers.isEmpty else {
            showArchivedActiveBlockers(blockers)
            return
        }

        confirmRestore(
            title: L10n.text("archive.restore.product.title", supplement.name),
            message: L10n.text("archive.restore.product.message")
        ) { [weak self] in
            guard let self else { return }
            self.performRestore {
                _ = try self.repository.restoreSupplement(id: supplement.id)
            }
        }
    }

    private func requestRestore(_ instance: SupplementInstance) {
        guard let product = supplement(for: instance) else {
            showError(RepositoryError.notFound(entity: "Supplement", id: instance.supplementID))
            return
        }

        if product.isArchived {
            let blockers = archivedActives.filter { active in
                product.components.contains { $0.activeID == active.id }
            }
            guard blockers.isEmpty else {
                showArchivedActiveBlockers(blockers)
                return
            }
            confirmRestore(
                title: L10n.text("archive.restore.inventory.parent.title"),
                message: L10n.text("archive.restore.inventory.parent.message", product.name)
            ) { [weak self] in
                guard let self else { return }
                self.performRestore {
                    _ = try self.repository.restoreSupplement(id: product.id)
                    if try self.repository.instance(id: instance.id)?.isArchived == true {
                        _ = try self.repository.restoreInstance(id: instance.id)
                    }
                }
            }
            return
        }

        confirmRestore(
            title: L10n.text(
                "archive.restore.inventory.title",
                instance.label.isEmpty ? (supplement(for: instance)?.name ?? "") : instance.label
            ),
            message: L10n.text("archive.restore.inventory.message")
        ) { [weak self] in
            guard let self else { return }
            self.performRestore {
                _ = try self.repository.restoreInstance(id: instance.id)
            }
        }
    }

    private func requestRestore(_ active: Active) {
        confirmRestore(
            title: L10n.text("archive.restore.active.title", active.localizedName(language: catalogLanguage)),
            message: L10n.text("archive.restore.active.message")
        ) { [weak self] in
            guard let self else { return }
            self.performRestore {
                _ = try self.repository.restoreActive(id: active.id)
            }
        }
    }

    private func confirmRestore(title: String, message: String, action: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.text("archive.restore"), style: .default) { _ in action() })
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 60, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    private func showArchivedActiveBlockers(_ blockers: [Active]) {
        let names = blockers
            .map { $0.localizedName(language: catalogLanguage) }
            .joined(separator: ", ")
        let alert = UIAlertController(
            title: L10n.text("archive.restore.blocked.title"),
            message: L10n.text("archive.restore.blocked.message", names),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.text("archive.restore.view_actives"), style: .default) { [weak self] _ in
            self?.selectMode(.actives)
        })
        present(alert, animated: true)
    }

    private func performRestore(_ action: () throws -> Void) {
        do {
            try action()
            UIImpactFeedbackGenerator.wellnarioSuccess()
            if let feedbackBanner {
                FeedbackPresenter.dismiss(feedbackBanner)
            }
            feedbackBanner = FeedbackPresenter.show(
                message: L10n.text("feedback.restored"),
                tone: .success,
                in: view
            )
            reloadContent()
        } catch {
            showError(error)
        }
    }

    private func selectMode(_ mode: Mode) {
        self.mode = mode
        if segmentedControl.selectedSegmentIndex != mode.rawValue {
            segmentedControl.selectedSegmentIndex = mode.rawValue
        }
        query = ""
        searchController.searchBar.text = nil
        tableView.reloadData()
        updateEmptyState()
        UIAccessibility.post(notification: .layoutChanged, argument: segmentedControl)
    }

    @objc private func modeChanged() {
        selectMode(Mode(rawValue: segmentedControl.selectedSegmentIndex) ?? .products)
    }
}

extension ArchivedItemsViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        tableView.reloadData()
        updateEmptyState()
    }
}

extension ArchivedItemsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleCount
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: ArchivedItemCell.reuseIdentifier,
            for: indexPath
        ) as! ArchivedItemCell
        switch mode {
        case .products: configureProduct(cell, supplement: filteredSupplements[indexPath.row])
        case .inventory: configureInstance(cell, instance: filteredInstances[indexPath.row])
        case .actives: configureActive(cell, active: filteredActives[indexPath.row])
        }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        126
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let restore = UIContextualAction(style: .normal, title: L10n.text("archive.restore")) { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            switch self.mode {
            case .products: self.requestRestore(self.filteredSupplements[indexPath.row])
            case .inventory: self.requestRestore(self.filteredInstances[indexPath.row])
            case .actives: self.requestRestore(self.filteredActives[indexPath.row])
            }
            completion(true)
        }
        restore.backgroundColor = WellnarioPalette.success
        restore.image = UIImage(systemName: "arrow.counterclockwise")
        let configuration = UISwipeActionsConfiguration(actions: [restore])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
}

@MainActor
private final class ArchivedItemCell: UITableViewCell {
    static let reuseIdentifier = "ArchivedItemCell"

    private let card = PremiumCardView()
    private let artwork = PresentationArtworkView(kind: .capsule)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let detailLabel = UILabel()
    private let restoreButton = UIButton(type: .system)
    private var onRestore: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onRestore = nil
        restoreButton.accessibilityIdentifier = nil
    }

    func configure(
        kind: PresentationKind,
        title: String,
        subtitle: String,
        detail: String,
        restoreTitle: String,
        identifier: String,
        onRestore: @escaping () -> Void
    ) {
        artwork.kind = kind
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle.isEmpty
        detailLabel.text = detail
        restoreButton.accessibilityLabel = "\(restoreTitle), \(title)"
        restoreButton.accessibilityIdentifier = identifier
        self.onRestore = onRestore
    }

    private func setUp() {
        backgroundColor = .clear
        selectionStyle = .none
        contentView.addForAutoLayout(card)
        card.pinEdges(
            to: contentView,
            insets: NSDirectionalEdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20)
        )

        NSLayoutConstraint.activate([
            artwork.widthAnchor.constraint(equalToConstant: 66),
            artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor),
            restoreButton.widthAnchor.constraint(greaterThanOrEqualToConstant: WellnarioLayout.minimumTouchTarget),
            restoreButton.heightAnchor.constraint(greaterThanOrEqualToConstant: WellnarioLayout.minimumTouchTarget)
        ])

        titleLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        titleLabel.numberOfLines = 1
        subtitleLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        subtitleLabel.numberOfLines = 1
        detailLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        detailLabel.numberOfLines = 2

        var configuration = UIButton.Configuration.tinted()
        configuration.image = UIImage(systemName: "arrow.counterclockwise")
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = WellnarioPalette.cyan
        configuration.baseBackgroundColor = WellnarioPalette.cyan
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        restoreButton.configuration = configuration
        restoreButton.addTarget(self, action: #selector(restoreTapped), for: .touchUpInside)
        restoreButton.setContentHuggingPriority(.required, for: .horizontal)
        restoreButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let labels = UIStackView(
            arrangedSubviews: [titleLabel, subtitleLabel, detailLabel],
            axis: .vertical,
            spacing: WellnarioSpacing.xxxSmall
        )
        let row = UIStackView(
            arrangedSubviews: [artwork, labels, restoreButton],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        card.contentView.addForAutoLayout(row)
        row.pinEdges(
            to: card.contentView,
            insets: NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        )
    }

    @objc private func restoreTapped() {
        onRestore?()
    }
}
