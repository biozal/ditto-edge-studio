package com.costoda.dittoedgestudio.data.logging

import com.costoda.dittoedgestudio.domain.model.LogEntry
import java.util.Date
import org.json.JSONObject

/**
 * A physical connection between this peer and a remote peer, reconstructed from
 * the SDK's `physical connection started` / `physical connection ended` log
 * lines.
 */
data class ConnectionSession(
    val start: Date,
    val end: Date? = null,
    val remotePeer: String,
    val transport: String,
    val role: String,
    val connectionId: String?,
) {
    /** Seconds the connection was open, or null while it is still open. */
    val duration: Double?
        get() = end?.let { (it.time - start.time) / 1000.0 }
}

/**
 * One parsed connection lifecycle event.
 *
 * ## Why this is not a single regex
 *
 * The SDK emits the *same* logical event in two different encodings, and this
 * app consumes both:
 *
 * - **Live capture** (`DittoLogger` callback) delivers a flattened text line
 *   whose body carries `key=value` pairs:
 *   `physical connection started remote=pkAoc… role=Client transport_type=Awdl connection_id=9`
 * - **Historical capture** ([LogFileParser]) reads the SDK's rotating
 *   `ditto_logs` `.log` files, which are **JSON Lines**. There the message is
 *   just `"physical connection started"` and the fields are siblings of it in
 *   the JSON object.
 *
 * A `remote=([^\s]+)` regex — the shape the VS Code extension uses, where only
 * the flattened encoding exists — matches **nothing** in the file encoding, so
 * [extract] tries the structured form first (the JSON is retained verbatim on
 * [LogEntry.rawLine]) and falls back to the flattened form.
 *
 * ## `connection_id` lives under `span` most of the time
 *
 * Measured over five real captures (156 `physical connection …` records): only
 * 38 carry a top-level `connection_id`, while 127 carry it as
 * `span.connection_id`. Reading only the top-level key — as the SwiftUI port
 * currently does — drops the exact match key on the majority of records and
 * silently falls back to fuzzy `remote::role` pairing. [extract] therefore reads
 * the top-level key **and** `span.connection_id`.
 */
data class LogConnectionEvent(
    val kind: Kind,
    val timestamp: Date,
    val remotePeer: String,
    val transport: String,
    val role: String,
    val connectionId: String?,
) {
    enum class Kind {
        STARTED,
        ENDED,

        /** Ditto re-initialised; every open connection is implicitly torn down. */
        REINIT,
    }

    companion object {
        internal const val UNKNOWN = "unknown"

        private val REMOTE = Regex("""remote=([^\s]+)""", RegexOption.IGNORE_CASE)
        private val TRANSPORT = Regex("""transport_type=([^\s]+)""", RegexOption.IGNORE_CASE)
        private val ROLE = Regex("""role=([^\s]+)""", RegexOption.IGNORE_CASE)
        private val CONNECTION_ID = Regex("""connection_id=([^\s]+)""", RegexOption.IGNORE_CASE)

        /**
         * The one line the SDK emits on every `ditto_init`, in **both**
         * encodings — as the JSON record
         * `{"message":"starting Ditto...","sdk.version":"5.1.0",…}` and, from the
         * live `DittoLogger` callback, as `ditto_init: starting Ditto... sdk.version=…`.
         *
         * Measured over all 31 real captures (663 807 JSON Lines records):
         *
         * | signal | count |
         * |---|---|
         * | `"starting Ditto"` in the **message** field | 14 |
         * | records with no `message` key that mention `ditto_init` | 11 |
         * | `ditto_init` in the **message** field | 0 |
         * | `ditto_init` anywhere on the raw line | 399 |
         *
         * The bare token `ditto_init` is therefore useless as a message probe —
         * it never appears in a message, only inside `span` / `spans` / `path`
         * values of ~399 unrelated records.
         *
         * The no-`message`-key rule the fix brief proposed as an alternative is
         * **not** 1:1 with init: it fires 11 times against 14 real inits. The
         * three it misses (`mongodb sample`, `mongodb-movies`, and
         * `quickstarts/…21-31-02`) contain the `starting Ditto...` INFO record but
         * no `{"span":{"name":"ditto_init"},…}` DEBUG record at all. So this
         * probe keys on `starting Ditto`, which is a strict superset and is
         * semantically the init rather than an artefact of a parser fallback.
         *
         * Where both signals are present the span marker precedes
         * `starting Ditto` by 5.3–24.4 ms, i.e. they are the same init event.
         */
        private const val REINIT_MARKER = "starting Ditto"

        /**
         * Parses a connection lifecycle event out of [entry], or returns null
         * when the entry is not one. Cheap for the overwhelming majority of
         * lines: a substring prefilter runs before any regex or JSON work.
         */
        fun extract(entry: LogEntry): LogConnectionEvent? {
            // Cheap prefilter, over whatever the parser called the message. Every
            // branch below needs one of these substrings and ~99.9% of log lines
            // contain none of them, so this is the only work most lines pay for.
            // It is a deliberate superset: a real event always contains one of
            // these substrings too, and the authoritative re-check below drops
            // the extras. `ditto_init` is kept here purely so the message-scoping
            // below is the thing that rejects the ~399 `span`/`path` mentions,
            // rather than the prefilter hiding them.
            if (!entry.message.contains("physical connection", ignoreCase = true) &&
                !entry.message.contains(REINIT_MARKER, ignoreCase = true) &&
                !entry.message.contains("ditto_init")
            ) {
                return null
            }

            // Authoritative message. `LogFileParser` falls back to the *whole raw
            // JSON line* when a record carries no `message` key — 22 such records
            // in the real captures — which drags `span` and `path` values into
            // the message. Re-derive the message from the JSON so the probes
            // below are scoped to the message field, as the spec requires.
            val json = jsonObject(entry.rawLine)
            val message = if (json != null) {
                json.optNonEmptyString("message") ?: json.optNonEmptyString("msg") ?: ""
            } else {
                entry.message
            }

            val isConnectionLine = message.contains("physical connection", ignoreCase = true)
            val isReinitLine = !isConnectionLine && message.contains(REINIT_MARKER, ignoreCase = true)
            if (!isConnectionLine && !isReinitLine) return null

            if (isReinitLine) {
                // A genuine init. `ditto_init` fires when the user switches
                // databases, not when the app dies — the process keeps running
                // and keeps logging — so a connection that was still open really
                // did last right up to this instant, and closing it here records
                // an accurate duration. Measured over the real captures: the gap
                // between the last log line and the init is ≤7 ms at all 14 inits,
                // and closing on them recovers 28 sessions (279 → 307 closed) that
                // previously stayed open forever and never reached the Connection
                // Durations histogram — the longest of them ran 22.9 hours.
                return LogConnectionEvent(
                    kind = Kind.REINIT,
                    timestamp = entry.timestamp,
                    remotePeer = UNKNOWN,
                    transport = UNKNOWN,
                    role = UNKNOWN,
                    connectionId = null,
                )
            }

            // "physical connection ended (extended info)" is a separate DEBUG
            // record that duplicates the INFO one; counting both would close
            // every session twice.
            val lower = message.lowercase()
            if (lower.contains("(extended info)")) return null

            val kind = when {
                lower.contains("started") -> Kind.STARTED
                lower.contains("ended") -> Kind.ENDED
                // e.g. "Physical connection shutting down" — not a lifecycle
                // edge; the matching "ended" record carries the fields we need.
                else -> return null
            }

            structuredFields(json)?.let { fields ->
                return LogConnectionEvent(
                    kind = kind,
                    timestamp = entry.timestamp,
                    remotePeer = fields.remote,
                    transport = fields.transport,
                    role = fields.role,
                    connectionId = fields.connectionId,
                )
            }

            return LogConnectionEvent(
                kind = kind,
                timestamp = entry.timestamp,
                remotePeer = REMOTE.capture(message) ?: UNKNOWN,
                transport = TRANSPORT.capture(message) ?: UNKNOWN,
                role = ROLE.capture(message) ?: UNKNOWN,
                connectionId = CONNECTION_ID.capture(message),
            )
        }

        /** Connection fields as carried by the JSON Lines encoding. */
        private data class StructuredFields(
            val remote: String,
            val transport: String,
            val role: String,
            val connectionId: String?,
        )

        /**
         * Parses [rawLine] as a JSON Lines record, or returns null for the
         * flattened text encoding. The `{` probe keeps the JSON parser off the
         * hot path for live-callback lines.
         */
        private fun jsonObject(rawLine: String): JSONObject? {
            if (!rawLine.trimStart().startsWith("{")) return null
            return runCatching { JSONObject(rawLine) }.getOrNull()
        }

        /**
         * Returns null for the flattened text encoding, so the caller falls back
         * to regex over the message body.
         */
        private fun structuredFields(json: JSONObject?): StructuredFields? {
            if (json == null) return null
            return StructuredFields(
                remote = json.optNonEmptyString("remote") ?: UNKNOWN,
                transport = json.optNonEmptyString("transport_type") ?: UNKNOWN,
                role = json.optNonEmptyString("role") ?: UNKNOWN,
                // Top level first, then the nested span — 127 of 156 real
                // records only carry it there.
                connectionId = json.optNonEmptyString("connection_id")
                    ?: json.optJSONObject("span")?.optNonEmptyString("connection_id"),
            )
        }

        /**
         * Reads a JSON value as a string permissively — `connection_id` is a
         * string in every capture inspected, but a numeric encoding would
         * otherwise silently drop the best available match key.
         */
        private fun JSONObject.optNonEmptyString(key: String): String? {
            if (!has(key) || isNull(key)) return null
            val value = opt(key) ?: return null
            if (value is JSONObject || value is org.json.JSONArray) return null
            return value.toString().takeIf { it.isNotEmpty() }
        }

        private fun Regex.capture(text: String): String? =
            find(text)?.groupValues?.getOrNull(1)?.takeIf { it.isNotEmpty() }
    }
}

/**
 * Pairs `physical connection started` / `ended` events into [ConnectionSession]s,
 * which feed the Connection Durations buckets.
 *
 * Port of the VS Code extension's `ConnectionTracker`, including the bounds that
 * file records as having been bugs — every history list is capped, the open-session
 * list included (a `started` whose `ended` never arrives, from a killed process or
 * a truncated log, would otherwise leak for the life of the view).
 */
class LogConnectionTracker {

    private val openList = ArrayList<ConnectionSession>()
    private val closedList = ArrayList<ConnectionSession>()
    private val reinitList = ArrayList<Date>()

    /** Re-init instants seen, oldest first. */
    val reinits: List<Date> get() = reinitList.toList()

    /**
     * `ended` events with no matching open session — a truncated log tail, or a
     * connection opened before capture started. Surfaced for diagnostics rather
     * than silently dropped.
     */
    var unmatchedEnds: Int = 0
        private set

    /** All sessions seen, closed ones first. Open sessions have `end == null`. */
    val sessions: List<ConnectionSession> get() = closedList + openList

    /**
     * Sessions that actually closed — the only ones with a duration, and so the
     * only ones the durations buckets can bin.
     */
    val closedSessions: List<ConnectionSession> get() = closedList.toList()

    fun consume(entry: LogEntry) {
        LogConnectionEvent.extract(entry)?.let { consume(it) }
    }

    fun consume(event: LogConnectionEvent) {
        when (event.kind) {
            LogConnectionEvent.Kind.REINIT -> {
                // Ditto restarted: everything still open ended at this instant.
                openList.forEach { closedList.add(it.copy(end = event.timestamp)) }
                openList.clear()
                reinitList.add(event.timestamp)
                trim(reinitList)
                trim(closedList)
            }

            LogConnectionEvent.Kind.STARTED -> {
                openList.add(
                    ConnectionSession(
                        start = event.timestamp,
                        end = null,
                        remotePeer = event.remotePeer,
                        transport = event.transport,
                        role = event.role,
                        connectionId = event.connectionId,
                    ),
                )
                trim(openList)
            }

            LogConnectionEvent.Kind.ENDED -> {
                // Match the most recently opened session with this key, not the
                // oldest: the SDK reuses `connection_id` values, so last-in
                // first-out pairs a close with the connection it belongs to.
                val index = openList.indexOfLast { matches(it, event) }
                if (index < 0) {
                    unmatchedEnds++
                    return
                }
                val session = openList.removeAt(index)
                closedList.add(session.copy(end = event.timestamp))
                trim(closedList)
            }
        }
    }

    /**
     * Prefer `connection_id` — it identifies one physical connection exactly.
     * Fall back to `remote::role` (what the VS Code tracker keys on) when the id
     * is absent, which happens for log lines that predate it.
     */
    private fun matches(session: ConnectionSession, event: LogConnectionEvent): Boolean {
        val sessionId = session.connectionId
        val eventId = event.connectionId
        if (sessionId != null && eventId != null) return sessionId == eventId
        return session.remotePeer == event.remotePeer && session.role == event.role
    }

    /**
     * Drops all history. Without clearing every list, "Clear" appears to work and
     * the next connection event resurrects the pre-Clear sessions, because
     * [sessions] is rebuilt from these lists rather than from what the view last
     * displayed.
     */
    fun reset() {
        openList.clear()
        closedList.clear()
        reinitList.clear()
        unmatchedEnds = 0
    }

    /** Trimmed in chunks so the per-event cost stays amortized O(1). */
    private fun <T> trim(list: MutableList<T>) {
        if (list.size > SESSION_HISTORY_CAP * 2) {
            val excess = list.size - SESSION_HISTORY_CAP
            list.subList(0, excess).clear()
        }
    }

    companion object {
        /** Upper bound on retained sessions per bucket. */
        const val SESSION_HISTORY_CAP = 1_000

        /** Builds a tracker from a whole buffer in one pass. */
        fun track(entries: List<LogEntry>): LogConnectionTracker {
            val tracker = LogConnectionTracker()
            for (entry in entries) tracker.consume(entry)
            return tracker
        }
    }
}
