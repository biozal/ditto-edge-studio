package com.costoda.dittoedgestudio.domain.model

import com.ditto.kotlin.DittoLogLevel
import java.util.Date
import java.util.UUID

data class LogEntry(
    val id: UUID = UUID.randomUUID(),
    val timestamp: Date,
    val level: DittoLogLevel,
    val message: String,
    val component: LogComponent,
    val source: LogEntrySource,
    val rawLine: String,
)

enum class LogComponent(val displayName: String) {
    ALL("All"),
    SYNC("Sync"),
    STORE("Store"),
    QUERY("Query"),
    OBSERVER("Observer"),
    TRANSPORT("Transport"),
    AUTH("Auth"),
    OTHER("Other");

    companion object {
        fun from(target: String): LogComponent {
            val lower = target.lowercase()
            return when {
                "sync" in lower -> SYNC
                "store" in lower -> STORE
                "query" in lower -> QUERY
                "observer" in lower -> OBSERVER
                "transport" in lower || "network" in lower || "bluetooth" in lower || "wifi" in lower -> TRANSPORT
                "auth" in lower -> AUTH
                else -> OTHER
            }
        }

        fun heuristic(message: String): LogComponent {
            val lower = message.lowercase()
            return when {
                lower.startsWith("[sync") || "sync::" in lower -> SYNC
                lower.startsWith("[store") || "store::" in lower -> STORE
                lower.startsWith("[query") || "query::" in lower -> QUERY
                lower.startsWith("[observer") || "observer::" in lower -> OBSERVER
                lower.startsWith("[transport") || "transport::" in lower ||
                    "bluetooth" in lower || "wifi" in lower -> TRANSPORT
                lower.startsWith("[auth") || "auth::" in lower -> AUTH
                else -> OTHER
            }
        }
    }
}

sealed class LogEntrySource {
    object DittoSDK : LogEntrySource()
    object Application : LogEntrySource()
}

val DittoLogLevel.displayName: String
    get() = when (this) {
        DittoLogLevel.Error -> "Error"
        DittoLogLevel.Warning -> "Warning"
        DittoLogLevel.Info -> "Info"
        DittoLogLevel.Debug -> "Debug"
        DittoLogLevel.Verbose -> "Verbose"
    }

val DittoLogLevel.shortName: String
    get() = when (this) {
        DittoLogLevel.Error -> "ERR"
        DittoLogLevel.Warning -> "WARN"
        DittoLogLevel.Info -> "INFO"
        DittoLogLevel.Debug -> "DBG"
        DittoLogLevel.Verbose -> "VERB"
    }
