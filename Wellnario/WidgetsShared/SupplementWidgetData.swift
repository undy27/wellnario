import Foundation

/// Contract shared by the app and its WidgetKit extension. The widget only
/// receives the minimum display data it needs; the SQLite store remains owned
/// by Wellnario, which keeps intake creation in one place.
enum WellnarioSupplementWidget {
    static let kind = "WellnarioSupplementIntakeWidget"
    static let appGroupID = "group.com.dtigl.wellnario"
    // Refresh stored widget data after expanding registration to all supported
    // package units, including mass and volume.
    static let snapshotKey = "wellnario.supplementWidget.snapshot.v3"
    static let selectedPackageIDsKey = "wellnario.supplementWidget.selectedPackageIDs.v1"
}

struct SupplementWidgetPackage: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let supplementName: String
    let instanceLabel: String
    let doseDescription: String
    let inventoryDescription: String?
    /// Whether this specific package has at least one intake recorded on the
    /// day represented by the snapshot.
    let hasIntakeToday: Bool
    /// Stable catalog key, so the widget can choose an icon without relying on
    /// localized presentation names.
    let presentationKey: String?

    init(
        id: String,
        supplementName: String,
        instanceLabel: String,
        doseDescription: String,
        inventoryDescription: String? = nil,
        hasIntakeToday: Bool = false,
        presentationKey: String? = nil
    ) {
        self.id = id
        self.supplementName = supplementName
        self.instanceLabel = instanceLabel
        self.doseDescription = doseDescription
        self.inventoryDescription = inventoryDescription
        self.hasIntakeToday = hasIntakeToday
        self.presentationKey = presentationKey
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case supplementName
        case instanceLabel
        case doseDescription
        case inventoryDescription
        case hasIntakeToday
        case presentationKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        supplementName = try container.decode(String.self, forKey: .supplementName)
        instanceLabel = try container.decode(String.self, forKey: .instanceLabel)
        doseDescription = try container.decode(String.self, forKey: .doseDescription)
        inventoryDescription = try container.decodeIfPresent(String.self, forKey: .inventoryDescription)
        // Existing widget data does not have this key. Decode it as false so
        // an installed widget remains usable until the app refreshes it.
        hasIntakeToday = try container.decodeIfPresent(Bool.self, forKey: .hasIntakeToday) ?? false
        presentationKey = try container.decodeIfPresent(String.self, forKey: .presentationKey)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(supplementName, forKey: .supplementName)
        try container.encode(instanceLabel, forKey: .instanceLabel)
        try container.encode(doseDescription, forKey: .doseDescription)
        try container.encodeIfPresent(inventoryDescription, forKey: .inventoryDescription)
        try container.encode(hasIntakeToday, forKey: .hasIntakeToday)
        try container.encodeIfPresent(presentationKey, forKey: .presentationKey)
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
        // The configuration picker must expose every active package. The widget
        // itself decides how many of the selected packages it can render.
        self.packages = packages
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
