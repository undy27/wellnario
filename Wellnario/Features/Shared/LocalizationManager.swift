import Foundation
import UIKit

enum AppLanguage: String, CaseIterable, Sendable {
    case spanish = "es"
    case english = "en"

    var localeIdentifier: String {
        switch self {
        case .spanish: "es_ES"
        case .english: "en_US"
        }
    }

    /// Language names are intentionally autonyms so the chooser remains usable
    /// even when the active language is unfamiliar.
    var nativeDisplayName: String {
        switch self {
        case .spanish: "Español"
        case .english: "English"
        }
    }
}

/// Resolves strings from an explicitly selected language bundle at runtime.
/// Changing `language` is persisted and broadcasts `didChangeNotification`; no
/// application restart or AppleLanguages mutation is required.
@MainActor
final class LocalizationManager {
    static let shared = LocalizationManager()
    static let didChangeNotification = Notification.Name("wellnario.localization.didChange")
    static let languageUserInfoKey = "language"

    private static let preferenceKey = "wellnario.preferredLanguage"

    private(set) var language: AppLanguage

    var locale: Locale { Locale(identifier: language.localeIdentifier) }

    private init(defaults: UserDefaults = .standard) {
        if let stored = defaults.string(forKey: Self.preferenceKey),
           let storedLanguage = AppLanguage(rawValue: stored) {
            language = storedLanguage
        } else {
            language = Self.systemLanguage()
        }
    }

    func setLanguage(_ language: AppLanguage) {
        guard self.language != language else { return }
        self.language = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.preferenceKey)
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: self,
            userInfo: [Self.languageUserInfoKey: language.rawValue]
        )
        UIAccessibility.post(
            notification: .announcement,
            argument: localized("settings.language.changed", arguments: [language.nativeDisplayName])
        )
    }

    func setLanguage(code: String) {
        guard let language = AppLanguage(rawValue: code) else { return }
        setLanguage(language)
    }

    func resetToSystemLanguage() {
        UserDefaults.standard.removeObject(forKey: Self.preferenceKey)
        setLanguage(Self.systemLanguage())
    }

    func localized(_ key: String, _ arguments: CVarArg...) -> String {
        localized(key, arguments: arguments)
    }

    func localized(_ key: String, arguments: [CVarArg]) -> String {
        let format = languageBundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: arguments)
    }

    private var languageBundle: Bundle {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    private static func systemLanguage() -> AppLanguage {
        let preferredCode = Locale.preferredLanguages.first
            .flatMap { Locale(identifier: $0).language.languageCode?.identifier }
        return AppLanguage(rawValue: preferredCode ?? "") ?? .spanish
    }
}

/// Typed access to the most frequently used strings. Less common copy can use
/// `L10n.text("key")` while still participating in runtime language changes.
@MainActor
enum L10n {
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        LocalizationManager.shared.localized(key, arguments: arguments)
    }

    @MainActor enum Common {
        static var add: String { text("common.add") }
        static var save: String { text("common.save") }
        static var edit: String { text("common.edit") }
        static var delete: String { text("common.delete") }
        static var cancel: String { text("common.cancel") }
        static var done: String { text("common.done") }
        static var close: String { text("common.close") }
        static var retry: String { text("common.retry") }
        static var search: String { text("common.search") }
        static var clear: String { text("common.clear") }
        static var next: String { text("common.next") }
        static var back: String { text("common.back") }
        static var continueTitle: String { text("common.continue") }
        static var confirm: String { text("common.confirm") }
        static var optional: String { text("common.optional") }
        static var required: String { text("common.required") }
        static var loading: String { text("common.loading") }
        static var success: String { text("common.success") }
        static var warning: String { text("common.warning") }
        static var error: String { text("common.error") }
        static var information: String { text("common.information") }
        static var status: String { text("common.status") }
        static var undo: String { text("common.undo") }
        static var noDate: String { text("common.no_date") }
        static var notes: String { text("common.notes") }
        static var targetProgress: String { text("common.target_progress") }
        static var dailyProgress: String { text("common.daily_progress") }
    }

    @MainActor enum Tab {
        static var today: String { text("tab.today") }
        static var supplements: String { text("tab.supplements") }
        static var sleep: String { text("tab.sleep") }
        static var health: String { text("tab.health") }
        static var fitness: String { text("tab.fitness") }
        static var trends: String { text("trends.title") }
    }

    @MainActor enum Today {
        static var suggestion: String { text("today.suggestion") }
        static var nextDose: String { text("today.next_dose") }
        static var adherence: String { text("today.adherence") }
        static var actives: String { text("today.actives") }
        static var inventory: String { text("today.inventory") }
        static var expiry: String { text("today.expiry") }
        static var summary: String { text("today.summary") }
        static var intakeByActive: String { text("today.intake_by_active") }
        static var logIntake: String { text("today.log_intake") }
        static var addFirstSupplement: String { text("today.add_first_supplement") }
        static var emptyTitle: String { text("today.empty.title") }
        static var emptyMessage: String { text("today.empty.message") }
    }

    @MainActor enum Supplements {
        static var title: String { text("supplements.title") }
        static var products: String { text("supplements.segment.products") }
        static var inventory: String { text("supplements.segment.inventory") }
        static var actives: String { text("supplements.segment.actives") }
        static var addSupplement: String { text("supplements.add") }
        static var composition: String { text("supplements.composition") }
        static var recentIntakes: String { text("supplements.recent_intakes") }
        static var noProductsTitle: String { text("supplements.empty.title") }
        static var noProductsMessage: String { text("supplements.empty.message") }
    }

    @MainActor enum Inventory {
        static var title: String { text("inventory.title") }
        static var add: String { text("inventory.add") }
        static var batch: String { text("inventory.batch") }
        static var expiryDate: String { text("inventory.expiry_date") }
        static var noItemsTitle: String { text("inventory.empty.title") }
        static var noItemsMessage: String { text("inventory.empty.message") }
    }

    @MainActor enum Actives {
        static var title: String { text("actives.title") }
        static var add: String { text("actives.add") }
        static var target: String { text("actives.target") }
        static var targetMinimum: String { text("actives.target_minimum") }
        static var targetMaximum: String { text("actives.target_maximum") }
        static var containedIn: String { text("actives.contained_in") }
        static var noItemsTitle: String { text("actives.empty.title") }
        static var noItemsMessage: String { text("actives.empty.message") }
    }

    @MainActor enum Diary {
        static var title: String { text("diary.title") }
        static var duplicate: String { text("diary.duplicate") }
        static var noEntriesTitle: String { text("diary.empty.title") }
        static var noEntriesMessage: String { text("diary.empty.message") }
    }

    @MainActor enum Trends {
        static var title: String { text("trends.title") }
        static var sevenDays: String { text("trends.period.7d") }
        static var thirtyDays: String { text("trends.period.30d") }
        static var oneYear: String { text("trends.period.1y") }
        static var customRange: String { text("trends.period.custom") }
        static var dailyConsumption: String { text("trends.daily_consumption") }
        static var targetBand: String { text("trends.target_band") }
        static var average: String { text("trends.average") }
        static var total: String { text("trends.total") }
        static var daysInTarget: String { text("trends.days_in_target") }
        static var noDataTitle: String { text("trends.empty.title") }
        static var noDataMessage: String { text("trends.empty.message") }
    }

    @MainActor enum More {
        static var title: String { text("more.title") }
        static var subtitle: String { text("more.subtitle") }
        static var comingSoon: String { text("more.coming_soon") }
        static var sleep: String { text("more.sleep") }
        static var sleepDescription: String { text("more.sleep.description") }
        static var biomarkers: String { text("more.biomarkers") }
        static var biomarkersDescription: String { text("more.biomarkers.description") }
        static var biologicalAge: String { text("more.biological_age") }
        static var biologicalAgeDescription: String { text("more.biological_age.description") }
        static var strength: String { text("more.strength") }
        static var strengthDescription: String { text("more.strength.description") }
        static var recovery: String { text("more.recovery") }
        static var recoveryDescription: String { text("more.recovery.description") }
        static var settings: String { text("more.settings") }
        static var availableLater: String { text("placeholder.available_later") }
    }

    @MainActor enum Form {
        static var basics: String { text("form.section.basics") }
        static var details: String { text("form.section.details") }
        static var review: String { text("form.section.review") }
        static var photo: String { text("form.photo") }
        static var choosePhoto: String { text("form.choose_photo") }
        static var name: String { text("form.name") }
        static var brand: String { text("form.brand") }
        static var category: String { text("form.category") }
        static var description: String { text("form.description") }
        static var price: String { text("form.price") }
        static var presentation: String { text("form.presentation") }
        static var active: String { text("form.active") }
        static var activeAmount: String { text("form.active_amount") }
        static var supplementAmount: String { text("form.supplement_amount") }
        static var unit: String { text("form.unit") }
        static var identifier: String { text("form.identifier") }
        static var date: String { text("form.date") }
        static var time: String { text("form.time") }
        static var amountConsumed: String { text("form.amount_consumed") }
        static var activeContribution: String { text("form.active_contribution") }
    }

    @MainActor enum Settings {
        static var title: String { text("settings.title") }
        static var language: String { text("settings.language") }
        static var spanish: String { text("settings.language.spanish") }
        static var english: String { text("settings.language.english") }
        static var languageFooter: String { text("settings.language.footer") }
        static var appearance: String { text("settings.appearance") }
        static var appearanceDark: String { text("settings.appearance.dark") }
        static var appearanceLight: String { text("settings.appearance.light") }
        static var appearanceSystem: String { text("settings.appearance.system") }
        static var appearanceFooter: String { text("settings.appearance.footer") }
        static var about: String { text("settings.about") }
        static var aboutBody: String { text("settings.about.body") }
        static var privacy: String { text("settings.privacy") }
        static var medicalDisclaimer: String { text("settings.medical_disclaimer") }
        static var medicalDisclaimerBody: String { text("settings.medical_disclaimer.body") }
    }

    @MainActor enum Error {
        static var required: String { text("error.required") }
        static var invalidNumber: String { text("error.invalid_number") }
        static var positiveAmount: String { text("error.positive_amount") }
        static var targetRange: String { text("error.target_range") }
        static var futureConsumption: String { text("error.future_consumption") }
        static var saveFailed: String { text("error.save_failed") }
        static var loadFailed: String { text("error.load_failed") }
        static var database: String { text("error.database") }
        static var unknown: String { text("error.unknown") }
    }
}

/// UILabel that refreshes itself after a runtime language change.
final class LocalizedLabel: UILabel {
    var localizationKey: String? {
        didSet { applyLocalization() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        observeLanguageChanges()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        observeLanguageChanges()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func observeLanguageChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyLocalization),
            name: LocalizationManager.didChangeNotification,
            object: nil
        )
    }

    @objc private func applyLocalization() {
        guard let localizationKey else { return }
        text = L10n.text(localizationKey)
    }
}

/// UIButton counterpart to `LocalizedLabel`.
final class LocalizedButton: UIButton {
    var localizationKey: String? {
        didSet { applyLocalization() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        observeLanguageChanges()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        observeLanguageChanges()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func observeLanguageChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyLocalization),
            name: LocalizationManager.didChangeNotification,
            object: nil
        )
    }

    @objc private func applyLocalization() {
        guard let localizationKey else { return }
        setTitle(L10n.text(localizationKey), for: .normal)
        accessibilityLabel = title(for: .normal)
    }
}
