import UIKit

enum MoreFeature: String, CaseIterable, Hashable, Sendable {
    case sleep
    case biomarkers
    case biologicalAge
    case strength
    case recovery

    @MainActor var title: String {
        switch self {
        case .sleep: L10n.More.sleep
        case .biomarkers: L10n.More.biomarkers
        case .biologicalAge: L10n.More.biologicalAge
        case .strength: L10n.More.strength
        case .recovery: L10n.More.recovery
        }
    }

    @MainActor var featureDescription: String {
        switch self {
        case .sleep: L10n.More.sleepDescription
        case .biomarkers: L10n.More.biomarkersDescription
        case .biologicalAge: L10n.More.biologicalAgeDescription
        case .strength: L10n.More.strengthDescription
        case .recovery: L10n.More.recoveryDescription
        }
    }

    var symbolName: String {
        switch self {
        case .sleep: "moon.stars.fill"
        case .biomarkers: "waveform.path.ecg"
        case .biologicalAge: "hourglass.circle.fill"
        case .strength: "dumbbell.fill"
        case .recovery: "figure.cooldown"
        }
    }

    @MainActor var accentColors: [UIColor] {
        switch self {
        case .sleep: [WellnarioPalette.violet, WellnarioPalette.magenta]
        case .biomarkers: [WellnarioPalette.cyan, WellnarioPalette.information]
        case .biologicalAge: [WellnarioPalette.warning, WellnarioPalette.pink]
        case .strength: [WellnarioPalette.magenta, WellnarioPalette.pink]
        case .recovery: [WellnarioPalette.success, WellnarioPalette.cyan]
        }
    }

    var accessibilityIdentifier: String {
        "more.feature.\(rawValue)"
    }

}

enum MoreRoute: Equatable, Sendable {
    case root
    case settings
    case placeholder(MoreFeature)
}
