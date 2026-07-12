import UIKit

@MainActor
protocol RootFeatureBuilding {
    func makeToday() -> TodayViewController
    func makeSupplements() -> SupplementsViewController
    func makeDiary() -> DiaryViewController
    func makeTrends() -> TrendsViewController
}

@MainActor
private final class LiveRootFeatureFactory: RootFeatureBuilding {
    private let repository: WellnarioRepositoryProtocol

    init(repository: WellnarioRepositoryProtocol) {
        self.repository = repository
    }

    func makeToday() -> TodayViewController {
        TodayViewController(repository: repository)
    }

    func makeSupplements() -> SupplementsViewController {
        SupplementsViewController(repository: repository)
    }

    func makeDiary() -> DiaryViewController {
        DiaryViewController(repository: repository)
    }

    func makeTrends() -> TrendsViewController {
        TrendsViewController(repository: repository)
    }
}

@MainActor
final class AppCoordinator: NSObject {
    private let window: UIWindow
    private let environment: AppEnvironment
    private let featureFactory: RootFeatureBuilding

    private var rootTabBarController: RootTabBarController?
    private var moreCoordinator: MoreCoordinator?
    private var isRebuildingRoot = false

    init(
        window: UIWindow,
        environment: AppEnvironment,
        featureFactory: RootFeatureBuilding? = nil
    ) {
        self.window = window
        self.environment = environment
        self.featureFactory = featureFactory
            ?? LiveRootFeatureFactory(repository: environment.repository)
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: LocalizationManager.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start() {
        let index = environment.launchConfiguration.initialTab.rawValue
        installRoot(selectedIndex: index, restoringMoreRoute: .root, animated: false)
        window.makeKeyAndVisible()
    }

    private func installRoot(
        selectedIndex: Int,
        restoringMoreRoute: MoreRoute,
        animated: Bool
    ) {
        let oldSnapshot = animated ? window.snapshotView(afterScreenUpdates: false) : nil

        let todayController = featureFactory.makeToday()
        let supplementsController = featureFactory.makeSupplements()
        let diaryController = featureFactory.makeDiary()
        let trendsController = featureFactory.makeTrends()

        let todayNavigation = makeNavigationController(root: todayController, identifier: "navigation.today")
        let supplementsNavigation = makeNavigationController(root: supplementsController, identifier: "navigation.supplements")
        let diaryNavigation = makeNavigationController(root: diaryController, identifier: "navigation.diary")
        let trendsNavigation = makeNavigationController(root: trendsController, identifier: "navigation.trends")
        let moreNavigation = WellnarioNavigationController()
        moreNavigation.view.accessibilityIdentifier = "navigation.more"

        let moreCoordinator = MoreCoordinator(navigationController: moreNavigation)
        moreCoordinator.start(restoring: restoringMoreRoute, animated: false)

        let rootController = RootTabBarController()
        rootController.install(
            viewControllers: [
                todayNavigation,
                supplementsNavigation,
                diaryNavigation,
                trendsNavigation,
                moreNavigation
            ],
            selectedIndex: selectedIndex
        )

        todayController.onOpenSettings = { [weak self] in
            self?.showMore(route: .settings)
        }
        todayController.onShowSupplements = { [weak rootController] in
            rootController?.select(index: AppLaunchConfiguration.InitialTab.supplements.rawValue)
        }
        todayController.onShowTrends = { [weak rootController] in
            rootController?.select(index: AppLaunchConfiguration.InitialTab.trends.rawValue)
        }

        self.moreCoordinator = moreCoordinator
        rootTabBarController = rootController
        window.rootViewController = rootController
        rootController.view.layoutIfNeeded()

        guard let oldSnapshot, WellnarioMotion.animationsEnabled else { return }
        oldSnapshot.frame = window.bounds
        oldSnapshot.isUserInteractionEnabled = false
        window.addSubview(oldSnapshot)
        UIView.animate(
            withDuration: WellnarioMotion.emphasized,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState],
            animations: {
                oldSnapshot.alpha = 0
                oldSnapshot.transform = CGAffineTransform(scaleX: 1.015, y: 1.015)
            },
            completion: { _ in oldSnapshot.removeFromSuperview() }
        )
    }

    private func makeNavigationController(
        root: UIViewController,
        identifier: String
    ) -> WellnarioNavigationController {
        let navigationController = WellnarioNavigationController(rootViewController: root)
        navigationController.view.accessibilityIdentifier = identifier
        return navigationController
    }

    private func showMore(route: MoreRoute) {
        rootTabBarController?.select(index: AppLaunchConfiguration.InitialTab.more.rawValue)
        moreCoordinator?.show(route, animated: true)
    }

    @objc private func languageDidChange() {
        guard !isRebuildingRoot else { return }
        isRebuildingRoot = true

        let selectedIndex = rootTabBarController?.selectedIndex
            ?? environment.launchConfiguration.initialTab.rawValue
        let moreRoute = moreCoordinator?.currentRoute ?? .root
        installRoot(
            selectedIndex: selectedIndex,
            restoringMoreRoute: moreRoute,
            animated: true
        )
        isRebuildingRoot = false
    }
}
