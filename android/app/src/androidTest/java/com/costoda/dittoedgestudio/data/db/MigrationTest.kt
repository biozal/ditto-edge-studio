package com.costoda.dittoedgestudio.data.db

import androidx.room.Room
import androidx.room.testing.MigrationTestHelper
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertNotNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Smoke tests for the Room schema and migration list.
 *
 * Why this exists (see plans/android/config-loss-investigation.md item B1):
 * `fallbackToDestructiveMigration(dropAllTables = true)` was removed from
 * [AppDatabase.create] so Room will throw on a missing migration rather than
 * silently wiping all user-saved data (database configs, subscriptions,
 * observers, favorites, history). These tests guard that policy:
 *
 *  1. The current schema JSON (3.json) exists, is readable, and matches the
 *     entities/DAOs compiled into the app — i.e. KSP is still exporting on
 *     every build and the latest schema is committed.
 *  2. The full migration chain (v1 -> v2 -> v3) runs without throwing and
 *     produces a schema that validates against 3.json — i.e. the
 *     hand-written migrations stay consistent with the entity changes.
 *
 * Caveat: production [AppDatabase] uses SQLCipher's [SupportOpenHelperFactory],
 * but [MigrationTestHelper] uses the framework's plain SQLite. That is fine
 * for schema-shape validation (column names, types, indexes, FKs) — SQLCipher
 * does not change the schema, only the on-disk page encryption — so we
 * intentionally do NOT wire SupportOpenHelperFactory into the helper here.
 */
@RunWith(AndroidJUnit4::class)
class MigrationTest {

    @get:Rule
    val helper: MigrationTestHelper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        AppDatabase::class.java
    )

    /**
     * Validates the current schema (v3) by creating a fresh DB at the current
     * version and then opening it through the real Room builder. Room compares
     * the live entity hash against schemas/.../3.json and throws if they
     * diverge — this is the smoke that catches "engineer changed an entity
     * but forgot to bump the version / regenerate the schema json".
     */
    @Test
    fun currentSchemaMatchesExportedJson() {
        helper.createDatabase(TEST_DB, CURRENT_VERSION).close()

        val db = Room.databaseBuilder(
            ApplicationProvider.getApplicationContext(),
            AppDatabase::class.java,
            TEST_DB
        )
            .addMigrations(AppDatabase.MIGRATION_1_2, AppDatabase.MIGRATION_2_3)
            // No fallbackToDestructiveMigration — see AppDatabase.create() comment.
            .build()

        // Open + close to force Room to validate the live schema against
        // the exported JSON. A mismatch throws IllegalStateException here.
        assertNotNull(db.openHelper.writableDatabase)
        db.close()
    }

    /**
     * Walks the full migration chain v1 -> v2 -> v3 to make sure the
     * hand-written MIGRATION_1_2 and MIGRATION_2_3 still produce a schema
     * that matches the exported v3 JSON.
     */
    @Test
    fun migrate1To3_preservesSchema() {
        helper.createDatabase(TEST_DB, 1).close()

        helper.runMigrationsAndValidate(
            TEST_DB,
            CURRENT_VERSION,
            /* validateDroppedTables = */ true,
            AppDatabase.MIGRATION_1_2,
            AppDatabase.MIGRATION_2_3
        ).close()
    }

    companion object {
        private const val TEST_DB = "migration-test.db"

        // Keep in sync with @Database(version = ...) on AppDatabase.
        private const val CURRENT_VERSION = 3
    }
}
