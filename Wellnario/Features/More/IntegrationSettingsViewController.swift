import UIKit

enum IntegrationProvider: String, Sendable {
    case appleHealth
    case oura

    @MainActor var title: String {
        switch self {
        case .appleHealth: "Apple Health"
        case .oura: "Oura"
        }
    }

    @MainActor var description: String {
        switch self {
        case .appleHealth: L10n.text("integrations.apple_health.description")
        case .oura: L10n.text("integrations.oura.description")
        }
    }

    @MainActor var detail: String {
        switch self {
        case .appleHealth: L10n.text("integrations.apple_health.detail")
        case .oura: L10n.text("integrations.oura.detail")
        }
    }

    var symbolName: String {
        switch self {
        case .appleHealth: "heart.fill"
        case .oura: "circle.hexagongrid.fill"
        }
    }

    @MainActor var tone: UIColor {
        switch self {
        case .appleHealth: WellnarioPalette.pink
        case .oura: WellnarioPalette.violet
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .appleHealth: "settings.integration.apple_health"
        case .oura: "settings.integration.oura"
        }
    }
}

@MainActor
final class IntegrationRowControl: UIControl {
    let provider: IntegrationProvider

    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let statusLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted
                ? WellnarioPalette.surfacePressed
                : WellnarioPalette.surfaceElevated
        }
    }

    init(provider: IntegrationProvider) {
        self.provider = provider
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configureStatus(_ text: String, tone: UIColor) {
        statusLabel.text = text
        statusLabel.textColor = tone
        accessibilityValue = text
    }

    private func setUp() {
        backgroundColor = WellnarioPalette.surfaceElevated
        applyContinuousCorners(WellnarioRadius.control)
        layer.borderWidth = 1
        layer.borderColor = WellnarioPalette.hairline.cgColor
        accessibilityIdentifier = provider.accessibilityIdentifier

        iconContainer.backgroundColor = provider.tone.withAlphaComponent(0.14)
        iconContainer.applyContinuousCorners(14)
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 46),
            iconContainer.heightAnchor.constraint(equalTo: iconContainer.widthAnchor)
        ])
        iconView.image = UIImage(systemName: provider.symbolName)
        iconView.tintColor = provider.tone
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        iconContainer.addForAutoLayout(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor)
        ])

        titleLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        titleLabel.text = provider.title
        detailLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        detailLabel.text = provider.description
        detailLabel.numberOfLines = 2
        let labels = UIStackView(arrangedSubviews: [titleLabel, detailLabel], axis: .vertical, spacing: 4)

        statusLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.cyan)
        statusLabel.text = L10n.text("integrations.connect")
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)

        chevron.tintColor = WellnarioPalette.textTertiary
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(
            arrangedSubviews: [iconContainer, labels, statusLabel, chevron],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        stack.isUserInteractionEnabled = false
        addForAutoLayout(stack)
        stack.pinEdges(to: self, insets: NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        heightAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true

        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = provider.title
        accessibilityValue = L10n.text("integrations.not_connected")
        accessibilityHint = provider.description
    }
}

@MainActor
final class IntegrationSetupViewController: WellnessScrollViewController {
    private let provider: IntegrationProvider
    private let appleHealthService: AppleHealthSyncing
    private let statusBanner = FeedbackBannerView()
    private let connectButton = PrimaryButton()

    init(
        provider: IntegrationProvider,
        appleHealthService: AppleHealthSyncing
    ) {
        self.provider = provider
        self.appleHealthService = appleHealthService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = provider.title
        navigationItem.largeTitleDisplayMode = .never
        view.accessibilityIdentifier = "\(provider.accessibilityIdentifier).detail"
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appleHealthDidChange),
            name: .appleHealthSyncDidChange,
            object: appleHealthService
        )
        buildContent()
        updateStatus()
    }

    private func buildContent() {
        let iconContainer = UIView()
        iconContainer.backgroundColor = provider.tone.withAlphaComponent(0.14)
        iconContainer.applyContinuousCorners(34)
        let icon = UIImageView(image: UIImage(systemName: provider.symbolName))
        icon.tintColor = provider.tone
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 38, weight: .semibold)
        iconContainer.addForAutoLayout(icon)
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 88),
            iconContainer.heightAnchor.constraint(equalTo: iconContainer.widthAnchor),
            icon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor)
        ])

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.pageTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = provider.title
        titleLabel.textAlignment = .center
        let bodyLabel = UILabel()
        bodyLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        bodyLabel.text = provider.detail
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0

        let hero = UIStackView(
            arrangedSubviews: [iconContainer, titleLabel, bodyLabel],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        contentStack.addArrangedSubview(makeCard(containing: hero))

        contentStack.addArrangedSubview(makeSectionTitle(L10n.text("integrations.data.title")))
        let dataStack = UIStackView(
            arrangedSubviews: dataRows(),
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        contentStack.addArrangedSubview(makeCard(containing: dataStack))

        let privacy = FeedbackBannerView()
        privacy.configure(message: L10n.text("integrations.privacy"), tone: .success)
        contentStack.addArrangedSubview(privacy)

        if provider == .appleHealth {
            contentStack.addArrangedSubview(statusBanner)
        }

        connectButton.accessibilityIdentifier = "\(provider.accessibilityIdentifier).connect"
        connectButton.addTarget(self, action: #selector(connect), for: .touchUpInside)
        contentStack.addArrangedSubview(connectButton)
    }

    private func updateStatus() {
        guard provider == .appleHealth else {
            connectButton.setTitle(L10n.text("integrations.connect"), for: .normal)
            return
        }

        connectButton.isLoading = appleHealthService.state == .syncing
        switch appleHealthService.state {
        case .unavailable:
            statusBanner.configure(message: L10n.text("apple_health.unavailable"), tone: .warning)
            connectButton.setTitle(L10n.text("integrations.connect"), for: .normal)
            connectButton.isEnabled = false
        case .notConfigured:
            statusBanner.configure(
                message: L10n.text("apple_health.permission_explanation"),
                tone: .information
            )
            connectButton.setTitle(L10n.text("integrations.connect"), for: .normal)
            connectButton.isEnabled = true
        case .syncing:
            statusBanner.configure(message: L10n.text("apple_health.syncing"), tone: .information)
            connectButton.setTitle(L10n.text("apple_health.sync_now"), for: .normal)
        case .failed:
            statusBanner.configure(message: L10n.text("apple_health.sync_failed"), tone: .warning)
            connectButton.setTitle(L10n.text("apple_health.try_again"), for: .normal)
            connectButton.isEnabled = true
        case .ready:
            let message = appleHealthService.snapshot.lastSyncedAt.map(AppleHealthUIFormatting.syncedAt)
                ?? L10n.text("apple_health.configured_privacy")
            statusBanner.configure(message: message, tone: .success)
            connectButton.setTitle(L10n.text("apple_health.sync_now"), for: .normal)
            connectButton.isEnabled = true
        }
    }

    private func dataRows() -> [UIView] {
        let keys: [(String, String)]
        switch provider {
        case .appleHealth:
            keys = [
                ("bed.double.fill", "integrations.data.sleep"),
                ("heart.fill", "integrations.data.heart"),
                ("figure.run", "integrations.data.activity"),
                ("figure.strengthtraining.traditional", "integrations.data.workouts")
            ]
        case .oura:
            keys = [
                ("moon.stars.fill", "integrations.data.sleep"),
                ("figure.cooldown", "integrations.data.recovery"),
                ("waveform.path.ecg", "integrations.data.heart"),
                ("flame.fill", "integrations.data.activity")
            ]
        }
        return keys.map { symbol, key in
            let icon = UIImageView(image: UIImage(systemName: symbol))
            icon.tintColor = provider.tone
            icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
            icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
            let label = UILabel()
            label.applyWellnarioStyle(.body, color: WellnarioPalette.textPrimary)
            label.text = L10n.text(key)
            return UIStackView(
                arrangedSubviews: [icon, label],
                axis: .horizontal,
                spacing: WellnarioSpacing.xSmall,
                alignment: .center
            )
        }
    }

    @objc private func connect() {
        if provider == .appleHealth {
            connectAppleHealth()
            return
        }

        let title: String
        let message: String
        switch provider {
        case .appleHealth:
            return
        case .oura:
            title = L10n.text("integrations.oura.authorization.title")
            message = L10n.text("integrations.oura.authorization.message")
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.Common.done, style: .default))
        present(alert, animated: true)
    }

    private func connectAppleHealth() {
        Task {
            do {
                if appleHealthService.isConfigured {
                    try await appleHealthService.sync()
                } else {
                    try await appleHealthService.requestAuthorizationAndSync()
                }
                let alert = UIAlertController(
                    title: L10n.text("apple_health.connected.title"),
                    message: L10n.text("apple_health.connected.message"),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: L10n.Common.done, style: .default))
                present(alert, animated: true)
            } catch {
                let alert = UIAlertController(
                    title: L10n.Common.error,
                    message: L10n.text("apple_health.sync_failed"),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: L10n.Common.done, style: .default))
                present(alert, animated: true)
            }
        }
    }

    @objc private func appleHealthDidChange() { updateStatus() }
}
