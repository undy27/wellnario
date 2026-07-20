import UIKit

enum MedicalReviewKind: String, CaseIterable, Codable, Sendable {
    case specialistConsultation
    case medicalTest
    case vaccination
    case selfTest

    @MainActor
    var title: String {
        switch self {
        case .specialistConsultation: L10n.text("health.medical_reviews.kind.consultation")
        case .medicalTest: L10n.text("health.medical_reviews.kind.test")
        case .vaccination: L10n.text("health.medical_reviews.kind.vaccination")
        case .selfTest: L10n.text("health.medical_reviews.kind.self_test")
        }
    }

    var symbolName: String {
        switch self {
        case .specialistConsultation: "stethoscope"
        case .medicalTest: "cross.case.fill"
        case .vaccination: "syringe.fill"
        case .selfTest: "testtube.2"
        }
    }
}

struct MedicalReviewCompletion: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let completedAt: Date
    let notes: String?

    init(id: UUID = UUID(), completedAt: Date, notes: String? = nil) {
        self.id = id
        self.completedAt = completedAt
        self.notes = notes
    }
}

struct MedicalReviewHistoryEntry: Identifiable, Equatable, Sendable {
    let reviewID: UUID
    let reviewTitle: String
    let kind: MedicalReviewKind
    let completion: MedicalReviewCompletion

    var id: UUID { completion.id }
}

struct MedicalReview: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var kind: MedicalReviewKind
    var intervalMonths: Int
    var completions: [MedicalReviewCompletion]

    var lastCompletedAt: Date {
        completions.map(\.completedAt).max() ?? .distantPast
    }

    init(
        id: UUID = UUID(),
        title: String,
        kind: MedicalReviewKind,
        intervalMonths: Int,
        lastCompletedAt: Date,
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.intervalMonths = intervalMonths
        completions = [MedicalReviewCompletion(completedAt: lastCompletedAt, notes: notes)]
    }

    init(
        id: UUID,
        title: String,
        kind: MedicalReviewKind,
        intervalMonths: Int,
        completions: [MedicalReviewCompletion]
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.intervalMonths = intervalMonths
        self.completions = completions.sorted { $0.completedAt > $1.completedAt }
    }

    func addingCompletion(
        on date: Date,
        notes: String? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) -> MedicalReview {
        let completedDay = calendar.startOfDay(for: date)
        var updated = self
        if let existingIndex = updated.completions.firstIndex(where: {
            calendar.isDate($0.completedAt, inSameDayAs: completedDay)
        }) {
            let existing = updated.completions[existingIndex]
            updated.completions[existingIndex] = MedicalReviewCompletion(
                id: existing.id,
                completedAt: completedDay,
                notes: notes
            )
        } else {
            updated.completions.append(MedicalReviewCompletion(
                completedAt: completedDay,
                notes: notes
            ))
        }
        updated.completions.sort { $0.completedAt > $1.completedAt }
        return updated
    }

    func updatingCompletion(
        id completionID: UUID,
        completedAt date: Date,
        notes: String?,
        calendar: Calendar = .autoupdatingCurrent
    ) -> MedicalReview {
        guard completions.contains(where: { $0.id == completionID }) else { return self }
        let completedDay = calendar.startOfDay(for: date)
        var updated = self
        updated.completions.removeAll {
            $0.id != completionID
                && calendar.isDate($0.completedAt, inSameDayAs: completedDay)
        }
        guard let index = updated.completions.firstIndex(where: { $0.id == completionID }) else {
            return self
        }
        updated.completions[index] = MedicalReviewCompletion(
            id: completionID,
            completedAt: completedDay,
            notes: notes
        )
        updated.completions.sort { $0.completedAt > $1.completedAt }
        return updated
    }

    func nextDueDate(calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.date(byAdding: .month, value: intervalMonths, to: lastCompletedAt)
            ?? lastCompletedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case kind
        case intervalMonths
        case lastCompletedAt
        case completions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decode(MedicalReviewKind.self, forKey: .kind)
        intervalMonths = try container.decode(Int.self, forKey: .intervalMonths)
        if let decoded = try container.decodeIfPresent(
            [MedicalReviewCompletion].self,
            forKey: .completions
        ), !decoded.isEmpty {
            completions = decoded.sorted { $0.completedAt > $1.completedAt }
        } else {
            let legacyDate = try container.decode(Date.self, forKey: .lastCompletedAt)
            completions = [MedicalReviewCompletion(completedAt: legacyDate)]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(kind, forKey: .kind)
        try container.encode(intervalMonths, forKey: .intervalMonths)
        try container.encode(lastCompletedAt, forKey: .lastCompletedAt)
        try container.encode(completions, forKey: .completions)
    }
}

enum MedicalReviewDueUrgency: Equatable, Sendable {
    case upcoming
    case overdueUnderQuarter
    case overdueFromQuarterThroughThreeQuarters
    case overdueOverThreeQuarters
}

struct MedicalReviewTimelineEntry: Equatable, Sendable {
    let review: MedicalReview
    let dueDate: Date
    let urgency: MedicalReviewDueUrgency
}

enum MedicalReviewTimeline {
    static func entries(
        from reviews: [MedicalReview],
        referenceDate: Date = Date(),
        limit: Int = 4,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [MedicalReviewTimelineEntry] {
        reviews.map { review in
            let dueDate = calendar.startOfDay(for: review.nextDueDate(calendar: calendar))
            return MedicalReviewTimelineEntry(
                review: review,
                dueDate: dueDate,
                urgency: urgency(
                    for: review,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
            return lhs.review.title.localizedCaseInsensitiveCompare(rhs.review.title)
                == .orderedAscending
        }
        .prefix(max(0, limit))
        .map { $0 }
    }

    static func urgency(
        for review: MedicalReview,
        referenceDate: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> MedicalReviewDueUrgency {
        let periodStart = calendar.startOfDay(for: review.lastCompletedAt)
        let dueDate = calendar.startOfDay(for: review.nextDueDate(calendar: calendar))
        let referenceDay = calendar.startOfDay(for: referenceDate)
        guard dueDate < referenceDay else { return .upcoming }

        let periodDuration = dueDate.timeIntervalSince(periodStart)
        guard periodDuration > 0 else { return .overdueOverThreeQuarters }
        let overdueRatio = referenceDay.timeIntervalSince(dueDate) / periodDuration
        if overdueRatio < 0.25 { return .overdueUnderQuarter }
        if overdueRatio <= 0.75 { return .overdueFromQuarterThroughThreeQuarters }
        return .overdueOverThreeQuarters
    }
}

@MainActor
final class MedicalReviewStore {
    private static let storageKey = "wellnario.health.medicalReviews"
    private let database: SQLiteDatabase
    private let userID: UUID

    init(
        databaseURL: URL,
        userID: UUID = WellnarioRepository.defaultUserID,
        legacyDefaults: UserDefaults? = nil
    ) throws {
        database = try SQLiteDatabase(url: databaseURL)
        self.userID = userID
        try SchemaMigrator.migrate(database)
        let now = Date().timeIntervalSince1970
        try database.execute(
            """
            INSERT OR IGNORE INTO app_users (id, created_at, updated_at)
            VALUES (?, ?, ?);
            """,
            bindings: [.text(userID.uuidString), .real(now), .real(now)]
        )
        if let legacyDefaults {
            try migrateLegacyReviews(from: legacyDefaults)
        }
    }

    convenience init() {
        try! self.init(databaseURL: URL(fileURLWithPath: ":memory:"))
    }

    convenience init(defaults: UserDefaults) {
        try! self.init(
            databaseURL: URL(fileURLWithPath: ":memory:"),
            legacyDefaults: defaults
        )
    }

    var reviews: [MedicalReview] {
        (try? fetchReviews()) ?? []
    }

    var historyEntries: [MedicalReviewHistoryEntry] {
        reviews.flatMap { review in
            review.completions.map { completion in
                MedicalReviewHistoryEntry(
                    reviewID: review.id,
                    reviewTitle: review.title,
                    kind: review.kind,
                    completion: completion
                )
            }
        }
        .sorted { lhs, rhs in
            if lhs.completion.completedAt != rhs.completion.completedAt {
                return lhs.completion.completedAt > rhs.completion.completedAt
            }
            let titleOrder = lhs.reviewTitle.localizedCaseInsensitiveCompare(rhs.reviewTitle)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func upsert(_ review: MedicalReview) {
        try? persist(review)
    }

    func delete(id: UUID) {
        _ = try? database.execute(
            "DELETE FROM medical_review_plans WHERE id = ? AND user_id = ?;",
            bindings: [.text(id.uuidString), .text(userID.uuidString)]
        )
    }

    func updateCompletion(
        reviewID: UUID,
        completionID: UUID,
        completedAt: Date,
        notes: String?
    ) {
        guard let review = reviews.first(where: { $0.id == reviewID }) else { return }
        upsert(review.updatingCompletion(
            id: completionID,
            completedAt: completedAt,
            notes: notes
        ))
    }

    func deleteCompletion(reviewID: UUID, completionID: UUID) {
        guard var review = reviews.first(where: { $0.id == reviewID }) else { return }
        if review.completions.count == 1 {
            delete(id: reviewID)
            return
        }
        review.completions.removeAll { $0.id == completionID }
        upsert(review)
    }

    private func fetchReviews() throws -> [MedicalReview] {
        let rows = try database.query(
            """
            SELECT id, title, kind, interval_months
            FROM medical_review_plans
            WHERE user_id = ?;
            """,
            bindings: [.text(userID.uuidString)]
        )
        return try rows.compactMap { row -> MedicalReview? in
            guard let id = UUID(uuidString: try row.string("id")),
                  let kind = MedicalReviewKind(rawValue: try row.string("kind")) else {
                return nil
            }
            let completionRows = try database.query(
                """
                SELECT id, completed_at, notes
                FROM medical_review_completions
                WHERE plan_id = ?
                ORDER BY completed_at DESC;
                """,
                bindings: [.text(id.uuidString)]
            )
            let completions = try completionRows.compactMap { completionRow -> MedicalReviewCompletion? in
                guard let completionID = UUID(uuidString: try completionRow.string("id")) else {
                    return nil
                }
                return MedicalReviewCompletion(
                    id: completionID,
                    completedAt: Date(
                        timeIntervalSince1970: try completionRow.double("completed_at")
                    ),
                    notes: try completionRow.optionalString("notes")
                )
            }
            guard !completions.isEmpty else { return nil }
            return MedicalReview(
                id: id,
                title: try row.string("title"),
                kind: kind,
                intervalMonths: Int(try row.integer("interval_months")),
                completions: completions
            )
        }
        .sorted(by: Self.isOrderedBefore)
    }

    private func persist(_ review: MedicalReview) throws {
        let currentReviews = reviews
        let matchingTitle = currentReviews.first {
            $0.id != review.id
                && $0.title.compare(
                    review.title,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
        }
        let matchingID = currentReviews.first { $0.id == review.id }
        let existing = matchingTitle ?? matchingID
        let targetID = existing?.id ?? review.id
        let combinedCompletions = Self.uniqueCompletions(
            review.completions + (existing?.completions ?? [])
        )
        let now = Date().timeIntervalSince1970

        try database.transaction {
            try database.execute(
                """
                INSERT INTO medical_review_plans (
                    id, user_id, title, kind, interval_months, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    kind = excluded.kind,
                    interval_months = excluded.interval_months,
                    updated_at = excluded.updated_at;
                """,
                bindings: [
                    .text(targetID.uuidString),
                    .text(userID.uuidString),
                    .text(review.title),
                    .text(review.kind.rawValue),
                    .integer(Int64(review.intervalMonths)),
                    .real(now),
                    .real(now)
                ]
            )
            try database.execute(
                "DELETE FROM medical_review_completions WHERE plan_id = ?;",
                bindings: [.text(targetID.uuidString)]
            )
            for completion in combinedCompletions {
                try database.execute(
                    """
                    INSERT OR IGNORE INTO medical_review_completions (
                        id, plan_id, completed_at, notes, created_at
                    ) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        completed_at = excluded.completed_at,
                        notes = excluded.notes;
                    """,
                    bindings: [
                        .text(completion.id.uuidString),
                        .text(targetID.uuidString),
                        .real(completion.completedAt.timeIntervalSince1970),
                        completion.notes.map(SQLiteBinding.text) ?? .null,
                        .real(now)
                    ]
                )
            }
            if targetID != review.id {
                try database.execute(
                    "DELETE FROM medical_review_plans WHERE id = ? AND user_id = ?;",
                    bindings: [.text(review.id.uuidString), .text(userID.uuidString)]
                )
            }
        }
    }

    private func migrateLegacyReviews(from defaults: UserDefaults) throws {
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        let legacyReviews = try JSONDecoder().decode([MedicalReview].self, from: data)
        for review in legacyReviews {
            try persist(review)
        }
        defaults.removeObject(forKey: Self.storageKey)
    }

    private static func uniqueCompletions(
        _ completions: [MedicalReviewCompletion],
        calendar: Calendar = .autoupdatingCurrent
    ) -> [MedicalReviewCompletion] {
        completions.reduce(into: []) { result, item in
            guard !result.contains(where: {
                $0.id == item.id
                    || calendar.isDate($0.completedAt, inSameDayAs: item.completedAt)
            }) else { return }
            result.append(item)
        }
        .sorted { $0.completedAt > $1.completedAt }
    }

    private static func isOrderedBefore(_ lhs: MedicalReview, _ rhs: MedicalReview) -> Bool {
        let lhsDate = lhs.nextDueDate()
        let rhsDate = rhs.nextDueDate()
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

@MainActor
enum MedicalReviewFormatting {
    static func cadence(months: Int) -> String {
        switch months {
        case 1:
            L10n.text("health.medical_reviews.cadence.one_month")
        case 12:
            L10n.text("health.medical_reviews.cadence.annual")
        case let months where months.isMultiple(of: 12):
            L10n.text("health.medical_reviews.cadence.years", months / 12)
        default:
            L10n.text("health.medical_reviews.cadence.months", months)
        }
    }

    static func dueStatus(
        _ review: MedicalReview,
        referenceDate: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let dueDate = calendar.startOfDay(for: review.nextDueDate(calendar: calendar))
        let today = calendar.startOfDay(for: referenceDate)
        if dueDate < today {
            return L10n.text(
                "health.medical_reviews.due.overdue",
                WellnarioFormatters.shortDate(dueDate)
            )
        }
        if dueDate == today {
            return L10n.text("health.medical_reviews.due.today")
        }
        return L10n.text(
            "health.medical_reviews.due.upcoming",
            WellnarioFormatters.shortDate(dueDate)
        )
    }

    static func relativeDayStatus(
        dueDate: Date,
        referenceDate: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let dueDay = calendar.startOfDay(for: dueDate)
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let dayDifference = calendar.dateComponents(
            [.day],
            from: referenceDay,
            to: dueDay
        ).day ?? 0

        switch dayDifference {
        case 0:
            return L10n.text("today.reviews.due.today")
        case 1:
            return L10n.text("today.reviews.due.remaining.one")
        case let days where days > 1:
            return L10n.text("today.reviews.due.remaining.many", days)
        case -1:
            return L10n.text("today.reviews.due.overdue.one")
        default:
            return L10n.text("today.reviews.due.overdue.many", abs(dayDifference))
        }
    }
}

@MainActor
final class MedicalReviewsViewController: UITableViewController {
    private let store: MedicalReviewStore
    private let emptyState = EmptyStateView()
    private var reviews: [MedicalReview] = []

    init(store: MedicalReviewStore) {
        self.store = store
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("health.medical_reviews.title")
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = WellnarioPalette.background
        view.accessibilityIdentifier = "health.medical_reviews.root"
        tableView.backgroundColor = .clear
        tableView.tintColor = WellnarioPalette.fuchsia
        tableView.separatorColor = WellnarioPalette.hairline
        tableView.contentInset.bottom = WellnarioSpacing.bottomNavigationInset
        tableView.verticalScrollIndicatorInsets.bottom = WellnarioSpacing.bottomNavigationInset
        let addButton = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addReview)
        )
        addButton.tintColor = WellnarioPalette.fuchsia
        addButton.accessibilityLabel = L10n.text("health.medical_reviews.add")
        addButton.accessibilityIdentifier = "health.medical_reviews.add"
        let historyButton = UIBarButtonItem(
            image: UIImage(systemName: "clock.arrow.circlepath"),
            style: .plain,
            target: self,
            action: #selector(showAllReviews)
        )
        historyButton.tintColor = WellnarioPalette.fuchsia
        historyButton.accessibilityLabel = L10n.text("health.medical_reviews.all.open")
        historyButton.accessibilityIdentifier = "health.medical_reviews.all.open"
        navigationItem.rightBarButtonItems = [addButton, historyButton]
        emptyState.accessibilityIdentifier = "health.medical_reviews.empty"
        emptyState.actionButton.accessibilityIdentifier = "health.medical_reviews.empty.add"
        emptyState.onAction = { [weak self] in self?.addReview() }
        reloadReviews()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.navigationBar.prefersLargeTitles = false
        reloadReviews()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        reviews.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        reviews.isEmpty ? nil : L10n.text("health.medical_reviews.reminders_later")
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let identifier = "MedicalReviewCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        let review = reviews[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = review.title
        content.secondaryText = [
            "\(review.kind.title) · \(MedicalReviewFormatting.cadence(months: review.intervalMonths))",
            MedicalReviewFormatting.dueStatus(review)
        ].joined(separator: "\n")
        content.textProperties.color = WellnarioPalette.textPrimary
        content.textProperties.font = WellnarioTypography.font(for: .body)
        content.secondaryTextProperties.color = WellnarioPalette.textSecondary
        content.secondaryTextProperties.font = WellnarioTypography.font(for: .caption)
        content.secondaryTextProperties.numberOfLines = 2
        content.image = UIImage(systemName: review.kind.symbolName)
        content.imageProperties.tintColor = WellnarioPalette.fuchsia
        cell.contentConfiguration = content
        cell.backgroundColor = WellnarioPalette.surface
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "health.medical_reviews.item.\(review.id.uuidString)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        presentEditor(review: reviews[indexPath.row])
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let review = reviews[indexPath.row]
        let delete = UIContextualAction(
            style: .destructive,
            title: L10n.Common.delete
        ) { [weak self] _, _, completion in
            self?.confirmDeletion(of: review, completion: completion)
        }
        delete.image = UIImage(systemName: "trash")
        let configuration = UISwipeActionsConfiguration(actions: [delete])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    func reloadReviews() {
        reviews = store.reviews
        tableView.reloadData()
        if reviews.isEmpty {
            emptyState.configure(
                kind: .other,
                title: L10n.text("health.medical_reviews.empty.title"),
                message: L10n.text("health.medical_reviews.empty.body"),
                actionTitle: L10n.text("health.medical_reviews.add")
            )
            tableView.backgroundView = emptyState
        } else {
            tableView.backgroundView = nil
        }
    }

    private func presentEditor(review: MedicalReview?) {
        let editor = MedicalReviewEditorViewController(review: review)
        editor.onSave = { [weak self] review in
            self?.store.upsert(review)
            self?.reloadReviews()
        }
        editor.onDeleteReview = { [weak self] reviewID in
            self?.store.delete(id: reviewID)
            self?.reloadReviews()
        }
        let navigationController = WellnarioNavigationController(rootViewController: editor)
        navigationController.modalPresentationStyle = .pageSheet
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = WellnarioRadius.card
        }
        present(navigationController, animated: true)
    }

    private func confirmDeletion(
        of review: MedicalReview,
        completion: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(
            title: L10n.text("health.medical_reviews.delete.title"),
            message: L10n.text("health.medical_reviews.delete.body", review.title),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel) { _ in
            completion(false)
        })
        alert.addAction(UIAlertAction(title: L10n.Common.delete, style: .destructive) { [weak self] _ in
            self?.store.delete(id: review.id)
            self?.reloadReviews()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            completion(true)
        })
        present(alert, animated: true)
    }

    @objc func addReview() {
        presentEditor(review: nil)
    }

    @objc func showAllReviews() {
        navigationController?.pushViewController(
            AllMedicalReviewHistoryViewController(store: store),
            animated: true
        )
    }
}

@MainActor
final class AllMedicalReviewHistoryViewController: UITableViewController {
    private let store: MedicalReviewStore
    private let emptyState = EmptyStateView()
    private var entries: [MedicalReviewHistoryEntry] = []

    init(store: MedicalReviewStore) {
        self.store = store
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("health.medical_reviews.all.title")
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = WellnarioPalette.background
        view.accessibilityIdentifier = "health.medical_reviews.all.root"
        tableView.backgroundColor = .clear
        tableView.separatorColor = WellnarioPalette.hairline
        tableView.contentInset.bottom = WellnarioSpacing.bottomNavigationInset
        tableView.verticalScrollIndicatorInsets.bottom = WellnarioSpacing.bottomNavigationInset
        emptyState.accessibilityIdentifier = "health.medical_reviews.all.empty"
        reloadEntries()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadEntries()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let identifier = "AllMedicalReviewHistoryCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        let entry = entries[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = entry.reviewTitle
        let metadata = [
            WellnarioFormatters.shortDate(entry.completion.completedAt),
            entry.kind.title
        ].joined(separator: " · ")
        content.secondaryText = [metadata, entry.completion.notes]
            .compactMap { $0 }
            .joined(separator: "\n")
        content.textProperties.color = WellnarioPalette.textPrimary
        content.textProperties.font = WellnarioTypography.font(for: .body)
        content.secondaryTextProperties.color = WellnarioPalette.textSecondary
        content.secondaryTextProperties.font = WellnarioTypography.font(for: .caption)
        content.secondaryTextProperties.numberOfLines = 0
        content.image = UIImage(systemName: entry.kind.symbolName)
        content.imageProperties.tintColor = WellnarioPalette.fuchsia
        cell.contentConfiguration = content
        cell.backgroundColor = WellnarioPalette.surface
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "health.medical_reviews.all.item.\(entry.id.uuidString)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entry = entries[indexPath.row]
        let editor = MedicalReviewCompletionEditorViewController(
            reviewTitle: entry.reviewTitle,
            completion: entry.completion
        )
        editor.onSave = { [weak self] completion in
            self?.store.updateCompletion(
                reviewID: entry.reviewID,
                completionID: completion.id,
                completedAt: completion.completedAt,
                notes: completion.notes
            )
            self?.reloadEntries()
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let entry = entries[indexPath.row]
        let delete = UIContextualAction(
            style: .destructive,
            title: L10n.Common.delete
        ) { [weak self] _, _, completion in
            self?.confirmCompletionDeletion(entry, completion: completion)
        }
        delete.image = UIImage(systemName: "trash")
        let configuration = UISwipeActionsConfiguration(actions: [delete])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    private func reloadEntries() {
        entries = store.historyEntries
        tableView.reloadData()
        if entries.isEmpty {
            emptyState.configure(
                kind: .other,
                title: L10n.text("health.medical_reviews.all.empty.title"),
                message: L10n.text("health.medical_reviews.all.empty.body")
            )
            tableView.backgroundView = emptyState
        } else {
            tableView.backgroundView = nil
        }
    }

    private func confirmCompletionDeletion(
        _ entry: MedicalReviewHistoryEntry,
        completion: @escaping (Bool) -> Void
    ) {
        let isOnlyCompletion = store.reviews.first(where: {
            $0.id == entry.reviewID
        })?.completions.count == 1
        let alert = UIAlertController(
            title: L10n.text("health.medical_reviews.completion.delete.title"),
            message: L10n.text(isOnlyCompletion
                ? "health.medical_reviews.completion.delete.last.body"
                : "health.medical_reviews.completion.delete.body"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel) { _ in
            completion(false)
        })
        alert.addAction(UIAlertAction(title: L10n.Common.delete, style: .destructive) {
            [weak self] _ in
            self?.store.deleteCompletion(
                reviewID: entry.reviewID,
                completionID: entry.completion.id
            )
            self?.reloadEntries()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            completion(true)
        })
        present(alert, animated: true)
    }
}

@MainActor
final class MedicalReviewEditorViewController: UIViewController {
    var onSave: ((MedicalReview) -> Void)?
    var onDeleteReview: ((UUID) -> Void)?

    private static let cadenceOptions = [1, 3, 6, 12, 18, 24, 36, 60]

    private let review: MedicalReview?
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let nameField = FormFieldView()
    private let kindField = SelectionFieldView(title: L10n.text("health.medical_reviews.kind"))
    private let cadenceField = SelectionFieldView(title: L10n.text("health.medical_reviews.cadence"))
    private let lastDatePicker = UIDatePicker()
    private let notesField = TextAreaFieldView()
    private let duePreview = FeedbackBannerView()
    private let historyCard = MedicalReviewHistoryCard()
    private var selectedKind: MedicalReviewKind
    private var selectedIntervalMonths: Int
    private var draftCompletions: [MedicalReviewCompletion]

    init(review: MedicalReview?) {
        self.review = review
        selectedKind = review?.kind ?? .specialistConsultation
        selectedIntervalMonths = review?.intervalMonths ?? 12
        draftCompletions = review?.completions ?? []
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = review == nil
            ? L10n.text("health.medical_reviews.add")
            : L10n.text("health.medical_reviews.edit")
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = WellnarioPalette.background
        view.accessibilityIdentifier = "health.medical_reviews.editor.root"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.Common.cancel,
            style: .plain,
            target: self,
            action: #selector(cancel)
        )
        navigationItem.leftBarButtonItem?.tintColor = WellnarioPalette.textSecondary
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.Common.save,
            style: .done,
            target: self,
            action: #selector(save)
        )
        navigationItem.rightBarButtonItem?.tintColor = WellnarioPalette.fuchsia
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "health.medical_reviews.editor.save"
        configureFields()
        buildContent()
        rebuildKindMenu()
        rebuildCadenceMenu()
        updateDuePreview()
        observeKeyboard()
    }

    private func configureFields() {
        nameField.configure(
            title: L10n.text("health.medical_reviews.name"),
            placeholder: L10n.text("health.medical_reviews.name.placeholder"),
            text: review?.title,
            contentType: .organizationName
        )
        nameField.helperText = L10n.text("health.medical_reviews.name.helper")
        nameField.textField.accessibilityIdentifier = "health.medical_reviews.editor.name"
        nameField.textField.addTarget(self, action: #selector(nameDidChange), for: .editingChanged)
        kindField.button.accessibilityIdentifier = "health.medical_reviews.editor.kind"
        cadenceField.button.accessibilityIdentifier = "health.medical_reviews.editor.cadence"
        kindField.button.addTarget(
            self,
            action: #selector(dismissKeyboard),
            for: .touchDown
        )
        cadenceField.button.addTarget(
            self,
            action: #selector(dismissKeyboard),
            for: .touchDown
        )

        lastDatePicker.datePickerMode = .date
        lastDatePicker.preferredDatePickerStyle = .compact
        lastDatePicker.tintColor = WellnarioPalette.fuchsia
        lastDatePicker.maximumDate = Date()
        lastDatePicker.minimumDate = Calendar.autoupdatingCurrent.date(
            byAdding: .year,
            value: -100,
            to: Date()
        )
        lastDatePicker.date = review?.lastCompletedAt ?? Date()
        lastDatePicker.accessibilityIdentifier = "health.medical_reviews.editor.last_date"
        lastDatePicker.addTarget(self, action: #selector(dateDidChange), for: .valueChanged)
        lastDatePicker.addTarget(self, action: #selector(dismissKeyboard), for: .touchDown)
        duePreview.accessibilityIdentifier = "health.medical_reviews.editor.preview"

        notesField.title = L10n.text("health.medical_reviews.notes")
        notesField.placeholder = L10n.text("health.medical_reviews.notes.placeholder")
        notesField.minimumHeight = 64
        notesField.text = review?.completions.first(where: {
            Calendar.autoupdatingCurrent.isDate($0.completedAt, inSameDayAs: lastDatePicker.date)
        })?.notes ?? ""
        notesField.textView.tintColor = WellnarioPalette.fuchsia
        notesField.textView.accessibilityIdentifier = "health.medical_reviews.editor.notes"

    }

    private func buildContent() {
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.showsVerticalScrollIndicator = false
        scrollView.accessibilityIdentifier = "health.medical_reviews.editor.scroll"
        view.addForAutoLayout(scrollView)
        scrollView.pinEdges(to: view)

        contentStack.axis = .vertical
        contentStack.spacing = WellnarioSpacing.cardGap
        scrollView.addForAutoLayout(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.leadingAnchor,
                constant: WellnarioSpacing.screenHorizontal
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.trailingAnchor,
                constant: -WellnarioSpacing.screenHorizontal
            ),
            contentStack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor,
                constant: WellnarioSpacing.medium
            ),
            contentStack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                constant: -WellnarioSpacing.large
            ),
            contentStack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -(WellnarioSpacing.screenHorizontal * 2)
            )
        ])

        let lastDateLabel = UILabel()
        lastDateLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textPrimary)
        lastDateLabel.text = L10n.text("health.medical_reviews.last_date")
        lastDateLabel.numberOfLines = 0
        let lastDateRow = UIStackView(
            arrangedSubviews: [lastDateLabel, UIView(), lastDatePicker],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )

        contentStack.addArrangedSubview(FormSectionView(
            title: L10n.text("health.medical_reviews.details"),
            views: [nameField, kindField]
        ))
        contentStack.addArrangedSubview(FormSectionView(
            title: L10n.text("health.medical_reviews.schedule"),
            views: [cadenceField, lastDateRow, notesField, duePreview]
        ))
        if review != nil {
            historyCard.onSelectCompletion = { [weak self] completion in
                self?.editCompletion(completion)
            }
            historyCard.onDeleteCompletion = { [weak self] completion in
                self?.confirmCompletionDeletion(completion)
            }
            historyCard.configure(completions: draftCompletions)
            contentStack.addArrangedSubview(historyCard)
        }

        let dismissTap = UITapGestureRecognizer(
            target: self,
            action: #selector(dismissKeyboard)
        )
        dismissTap.cancelsTouchesInView = false
        view.addGestureRecognizer(dismissTap)
    }

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardHidden(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardFrameChanged(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        let convertedFrame = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - convertedFrame.minY)
        let bottomInset = overlap > 0 ? overlap + WellnarioSpacing.small : 0
        scrollView.contentInset.bottom = bottomInset
        scrollView.verticalScrollIndicatorInsets.bottom = bottomInset
    }

    @objc private func keyboardHidden(_ notification: Notification) {
        scrollView.contentInset.bottom = 0
        scrollView.verticalScrollIndicatorInsets.bottom = 0
    }

    private func rebuildKindMenu() {
        kindField.value = selectedKind.title
        kindField.menu = UIMenu(children: MedicalReviewKind.allCases.map { kind in
            UIAction(
                title: kind.title,
                image: UIImage(systemName: kind.symbolName),
                state: kind == selectedKind ? .on : .off
            ) { [weak self] _ in
                self?.selectedKind = kind
                self?.rebuildKindMenu()
            }
        })
    }

    private func rebuildCadenceMenu() {
        cadenceField.value = MedicalReviewFormatting.cadence(months: selectedIntervalMonths)
        cadenceField.menu = UIMenu(children: Self.cadenceOptions.map { months in
            UIAction(
                title: MedicalReviewFormatting.cadence(months: months),
                state: months == selectedIntervalMonths ? .on : .off
            ) { [weak self] _ in
                self?.selectedIntervalMonths = months
                self?.rebuildCadenceMenu()
                self?.updateDuePreview()
            }
        })
    }

    private func updateDuePreview() {
        let draft = MedicalReview(
            title: review?.title ?? "",
            kind: selectedKind,
            intervalMonths: selectedIntervalMonths,
            lastCompletedAt: lastDatePicker.date
        )
        duePreview.configure(
            message: L10n.text(
                "health.medical_reviews.next_preview",
                WellnarioFormatters.shortDate(draft.nextDueDate())
            ),
            tone: .information
        )
    }

    @objc private func save() {
        let normalizedName = nameField.textField.text?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalizedName.isEmpty else {
            nameField.setError(L10n.text("health.medical_reviews.name.required"))
            return
        }
        nameField.setError(nil)
        let completedAt = Calendar.autoupdatingCurrent.startOfDay(for: lastDatePicker.date)
        let notes = normalizedNotes
        let updated: MedicalReview
        if var existingReview = review {
            existingReview.title = normalizedName
            existingReview.kind = selectedKind
            existingReview.intervalMonths = selectedIntervalMonths
            existingReview.completions = draftCompletions
            updated = existingReview.addingCompletion(on: completedAt, notes: notes)
        } else {
            updated = MedicalReview(
                title: normalizedName,
                kind: selectedKind,
                intervalMonths: selectedIntervalMonths,
                lastCompletedAt: completedAt,
                notes: notes
            )
        }
        onSave?(updated)
        UIImpactFeedbackGenerator.wellnarioSuccess()
        dismiss(animated: true)
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func nameDidChange() {
        if !(nameField.textField.text ?? "").isEmpty { nameField.setError(nil) }
    }

    @objc private func dateDidChange() {
        notesField.text = review?.completions.first(where: {
            Calendar.autoupdatingCurrent.isDate($0.completedAt, inSameDayAs: lastDatePicker.date)
        })?.notes ?? ""
        updateDuePreview()
    }

    private var normalizedNotes: String? {
        let value = notesField.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func editCompletion(_ completion: MedicalReviewCompletion) {
        let editor = MedicalReviewCompletionEditorViewController(
            reviewTitle: review?.title ?? "",
            completion: completion
        )
        editor.onSave = { [weak self] editedCompletion in
            guard let self else { return }
            let selectedDateWasEdited = Calendar.autoupdatingCurrent.isDate(
                lastDatePicker.date,
                inSameDayAs: completion.completedAt
            )
            var draft = MedicalReview(
                id: review?.id ?? UUID(),
                title: review?.title ?? "",
                kind: selectedKind,
                intervalMonths: selectedIntervalMonths,
                completions: draftCompletions
            )
            draft = draft.updatingCompletion(
                id: editedCompletion.id,
                completedAt: editedCompletion.completedAt,
                notes: editedCompletion.notes
            )
            draftCompletions = draft.completions
            historyCard.configure(completions: draftCompletions)
            if selectedDateWasEdited {
                lastDatePicker.date = editedCompletion.completedAt
                notesField.text = editedCompletion.notes ?? ""
                updateDuePreview()
            } else if !draftCompletions.contains(where: {
                Calendar.autoupdatingCurrent.isDate(
                    $0.completedAt,
                    inSameDayAs: lastDatePicker.date
                )
            }), let latest = draftCompletions.first {
                lastDatePicker.date = latest.completedAt
                notesField.text = latest.notes ?? ""
                updateDuePreview()
            }
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    private func confirmCompletionDeletion(_ completion: MedicalReviewCompletion) {
        let isOnlyCompletion = draftCompletions.count == 1
        let alert = UIAlertController(
            title: L10n.text("health.medical_reviews.completion.delete.title"),
            message: L10n.text(isOnlyCompletion
                ? "health.medical_reviews.completion.delete.last.body"
                : "health.medical_reviews.completion.delete.body"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.Common.delete, style: .destructive) {
            [weak self] _ in
            guard let self else { return }
            if isOnlyCompletion, let reviewID = review?.id {
                onDeleteReview?(reviewID)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss(animated: true)
                return
            }
            let deletedSelectedDate = Calendar.autoupdatingCurrent.isDate(
                completion.completedAt,
                inSameDayAs: lastDatePicker.date
            )
            draftCompletions.removeAll { $0.id == completion.id }
            historyCard.configure(completions: draftCompletions)
            if deletedSelectedDate, let latest = draftCompletions.first {
                lastDatePicker.date = latest.completedAt
                notesField.text = latest.notes ?? ""
                updateDuePreview()
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        })
        present(alert, animated: true)
    }
}

@MainActor
final class MedicalReviewCompletionEditorViewController: UIViewController {
    var onSave: ((MedicalReviewCompletion) -> Void)?

    private let completion: MedicalReviewCompletion
    private let datePicker = UIDatePicker()
    private let notesField = TextAreaFieldView()

    init(reviewTitle: String, completion: MedicalReviewCompletion) {
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
        title = reviewTitle
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = WellnarioPalette.background
        view.accessibilityIdentifier = "health.medical_reviews.completion.editor.root"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.Common.save,
            style: .done,
            target: self,
            action: #selector(save)
        )
        navigationItem.rightBarButtonItem?.tintColor = WellnarioPalette.fuchsia
        navigationItem.rightBarButtonItem?.accessibilityIdentifier =
            "health.medical_reviews.completion.editor.save"
        buildContent()
    }

    private func buildContent() {
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .compact
        datePicker.tintColor = WellnarioPalette.fuchsia
        datePicker.maximumDate = Date()
        datePicker.minimumDate = Calendar.autoupdatingCurrent.date(
            byAdding: .year,
            value: -100,
            to: Date()
        )
        datePicker.date = completion.completedAt
        datePicker.accessibilityIdentifier = "health.medical_reviews.completion.editor.date"

        notesField.title = L10n.text("health.medical_reviews.notes")
        notesField.placeholder = L10n.text("health.medical_reviews.notes.placeholder")
        notesField.minimumHeight = 64
        notesField.text = completion.notes ?? ""
        notesField.textView.tintColor = WellnarioPalette.fuchsia
        notesField.textView.accessibilityIdentifier =
            "health.medical_reviews.completion.editor.notes"

        let dateLabel = UILabel()
        dateLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textPrimary)
        dateLabel.text = L10n.text("health.medical_reviews.completion.date")
        let dateRow = UIStackView(
            arrangedSubviews: [dateLabel, UIView(), datePicker],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        let section = FormSectionView(
            title: L10n.text("health.medical_reviews.completion.edit"),
            views: [dateRow, notesField]
        )
        view.addForAutoLayout(section)
        NSLayoutConstraint.activate([
            section.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: WellnarioSpacing.screenHorizontal
            ),
            section.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -WellnarioSpacing.screenHorizontal
            ),
            section.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: WellnarioSpacing.medium
            ),
            section.bottomAnchor.constraint(
                lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor,
                constant: -WellnarioSpacing.small
            )
        ])

        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        dismissTap.cancelsTouchesInView = false
        view.addGestureRecognizer(dismissTap)
    }

    @objc private func save() {
        let trimmedNotes = notesField.text.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave?(MedicalReviewCompletion(
            id: completion.id,
            completedAt: Calendar.autoupdatingCurrent.startOfDay(for: datePicker.date),
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        ))
        UIImpactFeedbackGenerator.wellnarioSuccess()
        navigationController?.popViewController(animated: true)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
}

@MainActor
final class MedicalReviewHistoryRowStackView: UIStackView {
    var onAccessibilityActivate: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        onAccessibilityActivate?()
        return onAccessibilityActivate != nil
    }
}

@MainActor
final class MedicalReviewHistoryCard: PremiumCardView {
    private let stack = UIStackView()
    private var displayedCompletions: [MedicalReviewCompletion] = []
    var onSelectCompletion: ((MedicalReviewCompletion) -> Void)?
    var onDeleteCompletion: ((MedicalReviewCompletion) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    func configure(completions: [MedicalReviewCompletion]) {
        stack.arrangedSubviews.dropFirst().forEach { $0.removeFromSuperview() }
        let sorted = completions.sorted { $0.completedAt > $1.completedAt }
        displayedCompletions = sorted
        for (index, completion) in sorted.enumerated() {
            let icon = UIImageView(image: UIImage(systemName: "calendar.badge.checkmark"))
            icon.tintColor = index == 0
                ? WellnarioPalette.fuchsia
                : WellnarioPalette.textTertiary
            icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
                pointSize: 14,
                weight: .medium
            )
            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: 22),
                icon.heightAnchor.constraint(equalToConstant: 22)
            ])

            let dateLabel = UILabel()
            dateLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textPrimary)
            dateLabel.text = WellnarioFormatters.shortDate(completion.completedAt)
            dateLabel.numberOfLines = 1

            let notesLabel = UILabel()
            notesLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
            notesLabel.text = completion.notes
            notesLabel.numberOfLines = 0
            notesLabel.isHidden = completion.notes == nil

            let details = UIStackView(
                arrangedSubviews: [dateLabel, notesLabel],
                axis: .vertical,
                spacing: 2,
                alignment: .fill
            )

            let statusLabel = UILabel()
            statusLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.fuchsia)
            statusLabel.text = index == 0
                ? L10n.text("health.medical_reviews.history.latest")
                : nil
            statusLabel.isHidden = index != 0

            let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
            chevron.tintColor = WellnarioPalette.textTertiary
            chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
                pointSize: 12,
                weight: .semibold
            )

            let row = MedicalReviewHistoryRowStackView(
                arrangedSubviews: [icon, details, UIView(), statusLabel, chevron]
            )
            row.axis = .horizontal
            row.spacing = WellnarioSpacing.xSmall
            row.alignment = .center
            row.accessibilityIdentifier = "health.medical_reviews.history.row.\(index)"
            row.tag = index
            row.onAccessibilityActivate = { [weak self] in
                self?.selectCompletion(at: index)
            }
            row.isUserInteractionEnabled = true
            row.addGestureRecognizer(UITapGestureRecognizer(
                target: self,
                action: #selector(historyRowTapped(_:))
            ))
            let deleteSwipe = UISwipeGestureRecognizer(
                target: self,
                action: #selector(historyRowSwiped(_:))
            )
            deleteSwipe.direction = .left
            row.addGestureRecognizer(deleteSwipe)
            row.isAccessibilityElement = true
            row.accessibilityTraits.insert(.button)
            row.accessibilityLabel = [dateLabel.text, statusLabel.text, notesLabel.text]
                .compactMap { $0 }
                .joined(separator: ", ")
            stack.addArrangedSubview(row)
        }
        accessibilityValue = sorted.count == 1
            ? L10n.text("health.medical_reviews.history.count.one")
            : L10n.text("health.medical_reviews.history.count.many", sorted.count)
    }

    func selectCompletion(at index: Int) {
        guard displayedCompletions.indices.contains(index) else { return }
        onSelectCompletion?(displayedCompletions[index])
    }

    func requestDeletion(at index: Int) {
        guard displayedCompletions.indices.contains(index) else { return }
        onDeleteCompletion?(displayedCompletions[index])
    }

    @objc private func historyRowTapped(_ recognizer: UITapGestureRecognizer) {
        guard let index = recognizer.view?.tag else { return }
        selectCompletion(at: index)
    }

    @objc private func historyRowSwiped(_ recognizer: UISwipeGestureRecognizer) {
        guard let index = recognizer.view?.tag else { return }
        requestDeletion(at: index)
    }

    private func setUp() {
        accessibilityIdentifier = "health.medical_reviews.history"
        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = L10n.text("health.medical_reviews.history.title")
        titleLabel.numberOfLines = 0

        stack.axis = .vertical
        stack.spacing = WellnarioSpacing.xSmall
        stack.addArrangedSubview(titleLabel)
        contentView.addForAutoLayout(stack)
        stack.pinEdges(to: contentView, insets: .all(WellnarioSpacing.cardPadding))
        isAccessibilityElement = false
    }
}
