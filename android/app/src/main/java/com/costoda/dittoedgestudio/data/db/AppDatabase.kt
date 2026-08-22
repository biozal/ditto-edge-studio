package com.costoda.dittoedgestudio.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.costoda.dittoedgestudio.data.db.dao.DatabaseConfigDao
import com.costoda.dittoedgestudio.data.db.dao.FavoriteDao
import com.costoda.dittoedgestudio.data.db.dao.HistoryDao
import com.costoda.dittoedgestudio.data.db.dao.ObservableDao
import com.costoda.dittoedgestudio.data.db.dao.QueryMetricsDao
import com.costoda.dittoedgestudio.data.db.dao.SubscriptionDao
import com.costoda.dittoedgestudio.data.db.entity.DatabaseConfigEntity
import com.costoda.dittoedgestudio.data.db.entity.FavoriteEntity
import com.costoda.dittoedgestudio.data.db.entity.HistoryEntity
import com.costoda.dittoedgestudio.data.db.entity.ObservableEntity
import com.costoda.dittoedgestudio.data.db.entity.QueryMetricsEntity
import com.costoda.dittoedgestudio.data.db.entity.SubscriptionEntity
import net.zetetic.database.sqlcipher.SupportOpenHelperFactory

@Database(
    entities = [
        DatabaseConfigEntity::class,
        SubscriptionEntity::class,
        HistoryEntity::class,
        FavoriteEntity::class,
        ObservableEntity::class,
        QueryMetricsEntity::class,
    ],
    version = 4,
    exportSchema = true
)
abstract class AppDatabase : RoomDatabase() {

    abstract fun databaseConfigDao(): DatabaseConfigDao
    abstract fun subscriptionDao(): SubscriptionDao
    abstract fun historyDao(): HistoryDao
    abstract fun favoriteDao(): FavoriteDao
    abstract fun observableDao(): ObservableDao
    abstract fun queryMetricsDao(): QueryMetricsDao

    companion object {
        private const val DB_NAME = "ditto_edge_studio.db"

        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    "ALTER TABLE databaseConfigs ADD COLUMN isStrictModeEnabled INTEGER NOT NULL DEFAULT 0"
                )
            }
        }

        val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `query_metrics` (
                        `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        `history_id` INTEGER NOT NULL,
                        `execution_time_ms` INTEGER NOT NULL,
                        `docs_examined` INTEGER NOT NULL,
                        `docs_returned` INTEGER NOT NULL,
                        `indexes_used` TEXT NOT NULL,
                        `bytes_read` INTEGER NOT NULL,
                        `explain_plan` TEXT,
                        `captured_at` INTEGER NOT NULL,
                        FOREIGN KEY(`history_id`) REFERENCES `history`(`_id`) ON DELETE CASCADE
                    )
                    """.trimIndent()
                )
                database.execSQL(
                    "CREATE INDEX IF NOT EXISTS `index_query_metrics_history_id` ON `query_metrics` (`history_id`)"
                )
            }
        }

        val MIGRATION_3_4 = object : Migration(3, 4) {
            override fun migrate(database: SupportSQLiteDatabase) {
                // Advanced Database Configuration (docs/ADVANCED_DATABASE_CONFIG.md):
                // per-database collection sync scopes and startup system settings,
                // stored as JSON-in-TEXT.
                database.execSQL(
                    "ALTER TABLE databaseConfigs ADD COLUMN collectionSyncScopes TEXT NOT NULL DEFAULT '[]'"
                )
                database.execSQL(
                    "ALTER TABLE databaseConfigs ADD COLUMN startupSettings TEXT NOT NULL DEFAULT '[]'"
                )
            }
        }

        // Migration policy (see plans/android/config-loss-investigation.md item B1):
        // - Every schema version bump REQUIRES a hand-written Migration AND a committed
        //   schema JSON under app/schemas/.../<version>.json (validated by MigrationTest).
        // - DO NOT re-add .fallbackToDestructiveMigration(...) / .fallbackToDestructiveMigrationOnDowngrade().
        //   Missing-migration failures are intentional: Room will throw IllegalStateException
        //   on app launch, surfacing the bug in QA instead of silently wiping every saved
        //   database config, subscription, observer, favorite, and history row in production.
        fun create(context: Context, key: ByteArray): AppDatabase =
            Room.databaseBuilder(context, AppDatabase::class.java, DB_NAME)
                .openHelperFactory(SupportOpenHelperFactory(key))
                .addMigrations(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4)
                .build()
    }
}
