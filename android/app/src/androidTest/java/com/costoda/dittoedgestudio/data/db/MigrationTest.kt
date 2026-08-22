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
 *  1. The current schema JSON (4.json) exists, is readable, and matches the
 *     entities/DAOs compiled into the app — i.e. KSP is still exporting on
 *     every build and the latest schema is committed.
 *  2. The full migration chain (v1 -> v4) runs without throwing and
 *     produces a schema that validates against 4.json — i.e. the
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
     * Validates the current schema (v4) by creating a fresh DB at the current
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
            .addMigrations(AppDatabase.MIGRATION_1_2, AppDatabase.MIGRATION_2_3, AppDatabase.MIGRATION_3_4)
            // No fallbackToDestructiveMigration — see AppDatabase.create() comment.
            .build()

        // Open + close to force Room to validate the live schema against
        // the exported JSON. A mismatch throws IllegalStateException here.
        assertNotNull(db.openHelper.writableDatabase)
        db.close()
    }

    /**
     * Walks the full migration chain v1 -> v4 to make sure the
     * hand-written migrations still produce a schema that matches the
     * exported v4 JSON.
     */
    @Test
    fun migrate1To4_preservesSchema() {
        helper.createDatabase(TEST_DB, 1).close()

        helper.runMigrationsAndValidate(
            TEST_DB,
            CURRENT_VERSION,
            /* validateDroppedTables = */ true,
            AppDatabase.MIGRATION_1_2,
            AppDatabase.MIGRATION_2_3,
            AppDatabase.MIGRATION_3_4
        ).close()
    }

    /**
     * v3 -> v4 adds the advanced-configuration columns (JSON-in-TEXT) with
     * `'[]'` defaults; existing rows must survive with both lists empty.
     */
    @Test
    fun migrate3To4_addsAdvancedConfigColumnsWithEmptyDefaults() {
        helper.createDatabase(TEST_DB, 3).apply {
            execSQL(
                """
                INSERT INTO databaseConfigs (
                    name, databaseId, mode, allowUntrustedCerts,
                    isBluetoothLeEnabled, isLanEnabled, isAwdlEnabled, isCloudSyncEnabled,
                    token, authUrl, websocketUrl, httpApiUrl, httpApiKey,
                    secretKey, logLevel, isStrictModeEnabled
                ) VALUES (
                    'Migrated', 'db-migrated', 'server', 0,
                    1, 1, 0, 1,
                    'tok', 'https://auth.example.com', '', '', '',
                    '', 'info', 0
                )
                """.trimIndent()
            )
            close()
        }

        val db = helper.runMigrationsAndValidate(
            TEST_DB,
            CURRENT_VERSION,
            /* validateDroppedTables = */ true,
            AppDatabase.MIGRATION_3_4
        )

        db.query("SELECT collectionSyncScopes, startupSettings FROM databaseConfigs").use { cursor ->
            assertNotNull(cursor)
            org.junit.Assert.assertTrue(cursor.moveToFirst())
            org.junit.Assert.assertEquals("[]", cursor.getString(0))
            org.junit.Assert.assertEquals("[]", cursor.getString(1))
        }
        db.close()
    }

    companion object {
        private const val TEST_DB = "migration-test.db"

        // Keep in sync with @Database(version = ...) on AppDatabase.
        private const val CURRENT_VERSION = 4
    }
}
