import Foundation

enum SchemaMigrator {
    private struct Migration {
        let version: Int
        let sql: String
    }

    static func migrate(_ database: SQLiteDatabase) throws {
        try database.executeScript(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY,
                applied_at REAL NOT NULL
            );
            """
        )

        let applied = Set(
            try database.query("SELECT version FROM schema_migrations;")
                .map { Int(try $0.integer("version")) }
        )

        for migration in migrations where !applied.contains(migration.version) {
            try database.transaction {
                try database.executeScript(migration.sql)
                try database.execute(
                    "INSERT OR IGNORE INTO schema_migrations (version, applied_at) VALUES (?, ?);",
                    bindings: [.integer(Int64(migration.version)), .real(Date().timeIntervalSince1970)]
                )
            }
        }

        let foreignKeysEnabled = try database.scalarInteger("PRAGMA foreign_keys;")
        guard foreignKeysEnabled == 1 else {
            throw SQLiteStoreError.execute(sql: "PRAGMA foreign_keys", message: "Foreign keys are disabled")
        }
    }

    private static let migrations: [Migration] = [
        Migration(
            version: 1,
            sql: """
            CREATE TABLE IF NOT EXISTS app_users (
                id TEXT PRIMARY KEY NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS actives (
                id TEXT PRIMARY KEY NOT NULL,
                name_key TEXT,
                custom_name TEXT,
                description_key TEXT,
                custom_description TEXT,
                base_unit TEXT NOT NULL,
                proposed_daily_male TEXT,
                proposed_daily_female TEXT,
                image_key TEXT,
                is_seeded INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                archived_at REAL,
                CHECK (name_key IS NOT NULL OR custom_name IS NOT NULL)
            );

            CREATE TABLE IF NOT EXISTS active_targets (
                id TEXT PRIMARY KEY NOT NULL,
                user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
                active_id TEXT NOT NULL REFERENCES actives(id) ON DELETE CASCADE,
                lower_amount TEXT NOT NULL,
                upper_amount TEXT NOT NULL,
                unit TEXT NOT NULL,
                effective_from TEXT NOT NULL,
                effective_through TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                UNIQUE(user_id, active_id, effective_from)
            );

            CREATE TABLE IF NOT EXISTS presentation_types (
                id TEXT PRIMARY KEY NOT NULL,
                name_key TEXT NOT NULL UNIQUE,
                default_unit TEXT NOT NULL,
                is_seeded INTEGER NOT NULL DEFAULT 1,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS presentation_illustrations (
                id TEXT PRIMARY KEY NOT NULL,
                presentation_type_id TEXT NOT NULL REFERENCES presentation_types(id) ON DELETE CASCADE,
                variant_key TEXT NOT NULL,
                asset_key TEXT NOT NULL,
                display_order INTEGER NOT NULL DEFAULT 0,
                UNIQUE(presentation_type_id, variant_key)
            );

            CREATE TABLE IF NOT EXISTS supplements (
                id TEXT PRIMARY KEY NOT NULL,
                user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                brand TEXT NOT NULL,
                details TEXT,
                category TEXT,
                price_amount TEXT,
                currency_code TEXT,
                image_reference TEXT,
                presentation_type_id TEXT NOT NULL REFERENCES presentation_types(id) ON DELETE RESTRICT,
                basis_quantity TEXT NOT NULL,
                basis_unit TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                archived_at REAL
            );

            CREATE TABLE IF NOT EXISTS supplement_components (
                id TEXT PRIMARY KEY NOT NULL,
                supplement_id TEXT NOT NULL REFERENCES supplements(id) ON DELETE CASCADE,
                active_id TEXT NOT NULL REFERENCES actives(id) ON DELETE RESTRICT,
                amount TEXT NOT NULL,
                unit TEXT NOT NULL,
                display_order INTEGER NOT NULL DEFAULT 0,
                UNIQUE(supplement_id, active_id)
            );

            CREATE TABLE IF NOT EXISTS supplement_instances (
                id TEXT PRIMARY KEY NOT NULL,
                supplement_id TEXT NOT NULL REFERENCES supplements(id) ON DELETE CASCADE,
                user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
                label TEXT NOT NULL,
                expiration_day TEXT,
                notes TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                archived_at REAL
            );

            CREATE TABLE IF NOT EXISTS consumptions (
                id TEXT PRIMARY KEY NOT NULL,
                instance_id TEXT NOT NULL REFERENCES supplement_instances(id) ON DELETE RESTRICT,
                user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
                supplement_name_snapshot TEXT NOT NULL,
                instance_label_snapshot TEXT NOT NULL,
                quantity TEXT NOT NULL,
                unit TEXT NOT NULL,
                consumed_at REAL NOT NULL,
                timezone_id TEXT NOT NULL,
                local_day TEXT NOT NULL,
                notes TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS consumption_active_snapshots (
                id TEXT PRIMARY KEY NOT NULL,
                consumption_id TEXT NOT NULL REFERENCES consumptions(id) ON DELETE CASCADE,
                active_id TEXT NOT NULL REFERENCES actives(id) ON DELETE RESTRICT,
                active_name_key_snapshot TEXT,
                active_custom_name_snapshot TEXT,
                amount TEXT NOT NULL,
                unit TEXT NOT NULL,
                UNIQUE(consumption_id, active_id)
            );
            """
        ),
        Migration(
            version: 2,
            sql: """
            CREATE INDEX IF NOT EXISTS idx_active_targets_lookup
                ON active_targets(user_id, active_id, effective_from, effective_through);
            CREATE INDEX IF NOT EXISTS idx_supplements_user_active
                ON supplements(user_id, archived_at, name);
            CREATE INDEX IF NOT EXISTS idx_components_active
                ON supplement_components(active_id);
            CREATE INDEX IF NOT EXISTS idx_instances_supplement
                ON supplement_instances(supplement_id, archived_at);
            CREATE INDEX IF NOT EXISTS idx_instances_expiration
                ON supplement_instances(user_id, expiration_day, archived_at);
            CREATE INDEX IF NOT EXISTS idx_consumptions_day
                ON consumptions(user_id, local_day, consumed_at);
            CREATE INDEX IF NOT EXISTS idx_consumptions_instance
                ON consumptions(instance_id);
            CREATE INDEX IF NOT EXISTS idx_snapshot_active
                ON consumption_active_snapshots(active_id, consumption_id);
            """
        ),
        Migration(
            version: 3,
            sql: """
            CREATE TABLE IF NOT EXISTS medical_review_plans (
                id TEXT PRIMARY KEY NOT NULL,
                user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
                title TEXT NOT NULL COLLATE NOCASE,
                kind TEXT NOT NULL,
                interval_months INTEGER NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                UNIQUE(user_id, title)
            );

            CREATE TABLE IF NOT EXISTS medical_review_completions (
                id TEXT PRIMARY KEY NOT NULL,
                plan_id TEXT NOT NULL REFERENCES medical_review_plans(id) ON DELETE CASCADE,
                completed_at REAL NOT NULL,
                created_at REAL NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_medical_review_plans_user
                ON medical_review_plans(user_id, title);
            CREATE INDEX IF NOT EXISTS idx_medical_review_completions_plan_date
                ON medical_review_completions(plan_id, completed_at DESC);
            """
        ),
        Migration(
            version: 4,
            sql: """
            ALTER TABLE medical_review_completions
                ADD COLUMN notes TEXT;
            """
        ),
        Migration(
            version: 5,
            sql: """
            CREATE TABLE IF NOT EXISTS active_category_assignments (
                active_id TEXT NOT NULL REFERENCES actives(id) ON DELETE CASCADE,
                category TEXT NOT NULL,
                PRIMARY KEY(active_id, category)
            );

            CREATE INDEX IF NOT EXISTS idx_active_category_lookup
                ON active_category_assignments(category, active_id);
            """
        ),
        Migration(
            version: 6,
            sql: """
            ALTER TABLE supplement_instances
                ADD COLUMN total_quantity TEXT;
            ALTER TABLE supplement_instances
                ADD COLUMN total_unit TEXT;
            """
        ),
        Migration(
            version: 7,
            sql: """
            CREATE TABLE IF NOT EXISTS active_favorites (
                user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
                active_id TEXT NOT NULL REFERENCES actives(id) ON DELETE CASCADE,
                created_at REAL NOT NULL,
                PRIMARY KEY(user_id, active_id)
            );

            CREATE INDEX IF NOT EXISTS idx_active_favorites_user
                ON active_favorites(user_id, active_id);
            """
        ),
        Migration(
            version: 8,
            sql: """
            ALTER TABLE supplement_instances
                ADD COLUMN initial_quantity TEXT;
            ALTER TABLE supplement_instances
                ADD COLUMN initial_unit TEXT;
            """
        ),
        Migration(
            version: 9,
            sql: """
            ALTER TABLE consumptions
                ADD COLUMN inventory_applied INTEGER NOT NULL DEFAULT 0;
            """
        ),
        Migration(
            version: 10,
            sql: """
            CREATE TABLE IF NOT EXISTS biomarkers (
                id TEXT PRIMARY KEY NOT NULL,
                name_key TEXT,
                custom_name TEXT,
                sample_type TEXT NOT NULL,
                default_unit TEXT NOT NULL,
                image_key TEXT,
                is_seeded INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                archived_at REAL,
                CHECK (name_key IS NOT NULL OR custom_name IS NOT NULL)
            );

            CREATE TABLE IF NOT EXISTS biomarker_favorites (
                user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
                biomarker_id TEXT NOT NULL REFERENCES biomarkers(id) ON DELETE CASCADE,
                created_at REAL NOT NULL,
                PRIMARY KEY(user_id, biomarker_id)
            );

            CREATE TABLE IF NOT EXISTS lab_analyses (
                id TEXT PRIMARY KEY NOT NULL,
                user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
                collected_at REAL NOT NULL,
                laboratory TEXT,
                notes TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS lab_results (
                id TEXT PRIMARY KEY NOT NULL,
                analysis_id TEXT NOT NULL REFERENCES lab_analyses(id) ON DELETE CASCADE,
                biomarker_id TEXT NOT NULL REFERENCES biomarkers(id) ON DELETE RESTRICT,
                value TEXT NOT NULL,
                unit TEXT NOT NULL,
                reference_lower TEXT,
                reference_upper TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                UNIQUE(analysis_id, biomarker_id)
            );

            CREATE INDEX IF NOT EXISTS idx_biomarkers_type
                ON biomarkers(sample_type, archived_at);
            CREATE INDEX IF NOT EXISTS idx_biomarker_favorites_user
                ON biomarker_favorites(user_id, biomarker_id);
            CREATE INDEX IF NOT EXISTS idx_lab_analyses_user_date
                ON lab_analyses(user_id, collected_at DESC);
            CREATE INDEX IF NOT EXISTS idx_lab_results_biomarker
                ON lab_results(biomarker_id, analysis_id);
            """
        ),
        Migration(
            version: 11,
            sql: """
            ALTER TABLE lab_results
                ADD COLUMN notes TEXT;
            """
        ),
        Migration(
            version: 12,
            sql: """
            ALTER TABLE lab_analyses
                ADD COLUMN imported_pdf_path TEXT;
            ALTER TABLE lab_analyses
                ADD COLUMN imported_pdf_name TEXT;
            """
        ),
        Migration(
            version: 13,
            sql: """
            UPDATE biomarkers
            SET sample_type = 'other'
            WHERE sample_type = 'physiological';
            """
        ),
        Migration(
            version: 14,
            sql: """
            CREATE TABLE IF NOT EXISTS recovery_baselines (
                user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
                date TEXT NOT NULL,
                hrv_mean REAL NOT NULL,
                hrv_stddev REAL NOT NULL,
                rhr_mean REAL NOT NULL,
                rhr_stddev REAL NOT NULL,
                updated_at REAL NOT NULL,
                PRIMARY KEY (user_id, date)
            );

            CREATE TABLE IF NOT EXISTS recovery_scores (
                user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
                date TEXT NOT NULL,
                score REAL NOT NULL,
                hrv_value REAL,
                rhr_value REAL,
                sleep_score REAL,
                respiratory_rate REAL,
                updated_at REAL NOT NULL,
                PRIMARY KEY (user_id, date)
            );
            """
        ),
        Migration(
            version: 15,
            sql: """
            -- Vitamin D used to be seeded in micrograms. It is now tracked
            -- in IU, which matches the catalog and prevents a generic
            -- mass-to-IU conversion from distorting reports.
            UPDATE consumption_active_snapshots
            SET
                amount = CASE
                    WHEN EXISTS (
                        SELECT 1
                        FROM consumptions c
                        JOIN supplement_instances i ON i.id = c.instance_id
                        JOIN supplement_components component
                            ON component.supplement_id = i.supplement_id
                        WHERE c.id = consumption_active_snapshots.consumption_id
                          AND component.active_id = consumption_active_snapshots.active_id
                          AND component.unit = 'IU'
                    ) THEN CAST(CAST(amount AS REAL) / 1000 AS TEXT)
                    ELSE CAST(CAST(amount AS REAL) * 40 AS TEXT)
                END,
                unit = 'IU'
            WHERE active_id = '20000000-0000-4000-8000-000000000002'
              AND unit = 'ug';

            UPDATE supplement_components
            SET amount = CAST(CAST(amount AS REAL) * 40 AS TEXT), unit = 'IU'
            WHERE active_id = '20000000-0000-4000-8000-000000000002'
              AND unit = 'ug';

            UPDATE active_targets
            SET
                lower_amount = CAST(CAST(lower_amount AS REAL) * 40 AS TEXT),
                upper_amount = CAST(CAST(upper_amount AS REAL) * 40 AS TEXT),
                unit = 'IU'
            WHERE active_id = '20000000-0000-4000-8000-000000000002'
              AND unit = 'ug';

            UPDATE actives
            SET
                base_unit = 'IU',
                proposed_daily_male = CASE
                    WHEN proposed_daily_male = '15' THEN '1000'
                    ELSE proposed_daily_male
                END,
                proposed_daily_female = CASE
                    WHEN proposed_daily_female = '15' THEN '1000'
                    ELSE proposed_daily_female
                END
            WHERE id = '20000000-0000-4000-8000-000000000002'
              AND is_seeded = 1;
            """
        ),
        Migration(
            version: 16,
            sql: """
            CREATE TABLE IF NOT EXISTS strength_exercises (
                id TEXT PRIMARY KEY NOT NULL,
                name_en TEXT NOT NULL,
                name_es TEXT NOT NULL,
                force TEXT,
                level TEXT,
                mechanic TEXT,
                equipment TEXT,
                primary_muscles_json TEXT NOT NULL,
                secondary_muscles_json TEXT NOT NULL,
                instructions_en_json TEXT NOT NULL,
                instructions_es_json TEXT,
                image_paths_json TEXT NOT NULL,
                source TEXT NOT NULL,
                is_seeded INTEGER NOT NULL DEFAULT 1
            );

            CREATE TABLE IF NOT EXISTS strength_workout_templates (
                id TEXT PRIMARY KEY NOT NULL,
                user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
                name TEXT NOT NULL COLLATE NOCASE,
                notes TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                UNIQUE(user_id, name)
            );

            CREATE TABLE IF NOT EXISTS strength_template_exercises (
                id TEXT PRIMARY KEY NOT NULL,
                template_id TEXT NOT NULL REFERENCES strength_workout_templates(id) ON DELETE CASCADE,
                exercise_id TEXT NOT NULL REFERENCES strength_exercises(id) ON DELETE RESTRICT,
                display_order INTEGER NOT NULL,
                default_rest_seconds INTEGER,
                UNIQUE(template_id, display_order)
            );

            CREATE TABLE IF NOT EXISTS strength_template_sets (
                id TEXT PRIMARY KEY NOT NULL,
                template_exercise_id TEXT NOT NULL REFERENCES strength_template_exercises(id) ON DELETE CASCADE,
                display_order INTEGER NOT NULL,
                weight TEXT,
                repetitions INTEGER,
                rest_seconds INTEGER,
                is_warmup INTEGER NOT NULL DEFAULT 0,
                is_failure INTEGER NOT NULL DEFAULT 0,
                is_drop_set INTEGER NOT NULL DEFAULT 0,
                UNIQUE(template_exercise_id, display_order)
            );

            CREATE TABLE IF NOT EXISTS strength_workouts (
                id TEXT PRIMARY KEY NOT NULL,
                user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                started_at REAL NOT NULL,
                ended_at REAL,
                notes TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS strength_workout_exercises (
                id TEXT PRIMARY KEY NOT NULL,
                workout_id TEXT NOT NULL REFERENCES strength_workouts(id) ON DELETE CASCADE,
                exercise_id TEXT NOT NULL REFERENCES strength_exercises(id) ON DELETE RESTRICT,
                exercise_name_snapshot TEXT NOT NULL,
                display_order INTEGER NOT NULL,
                notes TEXT,
                UNIQUE(workout_id, display_order)
            );

            CREATE TABLE IF NOT EXISTS strength_workout_sets (
                id TEXT PRIMARY KEY NOT NULL,
                workout_exercise_id TEXT NOT NULL REFERENCES strength_workout_exercises(id) ON DELETE CASCADE,
                display_order INTEGER NOT NULL,
                weight TEXT,
                repetitions INTEGER,
                rest_seconds INTEGER,
                is_warmup INTEGER NOT NULL DEFAULT 0,
                is_failure INTEGER NOT NULL DEFAULT 0,
                is_drop_set INTEGER NOT NULL DEFAULT 0,
                completed_at REAL,
                UNIQUE(workout_exercise_id, display_order)
            );

            CREATE INDEX IF NOT EXISTS idx_strength_templates_user
                ON strength_workout_templates(user_id, updated_at DESC);
            CREATE INDEX IF NOT EXISTS idx_strength_workouts_user
                ON strength_workouts(user_id, started_at DESC);
            CREATE INDEX IF NOT EXISTS idx_strength_template_exercises_template
                ON strength_template_exercises(template_id, display_order);
            CREATE INDEX IF NOT EXISTS idx_strength_workout_exercises_workout
                ON strength_workout_exercises(workout_id, display_order);
            """
        ),
        Migration(
            version: 17,
            sql: """
            ALTER TABLE strength_workout_templates ADD COLUMN name_key TEXT;
            CREATE INDEX IF NOT EXISTS idx_strength_templates_name_key
                ON strength_workout_templates(user_id, name_key);
            """
        ),
        Migration(
            version: 18,
            sql: """
            CREATE TABLE IF NOT EXISTS strength_exercise_favorites (
                user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
                exercise_id TEXT NOT NULL REFERENCES strength_exercises(id) ON DELETE CASCADE,
                created_at REAL NOT NULL,
                PRIMARY KEY (user_id, exercise_id)
            );
            CREATE INDEX IF NOT EXISTS idx_strength_exercise_favorites_user
                ON strength_exercise_favorites(user_id, created_at DESC);
            """
        ),
        Migration(
            version: 19,
            sql: """
            CREATE TABLE IF NOT EXISTS strength_exercise_custom_names (
                user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
                exercise_id TEXT NOT NULL REFERENCES strength_exercises(id) ON DELETE CASCADE,
                name TEXT NOT NULL COLLATE NOCASE,
                updated_at REAL NOT NULL,
                PRIMARY KEY (user_id, exercise_id)
            );
            """
        ),
        Migration(
            version: 20,
            sql: """
            CREATE TABLE IF NOT EXISTS strength_body_metrics (
                id TEXT PRIMARY KEY NOT NULL,
                user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
                name TEXT NOT NULL COLLATE NOCASE,
                value TEXT NOT NULL,
                unit TEXT,
                measured_at REAL NOT NULL,
                created_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_strength_body_metrics_user_date
                ON strength_body_metrics(user_id, measured_at DESC);
            """
        ),
        Migration(
            version: 21,
            sql: """
            CREATE TABLE IF NOT EXISTS strength_predefined_template_deletions (
                user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
                name_key TEXT NOT NULL,
                deleted_at REAL NOT NULL,
                PRIMARY KEY (user_id, name_key)
            );
            """
        ),
        Migration(
            version: 22,
            sql: """
            CREATE TABLE IF NOT EXISTS strength_hidden_exercises (
                user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
                exercise_id TEXT NOT NULL REFERENCES strength_exercises(id) ON DELETE CASCADE,
                hidden_at REAL NOT NULL,
                PRIMARY KEY (user_id, exercise_id)
            );
            CREATE INDEX IF NOT EXISTS idx_strength_hidden_exercises_user
                ON strength_hidden_exercises(user_id, hidden_at DESC);
            """
        ),
        Migration(
            version: 23,
            sql: """
            -- Package inventory started recording its original quantity after
            -- remaining content had already been in use. For existing
            -- packages, the earliest reliable baseline is the quantity that
            -- was available at the time of this migration.
            UPDATE supplement_instances
            SET initial_quantity = total_quantity,
                initial_unit = total_unit
            WHERE total_quantity IS NOT NULL
              AND total_unit IS NOT NULL
              AND (initial_quantity IS NULL OR initial_unit IS NULL);
            """
        ),
        Migration(
            version: 24,
            sql: """
            ALTER TABLE supplements ADD COLUMN package_quantity TEXT;
            ALTER TABLE supplements ADD COLUMN package_unit TEXT;
            """
        ),
        Migration(
            version: 25,
            sql: """
            -- Before package capacity belonged to the product, it was stored
            -- only on individual packages. Use the largest known original
            -- package as the best available nominal capacity for each product.
            UPDATE supplements
            SET package_quantity = (
                    SELECT i.initial_quantity
                    FROM supplement_instances i
                    WHERE i.supplement_id = supplements.id
                      AND i.initial_quantity IS NOT NULL
                      AND i.initial_unit IS NOT NULL
                    ORDER BY CAST(i.initial_quantity AS REAL) DESC
                    LIMIT 1
                ),
                package_unit = (
                    SELECT i.initial_unit
                    FROM supplement_instances i
                    WHERE i.supplement_id = supplements.id
                      AND i.initial_quantity IS NOT NULL
                      AND i.initial_unit IS NOT NULL
                    ORDER BY CAST(i.initial_quantity AS REAL) DESC
                    LIMIT 1
                )
            WHERE package_quantity IS NULL
              AND package_unit IS NULL;
            """
        )
    ]
}
