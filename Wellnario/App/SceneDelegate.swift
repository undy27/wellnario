import UIKit

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private var coordinator: AppCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = WellnarioPalette.background
        self.window = window
        bootstrap(in: window)
    }

    private func bootstrap(in window: UIWindow) {
        do {
            let environment = try AppEnvironment()
            let coordinator = AppCoordinator(window: window, environment: environment)
            self.coordinator = coordinator
            coordinator.start()
        } catch {
            let controller = BootstrapFailureViewController(error: error) { [weak self, weak window] in
                guard let self, let window else { return }
                self.bootstrap(in: window)
            }
            window.rootViewController = controller
            window.makeKeyAndVisible()
        }
    }
}

@MainActor
private final class BootstrapFailureViewController: UIViewController {
    private let error: Error
    private let retry: () -> Void

    init(error: Error, retry: @escaping () -> Void) {
        self.error = error
        self.retry = retry
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WellnarioPalette.background
        view.accessibilityIdentifier = "bootstrap.error"

        let iconView = UIImageView(image: UIImage(systemName: "externaldrive.badge.exclamationmark"))
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .medium)
        iconView.tintColor = WellnarioPalette.warning
        iconView.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.pageTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = L10n.Error.database
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center

        let messageLabel = UILabel()
        messageLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        messageLabel.text = error.localizedDescription
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center

        let retryButton = PrimaryButton(title: L10n.Common.retry, style: .secondary)
        retryButton.accessibilityIdentifier = "bootstrap.retry"
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        let stack = UIStackView(
            arrangedSubviews: [iconView, titleLabel, messageLabel, retryButton],
            axis: .vertical,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
        stack.setCustomSpacing(WellnarioSpacing.large, after: iconView)
        stack.setCustomSpacing(WellnarioSpacing.large, after: messageLabel)
        view.addForAutoLayout(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: WellnarioSpacing.large),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -WellnarioSpacing.large),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            retryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
    }

    @objc private func retryTapped() {
        retry()
    }
}
