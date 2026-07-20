import Foundation

/// Contract shared by the app and its WidgetKit extension. The widget only
/// receives the minimum display data it needs; the SQLite store remains owned
/// by Wellnario, which keeps intake creation in one place.
enum WellnarioSupplementWidget {
    static let kind = "WellnarioSupplementIntakeWidget"
    static let appGroupID = "group.com.dtigl.wellnario"
    // Versioning this key prevents a pre-filter snapshot from exposing
    // mass- or volume-based packages after the widget becomes discrete-only.
    static let snapshotKey = "wellnario.supplementWidget.snapshot.v2"
    static let selectedPackageIDsKey = "wellnario.supplementWidget.selectedPackageIDs.v1"
}

struct SupplementWidgetPackage: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let supplementName: String
    let instanceLabel: String
    let doseDescription: String
    let inventoryDescription: String?
    /// Stable catalog key, so the widget can choose an icon without relying on
    /// localized presentation names.
    let presentationKey: String?

    init(
        id: String,
        supplementName: String,
        instanceLabel: String,
        doseDescription: String,
        inventoryDescription: String? = nil,
        presentationKey: String? = nil
    ) {
        self.id = id
        self.supplementName = supplementName
        self.instanceLabel = instanceLabel
        self.doseDescription = doseDescription
        self.inventoryDescription = inventoryDescription
        self.presentationKey = presentationKey
    }
}

struct SupplementWidgetSnapshot: Codable, Hashable, Sendable {
    let packages: [SupplementWidgetPackage]
    let languageCode: String
    let updatedAt: Date

    init(
        packages: [SupplementWidgetPackage],
        languageCode: String,
        updatedAt: Date = Date()
    ) {
        self.packages = Array(packages.prefix(24))
        self.languageCode = languageCode
        self.updatedAt = updatedAt
    }

    static let placeholder = SupplementWidgetSnapshot(
        packages: [
            SupplementWidgetPackage(
                id: "placeholder-magnesium",
                supplementName: "Magnesio",
                instanceLabel: "Envase diario",
                doseDescription: "2 cáps.",
                inventoryDescription: "60 cáps. restantes",
                presentationKey: "presentation.capsule.name"
            ),
            SupplementWidgetPackage(
                id: "placeholder-vitamin-d",
                supplementName: "Vitamina D",
                instanceLabel: "Envase actual",
                doseDescription: "1 cáps.",
                inventoryDescription: "42 cáps. restantes",
                presentationKey: "presentation.capsule.name"
            ),
            SupplementWidgetPackage(
                id: "placeholder-omega",
                supplementName: "Omega-3",
                instanceLabel: "Mañana",
                doseDescription: "2 cáps.",
                inventoryDescription: "34 cáps. restantes",
                presentationKey: "presentation.capsule.name"
            ),
            SupplementWidgetPackage(
                id: "placeholder-gummy",
                supplementName: "Vitamina C",
                instanceLabel: "Entrenamiento",
                doseDescription: "1 gominola",
                inventoryDescription: "30 gominolas restantes",
                presentationKey: "presentation.gummy.name"
            )
        ],
        languageCode: "es"
    )
}

struct SupplementWidgetDataStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: WellnarioSupplementWidget.appGroupID)) {
        self.defaults = defaults ?? .standard
    }

    func snapshot() -> SupplementWidgetSnapshot? {
        guard let data = defaults.data(forKey: WellnarioSupplementWidget.snapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(SupplementWidgetSnapshot.self, from: data)
    }

    func save(_ snapshot: SupplementWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: WellnarioSupplementWidget.snapshotKey)
    }

    func selectedPackageIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: WellnarioSupplementWidget.selectedPackageIDsKey) ?? [])
    }

    func toggleSelection(for packageID: String) {
        var selected = selectedPackageIDs()
        if selected.contains(packageID) {
            selected.remove(packageID)
        } else {
            selected.insert(packageID)
        }
        saveSelectedPackageIDs(selected)
    }

    func clearSelectedPackageIDs() {
        defaults.removeObject(forKey: WellnarioSupplementWidget.selectedPackageIDsKey)
    }

    func retainSelections(in packageIDs: Set<String>) {
        saveSelectedPackageIDs(selectedPackageIDs().intersection(packageIDs))
    }

    private func saveSelectedPackageIDs(_ packageIDs: Set<String>) {
        defaults.set(packageIDs.sorted(), forKey: WellnarioSupplementWidget.selectedPackageIDsKey)
    }
}

enum SupplementWidgetURL {
    static var home: URL {
        URL(string: "wellnario://widget")!
    }

    static func intake(for packageID: String) -> URL {
        var components = URLComponents()
        components.scheme = "wellnario"
        components.host = "widget"
        components.path = "/intake"
        components.queryItems = [URLQueryItem(name: "package", value: packageID)]
        return components.url ?? home
    }

    static var confirmSelectedIntakes: URL {
        URL(string: "wellnario://widget/confirm-selected")!
    }

    static var sleepWidget: URL {
        URL(string: "wellnario://widget/sleep")!
    }

    static var sleepWidgetSync: URL {
        URL(string: "wellnario://widget/sleep-sync")!
    }

    static func packageID(from url: URL) -> UUID? {
        guard url.scheme == "wellnario",
              url.host == "widget",
              url.path == "/intake",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "package" })?
                .value else {
            return nil
        }
        return UUID(uuidString: value)
    }

    static func requestsSelectedIntakesConfirmation(from url: URL) -> Bool {
        url.scheme == "wellnario"
            && url.host == "widget"
            && url.path == "/confirm-selected"
    }

    static func requestsSleepWidget(from url: URL) -> Bool {
        url.scheme == "wellnario"
            && url.host == "widget"
            && url.path == "/sleep"
    }

    static func requestsSleepWidgetSync(from url: URL) -> Bool {
        url.scheme == "wellnario"
            && url.host == "widget"
            && url.path == "/sleep-sync"
    }
}
