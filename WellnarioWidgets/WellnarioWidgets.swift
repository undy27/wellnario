import AppIntents
import SwiftUI
import WidgetKit

struct SupplementPackageEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Envase")
    static let defaultQuery = SupplementPackageEntityQuery()

    let id: String
    let supplementName: String
    let instanceLabel: String
    let doseDescription: String
    let iconName: String

    init(package: SupplementWidgetPackage) {
        id = package.id
        supplementName = package.supplementName
        instanceLabel = package.instanceLabel
        doseDescription = package.doseDescription
        iconName = package.packageIconName
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(supplementName)",
            subtitle: "\(instanceLabel) · \(doseDescription)",
            image: .init(systemName: iconName)
        )
    }
}

struct SupplementPackageEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SupplementPackageEntity] {
        let packages = SupplementWidgetDataStore().snapshot()?.packages ?? []
        let entities = Dictionary(uniqueKeysWithValues: packages.map {
            ($0.id, SupplementPackageEntity(package: $0))
        })
        return identifiers.compactMap { entities[$0] }
    }

    func suggestedEntities() async throws -> [SupplementPackageEntity] {
        (SupplementWidgetDataStore().snapshot()?.packages ?? []).map(SupplementPackageEntity.init)
    }
}

struct SupplementWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Tomas de suplementos"
    static let description = IntentDescription("Elige hasta ocho envases. El widget mediano muestra cuatro y el grande muestra ocho.")

    @Parameter(title: "Envase 1") var package1: SupplementPackageEntity?
    @Parameter(title: "Envase 2") var package2: SupplementPackageEntity?
    @Parameter(title: "Envase 3") var package3: SupplementPackageEntity?
    @Parameter(title: "Envase 4") var package4: SupplementPackageEntity?
    @Parameter(title: "Envase 5") var package5: SupplementPackageEntity?
    @Parameter(title: "Envase 6") var package6: SupplementPackageEntity?
    @Parameter(title: "Envase 7") var package7: SupplementPackageEntity?
    @Parameter(title: "Envase 8") var package8: SupplementPackageEntity?

    init() {}

    var selectedPackageIDs: [String] {
        [
            package1?.id, package2?.id, package3?.id, package4?.id,
            package5?.id, package6?.id, package7?.id, package8?.id
        ].compactMap { $0 }
    }
}

struct ToggleSupplementPackageSelectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Seleccionar envase"

    @Parameter(title: "Envase") var packageID: String

    init() {
        packageID = ""
    }

    init(packageID: String) {
        self.packageID = packageID
    }

    func perform() async throws -> some IntentResult {
        let store = SupplementWidgetDataStore()
        guard store.snapshot()?.packages.contains(where: { $0.id == packageID }) == true else {
            return .result()
        }
        store.toggleSelection(for: packageID)
        WidgetCenter.shared.reloadTimelines(ofKind: WellnarioSupplementWidget.kind)
        return .result()
    }
}

struct SupplementWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: SupplementWidgetConfigurationIntent
    let snapshot: SupplementWidgetSnapshot
}

struct SupplementWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SupplementWidgetEntry {
        SupplementWidgetEntry(
            date: Date(),
            configuration: SupplementWidgetConfigurationIntent(),
            snapshot: .placeholder
        )
    }

    func snapshot(
        for configuration: SupplementWidgetConfigurationIntent,
        in context: Context
    ) async -> SupplementWidgetEntry {
        currentEntry(configuration: configuration)
    }

    func timeline(
        for configuration: SupplementWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<SupplementWidgetEntry> {
        Timeline(entries: [currentEntry(configuration: configuration)], policy: .never)
    }

    private func currentEntry(
        configuration: SupplementWidgetConfigurationIntent
    ) -> SupplementWidgetEntry {
        SupplementWidgetEntry(
            date: Date(),
            configuration: configuration,
            snapshot: SupplementWidgetDataStore().snapshot() ?? .placeholder
        )
    }
}

struct SupplementIntakeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WellnarioSupplementWidget.kind,
            intent: SupplementWidgetConfigurationIntent.self,
            provider: SupplementWidgetProvider()
        ) { entry in
            SupplementIntakeWidgetView(entry: entry)
        }
        .configurationDisplayName("Registrar suplementos")
        .description("Selecciona envases y confirma sus tomas juntas. El tamaño grande admite hasta ocho.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct SupplementIntakeWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: SupplementWidgetEntry

    private var copy: SupplementWidgetCopy {
        SupplementWidgetCopy(languageCode: entry.snapshot.languageCode)
    }

    private var packages: [SupplementWidgetPackage] {
        let wantedIDs = entry.configuration.selectedPackageIDs
        let identifiers = wantedIDs.isEmpty
            ? entry.snapshot.packages.map(\.id)
            : wantedIDs
        let indexed = Dictionary(uniqueKeysWithValues: entry.snapshot.packages.map { ($0.id, $0) })
        var seen = Set<String>()
        return identifiers.compactMap { identifier in
            guard seen.insert(identifier).inserted else { return nil }
            return indexed[identifier]
        }.prefix(maximumPackageCount).map { $0 }
    }

    private var selectedPackageIDs: Set<String> {
        SupplementWidgetDataStore().selectedPackageIDs().intersection(Set(packages.map(\.id)))
    }

    private var selectedPackages: [SupplementWidgetPackage] {
        packages.filter { selectedPackageIDs.contains($0.id) }
    }

    private var isCompact: Bool { family == .systemMedium }
    private var maximumPackageCount: Int { isCompact ? 4 : 8 }

    var body: some View {
        if packages.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: isCompact ? 5 : 6) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: isCompact ? 5 : 6),
                        GridItem(.flexible(), spacing: isCompact ? 5 : 6)
                    ],
                    spacing: isCompact ? 5 : 6
                ) {
                    ForEach(packages) { package in
                        let isSelected = selectedPackageIDs.contains(package.id)
                        Button(intent: ToggleSupplementPackageSelectionIntent(packageID: package.id)) {
                            SupplementPackageCard(
                                package: package,
                                isSelected: isSelected,
                                isCompact: isCompact
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(copy.accessibilityLabel(for: package, isSelected: isSelected))
                    }
                }
                batchAction
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .containerBackground(for: .widget) {
                Color(red: 0.06, green: 0.09, blue: 0.13)
            }
        }
    }

    @ViewBuilder
    private var batchAction: some View {
        if selectedPackages.isEmpty {
            Label(copy.selectPrompt, systemImage: "hand.tap.fill")
                .font(isCompact ? .caption2 : .caption)
                .foregroundStyle(.white.opacity(0.58))
                .frame(maxWidth: .infinity, minHeight: isCompact ? 22 : 30)
        } else {
            Link(destination: SupplementWidgetURL.confirmSelectedIntakes) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(copy.batchAction(selectedPackages.count))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font((isCompact ? Font.caption : .subheadline).weight(.semibold))
                .foregroundStyle(Color(red: 0.05, green: 0.16, blue: 0.18))
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: isCompact ? 28 : 34)
                .background(Color(red: 0.40, green: 0.89, blue: 0.86), in: RoundedRectangle(cornerRadius: 11))
            }
            .accessibilityLabel(copy.batchAction(selectedPackages.count))
        }
    }

    private var emptyState: some View {
        Link(destination: SupplementWidgetURL.home) {
            VStack(spacing: 10) {
                Image(systemName: "pills.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color(red: 0.39, green: 0.88, blue: 0.86))
                Text(copy.emptyTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(copy.emptyMessage)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.72))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .containerBackground(for: .widget) {
            Color(red: 0.06, green: 0.09, blue: 0.13)
        }
    }
}

private struct SupplementPackageCard: View {
    let package: SupplementWidgetPackage
    let isSelected: Bool
    let isCompact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: isCompact ? 5 : 7) {
            Image(systemName: package.packageIconName)
                .font(.system(size: isCompact ? 10 : 12, weight: .semibold))
                .foregroundStyle(Color(red: 1.00, green: 0.56, blue: 0.14))
                .frame(width: isCompact ? 21 : 26, height: isCompact ? 21 : 26)
                .background(
                    isSelected ? Color(red: 0.40, green: 0.89, blue: 0.86) : Color.white.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: isCompact ? 7 : 8)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(package.supplementName)
                    .font((isCompact ? Font.caption2 : .caption).weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(isCompact ? 1 : 2)
                Text("\(package.instanceLabel) · \(package.doseDescription)")
                    .font(.system(size: isCompact ? 9 : 10, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.82) : Color.white.opacity(0.68))
                    .lineLimit(isCompact ? 1 : 2)
            }
            .layoutPriority(1)
            .fixedSize(horizontal: false, vertical: true)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: isCompact ? 9 : 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.40, green: 0.89, blue: 0.86))
            }
            Spacer(minLength: 0)
        }
        .padding(isCompact ? 6 : 5)
        .frame(maxWidth: .infinity, minHeight: isCompact ? 38 : 64, alignment: .leading)
        .background(
            isSelected ? Color(red: 0.12, green: 0.30, blue: 0.31) : Color.white.opacity(0.10),
            in: RoundedRectangle(cornerRadius: isCompact ? 12 : 15)
        )
        .overlay {
            RoundedRectangle(cornerRadius: isCompact ? 12 : 15)
                .stroke(isSelected ? Color(red: 0.40, green: 0.89, blue: 0.86) : .clear, lineWidth: 1)
        }
    }
}

private struct SupplementWidgetCopy {
    let languageCode: String

    private var isEnglish: Bool { languageCode.lowercased().hasPrefix("en") }

    var selectPrompt: String { isEnglish ? "Select a package" : "Selecciona los envases" }
    var emptyTitle: String { isEnglish ? "No packages yet" : "Aún no hay envases" }
    var emptyMessage: String {
        isEnglish
            ? "Add a discrete package in Wellnario, then choose it here."
            : "Añade un envase en unidades discretas en Wellnario y elígelo aquí."
    }

    func batchAction(_ count: Int) -> String {
        if isEnglish {
            return count == 1 ? "Log 1 intake" : "Log \(count) intakes"
        }
        return count == 1 ? "Registrar 1 toma" : "Registrar \(count) tomas"
    }

    func accessibilityLabel(for package: SupplementWidgetPackage, isSelected: Bool) -> String {
        let action = isSelected
            ? (isEnglish ? "Deselect" : "Deseleccionar")
            : (isEnglish ? "Select" : "Seleccionar")
        return "\(action): \(package.supplementName), \(package.instanceLabel), \(package.doseDescription)"
    }
}

private extension SupplementWidgetPackage {
    var packageIconName: String {
        switch presentationKey {
        case "presentation.capsule.name": "capsule.portrait.fill"
        case "presentation.tablet.name": "pills.fill"
        case "presentation.drops.name": "drop.fill"
        case "presentation.gummy.name": "seal.fill"
        case "presentation.sachet.name": "envelope.fill"
        case "presentation.scoop.name": "cup.and.saucer.fill"
        default: "pills.fill"
        }
    }
}

@main
struct WellnarioWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SupplementIntakeWidget()
        SleepSummaryWidget()
    }
}
