import Foundation

public enum CatalogLanguage: String, Codable, CaseIterable, Sendable {
    case spanish = "es"
    case english = "en"

    public init(languageCode: String) {
        self = languageCode.lowercased().hasPrefix("en") ? .english : .spanish
    }
}

public enum ActiveCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case sleep
    case physicalPerformance = "physical_performance"
    case energy
    case stress
    case cardiovascular
    case cognition
    case immunity
    case bonesAndJoints = "bones_joints"
    case aesthetics
    case antioxidant
    case metabolicHealth = "metabolic_health"
    case healthyAging = "healthy_aging"
    case vision

    public func localizedName(language: CatalogLanguage) -> String {
        CatalogLocalization.text(for: "active.category.\(rawValue)", language: language)
    }
}

/// Seed records persist keys, never translated labels. This small fallback
/// catalog keeps seeded data bilingual even before UI localization resources
/// are loaded; the UI can use the same keys in its strings catalogs.
public enum CatalogLocalization {
    public static func text(for key: String, language: CatalogLanguage) -> String {
        translations[key]?[language] ?? key
    }

    private static let translations: [String: [CatalogLanguage: String]] = [
        "active.vitamin_c.name": [.spanish: "Vitamina C", .english: "Vitamin C"],
        "active.vitamin_d.name": [.spanish: "Vitamina D", .english: "Vitamin D"],
        "active.vitamin_b12.name": [.spanish: "Vitamina B12", .english: "Vitamin B12"],
        "active.magnesium.name": [.spanish: "Magnesio", .english: "Magnesium"],
        "active.omega_3.name": [.spanish: "Omega-3", .english: "Omega-3"],
        "active.caffeine.name": [.spanish: "Cafeína", .english: "Caffeine"],
        "active.zinc.name": [.spanish: "Zinc", .english: "Zinc"],
        "active.iron.name": [.spanish: "Hierro", .english: "Iron"],
        "active.calcium.name": [.spanish: "Calcio", .english: "Calcium"],
        "active.creatine.name": [.spanish: "Creatina", .english: "Creatine"],
        "active.melatonin.name": [.spanish: "Melatonina", .english: "Melatonin"],
        "active.ashwagandha.name": [.spanish: "Ashwagandha", .english: "Ashwagandha"],
        "active.astaxanthin.name": [.spanish: "Astaxantina", .english: "Astaxanthin"],
        "active.berberine.name": [.spanish: "Berberina", .english: "Berberine"],
        "active.coenzyme_q10.name": [.spanish: "Coenzima Q10", .english: "Coenzyme Q10"],
        "active.hydrolyzed_collagen.name": [.spanish: "Colágeno hidrolizado", .english: "Hydrolyzed collagen"],
        "active.spermidine.name": [.spanish: "Espermidina", .english: "Spermidine"],
        "active.l_arginine.name": [.spanish: "L-arginina", .english: "L-arginine"],
        "active.glycine.name": [.spanish: "Glicina", .english: "Glycine"],
        "active.taurine.name": [.spanish: "Taurina", .english: "Taurine"],
        "active.resveratrol.name": [.spanish: "Resveratrol", .english: "Resveratrol"],
        "active.nicotinamide_riboside.name": [.spanish: "Nicotinamida ribósido", .english: "Nicotinamide riboside"],
        "active.quercetin.name": [.spanish: "Quercetina", .english: "Quercetin"],
        "active.lutein.name": [.spanish: "Luteína", .english: "Lutein"],
        "active.sulforaphane.name": [.spanish: "Sulforafano", .english: "Sulforaphane"],
        "active.category.sleep": [.spanish: "Sueño", .english: "Sleep"],
        "active.category.physical_performance": [.spanish: "Rendimiento físico", .english: "Physical performance"],
        "active.category.energy": [.spanish: "Energía", .english: "Energy"],
        "active.category.stress": [.spanish: "Estrés", .english: "Stress"],
        "active.category.cardiovascular": [.spanish: "Cardiovascular", .english: "Cardiovascular"],
        "active.category.cognition": [.spanish: "Cognición", .english: "Cognition"],
        "active.category.immunity": [.spanish: "Inmunidad", .english: "Immunity"],
        "active.category.bones_joints": [.spanish: "Huesos y articulaciones", .english: "Bones and joints"],
        "active.category.aesthetics": [.spanish: "Estética", .english: "Aesthetics"],
        "active.category.antioxidant": [.spanish: "Antioxidante", .english: "Antioxidant"],
        "active.category.metabolic_health": [.spanish: "Salud metabólica", .english: "Metabolic health"],
        "active.category.healthy_aging": [.spanish: "Envejecimiento saludable", .english: "Healthy aging"],
        "active.category.vision": [.spanish: "Visión", .english: "Vision"],
        "active.vitamin_c.description": [
            .spanish: "Vitamina hidrosoluble con función antioxidante.",
            .english: "Water-soluble vitamin with antioxidant activity."
        ],
        "active.vitamin_d.description": [
            .spanish: "Vitamina liposoluble relacionada con la salud ósea.",
            .english: "Fat-soluble vitamin associated with bone health."
        ],
        "active.vitamin_b12.description": [
            .spanish: "Vitamina relacionada con el metabolismo y el sistema nervioso.",
            .english: "Vitamin associated with metabolism and the nervous system."
        ],
        "active.magnesium.description": [
            .spanish: "Mineral presente en numerosos procesos celulares.",
            .english: "Mineral involved in many cellular processes."
        ],
        "active.omega_3.description": [
            .spanish: "Familia de ácidos grasos poliinsaturados.",
            .english: "Family of polyunsaturated fatty acids."
        ],
        "active.caffeine.description": [
            .spanish: "Compuesto estimulante presente en café, té y suplementos.",
            .english: "Stimulant compound found in coffee, tea, and supplements."
        ],
        "active.zinc.description": [
            .spanish: "Mineral esencial presente en numerosos tejidos.",
            .english: "Essential mineral found throughout the body."
        ],
        "active.iron.description": [
            .spanish: "Mineral que forma parte de proteínas transportadoras de oxígeno.",
            .english: "Mineral found in oxygen-carrying proteins."
        ],
        "active.calcium.description": [
            .spanish: "Mineral abundante en huesos y dientes.",
            .english: "Mineral abundant in bones and teeth."
        ],
        "active.creatine.description": [
            .spanish: "Compuesto relacionado con la disponibilidad rápida de energía muscular.",
            .english: "Compound associated with rapid energy availability in muscle."
        ],
        "active.melatonin.description": [
            .spanish: "Hormona implicada en la regulación del ciclo sueño-vigilia.",
            .english: "Hormone involved in regulating the sleep-wake cycle."
        ],
        "active.ashwagandha.description": [
            .spanish: "Extracto botánico de Withania somnifera utilizado en suplementos.",
            .english: "Botanical extract from Withania somnifera used in supplements."
        ],
        "active.astaxanthin.description": [
            .spanish: "Carotenoide rojizo presente en microalgas y organismos marinos.",
            .english: "Red carotenoid found in microalgae and marine organisms."
        ],
        "active.berberine.description": [
            .spanish: "Alcaloide vegetal presente en plantas del género Berberis.",
            .english: "Plant alkaloid found in species of the Berberis genus."
        ],
        "active.coenzyme_q10.description": [
            .spanish: "Coenzima implicada en el transporte electrónico y la energía celular.",
            .english: "Coenzyme involved in electron transport and cellular energy."
        ],
        "active.hydrolyzed_collagen.description": [
            .spanish: "Péptidos proteicos obtenidos mediante la hidrólisis del colágeno.",
            .english: "Protein peptides produced by hydrolyzing collagen."
        ],
        "active.spermidine.description": [
            .spanish: "Poliamina presente de forma natural en alimentos y células.",
            .english: "Polyamine naturally present in foods and cells."
        ],
        "active.l_arginine.description": [
            .spanish: "Aminoácido que actúa como precursor del óxido nítrico.",
            .english: "Amino acid that acts as a precursor to nitric oxide."
        ],
        "active.glycine.description": [
            .spanish: "Aminoácido sencillo que forma parte de proteínas como el colágeno.",
            .english: "Simple amino acid found in proteins such as collagen."
        ],
        "active.taurine.description": [
            .spanish: "Compuesto azufrado presente de forma natural en numerosos tejidos.",
            .english: "Sulfur-containing compound naturally present in many tissues."
        ],
        "active.resveratrol.description": [
            .spanish: "Polifenol presente en la piel de la uva y otras plantas.",
            .english: "Polyphenol found in grape skins and other plants."
        ],
        "active.nicotinamide_riboside.description": [
            .spanish: "Forma de vitamina B3 que actúa como precursora de NAD+.",
            .english: "Form of vitamin B3 that acts as a precursor to NAD+."
        ],
        "active.quercetin.description": [
            .spanish: "Flavonoide presente en numerosos alimentos de origen vegetal.",
            .english: "Flavonoid found in many plant-based foods."
        ],
        "active.lutein.description": [
            .spanish: "Carotenoide presente en vegetales y en la mácula del ojo.",
            .english: "Carotenoid found in vegetables and in the eye's macula."
        ],
        "active.sulforaphane.description": [
            .spanish: "Isotiocianato procedente de verduras crucíferas y brotes de brócoli.",
            .english: "Isothiocyanate derived from cruciferous vegetables and broccoli sprouts."
        ],
        "presentation.capsule.name": [.spanish: "Cápsulas", .english: "Capsules"],
        "presentation.tablet.name": [.spanish: "Comprimidos", .english: "Tablets"],
        "presentation.powder.name": [.spanish: "Polvo", .english: "Powder"],
        "presentation.liquid.name": [.spanish: "Líquido", .english: "Liquid"],
        "presentation.drops.name": [.spanish: "Gotas", .english: "Drops"],
        "presentation.gummy.name": [.spanish: "Gominolas", .english: "Gummies"],
        "presentation.sachet.name": [.spanish: "Sobres", .english: "Sachets"],
        "presentation.scoop.name": [.spanish: "Cacitos", .english: "Scoops"]
    ]
}

public struct ActiveTarget: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let activeID: UUID
    public let lowerBound: Decimal
    public let upperBound: Decimal
    public let unit: DoseUnit
    public let effectiveFrom: LocalDay
    public let effectiveThrough: LocalDay?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        activeID: UUID,
        lowerBound: Decimal,
        upperBound: Decimal,
        unit: DoseUnit,
        effectiveFrom: LocalDay,
        effectiveThrough: LocalDay?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.activeID = activeID
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.unit = unit
        self.effectiveFrom = effectiveFrom
        self.effectiveThrough = effectiveThrough
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Active: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let nameKey: String?
    public let customName: String?
    public let descriptionKey: String?
    public let customDescription: String?
    public let baseUnit: DoseUnit
    public let proposedDailyMale: Decimal?
    public let proposedDailyFemale: Decimal?
    public let imageKey: String?
    public let categories: [ActiveCategory]
    public let isSeeded: Bool
    public let currentTarget: ActiveTarget?
    public let createdAt: Date
    public let updatedAt: Date
    public let archivedAt: Date?

    public init(
        id: UUID,
        nameKey: String?,
        customName: String?,
        descriptionKey: String?,
        customDescription: String?,
        baseUnit: DoseUnit,
        proposedDailyMale: Decimal?,
        proposedDailyFemale: Decimal?,
        imageKey: String?,
        categories: [ActiveCategory],
        isSeeded: Bool,
        currentTarget: ActiveTarget?,
        createdAt: Date,
        updatedAt: Date,
        archivedAt: Date?
    ) {
        self.id = id
        self.nameKey = nameKey
        self.customName = customName
        self.descriptionKey = descriptionKey
        self.customDescription = customDescription
        self.baseUnit = baseUnit
        self.proposedDailyMale = proposedDailyMale
        self.proposedDailyFemale = proposedDailyFemale
        self.imageKey = imageKey
        self.categories = categories
        self.isSeeded = isSeeded
        self.currentTarget = currentTarget
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
    }

    public var isArchived: Bool { archivedAt != nil }

    public func localizedName(language: CatalogLanguage) -> String {
        if let customName { return customName }
        return nameKey.map { CatalogLocalization.text(for: $0, language: language) } ?? ""
    }

    public func localizedDescription(language: CatalogLanguage) -> String? {
        if let customDescription, !customDescription.isEmpty { return customDescription }
        return descriptionKey.map { CatalogLocalization.text(for: $0, language: language) }
    }
}

public struct ActiveDraft: Hashable, Sendable {
    public var name: String
    public var description: String?
    public var baseUnit: DoseUnit
    public var proposedDailyMale: Decimal?
    public var proposedDailyFemale: Decimal?
    public var imageKey: String?
    public var categories: [ActiveCategory]

    public init(
        name: String,
        description: String? = nil,
        baseUnit: DoseUnit,
        proposedDailyMale: Decimal? = nil,
        proposedDailyFemale: Decimal? = nil,
        imageKey: String? = nil,
        categories: [ActiveCategory] = []
    ) {
        self.name = name
        self.description = description
        self.baseUnit = baseUnit
        self.proposedDailyMale = proposedDailyMale
        self.proposedDailyFemale = proposedDailyFemale
        self.imageKey = imageKey
        self.categories = categories
    }
}
