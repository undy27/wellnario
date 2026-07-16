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
        )
    ]
}
