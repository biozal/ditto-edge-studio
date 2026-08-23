package com.costoda.dittoedgestudio.data.db

/**
 * Outcome of attempting to open and probe the SQLCipher-encrypted [AppDatabase].
 *
 * Used by [DatabaseOpener] to surface decrypt / key-mismatch failures at app start
 * rather than crashing on first feature use. The key may become invalid outside the
 * app's control (OS security event, biometric/PIN reset on some OEMs, keystore
 * corruption, restored backup whose keystore key didn't travel). When that happens,
 * the user-driven recovery flow (see [DatabaseRecovery]) is the only way out.
 *
 * See plans/android/config-loss-investigation.md (item B3).
 */
sealed class DatabaseOpenResult {
    /** Database opened and a probe query (`SELECT 1`) succeeded. */
    data class Ok(val db: AppDatabase) : DatabaseOpenResult()

    /**
     * Database could not be opened with the current Keystore-derived key.
     *
     * @property throwable original cause — typically a `SQLiteException` from
     *  SQLCipher when the passphrase doesn't match, but can also be a
     *  KeyStoreException / KeyPermanentlyInvalidatedException if the alias was
     *  invalidated by an OS security event.
     * @property errorSummary short single-line summary suitable for clipboard /
     *  error log (does NOT include the stack trace).
     */
    data class KeyFailure(
        val throwable: Throwable,
        val errorSummary: String,
    ) : DatabaseOpenResult()
}
