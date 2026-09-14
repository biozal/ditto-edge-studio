package com.costoda.dittoedgestudio.data.logging

import com.ditto.kotlin.DittoLogLevel

/**
 * Translation between [DittoLogLevel] and the string stored on
 * `DittoDatabase.logLevel`.
 *
 * ## Why this exists
 *
 * SwiftUI persists the SDK log level chosen in the Logs toolbar onto the active
 * database config (`LoggingDetailView` → `DittoManager.changeDittoLogLevel`), so
 * the choice survives a relaunch. The Android equivalent is
 * `DittoDatabase.logLevel` — the same field the Database Editor's "Log Level"
 * dropdown writes, persisted by `DatabaseConfigEntity.logLevel` — which the Logs
 * screen previously ignored, setting only the in-process
 * `DittoLogger.minimumLogLevel`.
 *
 * The string vocabulary is fixed by the editor's `logLevelOptions` and by rows
 * already in the Room database; it is not free to change here.
 */
internal fun sdkLogLevelConfigValue(level: DittoLogLevel): String = when (level) {
    DittoLogLevel.Error -> "error"
    DittoLogLevel.Warning -> "warning"
    DittoLogLevel.Info -> "info"
    DittoLogLevel.Debug -> "debug"
    DittoLogLevel.Verbose -> "verbose"
}

/**
 * Parses a stored `DittoDatabase.logLevel` back to a [DittoLogLevel].
 *
 * Returns null for an unrecognised or absent value rather than guessing, so the
 * caller can fall back to whatever the SDK is currently set to instead of
 * silently re-writing a config it could not read.
 */
internal fun sdkLogLevelFromConfigValue(raw: String?): DittoLogLevel? = when (raw?.trim()?.lowercase()) {
    "error" -> DittoLogLevel.Error
    "warning", "warn" -> DittoLogLevel.Warning
    "info" -> DittoLogLevel.Info
    "debug" -> DittoLogLevel.Debug
    "verbose", "trace" -> DittoLogLevel.Verbose
    else -> null
}
