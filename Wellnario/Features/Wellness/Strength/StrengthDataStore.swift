import Foundation

enum StrengthDataStoreError: Error, LocalizedError {
    case missingCatalog
    case invalidTemplate
    case invalidWorkout
    case notFound

    var errorDescription: String? {
        switch self {
        case .missingCatalog: return "The embedded strength exercise catalog could not be loaded."
        case .invalidTemplate: return "A template needs a name and at least one exercise."
        case .invalidWorkout: return "A workout needs at least one exercise."
        case .notFound: return "The requested strength training item no longer exists."
        }
    }
}

@MainActor
final class StrengthDataStore {
    private let database: SQLiteDatabase
    private let userID: UUID

    init(databaseURL: URL, userID: UUID) throws {
        database = try SQLiteDatabase(url: databaseURL)
        self.userID = userID
        try seedExerciseCatalog()
        try seedPredefinedTemplates()
    }

    func fetchExercises() throws -> [StrengthExercise] {
        try database.query(
            """
            SELECT id, name_en, name_es, force, level, mechanic, equipment,
                   primary_muscles_json, secondary_muscles_json,
                   instructions_en_json, instructions_es_json, image_paths_json
            FROM strength_exercises
            ORDER BY name_en COLLATE NOCASE ASC;
            """
        ).map(mapExercise)
    }

    func exercise(id: String) throws -> StrengthExercise? {
        try database.query(
            """
            SELECT id, name_en, name_es, force, level, mechanic, equipment,
                   primary_muscles_json, secondary_muscles_json,
                   instructions_en_json, instructions_es_json, image_paths_json
            FROM strength_exercises WHERE id = ? LIMIT 1;
            """,
            bindings: [.text(id)]
        ).first.map(mapExercise)
    }

    func fetchTemplates() throws -> [StrengthWorkoutTemplate] {
        try database.query(
            """
            SELECT id, name_key, name, notes, created_at, updated_at
            FROM strength_workout_templates
            WHERE user_id = ?
            ORDER BY updated_at DESC, name COLLATE NOCASE ASC;
            """,
            bindings: [.text(userID.uuidString)]
        ).map { row in
            let id = try uuid(row, "id")
            return StrengthWorkoutTemplate(
                id: id,
                nameKey: try row.optionalString("name_key"),
                name: try row.string("name"),
                notes: try row.optionalString("notes"),
                exercises: try fetchTemplateExercises(templateID: id),
                createdAt: try date(row, "created_at"),
                updatedAt: try date(row, "updated_at")
            )
        }
    }

    @discardableResult
    func saveTemplate(_ draft: StrengthWorkoutTemplateDraft) throws -> StrengthWorkoutTemplate {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !draft.exercises.isEmpty else {
            throw StrengthDataStoreError.invalidTemplate
        }
        let templateID = UUID()
        let now = Date()
        try database.transaction {
            try database.execute(
                """
                INSERT INTO strength_workout_templates
                    (id, user_id, name_key, name, notes, created_at, updated_at)
                VALUES (?, ?, NULL, ?, ?, ?, ?);
                """,
                bindings: [
                    .text(templateID.uuidString), .text(userID.uuidString), .text(name),
                    optionalText(draft.notes), .real(now.timeIntervalSince1970), .real(now.timeIntervalSince1970)
                ]
            )
            try saveTemplateExercises(draft.exercises, templateID: templateID)
        }
        guard let template = try fetchTemplates().first(where: { $0.id == templateID }) else {
            throw StrengthDataStoreError.notFound
        }
        return template
    }

    func deleteTemplate(id: UUID) throws {
        let deleted = try database.execute(
            "DELETE FROM strength_workout_templates WHERE id = ? AND user_id = ?;",
            bindings: [.text(id.uuidString), .text(userID.uuidString)]
        )
        guard deleted > 0 else { throw StrengthDataStoreError.notFound }
    }

    @discardableResult
    func saveWorkout(_ workout: StrengthWorkout) throws -> StrengthWorkout {
        guard !workout.exercises.isEmpty else { throw StrengthDataStoreError.invalidWorkout }
        let now = Date()
        let endedAt = workout.endedAt ?? now
        try database.transaction {
            try database.execute(
                """
                INSERT INTO strength_workouts
                    (id, user_id, title, started_at, ended_at, notes, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    .text(workout.id.uuidString), .text(userID.uuidString), .text(workout.title),
                    .real(workout.startedAt.timeIntervalSince1970), .real(endedAt.timeIntervalSince1970),
                    optionalText(workout.notes), .real(now.timeIntervalSince1970), .real(now.timeIntervalSince1970)
                ]
            )
            for (exerciseIndex, workoutExercise) in workout.exercises.enumerated() {
                try database.execute(
                    """
                    INSERT INTO strength_workout_exercises
                        (id, workout_id, exercise_id, exercise_name_snapshot, display_order, notes)
                    VALUES (?, ?, ?, ?, ?, ?);
                    """,
                    bindings: [
                        .text(workoutExercise.id.uuidString), .text(workout.id.uuidString),
                        .text(workoutExercise.exercise.id), .text(workoutExercise.exercise.nameEnglish),
                        .integer(Int64(exerciseIndex)), optionalText(workoutExercise.notes)
                    ]
                )
                for (setIndex, set) in workoutExercise.sets.enumerated() {
                    try database.execute(
                        """
                        INSERT INTO strength_workout_sets
                            (id, workout_exercise_id, display_order, weight, repetitions, rest_seconds,
                             is_warmup, is_failure, is_drop_set, completed_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                        """,
                        bindings: [
                            .text(set.id.uuidString), .text(workoutExercise.id.uuidString), .integer(Int64(setIndex)),
                            optionalDecimal(set.weight), set.repetitions.map { .integer(Int64($0)) } ?? .null,
                            set.restSeconds.map { .integer(Int64($0)) } ?? .null,
                            .integer(set.isWarmup ? 1 : 0), .integer(set.isFailure ? 1 : 0),
                            .integer(set.isDropSet ? 1 : 0),
                            set.completedAt.map { .real($0.timeIntervalSince1970) } ?? .null
                        ]
                    )
                }
            }
        }
        var saved = workout
        saved.endedAt = endedAt
        return saved
    }

    func workoutCount() throws -> Int {
        Int(try database.scalarInteger(
            "SELECT COUNT(*) FROM strength_workouts WHERE user_id = ?;",
            bindings: [.text(userID.uuidString)]
        ))
    }

    func workout(from template: StrengthWorkoutTemplate? = nil, title: String) -> StrengthWorkout {
        let exercises = (template?.exercises ?? []).enumerated().map { index, item in
            StrengthWorkoutExercise(
                exercise: item.exercise,
                order: index,
                sets: item.sets.map { set in
                    StrengthWorkoutSet(
                        order: set.order,
                        weight: set.weight,
                        repetitions: set.repetitions,
                        restSeconds: set.restSeconds,
                        isWarmup: set.isWarmup,
                        isFailure: set.isFailure,
                        isDropSet: set.isDropSet
                    )
                }
            )
        }
        return StrengthWorkout(title: title, exercises: exercises)
    }

    private func fetchTemplateExercises(templateID: UUID) throws -> [StrengthWorkoutTemplateExercise] {
        try database.query(
            """
            SELECT te.id AS template_exercise_id, te.display_order, te.default_rest_seconds,
                   e.id, e.name_en, e.name_es, e.force, e.level, e.mechanic, e.equipment,
                   e.primary_muscles_json, e.secondary_muscles_json,
                   e.instructions_en_json, e.instructions_es_json, e.image_paths_json
            FROM strength_template_exercises te
            JOIN strength_exercises e ON e.id = te.exercise_id
            WHERE te.template_id = ?
            ORDER BY te.display_order ASC;
            """,
            bindings: [.text(templateID.uuidString)]
        ).map { row in
            let templateExerciseID = try uuid(row, "template_exercise_id")
            return StrengthWorkoutTemplateExercise(
                id: templateExerciseID,
                exercise: try mapExercise(row),
                order: Int(try row.integer("display_order")),
                defaultRestSeconds: try row.optionalInteger("default_rest_seconds").map(Int.init),
                sets: try fetchTemplateSets(templateExerciseID: templateExerciseID)
            )
        }
    }

    private func fetchTemplateSets(templateExerciseID: UUID) throws -> [StrengthWorkoutSet] {
        try database.query(
            """
            SELECT id, display_order, weight, repetitions, rest_seconds,
                   is_warmup, is_failure, is_drop_set
            FROM strength_template_sets
            WHERE template_exercise_id = ?
            ORDER BY display_order ASC;
            """,
            bindings: [.text(templateExerciseID.uuidString)]
        ).map { row in
            StrengthWorkoutSet(
                id: try uuid(row, "id"),
                order: Int(try row.integer("display_order")) + 1,
                weight: try optionalDecimal(row, "weight"),
                repetitions: try row.optionalInteger("repetitions").map(Int.init),
                restSeconds: try row.optionalInteger("rest_seconds").map(Int.init),
                isWarmup: try row.integer("is_warmup") != 0,
                isFailure: try row.integer("is_failure") != 0,
                isDropSet: try row.integer("is_drop_set") != 0
            )
        }
    }

    private func saveTemplateExercises(
        _ exercises: [StrengthWorkoutTemplateExercise],
        templateID: UUID
    ) throws {
        for (exerciseIndex, templateExercise) in exercises.enumerated() {
            let templateExerciseID = UUID()
            try database.execute(
                """
                INSERT INTO strength_template_exercises
                    (id, template_id, exercise_id, display_order, default_rest_seconds)
                VALUES (?, ?, ?, ?, ?);
                """,
                bindings: [
                    .text(templateExerciseID.uuidString), .text(templateID.uuidString),
                    .text(templateExercise.exercise.id), .integer(Int64(exerciseIndex)),
                    templateExercise.defaultRestSeconds.map { .integer(Int64($0)) } ?? .null
                ]
            )
            for (setIndex, set) in templateExercise.sets.enumerated() {
                try database.execute(
                    """
                    INSERT INTO strength_template_sets
                        (id, template_exercise_id, display_order, weight, repetitions, rest_seconds,
                         is_warmup, is_failure, is_drop_set)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """,
                    bindings: [
                        .text(UUID().uuidString), .text(templateExerciseID.uuidString), .integer(Int64(setIndex)),
                        optionalDecimal(set.weight), set.repetitions.map { .integer(Int64($0)) } ?? .null,
                        set.restSeconds.map { .integer(Int64($0)) } ?? .null,
                        .integer(set.isWarmup ? 1 : 0), .integer(set.isFailure ? 1 : 0),
                        .integer(set.isDropSet ? 1 : 0)
                    ]
                )
            }
        }
    }

    private func mapExercise(_ row: SQLiteRow) throws -> StrengthExercise {
        StrengthExercise(
            id: try row.string("id"),
            nameEnglish: try row.string("name_en"),
            nameSpanish: try row.string("name_es"),
            force: try row.optionalString("force"),
            level: try row.optionalString("level"),
            mechanic: try row.optionalString("mechanic"),
            equipment: try row.optionalString("equipment"),
            primaryMuscles: try jsonArray(row, "primary_muscles_json"),
            secondaryMuscles: try jsonArray(row, "secondary_muscles_json"),
            instructionsEnglish: try jsonArray(row, "instructions_en_json"),
            instructionsSpanish: try row.optionalString("instructions_es_json").map(jsonArray),
            imagePaths: try jsonArray(row, "image_paths_json")
        )
    }

    private func seedExerciseCatalog() throws {
        let records = try loadCatalog()
        try database.transaction {
            for record in records {
                try database.execute(
                    """
                    INSERT INTO strength_exercises
                        (id, name_en, name_es, force, level, mechanic, equipment,
                         primary_muscles_json, secondary_muscles_json, instructions_en_json,
                         instructions_es_json, image_paths_json, source, is_seeded)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, 1)
                    ON CONFLICT(id) DO UPDATE SET
                        name_en = excluded.name_en,
                        name_es = excluded.name_es,
                        force = excluded.force,
                        level = excluded.level,
                        mechanic = excluded.mechanic,
                        equipment = excluded.equipment,
                        primary_muscles_json = excluded.primary_muscles_json,
                        secondary_muscles_json = excluded.secondary_muscles_json,
                        instructions_en_json = excluded.instructions_en_json,
                        image_paths_json = excluded.image_paths_json,
                        source = excluded.source;
                    """,
                    bindings: [
                        .text(record.id), .text(record.nameEnglish), .text(record.nameSpanish),
                        optionalText(record.force), optionalText(record.level), optionalText(record.mechanic),
                        optionalText(record.equipment), .text(try json(record.primaryMuscles)),
                        .text(try json(record.secondaryMuscles)), .text(try json(record.instructionsEnglish)),
                        .text(try json(record.imagePaths)),
                        .text("https://github.com/yuhonas/free-exercise-db")
                    ]
                )
            }
        }
    }

    private func seedPredefinedTemplates() throws {
        let seeds: [(nameKey: String, name: String, exerciseIDs: [String])] = [
            (
                "strength.template.full_body",
                "Full body",
                ["Barbell_Squat", "Barbell_Bench_Press_-_Medium_Grip", "Barbell_Deadlift", "Pullups"]
            ),
            (
                "strength.template.upper_body",
                "Upper body",
                ["Barbell_Bench_Press_-_Medium_Grip", "Dumbbell_Shoulder_Press", "Pullups"]
            ),
            (
                "strength.template.lower_body",
                "Lower body",
                ["Barbell_Squat", "Barbell_Deadlift", "Leg_Press"]
            )
        ]
        let now = Date().timeIntervalSince1970
        try database.transaction {
            for seed in seeds {
                let count = try database.scalarInteger(
                    """
                    SELECT COUNT(*) FROM strength_workout_templates
                    WHERE user_id = ? AND name_key = ?;
                    """,
                    bindings: [.text(userID.uuidString), .text(seed.nameKey)]
                )
                guard count == 0 else { continue }

                let templateID = UUID()
                try database.execute(
                    """
                    INSERT INTO strength_workout_templates
                        (id, user_id, name_key, name, notes, created_at, updated_at)
                    VALUES (?, ?, ?, ?, NULL, ?, ?);
                    """,
                    bindings: [
                        .text(templateID.uuidString), .text(userID.uuidString), .text(seed.nameKey),
                        .text(seed.name), .real(now), .real(now)
                    ]
                )
                for (exerciseIndex, exerciseID) in seed.exerciseIDs.enumerated() {
                    let templateExerciseID = UUID()
                    try database.execute(
                        """
                        INSERT INTO strength_template_exercises
                            (id, template_id, exercise_id, display_order, default_rest_seconds)
                        VALUES (?, ?, ?, ?, 90);
                        """,
                        bindings: [
                            .text(templateExerciseID.uuidString), .text(templateID.uuidString), .text(exerciseID),
                            .integer(Int64(exerciseIndex))
                        ]
                    )
                    for setOrder in 0..<3 {
                        try database.execute(
                            """
                            INSERT INTO strength_template_sets
                                (id, template_exercise_id, display_order, weight, repetitions, rest_seconds,
                                 is_warmup, is_failure, is_drop_set)
                            VALUES (?, ?, ?, NULL, 8, 90, 0, 0, 0);
                            """,
                            bindings: [
                                .text(UUID().uuidString), .text(templateExerciseID.uuidString),
                                .integer(Int64(setOrder))
                            ]
                        )
                    }
                }
            }
        }
    }

    private func loadCatalog() throws -> [CatalogRecord] {
        let bundle = Bundle(for: StrengthCatalogBundleMarker.self)
        guard let url = bundle.url(forResource: "StrengthExercises", withExtension: "json")
                ?? Bundle.main.url(forResource: "StrengthExercises", withExtension: "json") else {
            throw StrengthDataStoreError.missingCatalog
        }
        return try JSONDecoder().decode([CatalogRecord].self, from: Data(contentsOf: url))
    }

    private func uuid(_ row: SQLiteRow, _ name: String) throws -> UUID {
        let value = try row.string(name)
        guard let id = UUID(uuidString: value) else { throw StrengthDataStoreError.notFound }
        return id
    }

    private func date(_ row: SQLiteRow, _ name: String) throws -> Date {
        Date(timeIntervalSince1970: try row.double(name))
    }

    private func optionalDecimal(_ row: SQLiteRow, _ name: String) throws -> Decimal? {
        guard let text = try row.optionalString(name) else { return nil }
        return try DecimalCodec.decode(text)
    }

    private func optionalDecimal(_ value: Decimal?) -> SQLiteBinding {
        guard let value, let encoded = try? DecimalCodec.encode(value) else { return .null }
        return .text(encoded)
    }

    private func optionalText(_ value: String?) -> SQLiteBinding {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return .null
        }
        return .text(value)
    }

    private func jsonArray(_ row: SQLiteRow, _ name: String) throws -> [String] {
        try jsonArray(try row.string(name))
    }

    private func jsonArray(_ value: String) throws -> [String] {
        try JSONDecoder().decode([String].self, from: Data(value.utf8))
    }

    private func json(_ values: [String]) throws -> String {
        String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
    }
}

private final class StrengthCatalogBundleMarker {}

private struct CatalogRecord: Codable {
    let id: String
    let nameEnglish: String
    let nameSpanish: String
    let force: String?
    let level: String?
    let mechanic: String?
    let equipment: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let instructionsEnglish: [String]
    let imagePaths: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case nameEnglish = "name_en"
        case nameSpanish = "name_es"
        case force, level, mechanic, equipment
        case primaryMuscles = "primary_muscles"
        case secondaryMuscles = "secondary_muscles"
        case instructionsEnglish = "instructions_en"
        case imagePaths = "image_paths"
    }
}
