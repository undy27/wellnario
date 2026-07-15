import UIKit

protocol WellnessCardKind: RawRepresentable, CaseIterable, Hashable, Sendable where RawValue == String {
    static var storageNamespace: String { get }
    @MainActor var title: String { get }
    var symbolName: String { get }
}

enum SleepCardKind: String, CaseIterable, WellnessCardKind, Sendable {
    case latestSession
    case trend
    case factors

    static let storageNamespace = "sleep"

    @MainActor
    var title: String {
        switch self {
        case .latestSession: L10n.text("sleep.latest.title")
        case .trend: L10n.text("sleep.trend.title")
        case .factors: L10n.text("sleep.factors.title")
        }
    }

    var symbolName: String {
        switch self {
        case .latestSession: "moon.stars.fill"
        case .trend: "chart.xyaxis.line"
        case .factors: "text.badge.plus"
        }
    }
}

@MainActor
final class WellnessCardLayoutPreferences<Card: WellnessCardKind> {
    private let defaults: UserDefaults

    private var orderKey: String { "wellnario.\(Card.storageNamespace).cards.order" }
    private var hiddenKey: String { "wellnario.\(Card.storageNamespace).cards.hidden" }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var orderedCards: [Card] {
        let storedCards = defaults.stringArray(forKey: orderKey) ?? []
        var seen = Set<Card>()
        var cards = storedCards.compactMap(Card.init(rawValue:)).filter { seen.insert($0).inserted }
        cards.append(contentsOf: Card.allCases.filter { seen.insert($0).inserted })
        return cards
    }

    var hiddenCards: Set<Card> {
        Set((defaults.stringArray(forKey: hiddenKey) ?? []).compactMap(Card.init(rawValue:)))
    }

    func isVisible(_ card: Card) -> Bool {
        !hiddenCards.contains(card)
    }

    func setVisible(_ isVisible: Bool, card: Card) {
        var hidden = hiddenCards
        if isVisible {
            hidden.remove(card)
        } else {
            hidden.insert(card)
        }
        defaults.set(hidden.map(\.rawValue).sorted(), forKey: hiddenKey)
    }

    func moveCard(from sourceIndex: Int, to destinationIndex: Int) {
        var cards = orderedCards
        guard cards.indices.contains(sourceIndex), cards.indices.contains(destinationIndex) else { return }
        let card = cards.remove(at: sourceIndex)
        cards.insert(card, at: destinationIndex)
        defaults.set(cards.map(\.rawValue), forKey: orderKey)
    }
}

typealias SleepCardLayoutPreferences = WellnessCardLayoutPreferences<SleepCardKind>

struct WellnessCardEditorConfiguration {
    let title: String
    let sectionTitle: String
    let footer: String
    let visibleText: String
    let hiddenText: String
    let visibilityAccessibilityFormatKey: String
    let accessibilityPrefix: String
}

@MainActor
class WellnessCardEditorViewController<Card: WellnessCardKind>: UITableViewController {
    var onLayoutChange: (() -> Void)?

    private let preferences: WellnessCardLayoutPreferences<Card>
    private let editorConfiguration: WellnessCardEditorConfiguration
    private var cards: [Card]

    init(
        preferences: WellnessCardLayoutPreferences<Card>,
        configuration: WellnessCardEditorConfiguration
    ) {
        self.preferences = preferences
        editorConfiguration = configuration
        cards = preferences.orderedCards
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = editorConfiguration.title
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = WellnarioPalette.background
        view.accessibilityIdentifier = "\(editorConfiguration.accessibilityPrefix).editor.root"
        tableView.backgroundColor = .clear
        tableView.tintColor = WellnarioPalette.fuchsia
        tableView.separatorColor = WellnarioPalette.hairline
        tableView.contentInset.bottom = WellnarioSpacing.bottomNavigationInset
        tableView.verticalScrollIndicatorInsets.bottom = WellnarioSpacing.bottomNavigationInset
        tableView.dragInteractionEnabled = true
        let doneItem = UIBarButtonItem(
            title: L10n.Common.done,
            style: .done,
            target: nil,
            action: nil
        )
        doneItem.primaryAction = UIAction { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        }
        doneItem.accessibilityIdentifier = "\(editorConfiguration.accessibilityPrefix).editor.done"
        navigationItem.rightBarButtonItem = doneItem
        setEditing(true, animated: false)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        cards.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        editorConfiguration.sectionTitle
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        editorConfiguration.footer
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let identifier = "WellnessCardEditorCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        let card = cards[indexPath.row]
        let isVisible = preferences.isVisible(card)

        var content = cell.defaultContentConfiguration()
        content.text = card.title
        content.secondaryText = isVisible
            ? editorConfiguration.visibleText
            : editorConfiguration.hiddenText
        content.textProperties.color = WellnarioPalette.textPrimary
        content.textProperties.font = WellnarioTypography.font(for: .body)
        content.secondaryTextProperties.color = WellnarioPalette.textSecondary
        content.secondaryTextProperties.font = WellnarioTypography.font(for: .caption)
        content.image = UIImage(systemName: card.symbolName)
        content.imageProperties.tintColor = WellnarioPalette.fuchsia
        cell.contentConfiguration = content
        cell.backgroundColor = WellnarioPalette.surface
        cell.selectionStyle = .none
        cell.shouldIndentWhileEditing = false
        cell.accessibilityIdentifier = "\(editorConfiguration.accessibilityPrefix).editor.card.\(card.rawValue)"

        let visibilitySwitch = UISwitch()
        visibilitySwitch.isOn = isVisible
        visibilitySwitch.onTintColor = WellnarioPalette.fuchsia
        visibilitySwitch.accessibilityIdentifier = "\(editorConfiguration.accessibilityPrefix).editor.visibility.\(card.rawValue)"
        visibilitySwitch.accessibilityLabel = L10n.text(
            editorConfiguration.visibilityAccessibilityFormatKey,
            card.title
        )
        visibilitySwitch.addAction(UIAction { [weak self, weak visibilitySwitch] _ in
            guard let self, let visibilitySwitch else { return }
            self.setVisibility(visibilitySwitch.isOn, for: card)
        }, for: .valueChanged)
        cell.accessoryView = nil
        cell.editingAccessoryView = visibilitySwitch
        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        editingStyleForRowAt indexPath: IndexPath
    ) -> UITableViewCell.EditingStyle {
        .none
    }

    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        false
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        true
    }

    override func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        let card = cards.remove(at: sourceIndexPath.row)
        cards.insert(card, at: destinationIndexPath.row)
        preferences.moveCard(from: sourceIndexPath.row, to: destinationIndexPath.row)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onLayoutChange?()
    }

    private func setVisibility(_ isVisible: Bool, for card: Card) {
        preferences.setVisible(isVisible, card: card)
        UISelectionFeedbackGenerator().selectionChanged()
        if let row = cards.firstIndex(of: card) {
            tableView.reloadRows(at: [IndexPath(row: row, section: 0)], with: .fade)
        }
        onLayoutChange?()
    }
}

@MainActor
final class SleepCardEditorViewController: WellnessCardEditorViewController<SleepCardKind> {
    init(preferences: SleepCardLayoutPreferences) {
        super.init(
            preferences: preferences,
            configuration: WellnessCardEditorConfiguration(
                title: L10n.text("sleep.cards.editor.title"),
                sectionTitle: L10n.text("sleep.cards.editor.section"),
                footer: L10n.text("sleep.cards.editor.footer"),
                visibleText: L10n.text("sleep.cards.visible"),
                hiddenText: L10n.text("sleep.cards.hidden"),
                visibilityAccessibilityFormatKey: "sleep.cards.visibility.accessibility",
                accessibilityPrefix: "sleep.cards"
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
