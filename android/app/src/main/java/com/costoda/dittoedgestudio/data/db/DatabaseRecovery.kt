package com.costoda.dittoedgestudio.data.db

import android.content.Context
import android.util.Log
import java.io.File

/**
 * User-driven recovery from an unopenable encrypted database (see [DatabaseOpenResult.KeyFailure]).
 *
 * **This is destructive.** It is invoked ONLY by an explicit user tap on
 * "Reset stored data" in `ui/recovery/KeyFailureScreen.kt`. There is no silent path
 * to this code — see plans/android/config-loss-investigation.md (item B3).
 *
 * Steps performed by [reset]:
 *  1. Delete the Room database file + its `-wal` / `-shm` / `-journal` sidecars.
 *  2. Delete the Ditto persistence directory (`<filesDir>/ditto`) — its on-disk
 *     state is keyed to a private key that no longer exists, so it is also
 *     unrecoverable.
 *  3. Wipe the Keystore alias + the stored encrypted passphrase so the next
 *     `DatabaseKeyManager.getOrCreateKey()` call generates a fresh key.
 *
 * After this returns successfully the caller should re-open the database (the
 * `AppHealthViewModel` does this via `DatabaseOpener.openAndProbe()`) and an
 * `Activity.recreate()` will land the user at the empty database list.
 */
class DatabaseRecovery(
    private val context: Context,
    private val keyManager: DatabaseKeyManager,
    private val opener: DatabaseOpener? = null,
) {

    /** @return `true` if every step completed without raising; `false` otherwise (best-effort). */
    fun reset(): Boolean {
        var ok = true
        ok = deleteRoomDatabaseFiles() && ok
        ok = deleteDittoPersistenceDirectory() && ok
        runCatching { keyManager.clearKey() }
            .onFailure { e ->
                Log.e(TAG, "Failed to clear keystore key: ${e.message}", e)
                ok = false
            }
        // Force the next openAndProbe() to do real work against the regenerated key
        // and clean disk state. Cached results from the failed-open path are stale now.
        opener?.invalidate()
        return ok
    }

    private fun deleteRoomDatabaseFiles(): Boolean {
        val main = context.getDatabasePath(DB_NAME)
        // -journal is the rollback journal (only present in non-WAL mode), -wal and
        // -shm are the WAL files. SQLCipher uses any combination of these depending
        // on the journal_mode pragma; we delete all of them defensively.
        val sidecars = listOf("$DB_NAME-wal", "$DB_NAME-shm", "$DB_NAME-journal")
            .map { File(main.parentFile, it) }

        val targets = listOf(main) + sidecars
        var ok = true
        for (file in targets) {
            if (!file.exists()) continue
            val deleted = runCatching { file.delete() }.getOrElse { false }
            if (!deleted) {
                Log.w(TAG, "Failed to delete ${file.absolutePath}")
                ok = false
            }
        }
        return ok
    }

    private fun deleteDittoPersistenceDirectory(): Boolean {
        val dittoDir = File(context.filesDir, DITTO_DIRECTORY_NAME)
        if (!dittoDir.exists()) return true
        return runCatching { dittoDir.deleteRecursively() }
            .onFailure { e -> Log.e(TAG, "Failed to delete ditto dir: ${e.message}", e) }
            .getOrElse { false }
    }

    companion object {
        private const val TAG = "DatabaseRecovery"
        // Must match AppDatabase.DB_NAME — kept here as a const because that one is private.
        private const val DB_NAME = "ditto_edge_studio.db"
        // Must match the directory excluded in res/xml/backup_rules.xml.
        private const val DITTO_DIRECTORY_NAME = "ditto"
    }
}
