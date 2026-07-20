import UIKit

/// Shared navigation-bar indicator used while Apple Health is synchronizing.
///
/// The indicator deliberately lives in the navigation bar instead of in the
/// scrollable content, so switching between the main sections does not move
/// the content or show a transient status card.
@MainActor
final class AppleHealthSyncNavigationIndicator {
    private let service: AppleHealthSyncing
    private weak var navigationItem: UINavigationItem?
    private var baseItems: [UIBarButtonItem] = []
    private let container = UIView()
    private let imageView = UIImageView()
    private lazy var barButtonItem = UIBarButtonItem(customView: container)
    private let animationKey = "wellnario.appleHealthSync"

    init(service: AppleHealthSyncing) {
        self.service = service
        container.backgroundColor = .clear
        container.accessibilityIdentifier = "apple_health.syncing"
        container.accessibilityLabel = L10n.text("apple_health.sync_now")
        container.isAccessibilityElement = true
        container.accessibilityTraits = [.button]
        container.isUserInteractionEnabled = true
        container.addGestureRecognizer(UITapGestureRecognizer(
            target: self,
            action: #selector(syncTapped)
        ))
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 36),
            container.heightAnchor.constraint(equalToConstant: 44)
        ])

        imageView.image = UIImage(systemName: "arrow.triangle.2.circlepath")
        imageView.tintColor = WellnarioPalette.orange
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 20,
            weight: .semibold
        )
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(syncStateDidChange),
            name: .appleHealthSyncDidChange,
            object: service
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func install(on navigationItem: UINavigationItem, baseItems: [UIBarButtonItem]) {
        self.navigationItem = navigationItem
        let incomingItems = baseItems.filter { $0 !== barButtonItem }
        if !incomingItems.isEmpty || self.baseItems.isEmpty {
            self.baseItems = incomingItems
        }
        apply(animated: false)
    }

    func setBaseItems(_ items: [UIBarButtonItem]) {
        baseItems = items.filter { $0 !== barButtonItem }
        apply(animated: false)
    }

    /// Re-applies the current HealthKit state after a tab becomes visible.
    /// This covers the case where synchronization started while this tab was
    /// off-screen and therefore no state-change notification was observed by
    /// its navigation bar.
    func refresh() {
        apply(animated: false)
    }

    @objc private func syncStateDidChange() {
        apply(animated: true)
    }

    @objc private func syncTapped() {
        guard service.state != .syncing else { return }
        Task { [weak self] in
            guard let self else { return }
            try? await service.sync()
        }
    }

    private func apply(animated: Bool) {
        guard let navigationItem else { return }
        let syncing = service.state == .syncing

        container.isHidden = false
        container.alpha = 1
        container.accessibilityLabel = L10n.text(
            syncing ? "apple_health.status.syncing" : "apple_health.sync_now"
        )
        imageView.tintColor = WellnarioPalette.orange
        navigationItem.rightBarButtonItems = baseItems + [barButtonItem]
        if syncing {
            startRotationIfNeeded()
        } else {
            imageView.layer.removeAnimation(forKey: animationKey)
        }
    }

    private func startRotationIfNeeded() {
        guard WellnarioMotion.animationsEnabled,
              imageView.layer.animation(forKey: animationKey) == nil else { return }
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = Double.pi * 2
        rotation.duration = 0.9
        rotation.repeatCount = .infinity
        rotation.timingFunction = CAMediaTimingFunction(name: .linear)
        imageView.layer.add(rotation, forKey: animationKey)
    }
}

@MainActor
class FeatureViewController: UIViewController {
    let repository: WellnarioRepositoryProtocol

    var catalogLanguage: CatalogLanguage {
        CatalogLanguage(languageCode: LocalizationManager.shared.language.rawValue)
    }

    init(repository: WellnarioRepositoryProtocol) {
        self.repository = repository
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WellnarioPalette.background
        navigationItem.backButtonDisplayMode = .minimal

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dataDidChange),
            name: .wellnarioRepositoryDidChange,
            object: repository
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: LocalizationManager.didChangeNotification,
            object: nil
        )
    }

    @objc func dataDidChange() {
        reloadContent()
    }

    @objc func languageDidChange() {
        applyLocalizedCopy()
        reloadContent()
    }

    func applyLocalizedCopy() {}

    func reloadContent() {}

    func showError(_ error: Error) {
        let alert = UIAlertController(
            title: L10n.Common.error,
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.done, style: .default))
        present(alert, animated: true)
    }

    func showConfirmation(
        title: String,
        message: String,
        destructiveTitle: String? = nil,
        action: @escaping () -> Void
    ) {
        let destructiveTitle = destructiveTitle ?? L10n.Common.delete
        let alert = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: destructiveTitle, style: .destructive) { _ in action() })
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 60, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    func presentSheet(_ controller: UIViewController, largeOnly: Bool = false) {
        let navigationController = controller as? UINavigationController
            ?? WellnarioNavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .pageSheet
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = largeOnly ? [.large()] : [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = WellnarioRadius.card
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        present(navigationController, animated: true)
    }
}

@MainActor
enum FeatureFormatting {
    static func decimal(_ value: Decimal, maximumFractionDigits: Int = 3) -> String {
        let formatter = NumberFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    static func parseDecimal(_ text: String?) -> Decimal? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        let formatter = NumberFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true
        if let value = formatter.number(from: text) as? NSDecimalNumber {
            return value.decimalValue
        }
        return Decimal(string: text.replacingOccurrences(of: ",", with: "."))
    }

    static func double(_ decimal: Decimal) -> Double {
        NSDecimalNumber(decimal: decimal).doubleValue
    }

    static func localDayDate(_ day: LocalDay, timeZone: TimeZone = .current) -> Date? {
        try? day.startDate(in: timeZone)
    }

    static func expirationText(_ day: LocalDay?) -> String {
        guard let day, let date = localDayDate(day) else { return L10n.Common.noDate }
        return WellnarioFormatters.expiryDescription(date)
    }
}

extension UIImpactFeedbackGenerator {
    static func wellnarioSuccess() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
}
