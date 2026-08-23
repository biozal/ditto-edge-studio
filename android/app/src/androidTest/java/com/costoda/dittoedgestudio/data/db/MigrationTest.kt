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
 *  1. The current schema JSON (6.json) exists, is readable, and matches the
 *     entities/DAOs compiled into the app — i.e. KSP is still exporting on
 *     every build and the latest schema is committed.
 *  2. The full migration chain (v1 -> v6) runs without throwing and
 *     produces a schema that validates against 6.json — i.e. the
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
     * Validates the current schema (v6) by creating a fresh DB at the current
     * version and then opening it through the real Room builder. Room compares
     * the live entity hash against the exported schema JSON and throws if they
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
            .addMigrations(
                AppDatabase.MIGRATION_1_2,
                AppDatabase.MIGRATION_2_3,
                AppDatabase.MIGRATION_3_4,
                AppDatabase.MIGRATION_4_5,
                AppDatabase.MIGRATION_5_6,
            )
            // No fallbackToDestructiveMigration — see AppDatabase.create() comment.
            .build()

        // Open + close to force Room to validate the live schema against
        // the exported JSON. A mismatch throws IllegalStateException here.
        assertNotNull(db.openHelper.writableDatabase)
        db.close()
    }

    /**
     * Walks the full migration chain v1 -> v6 to make sure the
     * hand-written migrations still produce a schema that matches the
     * exported v6 JSON.
     */
    @Test
    fun migrate1To6_preservesSchema() {
        helper.createDatabase(TEST_DB, 1).close()

        helper.runMigrationsAndValidate(
            TEST_DB,
            CURRENT_VERSION,
            /* validateDroppedTables = */ true,
            AppDatabase.MIGRATION_1_2,
            AppDatabase.MIGRATION_2_3,
            AppDatabase.MIGRATION_3_4,
            AppDatabase.MIGRATION_4_5,
            AppDatabase.MIGRATION_5_6
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
            4,
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

    /**
     * v4 -> v5 adds `query_metrics.query_text` with a `''` default; existing rows must
     * survive with an empty query text.
     */
    @Test
    fun migrate4To5_addsQueryTextColumnWithEmptyDefault() {
        helper.createDatabase(TEST_DB, 4).apply {
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
            execSQL(
                """
                INSERT INTO history (databaseId, query, createdDate)
                VALUES ('db-migrated', 'SELECT * FROM tasks', 1)
                """.trimIndent()
            )
            execSQL(
                """
                INSERT INTO query_metrics (
                    history_id, execution_time_ms, docs_examined, docs_returned,
                    indexes_used, bytes_read, explain_plan, captured_at
                ) VALUES (1, 7, 3, 3, '[]', 0, NULL, 1)
                """.trimIndent()
            )
            close()
        }

        val db = helper.runMigrationsAndValidate(
            TEST_DB,
            5,
            /* validateDroppedTables = */ true,
            AppDatabase.MIGRATION_4_5
        )

        db.query("SELECT query_text FROM query_metrics").use { cursor ->
            assertNotNull(cursor)
            org.junit.Assert.assertTrue(cursor.moveToFirst())
            org.junit.Assert.assertEquals("", cursor.getString(0))
        }
        db.close()
    }

    /**
     * v5 -> v6 rebuilds `query_metrics` WITHOUT the `history_id` foreign key (the
     * ON DELETE CASCADE let history housekeeping wipe metrics captures) and adds
     * `database_id` for per-database scoping. Existing rows must survive the
     * create/copy/drop/rename rebuild with `database_id` backfilled to ''.
     */
    @Test
    fun migrate5To6_dropsForeignKeyAndPreservesRows() {
        helper.createDatabase(TEST_DB, 5).apply {
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
            execSQL(
                """
                INSERT INTO history (databaseId, query, createdDate)
                VALUES ('db-migrated', 'SELECT * FROM tasks', 1)
                """.trimIndent()
            )
            execSQL(
                """
                INSERT INTO query_metrics (
                    history_id, execution_time_ms, docs_examined, docs_returned,
                    indexes_used, bytes_read, explain_plan, captured_at, query_text
                ) VALUES (1, 7, 3, 3, '[]', 0, NULL, 1, 'SELECT * FROM tasks')
                """.trimIndent()
            )
            execSQL(
                """
                INSERT INTO query_metrics (
                    history_id, execution_time_ms, docs_examined, docs_returned,
                    indexes_used, bytes_read, explain_plan, captured_at, query_text
                ) VALUES (1, 9, 5, 5, '["index"]', 0, 'plan', 2, 'SELECT * FROM tasks')
                """.trimIndent()
            )
            close()
        }

        val db = helper.runMigrationsAndValidate(
            TEST_DB,
            CURRENT_VERSION,
            /* validateDroppedTables = */ true,
            AppDatabase.MIGRATION_5_6
        )

        // Both rows survive, ids and payloads intact, database_id backfilled to ''.
        db.query(
            "SELECT id, history_id, database_id, execution_time_ms, query_text " +
                "FROM query_metrics ORDER BY id"
        ).use { cursor ->
            assertNotNull(cursor)
            org.junit.Assert.assertTrue(cursor.moveToFirst())
            org.junit.Assert.assertEquals(1L, cursor.getLong(0))
            org.junit.Assert.assertEquals(1L, cursor.getLong(1))
            org.junit.Assert.assertEquals("", cursor.getString(2))
            org.junit.Assert.assertEquals(7L, cursor.getLong(3))
            org.junit.Assert.assertEquals("SELECT * FROM tasks", cursor.getString(4))
            org.junit.Assert.assertTrue(cursor.moveToNext())
            org.junit.Assert.assertEquals(2L, cursor.getLong(0))
            org.junit.Assert.assertEquals("", cursor.getString(2))
            org.junit.Assert.assertEquals(9L, cursor.getLong(3))
            org.junit.Assert.assertFalse(cursor.moveToNext())
        }

        // The FK is gone: deleting the referenced history row must NOT cascade-wipe
        // the metrics captures. (Enforce FKs explicitly — the helper's framework
        // SQLite database does not enable them by default.)
        db.execSQL("PRAGMA foreign_keys=ON")
        db.execSQL("DELETE FROM history WHERE _id = 1")
        db.query("SELECT COUNT(*) FROM query_metrics").use { cursor ->
            assertNotNull(cursor)
            org.junit.Assert.assertTrue(cursor.moveToFirst())
            org.junit.Assert.assertEquals(2, cursor.getInt(0))
        }
        db.close()
    }

    companion object {
        private const val TEST_DB = "migration-test.db"

        // Keep in sync with @Database(version = ...) on AppDatabase.
        private const val CURRENT_VERSION = 6
    }
}
