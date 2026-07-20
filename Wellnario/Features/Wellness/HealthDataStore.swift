import Foundation

extension Notification.Name {
    /// Posted after an analysis and its results have been saved or deleted.
    /// Derived health calculations can then refresh immediately.
    static let healthAnalysesDidChange = Notification.Name("wellnarioHealthAnalysesDidChange")
}

enum BiomarkerSampleType: String, CaseIterable, Sendable {
    case blood
    case urine
    case other

    /// `physiological` was the persisted value used before this category was
    /// presented as "Other". Keeping this conversion makes a partially
    /// migrated local database safe to open while the UI uses the clearer
    /// "Physiological" label again.
    static func fromStoredValue(_ value: String) -> BiomarkerSampleType? {
        value == "physiological" ? .other : Self(rawValue: value)
    }

    @MainActor
    var title: String {
        switch self {
        case .blood: L10n.text("health.biomarkers.filter.blood")
        case .urine: L10n.text("health.biomarkers.filter.urine")
        case .other: L10n.text("health.biomarkers.filter.physiological")
        }
    }

    var symbolName: String {
        switch self {
        case .blood: "drop.fill"
        case .urine: "testtube.2"
        case .other: "waveform.path.ecg"
        }
    }
}

struct HealthBiomarker: Identifiable, Equatable, Sendable {
    let id: UUID
    var nameKey: String?
    var customName: String?
    var sampleType: BiomarkerSampleType
    var defaultUnit: String
    var imageKey: String?
    var isSeeded: Bool
    var isFavorite: Bool

    @MainActor
    var name: String {
        if let nameKey { return L10n.text(nameKey) }
        return customName ?? L10n.text("health.biomarkers.unnamed")
    }

    /// Units commonly used by laboratories for this measurement. Custom
    /// biomarkers retain the unit chosen when they were created.
    var typicalLabUnits: [String] {
        let alternatives: [String]
        switch nameKey {
        case "health.biomarker.catalog.hemoglobin": alternatives = ["g/dL", "g/L", "mmol/L"]
        case "health.biomarker.catalog.hematocrit": alternatives = ["%", "L/L"]
        case "health.biomarker.catalog.leukocytes_blood",
             "health.biomarker.catalog.platelets": alternatives = ["10³/µL", "10⁹/L"]
        case "health.biomarker.catalog.glucose_blood",
             "health.biomarker.catalog.glucose_urine": alternatives = ["mg/dL", "mmol/L"]
        case "health.biomarker.catalog.creatinine": alternatives = ["mg/dL", "µmol/L"]
        case "health.biomarker.catalog.cholesterol",
             "health.biomarker.catalog.triglycerides",
             "health.biomarker.catalog.hdl",
             "health.biomarker.catalog.ldl": alternatives = ["mg/dL", "mmol/L"]
        case "health.biomarker.catalog.psa": alternatives = ["ng/mL", "µg/L"]
        case "health.biomarker.catalog.crp": alternatives = ["mg/L", "mg/dL"]
        case "health.biomarker.catalog.esr": alternatives = ["mm/h"]
        case "health.biomarker.catalog.alt": alternatives = ["U/L", "µkat/L"]
        case "health.biomarker.catalog.ggt": alternatives = ["U/L", "µkat/L"]
        case "health.biomarker.catalog.albumin": alternatives = ["g/dL", "g/L"]
        case "health.biomarker.catalog.ferritin": alternatives = ["ng/mL", "µg/L"]
        case "health.biomarker.catalog.cortisol": alternatives = ["µg/dL", "nmol/L"]
        case "health.biomarker.catalog.testosterone_total": alternatives = ["ng/dL", "nmol/L"]
        case "health.biomarker.catalog.vitamin_d": alternatives = ["ng/mL", "nmol/L"]
        case "health.biomarker.catalog.glycated_hemoglobin": alternatives = ["%", "mmol/mol"]
        case "health.biomarker.catalog.tsh": alternatives = ["mIU/L", "µIU/mL"]
        case "health.biomarker.catalog.lymphocyte_percentage": alternatives = ["%"]
        case "health.biomarker.catalog.mcv": alternatives = ["fL"]
        case "health.biomarker.catalog.rdw": alternatives = ["%"]
        case "health.biomarker.catalog.alkaline_phosphatase": alternatives = ["U/L", "µkat/L"]
        case "health.biomarker.catalog.bun": alternatives = ["mg/dL", "mmol/L"]
        case "health.biomarker.catalog.fev1": alternatives = ["mL", "L"]
        case "health.biomarker.catalog.systolic_blood_pressure": alternatives = ["mmHg"]
        case "health.biomarker.catalog.vo2_max": alternatives = ["mL/kg/min"]
        case "health.biomarker.catalog.ph_urine": alternatives = ["pH"]
        case "health.biomarker.catalog.specific_gravity": alternatives = [""]
        case "health.biomarker.catalog.protein_urine": alternatives = ["mg/dL", "mg/L", "g/L"]
        case "health.biomarker.catalog.leukocytes_urine": alternatives = ["/µL", "10⁶/L"]
        default: alternatives = [defaultUnit]
        }
        return ([defaultUnit] + alternatives).reduce(into: []) { units, unit in
            if !units.contains(unit) { units.append(unit) }
        }
    }
}

struct HealthBiomarkerDraft: Sendable {
    var name: String
    var sampleType: BiomarkerSampleType
    var defaultUnit: String
}

struct LabResult: Identifiable, Equatable, Sendable {
    let id: UUID
    let biomarkerID: UUID
    var value: Decimal
    var unit: String
    var referenceLower: Decimal?
    var referenceUpper: Decimal?
    var notes: String? = nil

    var isOutsideReferenceRange: Bool {
        if let referenceLower, value < referenceLower {
            return true
        }
        if let referenceUpper, value > referenceUpper {
            return true
        }
        return false
    }
}

struct LabAnalysis: Identifiable, Equatable, Sendable {
    let id: UUID
    var collectedAt: Date
    var laboratory: String?
    var notes: String?
    var results: [LabResult]
    /// Private local copy of the PDF that was used to import this analysis.
    /// The document remains available after the security-scoped picker URL
    /// has been released.
    var importedPDFPath: String? = nil
    var importedPDFName: String? = nil

    var outOfRangeResultCount: Int {
        results.count(where: \.isOutsideReferenceRange)
    }
}

struct BiomarkerMeasurement: Identifiable, Equatable, Sendable {
    let analysisID: UUID
    let result: LabResult
    let collectedAt: Date
    let laboratory: String?

    var id: UUID { result.id }
}

@MainActor
final class HealthDataStore {
    private struct Seed {
        let id: UUID
        let nameKey: String
        let type: BiomarkerSampleType
        let unit: String
        let imageKey: String
    }

    private let database: SQLiteDatabase
    private let userID: UUID

    init(
        databaseURL: URL,
        userID: UUID = WellnarioRepository.defaultUserID
    ) throws {
        database = try SQLiteDatabase(url: databaseURL)
        self.userID = userID
        try SchemaMigrator.migrate(database)
        let now = Date().timeIntervalSince1970
        try database.execute(
            """
            INSERT OR IGNORE INTO app_users (id, created_at, updated_at)
            VALUES (?, ?, ?);
            """,
            bindings: [.text(userID.uuidString), .real(now), .real(now)]
        )
        try seedCatalog()
    }

    convenience init() {
        try! self.init(databaseURL: URL(fileURLWithPath: ":memory:"))
    }

    func biomarkers(includeArchived: Bool = false) -> [HealthBiomarker] {
        (try? fetchBiomarkers(includeArchived: includeArchived)) ?? []
    }

    func createBiomarker(_ draft: HealthBiomarkerDraft) throws -> HealthBiomarker {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = draft.defaultUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw RepositoryError.validation(L10n.text("health.biomarkers.editor.name.required"))
        }
        let id = UUID()
        let now = Date().timeIntervalSince1970
        try database.execute(
            """
            INSERT INTO biomarkers (
                id, custom_name, sample_type, default_unit, is_seeded, created_at, updated_at
            ) VALUES (?, ?, ?, ?, 0, ?, ?);
            """,
            bindings: [
                .text(id.uuidString),
                .text(name),
                .text(draft.sampleType.rawValue),
                .text(unit),
                .real(now),
                .real(now)
            ]
        )
        return biomarkers().first(where: { $0.id == id })!
    }

    func updateBiomarker(id: UUID, with draft: HealthBiomarkerDraft) throws {
        guard let biomarker = biomarkers(includeArchived: true).first(where: { $0.id == id }) else {
            throw RepositoryError.notFound(entity: "Biomarker", id: id)
        }
        guard !biomarker.isSeeded else { throw RepositoryError.readOnlySeed }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = draft.defaultUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw RepositoryError.validation(L10n.text("health.biomarkers.editor.name.required"))
        }
        try database.execute(
            """
            UPDATE biomarkers
            SET custom_name = ?, sample_type = ?, default_unit = ?, updated_at = ?
            WHERE id = ?;
            """,
            bindings: [
                .text(name),
                .text(draft.sampleType.rawValue),
                .text(unit),
                .real(Date().timeIntervalSince1970),
                .text(id.uuidString)
            ]
        )
    }

    func archiveBiomarker(id: UUID) throws {
        guard let biomarker = biomarkers().first(where: { $0.id == id }), !biomarker.isSeeded else {
            throw RepositoryError.readOnlySeed
        }
        try database.execute(
            "UPDATE biomarkers SET archived_at = ?, updated_at = ? WHERE id = ?;",
            bindings: [
                .real(Date().timeIntervalSince1970),
                .real(Date().timeIntervalSince1970),
                .text(id.uuidString)
            ]
        )
    }

    func setFavorite(_ isFavorite: Bool, biomarkerID: UUID) throws {
        if isFavorite {
            try database.execute(
                """
                INSERT OR IGNORE INTO biomarker_favorites (
                    user_id, biomarker_id, created_at
                ) VALUES (?, ?, ?);
                """,
                bindings: [
                    .text(userID.uuidString),
                    .text(biomarkerID.uuidString),
                    .real(Date().timeIntervalSince1970)
                ]
            )
        } else {
            try database.execute(
                "DELETE FROM biomarker_favorites WHERE user_id = ? AND biomarker_id = ?;",
                bindings: [.text(userID.uuidString), .text(biomarkerID.uuidString)]
            )
        }
    }

    func analyses() -> [LabAnalysis] {
        (try? fetchAnalyses()) ?? []
    }

    func saveAnalysis(_ analysis: LabAnalysis) throws {
        guard !analysis.results.isEmpty else {
            throw RepositoryError.validation(L10n.text("health.analytics.editor.results.required"))
        }
        let now = Date().timeIntervalSince1970
        try database.transaction {
            try database.execute(
                """
                INSERT INTO lab_analyses (
                    id, user_id, collected_at, laboratory, notes,
                    imported_pdf_path, imported_pdf_name, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    collected_at = excluded.collected_at,
                    laboratory = excluded.laboratory,
                    notes = excluded.notes,
                    imported_pdf_path = excluded.imported_pdf_path,
                    imported_pdf_name = excluded.imported_pdf_name,
                    updated_at = excluded.updated_at;
                """,
                bindings: [
                    .text(analysis.id.uuidString),
                    .text(userID.uuidString),
                    .real(analysis.collectedAt.timeIntervalSince1970),
                    analysis.laboratory.flatMap(Self.nonEmpty).map(SQLiteBinding.text) ?? .null,
                    analysis.notes.flatMap(Self.nonEmpty).map(SQLiteBinding.text) ?? .null,
                    analysis.importedPDFPath.flatMap(Self.nonEmpty).map(SQLiteBinding.text) ?? .null,
                    analysis.importedPDFName.flatMap(Self.nonEmpty).map(SQLiteBinding.text) ?? .null,
                    .real(now),
                    .real(now)
                ]
            )
            try database.execute(
                "DELETE FROM lab_results WHERE analysis_id = ?;",
                bindings: [.text(analysis.id.uuidString)]
            )
            for result in analysis.results {
                try database.execute(
                    """
                    INSERT INTO lab_results (
                        id, analysis_id, biomarker_id, value, unit,
                        reference_lower, reference_upper, notes, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """,
                    bindings: [
                        .text(result.id.uuidString),
                        .text(analysis.id.uuidString),
                        .text(result.biomarkerID.uuidString),
                        .text(try DecimalCodec.encode(result.value)),
                        .text(result.unit),
                        try result.referenceLower.map { .text(try DecimalCodec.encode($0)) } ?? .null,
                        try result.referenceUpper.map { .text(try DecimalCodec.encode($0)) } ?? .null,
                        result.notes.flatMap(Self.nonEmpty).map(SQLiteBinding.text) ?? .null,
                        .real(now),
                        .real(now)
                    ]
                )
            }
        }
        NotificationCenter.default.post(name: .healthAnalysesDidChange, object: self)
    }

    func deleteAnalysis(id: UUID) throws {
        try database.execute(
            "DELETE FROM lab_analyses WHERE id = ? AND user_id = ?;",
            bindings: [.text(id.uuidString), .text(userID.uuidString)]
        )
        NotificationCenter.default.post(name: .healthAnalysesDidChange, object: self)
    }

    func measurements(for biomarkerID: UUID) -> [BiomarkerMeasurement] {
        analyses().compactMap { analysis in
            analysis.results.first(where: { $0.biomarkerID == biomarkerID }).map {
                BiomarkerMeasurement(
                    analysisID: analysis.id,
                    result: $0,
                    collectedAt: analysis.collectedAt,
                    laboratory: analysis.laboratory
                )
            }
        }
        .sorted { $0.collectedAt > $1.collectedAt }
    }

    private func fetchBiomarkers(includeArchived: Bool) throws -> [HealthBiomarker] {
        let rows = try database.query(
            """
            SELECT b.id, b.name_key, b.custom_name, b.sample_type, b.default_unit,
                   b.image_key, b.is_seeded,
                   CASE WHEN f.biomarker_id IS NULL THEN 0 ELSE 1 END AS is_favorite
            FROM biomarkers b
            LEFT JOIN biomarker_favorites f
              ON f.biomarker_id = b.id AND f.user_id = ?
            WHERE (? = 1 OR b.archived_at IS NULL)
            ORDER BY b.sample_type, COALESCE(b.name_key, b.custom_name);
            """,
            bindings: [.text(userID.uuidString), .integer(includeArchived ? 1 : 0)]
        )
        return try rows.compactMap { row in
            guard let id = UUID(uuidString: try row.string("id")),
                  let type = BiomarkerSampleType.fromStoredValue(try row.string("sample_type")) else {
                return nil
            }
            return HealthBiomarker(
                id: id,
                nameKey: try row.optionalString("name_key"),
                customName: try row.optionalString("custom_name"),
                sampleType: type,
                defaultUnit: try row.string("default_unit"),
                imageKey: try row.optionalString("image_key"),
                isSeeded: try row.integer("is_seeded") == 1,
                isFavorite: try row.integer("is_favorite") == 1
            )
        }
    }

    private func fetchAnalyses() throws -> [LabAnalysis] {
        let rows = try database.query(
            """
            SELECT id, collected_at, laboratory, notes, imported_pdf_path, imported_pdf_name
            FROM lab_analyses
            WHERE user_id = ?
            ORDER BY collected_at DESC, created_at DESC;
            """,
            bindings: [.text(userID.uuidString)]
        )
        return try rows.compactMap { row -> LabAnalysis? in
            guard let id = UUID(uuidString: try row.string("id")) else { return nil }
            let resultRows = try database.query(
                """
                SELECT id, biomarker_id, value, unit, reference_lower, reference_upper, notes
                FROM lab_results
                WHERE analysis_id = ?
                ORDER BY created_at;
                """,
                bindings: [.text(id.uuidString)]
            )
            let results = try resultRows.compactMap { resultRow -> LabResult? in
                guard let resultID = UUID(uuidString: try resultRow.string("id")),
                      let biomarkerID = UUID(uuidString: try resultRow.string("biomarker_id")) else {
                    return nil
                }
                return LabResult(
                    id: resultID,
                    biomarkerID: biomarkerID,
                    value: try DecimalCodec.decode(resultRow.string("value")),
                    unit: try resultRow.string("unit"),
                    referenceLower: try resultRow.optionalString("reference_lower").map(DecimalCodec.decode),
                    referenceUpper: try resultRow.optionalString("reference_upper").map(DecimalCodec.decode),
                    notes: try resultRow.optionalString("notes")
                )
            }
            return LabAnalysis(
                id: id,
                collectedAt: Date(timeIntervalSince1970: try row.double("collected_at")),
                laboratory: try row.optionalString("laboratory"),
                notes: try row.optionalString("notes"),
                results: results,
                importedPDFPath: try row.optionalString("imported_pdf_path"),
                importedPDFName: try row.optionalString("imported_pdf_name")
            )
        }
    }

    private func seedCatalog() throws {
        let now = Date().timeIntervalSince1970
        for seed in Self.seeds {
            try database.execute(
                """
                INSERT OR IGNORE INTO biomarkers (
                    id, name_key, sample_type, default_unit, image_key,
                    is_seeded, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, 1, ?, ?);
                """,
                bindings: [
                    .text(seed.id.uuidString),
                    .text(seed.nameKey),
                    .text(seed.type.rawValue),
                    .text(seed.unit),
                    .text(seed.imageKey),
                    .real(now),
                    .real(now)
                ]
            )
        }
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let seeds: [Seed] = [
        Seed(id: seedID(1), nameKey: "health.biomarker.catalog.hemoglobin", type: .blood, unit: "g/dL", imageKey: "biomarker_hemoglobin"),
        Seed(id: seedID(2), nameKey: "health.biomarker.catalog.hematocrit", type: .blood, unit: "%", imageKey: "biomarker_hematocrit"),
        Seed(id: seedID(3), nameKey: "health.biomarker.catalog.leukocytes_blood", type: .blood, unit: "10³/µL", imageKey: "biomarker_leukocytes_blood"),
        Seed(id: seedID(4), nameKey: "health.biomarker.catalog.platelets", type: .blood, unit: "10³/µL", imageKey: "biomarker_platelets"),
        Seed(id: seedID(5), nameKey: "health.biomarker.catalog.glucose_blood", type: .blood, unit: "mg/dL", imageKey: "biomarker_glucose_blood"),
        Seed(id: seedID(6), nameKey: "health.biomarker.catalog.creatinine", type: .blood, unit: "mg/dL", imageKey: "biomarker_creatinine"),
        Seed(id: seedID(7), nameKey: "health.biomarker.catalog.cholesterol", type: .blood, unit: "mg/dL", imageKey: "biomarker_cholesterol"),
        Seed(id: seedID(8), nameKey: "health.biomarker.catalog.triglycerides", type: .blood, unit: "mg/dL", imageKey: "biomarker_triglycerides"),
        Seed(id: seedID(9), nameKey: "health.biomarker.catalog.alt", type: .blood, unit: "U/L", imageKey: "biomarker_alt"),
        Seed(id: seedID(10), nameKey: "health.biomarker.catalog.tsh", type: .blood, unit: "mIU/L", imageKey: "biomarker_tsh"),
        Seed(id: seedID(11), nameKey: "health.biomarker.catalog.ph_urine", type: .urine, unit: "pH", imageKey: "biomarker_ph_urine"),
        Seed(id: seedID(12), nameKey: "health.biomarker.catalog.specific_gravity", type: .urine, unit: "", imageKey: "biomarker_specific_gravity"),
        Seed(id: seedID(13), nameKey: "health.biomarker.catalog.protein_urine", type: .urine, unit: "mg/dL", imageKey: "biomarker_protein_urine"),
        Seed(id: seedID(14), nameKey: "health.biomarker.catalog.glucose_urine", type: .urine, unit: "mg/dL", imageKey: "biomarker_glucose_urine"),
        Seed(id: seedID(15), nameKey: "health.biomarker.catalog.leukocytes_urine", type: .urine, unit: "/µL", imageKey: "biomarker_leukocytes_urine"),
        Seed(id: seedID(16), nameKey: "health.biomarker.catalog.hdl", type: .blood, unit: "mg/dL", imageKey: "biomarker_hdl"),
        Seed(id: seedID(17), nameKey: "health.biomarker.catalog.ldl", type: .blood, unit: "mg/dL", imageKey: "biomarker_ldl"),
        Seed(id: seedID(18), nameKey: "health.biomarker.catalog.psa", type: .blood, unit: "ng/mL", imageKey: "biomarker_psa"),
        Seed(id: seedID(19), nameKey: "health.biomarker.catalog.crp", type: .blood, unit: "mg/L", imageKey: "biomarker_crp"),
        Seed(id: seedID(20), nameKey: "health.biomarker.catalog.esr", type: .blood, unit: "mm/h", imageKey: "biomarker_esr"),
        Seed(id: seedID(21), nameKey: "health.biomarker.catalog.ggt", type: .blood, unit: "U/L", imageKey: "biomarker_ggt"),
        Seed(id: seedID(22), nameKey: "health.biomarker.catalog.albumin", type: .blood, unit: "g/dL", imageKey: "biomarker_albumin"),
        Seed(id: seedID(23), nameKey: "health.biomarker.catalog.ferritin", type: .blood, unit: "ng/mL", imageKey: "biomarker_ferritin"),
        Seed(id: seedID(24), nameKey: "health.biomarker.catalog.cortisol", type: .blood, unit: "µg/dL", imageKey: "biomarker_cortisol"),
        Seed(id: seedID(25), nameKey: "health.biomarker.catalog.testosterone_total", type: .blood, unit: "ng/dL", imageKey: "biomarker_testosterone_total"),
        Seed(id: seedID(26), nameKey: "health.biomarker.catalog.vitamin_d", type: .blood, unit: "ng/mL", imageKey: "biomarker_vitamin_d"),
        Seed(id: seedID(27), nameKey: "health.biomarker.catalog.glycated_hemoglobin", type: .blood, unit: "%", imageKey: "biomarker_glycated_hemoglobin"),
        Seed(id: seedID(28), nameKey: "health.biomarker.catalog.lymphocyte_percentage", type: .blood, unit: "%", imageKey: "biomarker_lymphocytes"),
        Seed(id: seedID(29), nameKey: "health.biomarker.catalog.mcv", type: .blood, unit: "fL", imageKey: "biomarker_mcv"),
        Seed(id: seedID(30), nameKey: "health.biomarker.catalog.rdw", type: .blood, unit: "%", imageKey: "biomarker_rdw"),
        Seed(id: seedID(31), nameKey: "health.biomarker.catalog.alkaline_phosphatase", type: .blood, unit: "U/L", imageKey: "biomarker_alkaline_phosphatase"),
        Seed(id: seedID(32), nameKey: "health.biomarker.catalog.bun", type: .blood, unit: "mg/dL", imageKey: "biomarker_bun"),
        Seed(id: seedID(33), nameKey: "health.biomarker.catalog.fev1", type: .other, unit: "mL", imageKey: "biomarker_fev1"),
        Seed(id: seedID(34), nameKey: "health.biomarker.catalog.systolic_blood_pressure", type: .other, unit: "mmHg", imageKey: "biomarker_systolic_blood_pressure"),
        Seed(id: seedID(35), nameKey: "health.biomarker.catalog.vo2_max", type: .other, unit: "mL/kg/min", imageKey: "biomarker_vo2_max")
    ]

    private static func seedID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "50000000-0000-4000-8000-%012d", value))!
    }
}
