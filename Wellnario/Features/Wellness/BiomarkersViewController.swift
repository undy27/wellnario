import UIKit

struct BiomarkerDisplayValue: Equatable {
    enum Source: Equatable {
        case laboratory
        case appleHealthVO2MaxThreeMonthAverage
    }

    let value: Decimal
    let unit: String
    let isOutsideReferenceRange: Bool
    let source: Source
}

@MainActor
final class BiomarkersViewController: UIViewController {
    private enum Filter: Equatable {
        case all
        case favorites
        case sample(BiomarkerSampleType)
    }

    private let store: HealthDataStore
    private let appleHealthService: AppleHealthSyncing?
    private let searchBar = UISearchBar()
    private let filterScrollView = UIScrollView()
    private let filterStack = UIStackView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyState = EmptyStateView()
    private var allBiomarkers: [HealthBiomarker] = []
    private var displayedBiomarkers: [HealthBiomarker] = []
    private var selectedFilter: Filter = .all
    private var query = ""
    private var filterButtons: [(Filter, ChipButton)] = []

    var healthDataStore: HealthDataStore { store }

    init(
        store: HealthDataStore,
        appleHealthService: AppleHealthSyncing? = nil
    ) {
        self.store = store
        self.appleHealthService = appleHealthService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WellnarioPalette.background
        view.accessibilityIdentifier = "health.biomarkers.root"
        configureSearch()
        configureFilters()
        configureTable()
        reloadContent()
    }

    func reloadContent() {
        allBiomarkers = store.biomarkers()
        applyFilter()
    }

    func addBiomarker() {
        presentEditor(biomarker: nil)
    }

    private func configureSearch() {
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = L10n.text("health.biomarkers.search")
        searchBar.searchTextField.backgroundColor = WellnarioPalette.surfaceElevated
        searchBar.searchTextField.textColor = WellnarioPalette.textPrimary
        searchBar.searchTextField.clearButtonMode = .whileEditing
        searchBar.accessibilityIdentifier = "health.biomarkers.search"
        view.addForAutoLayout(searchBar)
    }

    private func configureFilters() {
        filterScrollView.showsHorizontalScrollIndicator = false
        filterScrollView.alwaysBounceHorizontal = true
        filterStack.axis = .horizontal
        filterStack.spacing = WellnarioSpacing.xSmall
        filterScrollView.addForAutoLayout(filterStack)
        NSLayoutConstraint.activate([
            filterStack.leadingAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.leadingAnchor),
            filterStack.trailingAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.trailingAnchor),
            filterStack.topAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.topAnchor),
            filterStack.bottomAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.bottomAnchor),
            filterStack.heightAnchor.constraint(equalTo: filterScrollView.frameLayoutGuide.heightAnchor)
        ])
        view.addForAutoLayout(filterScrollView)

        let filters: [(Filter, String)] = [
            (.all, L10n.text("health.biomarkers.filter.all")),
            (.favorites, L10n.text("health.biomarkers.filter.favorites")),
            (.sample(.blood), L10n.text("health.biomarkers.filter.blood")),
            (.sample(.urine), L10n.text("health.biomarkers.filter.urine")),
            (.sample(.other), L10n.text("health.biomarkers.filter.physiological"))
        ]
        filterButtons = filters.enumerated().map { index, item in
            let button = ChipButton()
            button.setTitle(item.1, for: .normal)
            button.tag = index
            button.isSelected = item.0 == selectedFilter
            button.addTarget(self, action: #selector(filterTapped(_:)), for: .touchUpInside)
            filterStack.addArrangedSubview(button)
            return (item.0, button)
        }
    }

    private func configureTable() {
        tableView.backgroundColor = .clear
        tableView.accessibilityIdentifier = "health.biomarkers.list"
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .onDrag
        // Keep enough vertical room for the three text rows when Dynamic Type
        // is increased, instead of clipping the latest-result line.
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        tableView.contentInset = UIEdgeInsets(
            top: WellnarioSpacing.xSmall,
            left: 0,
            bottom: WellnarioSpacing.bottomNavigationInset,
            right: 0
        )
        tableView.verticalScrollIndicatorInsets.bottom = WellnarioSpacing.bottomNavigationInset
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(BiomarkerListCell.self, forCellReuseIdentifier: BiomarkerListCell.reuseIdentifier)
        emptyState.onAction = { [weak self] in self?.addBiomarker() }
        view.addForAutoLayout(tableView)

        NSLayoutConstraint.activate([
            searchBar.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: WellnarioSpacing.screenHorizontal
            ),
            searchBar.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -WellnarioSpacing.screenHorizontal
            ),
            searchBar.topAnchor.constraint(equalTo: view.topAnchor),
            filterScrollView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: WellnarioSpacing.screenHorizontal
            ),
            filterScrollView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -WellnarioSpacing.screenHorizontal
            ),
            filterScrollView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            filterScrollView.heightAnchor.constraint(equalToConstant: 42),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: filterScrollView.bottomAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func applyFilter() {
        let normalizedQuery = query.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: LocalizationManager.shared.locale
        )
        displayedBiomarkers = allBiomarkers.filter { biomarker in
            let matchesFilter: Bool
            switch selectedFilter {
            case .all: matchesFilter = true
            case .favorites: matchesFilter = biomarker.isFavorite
            case let .sample(type): matchesFilter = biomarker.sampleType == type
            }
            guard matchesFilter else { return false }
            guard !normalizedQuery.isEmpty else { return true }
            let searchable = [
                biomarker.name,
                biomarker.sampleType.title,
                biomarker.defaultUnit
            ].joined(separator: " ").folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: LocalizationManager.shared.locale
            )
            return searchable.contains(normalizedQuery)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        tableView.reloadData()
        if displayedBiomarkers.isEmpty {
            emptyState.configure(
                kind: .other,
                title: L10n.text("health.biomarkers.empty.title"),
                message: L10n.text("health.biomarkers.empty.body"),
                actionTitle: L10n.text("health.biomarkers.add")
            )
            tableView.backgroundView = emptyState
        } else {
            tableView.backgroundView = nil
        }
    }

    private func presentEditor(biomarker: HealthBiomarker?) {
        let editor = BiomarkerEditorViewController(biomarker: biomarker)
        editor.onSave = { [weak self] draft in
            guard let self else { return }
            do {
                if let biomarker {
                    try store.updateBiomarker(id: biomarker.id, with: draft)
                } else {
                    _ = try store.createBiomarker(draft)
                }
                reloadContent()
                dismiss(animated: true)
            } catch {
                editor.showError(error)
            }
        }
        editor.onDelete = { [weak self] id in
            guard let self else { return }
            do {
                try store.archiveBiomarker(id: id)
                reloadContent()
                dismiss(animated: true)
            } catch {
                editor.showError(error)
            }
        }
        let navigation = WellnarioNavigationController(rootViewController: editor)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = WellnarioRadius.card
        }
        present(navigation, animated: true)
    }

    /// The catalog keeps laboratory readings as the primary source. VO₂Max is
    /// the exception: a three-month Apple Health average fills the card until
    /// a laboratory result from the last two years is available.
    static func displayValue(
        for biomarker: HealthBiomarker,
        latestLaboratoryMeasurement: BiomarkerMeasurement?,
        appleHealthSnapshot: AppleHealthSnapshot,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> BiomarkerDisplayValue? {
        let laboratoryValue = latestLaboratoryMeasurement.map {
            BiomarkerDisplayValue(
                value: $0.result.value,
                unit: $0.result.unit,
                isOutsideReferenceRange: $0.result.isOutsideReferenceRange,
                source: .laboratory
            )
        }
        guard biomarker.nameKey == "health.biomarker.catalog.vo2_max",
              let appleHealthVO2Max = appleHealthSnapshot.vo2Max,
              appleHealthVO2Max.value.isFinite,
              appleHealthVO2Max.value >= 0 else {
            return laboratoryValue
        }

        let recentLimit = calendar.date(byAdding: .year, value: -2, to: now) ?? .distantPast
        if let latestLaboratoryMeasurement, latestLaboratoryMeasurement.collectedAt >= recentLimit {
            return laboratoryValue
        }
        return BiomarkerDisplayValue(
            value: Decimal(appleHealthVO2Max.value),
            unit: biomarker.defaultUnit,
            isOutsideReferenceRange: false,
            source: .appleHealthVO2MaxThreeMonthAverage
        )
    }

    @objc private func filterTapped(_ sender: ChipButton) {
        guard filterButtons.indices.contains(sender.tag) else { return }
        selectedFilter = filterButtons[sender.tag].0
        filterButtons.forEach { $0.1.isSelected = $0.0 == selectedFilter }
        applyFilter()
        tableView.setContentOffset(
            CGPoint(x: 0, y: -tableView.adjustedContentInset.top),
            animated: false
        )
    }
}

extension BiomarkersViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        applyFilter()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

extension BiomarkersViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        displayedBiomarkers.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: BiomarkerListCell.reuseIdentifier,
            for: indexPath
        ) as! BiomarkerListCell
        let biomarker = displayedBiomarkers[indexPath.row]
        let latestLaboratoryMeasurement = store.measurements(for: biomarker.id).first
        let currentValue = Self.displayValue(
            for: biomarker,
            latestLaboratoryMeasurement: latestLaboratoryMeasurement,
            appleHealthSnapshot: appleHealthService?.snapshot ?? .empty
        )
        cell.configure(biomarker: biomarker, currentValue: currentValue)
        cell.onFavorite = { [weak self] in
            guard let self else { return }
            try? store.setFavorite(!biomarker.isFavorite, biomarkerID: biomarker.id)
            reloadContent()
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let biomarker = displayedBiomarkers[indexPath.row]
        navigationController?.pushViewController(
            BiomarkerHistoryViewController(store: store, biomarker: biomarker),
            animated: true
        )
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let biomarker = displayedBiomarkers[indexPath.row]
        guard !biomarker.isSeeded else { return nil }
        let edit = UIContextualAction(style: .normal, title: L10n.Common.edit) { [weak self] _, _, done in
            self?.presentEditor(biomarker: biomarker)
            done(true)
        }
        edit.backgroundColor = WellnarioPalette.cyan
        edit.image = UIImage(systemName: "pencil")
        return UISwipeActionsConfiguration(actions: [edit])
    }
}

@MainActor
private final class BiomarkerListCell: UITableViewCell {
    static let reuseIdentifier = "BiomarkerListCell"

    var onFavorite: (() -> Void)?

    private let card = UIView()
    private let artwork = UIImageView()
    private let titleLabel = ContinuousMarqueeLabel()
    private let detailLabel = UILabel()
    private let valueLabel = UILabel()
    private let favoriteButton = UIButton(type: .system)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        card.backgroundColor = WellnarioPalette.surface
        card.applyContinuousCorners(WellnarioRadius.small)
        card.layer.borderWidth = 1
        card.layer.borderColor = WellnarioPalette.hairline.cgColor
        contentView.addForAutoLayout(card)

        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.applyContinuousCorners(14)
        artwork.backgroundColor = WellnarioPalette.surfaceElevated

        titleLabel.applyTextStyle(.bodyBold, color: WellnarioPalette.textPrimary)
        titleLabel.isMarqueeEnabled = true
        detailLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        detailLabel.numberOfLines = 1
        valueLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.cyan)
        valueLabel.textAlignment = .left
        valueLabel.numberOfLines = 1

        favoriteButton.tintColor = WellnarioPalette.fuchsia
        favoriteButton.addTarget(self, action: #selector(favoriteTapped), for: .touchUpInside)
        favoriteButton.accessibilityIdentifier = "health.biomarker.favorite"

        let titleRow = UIStackView(
            arrangedSubviews: [titleLabel, favoriteButton],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let labels = UIStackView(
            arrangedSubviews: [titleRow, detailLabel, valueLabel],
            axis: .vertical,
            spacing: 1
        )
        let row = UIStackView(
            arrangedSubviews: [artwork, labels],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        card.addForAutoLayout(row)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: WellnarioSpacing.screenHorizontal),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -WellnarioSpacing.screenHorizontal),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            artwork.widthAnchor.constraint(equalToConstant: 54),
            artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor),
            favoriteButton.widthAnchor.constraint(equalToConstant: 38),
            favoriteButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        onFavorite = nil
    }

    func configure(biomarker: HealthBiomarker, currentValue: BiomarkerDisplayValue?) {
        artwork.image = biomarker.imageKey.flatMap(UIImage.init(named:))
            ?? UIImage(systemName: biomarker.sampleType.symbolName)
        titleLabel.text = biomarker.name
        detailLabel.text = [biomarker.sampleType.title, biomarker.defaultUnit]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        favoriteButton.setImage(
            UIImage(systemName: biomarker.isFavorite ? "star.fill" : "star"),
            for: .normal
        )
        favoriteButton.accessibilityLabel = biomarker.isFavorite
            ? L10n.text("health.biomarkers.favorite.remove")
            : L10n.text("health.biomarkers.favorite.add")
        if let currentValue {
            valueLabel.text = [
                FeatureFormatting.decimal(currentValue.value),
                currentValue.unit
            ].filter { !$0.isEmpty }.joined(separator: " ")
            valueLabel.textColor = currentValue.isOutsideReferenceRange
                ? WellnarioPalette.danger
                : WellnarioPalette.cyan
        } else {
            valueLabel.text = L10n.text("health.biomarkers.no_results")
            valueLabel.textColor = WellnarioPalette.cyan
        }
        accessibilityLabel = biomarker.name
        accessibilityValue = [detailLabel.text, valueLabel.text].compactMap { $0 }.joined(separator: ". ")
    }

    @objc private func favoriteTapped() {
        onFavorite?()
    }
}

@MainActor
private final class BiomarkerEditorViewController: UIViewController {
    var onSave: ((HealthBiomarkerDraft) -> Void)?
    var onDelete: ((UUID) -> Void)?

    private let biomarker: HealthBiomarker?
    private let nameField = FormFieldView()
    private let unitField = FormFieldView()
    private let typeControl = UISegmentedControl(items: ["", "", ""])

    init(biomarker: HealthBiomarker?) {
        self.biomarker = biomarker
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WellnarioPalette.background
        title = biomarker == nil
            ? L10n.text("health.biomarkers.editor.add.title")
            : L10n.text("health.biomarkers.editor.edit.title")

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel)
        )
        let save = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(save)
        )
        save.tintColor = WellnarioPalette.fuchsia
        navigationItem.rightBarButtonItem = save

        nameField.configure(
            title: L10n.text("health.biomarkers.editor.name"),
            placeholder: L10n.text("health.biomarkers.editor.name.placeholder"),
            text: biomarker?.customName
        )
        unitField.configure(
            title: L10n.text("health.biomarkers.editor.unit"),
            placeholder: L10n.text("health.biomarkers.editor.unit.placeholder"),
            text: biomarker?.defaultUnit
        )
        typeControl.setTitle(L10n.text("health.biomarkers.filter.blood"), forSegmentAt: 0)
        typeControl.setTitle(L10n.text("health.biomarkers.filter.urine"), forSegmentAt: 1)
        typeControl.setTitle(L10n.text("health.biomarkers.filter.physiological"), forSegmentAt: 2)
        switch biomarker?.sampleType {
        case .urine: typeControl.selectedSegmentIndex = 1
        case .other: typeControl.selectedSegmentIndex = 2
        default: typeControl.selectedSegmentIndex = 0
        }
        typeControl.selectedSegmentTintColor = WellnarioPalette.fuchsia
        typeControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)

        let typeTitle = UILabel()
        typeTitle.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        typeTitle.text = L10n.text("health.biomarkers.editor.type")
        let stack = UIStackView(
            arrangedSubviews: [nameField, typeTitle, typeControl, unitField],
            axis: .vertical,
            spacing: WellnarioSpacing.small
        )
        view.addForAutoLayout(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: WellnarioSpacing.screenHorizontal),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -WellnarioSpacing.screenHorizontal),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: WellnarioSpacing.large),
            typeControl.heightAnchor.constraint(equalToConstant: 40)
        ])

        if let biomarker, !biomarker.isSeeded {
            let delete = UIBarButtonItem(
                image: UIImage(systemName: "trash"),
                style: .plain,
                target: self,
                action: #selector(deleteBiomarker)
            )
            delete.tintColor = WellnarioPalette.danger
            navigationItem.leftBarButtonItems = [navigationItem.leftBarButtonItem!, delete]
        }
        if biomarker?.isSeeded == true {
            nameField.textField.isEnabled = false
            typeControl.isEnabled = false
            unitField.textField.isEnabled = false
            save.isEnabled = false
        }
    }

    func showError(_ error: Error) {
        let alert = UIAlertController(
            title: L10n.Common.error,
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.done, style: .default))
        present(alert, animated: true)
    }

    @objc private func save() {
        let sampleType: BiomarkerSampleType
        switch typeControl.selectedSegmentIndex {
        case 1: sampleType = .urine
        case 2: sampleType = .other
        default: sampleType = .blood
        }
        onSave?(HealthBiomarkerDraft(
            name: nameField.textField.text ?? "",
            sampleType: sampleType,
            defaultUnit: unitField.textField.text ?? ""
        ))
    }

    @objc private func cancel() { dismiss(animated: true) }
    @objc private func deleteBiomarker() {
        guard let id = biomarker?.id else { return }
        onDelete?(id)
    }
}

@MainActor
private final class BiomarkerHistoryViewController: UITableViewController {
    private let store: HealthDataStore
    private var biomarker: HealthBiomarker
    private var measurements: [BiomarkerMeasurement] = []
    private let emptyState = EmptyStateView()
    private let trendFooter: BiomarkerHistoryTrendFooterView

    init(store: HealthDataStore, biomarker: HealthBiomarker) {
        self.store = store
        self.biomarker = biomarker
        trendFooter = BiomarkerHistoryTrendFooterView(store: store, biomarker: biomarker)
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = biomarker.name
        view.backgroundColor = WellnarioPalette.background
        tableView.backgroundColor = .clear
        tableView.separatorColor = WellnarioPalette.hairline
        tableView.contentInset.bottom = WellnarioSpacing.bottomNavigationInset
        tableView.tableFooterView = trendFooter
        reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTrendFooterLayout()
    }

    private func reload() {
        measurements = store.measurements(for: biomarker.id)
        trendFooter.configure(biomarker: biomarker)
        tableView.reloadData()
        view.setNeedsLayout()
        if measurements.isEmpty {
            emptyState.configure(
                kind: .other,
                title: L10n.text("health.biomarkers.history.empty.title"),
                message: L10n.text("health.biomarkers.history.empty.body"),
                actionTitle: nil
            )
            tableView.backgroundView = emptyState
        } else {
            tableView.backgroundView = nil
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        measurements.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        let measurement = measurements[indexPath.row]
        var configuration = cell.defaultContentConfiguration()
        configuration.text = [
            FeatureFormatting.decimal(measurement.result.value),
            measurement.result.unit
        ].filter { !$0.isEmpty }.joined(separator: " ")
        configuration.secondaryText = WellnarioFormatters.shortDate(measurement.collectedAt)
        configuration.textProperties.color = WellnarioPalette.textPrimary
        configuration.secondaryTextProperties.color = WellnarioPalette.textSecondary
        cell.contentConfiguration = configuration
        cell.backgroundColor = WellnarioPalette.surface
        return cell
    }

    private func updateTrendFooterLayout() {
        let width = tableView.bounds.width
        guard width > 0 else { return }
        let targetSize = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let height = trendFooter.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        guard trendFooter.frame.width != width || abs(trendFooter.frame.height - height) > 0.5 else { return }
        trendFooter.frame.size = CGSize(width: width, height: height)
        tableView.tableFooterView = trendFooter
    }
}

@MainActor
private final class BiomarkerHistoryTrendFooterView: UIView {
    private enum Period: Int, CaseIterable {
        case lastYear
        case allTime
    }

    private static let referenceLinePreferenceKey = "wellnario.biomarkers.trend.referenceLine"

    private let store: HealthDataStore
    private let defaults: UserDefaults
    private let card = PremiumCardView()
    private let chartView = WellnessTrendChartView()
    private let titleLabel = UILabel()
    private lazy var periodControl = makePeriodControl()
    private lazy var referenceLineControl = makeReferenceLineControl()
    private var biomarker: HealthBiomarker
    private var selectedPeriod: Period = .allTime
    private var selectedReferenceLine: WellnessTrendReferenceLine

    init(store: HealthDataStore, biomarker: HealthBiomarker, defaults: UserDefaults = .standard) {
        self.store = store
        self.biomarker = biomarker
        self.defaults = defaults
        let storedReference = defaults.object(forKey: Self.referenceLinePreferenceKey) as? Int
        selectedReferenceLine = storedReference
            .flatMap(WellnessTrendReferenceLine.init(rawValue:))
            ?? .linearTrend
        super.init(frame: .zero)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(biomarker: HealthBiomarker) {
        self.biomarker = biomarker
        configureChart()
    }

    private func configureView() {
        titleLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = L10n.text("health.biomarker_trends.chart.title")
        let icon = UIImageView(image: UIImage(systemName: "chart.xyaxis.line"))
        icon.tintColor = WellnarioPalette.fuchsia
        let header = UIStackView(
            arrangedSubviews: [titleLabel, UIView(), icon],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )

        chartView.heightAnchor.constraint(equalToConstant: 190).isActive = true
        chartView.accessibilityIdentifier = "health.biomarker.history.trends.chart"
        chartView.lineColor = WellnarioPalette.fuchsia
        chartView.averageColor = WellnarioPalette.cyan
        chartView.smoothingWindow = 1

        let referenceContainer = UIView()
        referenceContainer.addForAutoLayout(referenceLineControl)
        NSLayoutConstraint.activate([
            referenceLineControl.topAnchor.constraint(equalTo: referenceContainer.topAnchor),
            referenceLineControl.bottomAnchor.constraint(equalTo: referenceContainer.bottomAnchor),
            referenceLineControl.centerXAnchor.constraint(equalTo: referenceContainer.centerXAnchor),
            referenceLineControl.widthAnchor.constraint(equalToConstant: 180),
            referenceLineControl.heightAnchor.constraint(equalToConstant: 28)
        ])

        let stack = UIStackView(
            arrangedSubviews: [header, referenceContainer, chartView, periodControl],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        card.contentView.addForAutoLayout(stack)
        stack.pinEdges(
            to: card.contentView,
            insets: NSDirectionalEdgeInsets(top: 16, leading: 8, bottom: 16, trailing: 8)
        )
        addForAutoLayout(card)
        card.pinEdges(
            to: self,
            insets: NSDirectionalEdgeInsets(top: 8, leading: WellnarioSpacing.screenHorizontal, bottom: 8, trailing: WellnarioSpacing.screenHorizontal)
        )
        configureChart()
    }

    private func configureChart() {
        let series = trendSeries()
        chartView.values = series.values
        chartView.labels = series.axisLabels
        chartView.selectionLabels = series.selectionLabels
        chartView.lineColor = WellnarioPalette.fuchsia
        chartView.lineColors = []
        chartView.targetRanges = []
        chartView.linearTrend = WellnessLinearRegression.fit(values: series.values)
        chartView.referenceLine = selectedReferenceLine
        chartView.averageTitle = L10n.text("health.biomarker_trends.reference.average")
        chartView.averageColor = WellnarioPalette.cyan
        chartView.smoothingWindow = 1
        chartView.emptyText = L10n.text("health.biomarker_trends.empty")
        chartView.valueFormatter = valueFormatter
        chartView.accessibilityHint = L10n.text("health.biomarker_trends.chart.interaction.hint")
        chartView.accessibilityLabel = L10n.text(
            "health.biomarker_trends.chart.accessibility",
            biomarker.name,
            periodTitle(selectedPeriod)
        )

        let values = series.values.compactMap { $0 }
        if let minimum = values.min(), let maximum = values.max() {
            let average = values.reduce(0, +) / Double(values.count)
            chartView.accessibilityValue = L10n.text(
                "health.biomarker_trends.chart.accessibility.values",
                valueFormatter(average),
                valueFormatter(minimum),
                valueFormatter(maximum)
            )
        } else {
            chartView.accessibilityValue = chartView.emptyText
        }
    }

    private func trendSeries() -> (values: [Double?], axisLabels: [String], selectionLabels: [String]) {
        let calendar = Calendar.autoupdatingCurrent
        let measurementsByDay = store.measurements(for: biomarker.id).reduce(into: [Date: BiomarkerMeasurement]()) {
            result, measurement in
            let day = calendar.startOfDay(for: measurement.collectedAt)
            if let existing = result[day], existing.collectedAt >= measurement.collectedAt { return }
            result[day] = measurement
        }
        guard let firstDay = measurementsByDay.keys.min(), let lastDay = measurementsByDay.keys.max() else {
            return ([], [], [])
        }

        let today = calendar.startOfDay(for: Date())
        let start: Date
        let end: Date
        switch selectedPeriod {
        case .lastYear:
            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: today) ?? today
            start = max(firstDay, oneYearAgo)
            end = today
        case .allTime:
            start = firstDay
            end = lastDay
        }
        guard start <= end else { return ([], [], []) }

        var dates: [Date] = []
        var cursor = start
        while cursor <= end {
            dates.append(cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = nextDay
        }
        return (
            dates.map { measurementsByDay[$0].map { FeatureFormatting.double($0.result.value) } },
            axisLabels(for: dates),
            selectionLabels(for: dates)
        )
    }

    private func axisLabels(for dates: [Date]) -> [String] {
        guard !dates.isEmpty else { return [] }
        let labelCount = min(3, dates.count)
        let displayedIndexes = Set((0..<labelCount).map { labelIndex in
            guard labelCount > 1 else { return 0 }
            return Int((Double(labelIndex) * Double(dates.count - 1) / Double(labelCount - 1)).rounded())
        })
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        let span = dates.last?.timeIntervalSince(dates.first ?? Date()) ?? 0
        formatter.setLocalizedDateFormatFromTemplate(span >= 365 * 86_400 ? "MMMyy" : "dMMM")
        return dates.enumerated().map { index, date in
            displayedIndexes.contains(index) ? formatter.string(from: date) : ""
        }
    }

    private func selectionLabels(for dates: [Date]) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.setLocalizedDateFormatFromTemplate("dMMMy")
        return dates.map { formatter.string(from: $0) }
    }

    private var valueFormatter: (Double) -> String {
        let unit = biomarker.defaultUnit
        return { value in
            [WellnarioFormatters.number(value, maximumFractionDigits: 2), unit]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }

    private func makePeriodControl() -> UISegmentedControl {
        let control = UISegmentedControl(items: Period.allCases.map(periodTitle))
        control.selectedSegmentIndex = selectedPeriod.rawValue
        control.apportionsSegmentWidthsByContent = true
        styleSelector(control, fontSize: 13)
        control.accessibilityIdentifier = "health.biomarker.history.trends.period.selector"
        control.addTarget(self, action: #selector(periodDidChange), for: .valueChanged)
        return control
    }

    private func makeReferenceLineControl() -> UISegmentedControl {
        let control = UISegmentedControl(items: WellnessTrendReferenceLine.allCases.map(referenceTitle))
        control.selectedSegmentIndex = selectedReferenceLine.rawValue
        styleSelector(control, fontSize: 11)
        control.accessibilityIdentifier = "health.biomarker.history.trends.reference.selector"
        control.addTarget(self, action: #selector(referenceLineDidChange), for: .valueChanged)
        return control
    }

    private func styleSelector(_ control: UISegmentedControl, fontSize: CGFloat) {
        control.selectedSegmentTintColor = WellnarioPalette.fuchsia
        control.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: WellnarioPalette.textSecondary
        ], for: .normal)
        control.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white
        ], for: .selected)
    }

    private func periodTitle(_ period: Period) -> String {
        switch period {
        case .lastYear: L10n.text("health.biomarker_trends.period.last_year")
        case .allTime: L10n.text("health.biomarker_trends.period.all_time")
        }
    }

    private func referenceTitle(_ line: WellnessTrendReferenceLine) -> String {
        switch line {
        case .average: L10n.text("health.biomarker_trends.reference.average")
        case .linearTrend: L10n.text("health.biomarker_trends.reference.trend")
        }
    }

    @objc private func periodDidChange() {
        guard let period = Period(rawValue: periodControl.selectedSegmentIndex) else { return }
        selectedPeriod = period
        configureChart()
    }

    @objc private func referenceLineDidChange() {
        guard let reference = WellnessTrendReferenceLine(rawValue: referenceLineControl.selectedSegmentIndex) else { return }
        selectedReferenceLine = reference
        defaults.set(reference.rawValue, forKey: Self.referenceLinePreferenceKey)
        chartView.referenceLine = reference
    }
}
