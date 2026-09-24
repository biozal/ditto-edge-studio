package com.costoda.dittoedgestudio.data.logging

import com.costoda.dittoedgestudio.domain.model.LogPattern
import com.costoda.dittoedgestudio.domain.model.LogPatternBody
import com.costoda.dittoedgestudio.domain.model.PatternSource
import com.costoda.dittoedgestudio.domain.model.parseLevelFilter
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Loads, validates and persists the log-analysis pattern catalog (parity port of
 * the VS Code extension's `PatternStore`).
 *
 * Sources:
 * - **Bundled** — `assets/problem_patterns.json` (read-only catalog of known
 *   Ditto problem signatures).
 * - **User** — `<filesDir>/log-analyzer/user_patterns.json`, same JSON shape.
 *
 * A user pattern cannot reuse a bundled key. Invalid entries are dropped from
 * [patterns] and reported via [patternErrors]; a missing/corrupt user file is
 * tolerated (empty catalog).
 */
class LogPatternStore(
    private val userPatternsFile: File,
    private val bundledJsonLoader: () -> String?,
    private val json: Json = Json { ignoreUnknownKeys = true },
) {

    // Declared before _patterns: the initial loadAll() publishes errors.
    private val _patternErrors = MutableStateFlow<Map<String, String>>(emptyMap())
    /** key → rejection reason for entries that failed validation. */
    val patternErrors: StateFlow<Map<String, String>> = _patternErrors.asStateFlow()

    private val _patterns = MutableStateFlow(loadAll())
    val patterns: StateFlow<Map<String, LogPattern>> = _patterns.asStateFlow()

    val bundledKeys: Set<String> get() = bundledBodies().keys

    private fun bundledBodies(): Map<String, LogPatternBody> =
        bundledJsonLoader()
            ?.let { raw -> runCatching { json.decodeFromString<Map<String, LogPatternBody>>(raw) }.getOrNull() }
            ?: emptyMap()

    private fun userBodies(): Map<String, LogPatternBody> {
        if (!userPatternsFile.exists()) return emptyMap()
        return runCatching {
            json.decodeFromString<Map<String, LogPatternBody>>(userPatternsFile.readText())
        }.getOrElse {
            emptyMap()
        }
    }

    private fun loadAll(): Map<String, LogPattern> {
        val errors = mutableMapOf<String, String>()
        val out = linkedMapOf<String, LogPattern>()

        fun addAll(bodies: Map<String, LogPatternBody>, source: PatternSource) {
            for ((key, body) in bodies) {
                val reason = LogPatternEngine.rejectReason(key, body, source)
                if (reason != null) {
                    errors[key] = reason
                    continue
                }
                out[key] = LogPattern(
                    key = key,
                    body = body,
                    severity = body.severity,
                    levelFilter = parseLevelFilter(body.levelFilter),
                    source = source,
                )
            }
        }

        addAll(bundledBodies(), PatternSource.BUNDLED)
        // User patterns may override bundled by key only via hand-editing the file,
        // matching the extension; add()/update() forbid bundled-key collisions.
        addAll(userBodies(), PatternSource.USER)

        _patternErrors.value = errors
        return out
    }

    /** Re-reads both sources — call after external edits of the user file. */
    fun reload() {
        _patterns.value = loadAll()
    }

    suspend fun add(key: String, body: LogPatternBody) = withContext(Dispatchers.IO) {
        require(!bundledKeys.contains(key)) { "key collides with a bundled pattern" }
        require(!userBodies().containsKey(key)) { "a pattern with this key already exists" }
        writeUser(userBodies() + (key to body))
        reload()
    }

    suspend fun update(key: String, body: LogPatternBody) = withContext(Dispatchers.IO) {
        require(userBodies().containsKey(key)) { "pattern '$key' is not a user pattern" }
        writeUser(userBodies().toMutableMap().apply { put(key, body) })
        reload()
    }

    suspend fun delete(key: String) = withContext(Dispatchers.IO) {
        require(userBodies().containsKey(key)) { "pattern '$key' is not a user pattern" }
        writeUser(userBodies().toMutableMap().apply { remove(key) })
        reload()
    }

    private fun writeUser(bodies: Map<String, LogPatternBody>) {
        userPatternsFile.parentFile?.mkdirs()
        // Write-temp-then-rename: a mid-write crash must not leave a corrupt
        // catalog file behind (Swift port writes atomically; keep parity).
        val payload = json.encodeToString(bodies)
        val tmp = File(userPatternsFile.parentFile, "${userPatternsFile.name}.tmp")
        tmp.writeText(payload)
        if (!tmp.renameTo(userPatternsFile)) {
            tmp.copyTo(userPatternsFile, overwrite = true)
            tmp.delete()
        }
    }
}
