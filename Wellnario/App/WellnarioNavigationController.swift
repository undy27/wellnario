import UIKit

@MainActor
final class WellnarioNavigationController: UINavigationController {
    override func viewDidLoad() {
        super.viewDidLoad()

        navigationBar.prefersLargeTitles = true
        navigationBar.tintColor = WellnarioPalette.cyan

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = WellnarioPalette.background
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [
            .foregroundColor: WellnarioPalette.textPrimary,
            .font: WellnarioTypography.font(for: .cardTitle)
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: WellnarioPalette.textPrimary,
            .font: WellnarioTypography.font(for: .pageTitle)
        ]

        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        view.backgroundColor = WellnarioPalette.background
    }
}
