import Foundation

enum SeedData {
    static let defaultUserID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    struct ActiveSeed {
        let id: UUID
        let slug: String
        let unit: DoseUnit
        let proposedMale: Decimal?
        let proposedFemale: Decimal?
        let categories: [ActiveCategory]
    }

    struct PresentationSeed {
        let id: UUID
        let slug: String
        let defaultUnit: DoseUnit
    }

    static let activeSeeds: [ActiveSeed] = [
        ActiveSeed(id: activeID(1), slug: "vitamin_c", unit: .milligram, proposedMale: 90, proposedFemale: 75, categories: [.immunity, .aesthetics, .antioxidant]),
        ActiveSeed(id: activeID(2), slug: "vitamin_d", unit: .microgram, proposedMale: 15, proposedFemale: 15, categories: [.immunity, .bonesAndJoints]),
        ActiveSeed(id: activeID(3), slug: "vitamin_b12", unit: .microgram, proposedMale: decimal("2.4"), proposedFemale: decimal("2.4"), categories: [.energy, .cognition]),
        ActiveSeed(id: activeID(4), slug: "magnesium", unit: .milligram, proposedMale: 420, proposedFemale: 320, categories: [.sleep, .physicalPerformance, .stress]),
        ActiveSeed(id: activeID(5), slug: "omega_3", unit: .milligram, proposedMale: nil, proposedFemale: nil, categories: [.cardiovascular, .cognition, .aesthetics]),
        ActiveSeed(id: activeID(6), slug: "caffeine", unit: .milligram, proposedMale: nil, proposedFemale: nil, categories: [.physicalPerformance, .energy, .cognition]),
        ActiveSeed(id: activeID(7), slug: "zinc", unit: .milligram, proposedMale: 11, proposedFemale: 8, categories: [.immunity, .aesthetics, .antioxidant]),
        ActiveSeed(id: activeID(8), slug: "iron", unit: .milligram, proposedMale: 8, proposedFemale: 18, categories: [.physicalPerformance, .energy]),
        ActiveSeed(id: activeID(9), slug: "calcium", unit: .milligram, proposedMale: 1_000, proposedFemale: 1_000, categories: [.bonesAndJoints]),
        ActiveSeed(id: activeID(10), slug: "creatine", unit: .gram, proposedMale: nil, proposedFemale: nil, categories: [.physicalPerformance, .energy, .cognition]),
        ActiveSeed(id: activeID(11), slug: "melatonin", unit: .milligram, proposedMale: nil, proposedFemale: nil, categories: [.sleep]),
        ActiveSeed(id: activeID(12), slug: "ashwagandha", unit: .milligram, proposedMale: nil, proposedFemale: nil, categories: [.sleep, .physicalPerformance, .stress]),
        ActiveSeed(id: activeID(13), slug: "astaxanthin", unit: .milligram, proposedMale: nil, proposedFemale: nil, categories: [.cardiovascular, .aesthetics, .antioxidant]),
        ActiveSeed(id: activeID(14), slug: "berberine", unit: .milligram, proposedMale: nil, proposedFemale: nil, categories: [.cardiovascular, .metabolicHealth]),
        ActiveSeed(id: activeID(15), slug: "coenzyme_q10", unit: .milligram, proposedMale: nil, proposedFemale: nil, categories: [.energy, .cardiovascular, .antioxidant]),
        ActiveSeed(id: activeID(16), slug: "hydrolyzed_collagen", unit: .gram, proposedMale: nil, proposedFemale: nil, categories: [.bonesAndJoints, .aesthetics]),
        ActiveSeed(id: activeID(17), slug: "spermidine", unit: .milligram, proposedMale: nil, proposedFemale: nil, categories: [.metabolicHealth, .healthyAging]),
        ActiveSeed(id: activeID(18), slug: "l_arginine", unit: .gram, proposedMale: nil, proposedFemale: nil, categories: [.physicalPerformance, .cardiovascular]),
        ActiveSeed(id: activeID(19), slug: "glycine", unit: .gram, proposedMale: nil, proposedFemale: nil, categories: [.sleep, .bonesAndJoints, .aesthetics]),
        ActiveSeed(id: activeID(20), slug: "taurine", unit: .gram, proposedMale: nil, proposedFemale: nil, categories: [.physicalPerformance, .energy, .cardiovascular]),
        ActiveSeed(id: activeID(21), slug: "resveratrol", unit: .milligram, proposedMale: nil, proposedFemale: nil, categories: [.cardiovascular, .antioxidant, .healthyAging]),
        ActiveSeed(id: activeID(22), slug: "nicotinamide_riboside", unit: .milligram, proposedMale: nil, proposedFemale: nil, categories: [.energy, .metabolicHealth, .healthyAging]),
        ActiveSeed(id: activeID(23), slug: "quercetin", unit: .milligram, proposedMale: nil, proposedFemale: nil, categories: [.immunity, .antioxidant]),
        ActiveSeed(id: activeID(24), slug: "lutein", unit: .milligram, proposedMale: nil, proposedFemale: nil, categories: [.antioxidant, .vision]),
        ActiveSeed(id: activeID(25), slug: "sulforaphane", unit: .milligram, proposedMale: nil, proposedFemale: nil, categories: [.antioxidant, .metabolicHealth])
    ]

    static let presentationSeeds: [PresentationSeed] = [
        PresentationSeed(id: presentationID(1), slug: "capsule", defaultUnit: .capsule),
        PresentationSeed(id: presentationID(2), slug: "tablet", defaultUnit: .tablet),
        PresentationSeed(id: presentationID(3), slug: "powder", defaultUnit: .gram),
        PresentationSeed(id: presentationID(4), slug: "liquid", defaultUnit: .milliliter),
        PresentationSeed(id: presentationID(5), slug: "drops", defaultUnit: .drop),
        PresentationSeed(id: presentationID(6), slug: "gummy", defaultUnit: .gummy),
        PresentationSeed(id: presentationID(7), slug: "sachet", defaultUnit: .sachet),
        PresentationSeed(id: presentationID(8), slug: "scoop", defaultUnit: .scoop)
    ]

    static func apply(to database: SQLiteDatabase, userID: UUID) throws {
        let now = Date().timeIntervalSince1970
        try database.transaction {
            try database.execute(
                "INSERT OR IGNORE INTO app_users (id, created_at, updated_at) VALUES (?, ?, ?);",
                bindings: [.text(userID.uuidString), .real(now), .real(now)]
            )

            for seed in activeSeeds {
                try database.execute(
                    """
                    INSERT OR IGNORE INTO actives (
                        id, name_key, custom_name, description_key, custom_description,
                        base_unit, proposed_daily_male, proposed_daily_female, image_key,
                        is_seeded, created_at, updated_at, archived_at
                    ) VALUES (?, ?, NULL, ?, NULL, ?, ?, ?, ?, 1, ?, ?, NULL);
                    """,
                    bindings: [
                        .text(seed.id.uuidString),
                        .text("active.\(seed.slug).name"),
                        .text("active.\(seed.slug).description"),
                        .text(seed.unit.rawValue),
                        optionalDecimal(seed.proposedMale),
                        optionalDecimal(seed.proposedFemale),
                        .text("active_\(seed.slug)"),
                        .real(now),
                        .real(now)
                    ]
                )

                for category in seed.categories {
                    try database.execute(
                        "INSERT OR IGNORE INTO active_category_assignments (active_id, category) VALUES (?, ?);",
                        bindings: [.text(seed.id.uuidString), .text(category.rawValue)]
                    )
                }
            }

            var illustrationCounter = 1
            for presentation in presentationSeeds {
                try database.execute(
                    """
                    INSERT OR IGNORE INTO presentation_types (
                        id, name_key, default_unit, is_seeded, created_at, updated_at
                    ) VALUES (?, ?, ?, 1, ?, ?);
                    """,
                    bindings: [
                        .text(presentation.id.uuidString),
                        .text("presentation.\(presentation.slug).name"),
                        .text(presentation.defaultUnit.rawValue),
                        .real(now),
                        .real(now)
                    ]
                )

                for (order, variant) in ["cyan", "violet", "rose"].enumerated() {
                    let illustrationID = deterministicUUID(prefix: "40000000-0000-4000-8000", number: illustrationCounter)
                    illustrationCounter += 1
                    try database.execute(
                        """
                        INSERT OR IGNORE INTO presentation_illustrations (
                            id, presentation_type_id, variant_key, asset_key, display_order
                        ) VALUES (?, ?, ?, ?, ?);
                        """,
                        bindings: [
                            .text(illustrationID.uuidString),
                            .text(presentation.id.uuidString),
                            .text("presentation.variant.\(variant)"),
                            .text("presentation_\(presentation.slug)_\(variant)"),
                            .integer(Int64(order))
                        ]
                    )
                }
            }
        }
    }

    private static func activeID(_ number: Int) -> UUID {
        deterministicUUID(prefix: "20000000-0000-4000-8000", number: number)
    }

    private static func presentationID(_ number: Int) -> UUID {
        deterministicUUID(prefix: "30000000-0000-4000-8000", number: number)
    }

    private static func deterministicUUID(prefix: String, number: Int) -> UUID {
        UUID(uuidString: "\(prefix)-\(String(format: "%012d", number))")!
    }

    private static func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private static func optionalDecimal(_ value: Decimal?) throws -> SQLiteBinding {
        guard let value else { return .null }
        return .text(try DecimalCodec.encode(value))
    }
}
