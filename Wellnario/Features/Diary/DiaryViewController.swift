import UIKit

@MainActor
final class DiaryViewController: FeatureViewController {
    enum PresentationMode {
        case diary
        case manage
    }

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyState = EmptyStateView()
    private let presentationMode: PresentationMode
    private var days: [DiaryDay] = []
    private var productPhotos: [UUID: UIImage] = [:]

    init(
        repository: WellnarioRepositoryProtocol,
        presentationMode: PresentationMode = .diary
    ) {
        self.presentationMode = presentationMode
        super.init(repository: repository)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpView()
        applyLocalizedCopy()
        reloadContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reloadContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
        if presentationMode == .manage {
            navigationController?.navigationBar.prefersLargeTitles = false
            navigationItem.largeTitleDisplayMode = .never
        } else {
            navigationController?.navigationBar.prefersLargeTitles = true
            navigationItem.largeTitleDisplayMode = .always
        }
    }

    override func applyLocalizedCopy() {
        title = presentationMode == .manage
            ? L10n.text("settings.advanced.intakes.title")
            : L10n.Diary.title
        navigationItem.rightBarButtonItem?.accessibilityLabel = L10n.Today.logIntake
        tableView.reloadData()
        updateEmptyState()
    }

    override func reloadContent() {
        do {
            let consumptions = try repository.fetchConsumptions(from: nil, through: nil, limit: nil)
            let instances = try repository.fetchInstances(supplementID: nil, includeArchived: true)
            let supplements = try repository.fetchSupplements(includeArchived: true)
            let supplementsByID = Dictionary(uniqueKeysWithValues: supplements.map { ($0.id, $0) })
            productPhotos = Dictionary(uniqueKeysWithValues: instances.compactMap { instance in
                guard let supplement = supplementsByID[instance.supplementID],
                      let photo = SupplementPhotoStore.image(
                        reference: supplement.imageReference,
                        databaseURL: repository.databaseURL
                      ) else {
                    return nil
                }
                return (instance.id, photo)
            })
            let grouped = Dictionary(grouping: consumptions, by: \.localDay)
            days = grouped.keys.sorted(by: >).map { day in
                DiaryDay(
                    day: day,
                    consumptions: grouped[day, default: []].sorted { $0.consumedAt > $1.consumedAt }
                )
            }
            tableView.reloadData()
            updateEmptyState()
        } catch { showError(error) }
    }

    private func setUpView() {
        if presentationMode == .diary {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "plus"),
                style: .plain,
                target: self,
                action: #selector(addTapped)
            )
            navigationItem.rightBarButtonItem?.tintColor = WellnarioPalette.cyan
            navigationItem.rightBarButtonItem?.accessibilityIdentifier = "diary.add"
        }

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: WellnarioSpacing.bottomNavigationInset, right: 0)
        tableView.verticalScrollIndicatorInsets.bottom = WellnarioSpacing.bottomNavigationInset
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(DiaryCell.self, forCellReuseIdentifier: DiaryCell.reuseIdentifier)
        view.addForAutoLayout(tableView)
        tableView.pinEdges(to: view)

        emptyState.onAction = { [weak self] in self?.addTapped() }
        view.addForAutoLayout(emptyState)
        NSLayoutConstraint.activate([
            emptyState.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: WellnarioSpacing.screenHorizontal),
            emptyState.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -WellnarioSpacing.screenHorizontal),
            emptyState.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            emptyState.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -WellnarioSpacing.bottomNavigationInset)
        ])
    }

    private func updateEmptyState() {
        let empty = days.isEmpty
        tableView.isHidden = empty
        emptyState.isHidden = !empty
        if empty {
            emptyState.configure(
                kind: .capsule,
                title: presentationMode == .manage
                    ? L10n.text("settings.advanced.intakes.empty.title")
                    : L10n.Diary.noEntriesTitle,
                message: presentationMode == .manage
                    ? L10n.text("settings.advanced.intakes.empty.body")
                    : L10n.Diary.noEntriesMessage,
                actionTitle: presentationMode == .diary ? L10n.Today.logIntake : nil
            )
        }
    }

    private func consumption(at indexPath: IndexPath) -> Consumption {
        days[indexPath.section].consumptions[indexPath.row]
    }

    private func edit(_ consumption: Consumption) {
        presentSheet(IntakeEditorViewController(repository: repository, consumption: consumption), largeOnly: true)
    }

    private func duplicate(_ consumption: Consumption) {
        let draft = ConsumptionDraft(
            instanceID: consumption.instanceID,
            quantity: consumption.quantity,
            unit: consumption.unit,
            consumedAt: Date(),
            timeZoneID: TimeZone.current.identifier,
            notes: consumption.notes
        )
        do {
            _ = try repository.createConsumption(draft)
            UIImpactFeedbackGenerator.wellnarioSuccess()
            _ = FeedbackPresenter.show(
                message: L10n.text("diary.duplicated"),
                tone: .success,
                in: view
            )
        } catch { showError(error) }
    }

    private func delete(_ consumption: Consumption) {
        showConfirmation(title: L10n.Common.delete, message: L10n.text("intake.delete.confirmation")) { [weak self] in
            guard let self else { return }
            do {
                try self.repository.deleteConsumption(id: consumption.id)
                UIImpactFeedbackGenerator.wellnarioSuccess()
            } catch { self.showError(error) }
        }
    }

    @objc private func addTapped() {
        do {
            guard !(try repository.fetchInstances(supplementID: nil, includeArchived: false)).isEmpty else {
                let alert = UIAlertController(title: L10n.Inventory.noItemsTitle, message: L10n.text("intake.requires_batch"), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: L10n.Common.done, style: .default))
                present(alert, animated: true)
                return
            }
            presentSheet(IntakeEditorViewController(repository: repository), largeOnly: true)
        } catch { showError(error) }
    }
}

extension DiaryViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { days.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        days[section].consumptions.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let date = FeatureFormatting.localDayDate(days[section].day) else { return days[section].day.iso8601 }
        return WellnarioFormatters.relativeDay(date)
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.textColor = WellnarioPalette.textSecondary
        header.textLabel?.font = WellnarioTypography.font(for: .sectionTitle)
        header.contentView.backgroundColor = WellnarioPalette.background
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DiaryCell.reuseIdentifier, for: indexPath) as! DiaryCell
        let consumption = consumption(at: indexPath)
        cell.configure(
            consumption,
            language: catalogLanguage,
            productPhoto: productPhotos[consumption.instanceID]
        )
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 120 }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        edit(consumption(at: indexPath))
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let consumption = consumption(at: indexPath)
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(title: L10n.Common.edit, image: UIImage(systemName: "pencil")) { _ in self?.edit(consumption) },
                UIAction(title: L10n.Diary.duplicate, image: UIImage(systemName: "plus.square.on.square")) { _ in self?.duplicate(consumption) },
                UIAction(title: L10n.Common.delete, image: UIImage(systemName: "trash"), attributes: .destructive) { _ in self?.delete(consumption) }
            ])
        })
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let consumption = consumption(at: indexPath)
        let delete = UIContextualAction(style: .destructive, title: L10n.Common.delete) { [weak self] _, _, completion in
            self?.delete(consumption)
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")
        let duplicate = UIContextualAction(style: .normal, title: L10n.Diary.duplicate) { [weak self] _, _, completion in
            self?.duplicate(consumption)
            completion(true)
        }
        duplicate.backgroundColor = WellnarioPalette.violet
        duplicate.image = UIImage(systemName: "plus.square.on.square")
        let configuration = UISwipeActionsConfiguration(actions: [delete, duplicate])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
}

@MainActor
private final class DiaryCell: UITableViewCell {
    static let reuseIdentifier = "DiaryCell"
    private let card = PremiumCardView()
    private let artworkContainer = UIView()
    private let artwork = PresentationArtworkView(kind: .capsule)
    private let productPhotoView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let activeLabel = UILabel()
    private let timeLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ consumption: Consumption, language: CatalogLanguage, productPhoto: UIImage?) {
        titleLabel.text = consumption.supplementNameSnapshot
        productPhotoView.image = productPhoto
        productPhotoView.isHidden = productPhoto == nil
        artwork.isHidden = productPhoto != nil
        let quantity = "\(FeatureFormatting.decimal(consumption.quantity)) \(consumption.unit.symbol(languageCode: language.rawValue))"
        detailLabel.text = [quantity, consumption.instanceLabelSnapshot]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        activeLabel.text = consumption.activeSnapshots.prefix(2).map {
            "\($0.localizedActiveName(language: language)) \(FeatureFormatting.decimal($0.amount)) \($0.unit.symbol(languageCode: language.rawValue))"
        }.joined(separator: " · ")
        timeLabel.text = WellnarioFormatters.time(
            consumption.consumedAt,
            timeZoneID: consumption.timeZoneID
        )
        accessibilityLabel = [titleLabel.text, detailLabel.text, activeLabel.text, timeLabel.text].compactMap { $0 }.joined(separator: ", ")
    }

    private func setUp() {
        backgroundColor = .clear
        selectionStyle = .none
        contentView.addForAutoLayout(card)
        card.pinEdges(to: contentView, insets: NSDirectionalEdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
        card.isUserInteractionEnabled = false

        productPhotoView.accessibilityIdentifier = "diary.product_photo"
        productPhotoView.contentMode = .scaleAspectFit
        productPhotoView.clipsToBounds = true
        productPhotoView.applyContinuousCorners(WellnarioRadius.control)
        artworkContainer.addForAutoLayout(artwork)
        artworkContainer.addForAutoLayout(productPhotoView)
        NSLayoutConstraint.activate([
            artworkContainer.widthAnchor.constraint(equalToConstant: 64),
            artworkContainer.heightAnchor.constraint(equalTo: artworkContainer.widthAnchor)
        ])
        artwork.pinEdges(to: artworkContainer)
        productPhotoView.pinEdges(to: artworkContainer)
        titleLabel.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        titleLabel.numberOfLines = 1
        detailLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        activeLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        activeLabel.numberOfLines = 2
        timeLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.cyan)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let titleRow = UIStackView(arrangedSubviews: [titleLabel, timeLabel], axis: .horizontal, spacing: 8, alignment: .firstBaseline)
        let labels = UIStackView(arrangedSubviews: [titleRow, detailLabel, activeLabel], axis: .vertical, spacing: 3)
        let row = UIStackView(arrangedSubviews: [artworkContainer, labels], axis: .horizontal, spacing: 12, alignment: .center)
        card.contentView.addForAutoLayout(row)
        row.pinEdges(to: card.contentView, insets: .all(12))
    }
}
