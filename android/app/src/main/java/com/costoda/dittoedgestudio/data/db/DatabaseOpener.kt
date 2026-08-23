package com.costoda.dittoedgestudio.data.db

import android.content.Context
import android.util.Log
import com.costoda.dittoedgestudio.BuildConfig

/**
 * Single seam that builds the [AppDatabase] and proves it can actually be opened with
 * the current Keystore-derived passphrase, BEFORE any feature code touches a DAO and
 * crashes on first query.
 *
 * Why a probe? Room's `databaseBuilder.build()` is lazy — it returns an [AppDatabase]
 * handle without opening the underlying SQLite file. The decrypt failure surfaces on
 * first DAO call (typically a `Flow<List<T>>` collect deep inside a screen), which
 * crashes the app well after the UI has tried to render. Calling a trivial
 * `SELECT 1` here forces the open + decrypt path on startup so we can surface a
 * proper recovery screen instead.
 *
 * See plans/android/config-loss-investigation.md (item B3).
 */
class DatabaseOpener(
    private val context: Context,
    private val keyManager: DatabaseKeyManager,
    private val factory: (Context, ByteArray) -> AppDatabase = AppDatabase.Companion::create,
) {

    @Volatile
    private var cachedResult: DatabaseOpenResult? = null

    /**
     * Builds the [AppDatabase] and runs a one-shot `SELECT 1` probe to force SQLCipher
     * to actually open the underlying file. Returns [DatabaseOpenResult.Ok] on success
     * or [DatabaseOpenResult.KeyFailure] with the captured throwable on any failure
     * during build or probe.
     *
     * Result is cached so the Koin `single<AppDatabase>` factory and the
     * `AppHealthViewModel` startup probe share one open — repeated calls return the
     * same [DatabaseOpenResult.Ok] instance (and therefore the same AppDatabase
     * handle). Call [invalidate] after a recovery to force a fresh open.
     *
     * Safe to call on a background thread; the caller is responsible for not blocking
     * the main thread.
     */
    @Synchronized
    fun openAndProbe(): DatabaseOpenResult {
        cachedResult?.let { return it }
        val result = doOpenAndProbe()
        cachedResult = result
        return result
    }

    /**
     * Discard the cached open result. Called by the recovery path after the DB file
     * has been deleted so the next `openAndProbe()` runs a fresh open against the
     * regenerated key + clean disk state.
     */
    @Synchronized
    fun invalidate() {
        cachedResult = null
    }

    private fun doOpenAndProbe(): DatabaseOpenResult {
        return try {
            val key = keyManager.getOrCreateKey()
            val db = factory(context, key)
            // Force the open path. Touching `readableDatabase` makes the underlying
            // SupportSQLiteOpenHelper open + decrypt the file; running a `SELECT 1`
            // proves we can actually read it. A wrong key throws on either step.
            // We do NOT close the SupportSQLiteDatabase here — it's owned by Room
            // and is the same handle subsequent DAO calls will use.
            val sqlDb = db.openHelper.readableDatabase
            sqlDb.query("SELECT 1").use { cursor ->
                cursor.moveToFirst()
            }
            DatabaseOpenResult.Ok(db)
        } catch (t: Throwable) {
            // Gated: SQLCipher/native error text can embed file paths and key-material
            // diagnostics. The user-facing summary still flows via DatabaseOpenResult.
            if (BuildConfig.DEBUG) {
                Log.e(TAG, "Database open/probe failed: ${t.javaClass.simpleName}: ${t.message}", t)
            }
            DatabaseOpenResult.KeyFailure(
                throwable = t,
                errorSummary = summarize(t),
            )
        }
    }

    private fun summarize(t: Throwable): String {
        // Short single-line summary safe for clipboard. Walks the cause chain so the
        // user can paste something diagnostic to a maintainer (SQLCipher wraps the
        // underlying error inside SQLiteException; we surface both layers).
        val chain = generateSequence(t as Throwable?) { it.cause }.take(4).toList()
        return chain.joinToString(separator = " | ") {
            "${it.javaClass.simpleName}: ${it.message ?: "(no message)"}"
        }
    }

    companion object {
        private const val TAG = "DatabaseOpener"
    }
}
