import UIKit

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
