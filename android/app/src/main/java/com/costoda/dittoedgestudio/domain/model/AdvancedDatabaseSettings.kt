package com.costoda.dittoedgestudio.domain.model

import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

// MARK: - Sync Scopes

/**
 * Where a single user collection is allowed to synchronize.
 *
 * The [dqlValue] strings are the literal values DQL expects in
 * `ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES` — they are a wire format, not a
 * display concern, so they must never be renamed. Note `SmallPeersOnly` is plural.
 *
 * There is deliberately **no** tolerant parser here. Sync scopes are a data
 * containment control: silently coercing an unrecognized value (say, a scope added
 * by a future SDK) into some other scope could let data leave a device the user
 * believed was local-only. An unknown value fails to decode instead.
 */
enum class SyncScope(val dqlValue: String, val displayName: String, val explanation: String) {
    AllPeers("AllPeers", "All Peers", "Ditto Server and Small Peers"),
    BigPeerOnly("BigPeerOnly", "Big Peer Only", "Ditto Server only"),
    SmallPeersOnly("SmallPeersOnly", "Small Peers Only", "Small Peers only"),
    LocalPeerOnly("LocalPeerOnly", "Local Peer Only", "never leaves this device"),
}

/**
 * One collection → scope mapping.
 *
 * [id] is a synthetic, stable identity, **not** the collection name. Using the
 * user-editable text as identity breaks three ways: two not-yet-named rows collide
 * on `""`, removing by id deletes every row sharing a name, and the identity changes
 * on every keystroke so the list tears the row's text field down and drops focus.
 * The collection name remains the *validation* key via [syncKey].
 *
 * [id] is serialized with the row so a decoded row still equals the row it was
 * encoded from; it carries no meaning beyond editor identity.
 */
@Serializable
data class CollectionSyncScope(
    val collection: String = "",
    val scope: SyncScope = SyncScope.AllPeers,
    val id: String = UUID.randomUUID().toString(),
) {
    /** The trimmed collection name — the key used for validation and DQL. */
    val syncKey: String get() = collection.trim()
}

// MARK: - Startup System Settings

/**
 * Value kinds offered for a startup `ALTER SYSTEM` setting.
 *
 * `ALTER SYSTEM` also accepts arrays; there is no dedicated array editor, but any
 * valid JSON document is accepted under [Json], so `["a","b"]` already produces a
 * real array.
 */
enum class StartupSettingType(val displayName: String) {
    String("String"),
    Json("JSON"),
    Integer("Integer"),
    Double("Double"),
    Boolean("Boolean"),
}

/**
 * A typed value on its way into `ditto.store.execute(query, arguments)`.
 *
 * Deliberately a closed type rather than `Any?`: the bridge to the SDK's argument
 * map happens at the execute call site.
 */
sealed interface DQLValue {
    data class StringValue(val value: String) : DQLValue
    data class IntValue(val value: Long) : DQLValue
    data class UIntValue(val value: ULong) : DQLValue
    data class DoubleValue(val value: Double) : DQLValue
    data class BoolValue(val value: Boolean) : DQLValue

    /** Raw JSON text, validated at construction and re-parsed at the call site. */
    data class JsonValue(val raw: String) : DQLValue

    /** The form the SDK's argument map expects (nested maps/lists for JSON). */
    fun argumentValue(): Any? = when (this) {
        is StringValue -> value
        is IntValue -> value
        is UIntValue -> value
        is DoubleValue -> value
        is BoolValue -> value
        is JsonValue -> raw.toPlainJson()
    }
}

/** Parses valid JSON text into plain maps/lists/primitives for the argument encoder. */
private fun String.toPlainJson(): Any? {
    val element = Json.parseToJsonElement(this)
    return element.toPlain()
}

private fun kotlinx.serialization.json.JsonElement.toPlain(): Any? = when (this) {
    is kotlinx.serialization.json.JsonNull -> null
    is kotlinx.serialization.json.JsonPrimitive -> when {
        isString -> content
        content == "true" || content == "false" -> content.toBoolean()
        content.contains('.') || content.contains('e', ignoreCase = true) ->
            content.toDoubleOrNull() ?: content.toLongOrNull() ?: content
        else -> content.toLongOrNull() ?: content.toULongOrNull() ?: content
    }
    is kotlinx.serialization.json.JsonObject -> mapValues { it.value.toPlain() }
    is kotlinx.serialization.json.JsonArray -> map { it.toPlain() }
}

/**
 * One startup `ALTER SYSTEM SET <parameter> = <value>` row.
 *
 * [value] is always stored as text — that keeps the model serializable and lets the
 * editor hold a single field type — and is coerced only when the statement is built.
 * [syncKey] (the trimmed parameter name) is the validation/DQL key; DQL treats
 * parameter names case-insensitively on write and reads them back lowercased, so
 * dedupe compares case-insensitively while the write preserves what was typed.
 */
@Serializable
data class StartupSetting(
    val parameter: String = "",
    val type: StartupSettingType = StartupSettingType.String,
    val value: String = "",
    /**
     * Set once the user has explicitly acknowledged a sensitive parameter name.
     *
     * **Persisted on purpose.** An acknowledgement held only in the view model would
     * mean a setting arriving from any non-UI ingress (a seeded config, a hand-edited
     * database, a future import) was applied with no prompt at all — including
     * `metrics_exporter_prometheus_http_listener_addr`, which opens a listening
     * socket on every interface. The apply path requires this flag.
     */
    val isAcknowledged: Boolean = false,
    val id: String = UUID.randomUUID().toString(),
) {
    /** The name used for validation, dedupe and DQL, trimmed. */
    val syncKey: String get() = parameter.trim()

    /**
     * The coerced value, or `null` when [value] does not parse as [type] — which the
     * editor surfaces as a row-level error and which blocks Save.
     */
    fun typedValue(): DQLValue? = when (type) {
        // Empty is legal: `transports_ble_adapter_mac` ships as "".
        StartupSettingType.String -> DQLValue.StringValue(value)

        StartupSettingType.Json -> {
            if (value.isEmpty()) return null
            val valid = runCatching { Json.parseToJsonElement(value) }.isSuccess
            if (valid) DQLValue.JsonValue(value) else null
        }

        StartupSettingType.Integer -> {
            // `Long` is not sufficient: real parameters ship as ULong.MAX, e.g.
            // `dql_request_history_log_dump_limit` == 18446744073709551615.
            value.toLongOrNull()?.let { return DQLValue.IntValue(it) }
            value.toULongOrNull()?.let { return DQLValue.UIntValue(it) }
            null
        }

        // Accepts scientific notation, e.g. "1.0000000000000001e-09".
        StartupSettingType.Double -> value.toDoubleOrNull()?.let { DQLValue.DoubleValue(it) }

        StartupSettingType.Boolean -> when (value.lowercase()) {
            "true" -> DQLValue.BoolValue(true)
            "false" -> DQLValue.BoolValue(false)
            else -> null
        }
    }

    companion object {
        /** Canonical picker values for [StartupSettingType.Boolean] rows. */
        val booleanValues = listOf("True", "False")

        /**
         * The canonical spelling of a boolean value, or `null` when the text is not
         * boolean at all. The value dropdown tags rows with these exact strings, so a
         * case variant — `true`, `FALSE` — is a *valid* setting that the dropdown
         * cannot render.
         */
        fun canonicalBooleanValue(value: String): String? =
            booleanValues.firstOrNull { it.equals(value, ignoreCase = true) }
    }
}

// MARK: - Apply Result

/**
 * What the apply pass actually managed to apply, returned rather than only logged so
 * tests and the UI can assert on it.
 */
data class AdvancedApplyResult(
    val appliedSettings: List<String> = emptyList(),
    val skippedSettings: List<Skipped> = emptyList(),
    val appliedScopeCount: Int = 0,
    /** True when scopes were written but the read-back could not confirm them. */
    val scopesUnverified: Boolean = false,
) {
    data class Skipped(val name: String, val reason: String)

    val hasFailures: Boolean get() = skippedSettings.isNotEmpty()
}

// MARK: - Storage JSON

/**
 * JSON-in-TEXT storage codec for the two advanced-configuration lists.
 *
 * Decoding is **strict** on purpose: an unknown scope value or a malformed row fails
 * rather than coercing to a default, because a sync scope is a containment control.
 * `ignoreUnknownKeys` only tolerates *new fields* added by a future version; it does
 * not rescue bad enum values.
 */
object AdvancedSettingsJson {
    private val json = Json { ignoreUnknownKeys = true }

    fun encodeScopes(scopes: List<CollectionSyncScope>): String =
        json.encodeToString(scopes)

    /** @throws kotlinx.serialization.SerializationException on unreadable input. */
    fun decodeScopes(raw: String): List<CollectionSyncScope> =
        json.decodeFromString(raw)

    fun encodeSettings(settings: List<StartupSetting>): String =
        json.encodeToString(settings)

    /** @throws kotlinx.serialization.SerializationException on unreadable input. */
    fun decodeSettings(raw: String): List<StartupSetting> =
        json.decodeFromString(raw)
}

// MARK: - Validation

/**
 * Pure validation shared by the editor and the apply path.
 *
 * The apply path is the real chokepoint — configs can reach it without passing
 * through the editor (seeded configs, imports, a future JSON import) — so every rule
 * lives here rather than in the view.
 */
object AdvancedSettingsValidator {
    /** Upper bound on a single setting value. */
    const val MAX_VALUE_LENGTH = 4096

    /** Upper bound on rows per list. */
    const val MAX_ROW_COUNT = 64

    /** Parameters the app owns through dedicated UI. */
    private val reservedParameterExactNames = setOf(
        "user_collection_sync_scopes",
        "dql_strict_mode",
        "mesh_chooser_max_wlan_clients",
        "data_sync_enabled",
    )

    /** Prefixes owned by the transport configuration UI. */
    private val reservedParameterPrefixes = listOf("transports_", "udp_")

    /**
     * Parameters that can expose data on the network or weaken durability. Allowed,
     * but the editor requires an explicit acknowledgement first.
     *
     * - `*_listener_addr` can open a listening socket on every interface.
     * - `*_certs` adds a trusted CA.
     * - `sqlite3_*` includes `synchronous` / `journal_mode`, i.e. store durability.
     */
    fun isSensitiveParameter(name: String): Boolean {
        val lowered = name.lowercase()
        if (lowered.endsWith("_listener_addr") || lowered.endsWith("_certs")) return true
        if (lowered.startsWith("sqlite3_")) return true
        // Token match, NOT contains("port"): that substring also matches "exporter",
        // "import" and "report", which flagged every `metrics_exporter_*` parameter
        // and trained users to tick the acknowledgement without reading it.
        val tokens = lowered.split('_')
        return "port" in tokens || "ports" in tokens
    }

    // MARK: Collections

    enum class CollectionError(val message: String) {
        Empty("Enter a collection name."),
        SystemCollection("System collections cannot be scoped."),
        NeedsQuoting("Collection names cannot contain quotes or spaces."),
        Duplicate("This collection already has a scope."),
    }

    /** Validates one collection name. [others] is every other row's raw name. */
    fun validateCollection(raw: String, others: List<String>): CollectionError? {
        val name = raw.trim()
        // Trim first: "   " and "orders " both pass a naive non-empty check and would
        // produce a scope key that matches no collection, silently doing nothing.
        if (name.isEmpty()) return CollectionError.Empty
        if (isSystemCollection(name)) return CollectionError.SystemCollection
        if (name.any { it.isWhitespace() } ||
            name.contains('"') || name.contains('\'') || name.contains('`')
        ) {
            return CollectionError.NeedsQuoting
        }
        if (others.map { it.trim() }.contains(name)) return CollectionError.Duplicate
        return null
    }

    /** System collections are `__`-prefixed in DQL; also surfaced as `system:`-prefixed. */
    fun isSystemCollection(name: String): Boolean =
        name.startsWith("__") || name.lowercase().startsWith("system:")

    // MARK: Parameters

    sealed interface ParameterError {
        val message: String

        data object Empty : ParameterError {
            override val message = "Enter a parameter name."
        }
        data object InvalidName : ParameterError {
            override val message = "Use letters, digits and underscores only."
        }
        data object Reserved : ParameterError {
            override val message = "This parameter is managed elsewhere in Edge Studio."
        }
        data object Duplicate : ParameterError {
            override val message = "This parameter is already set."
        }
        data object ValueTooLong : ParameterError {
            override val message = "Value is too long (max $MAX_VALUE_LENGTH characters)."
        }
        data class ValueNotParsable(val type: StartupSettingType) : ParameterError {
            override val message = "Value is not a valid ${type.displayName}."
        }
        data object NeedsAcknowledgement : ParameterError {
            override val message = "Confirm you understand this parameter's risk before saving."
        }
        data object TooManyRows : ParameterError {
            override val message = "Too many startup settings (max $MAX_ROW_COUNT)."
        }
    }

    /**
     * True when [name] is a legal `ALTER SYSTEM` parameter identifier.
     *
     * Whole-string matched on purpose: the parameter name is interpolated into DQL
     * (identifiers cannot be parameterized), so this is the injection guard.
     */
    fun isValidParameterName(name: String): Boolean {
        if (name.isEmpty() || name.length > 128) return false
        name.forEachIndexed { index, c ->
            val isLetter = c in 'a'..'z' || c in 'A'..'Z'
            val isDigit = c in '0'..'9'
            val isUnderscore = c == '_'
            if (index == 0) {
                if (!isLetter && !isUnderscore) return false
            } else if (!isLetter && !isDigit && !isUnderscore) {
                return false
            }
        }
        return true
    }

    fun isReservedParameter(name: String): Boolean {
        val lowered = name.lowercase()
        if (lowered in reservedParameterExactNames) return true
        return reservedParameterPrefixes.any { lowered.startsWith(it) }
    }

    /** Validates one startup setting. [others] is every other row's raw parameter name. */
    fun validateSetting(setting: StartupSetting, others: List<String>): ParameterError? {
        val name = setting.parameter.trim()
        if (name.isEmpty()) return ParameterError.Empty
        if (!isValidParameterName(name)) return ParameterError.InvalidName
        if (isReservedParameter(name)) return ParameterError.Reserved
        val normalizedOthers = others.map { it.trim().lowercase() }
        if (name.lowercase() in normalizedOthers) return ParameterError.Duplicate
        if (setting.value.length > MAX_VALUE_LENGTH) return ParameterError.ValueTooLong
        if (setting.typedValue() == null) return ParameterError.ValueNotParsable(setting.type)
        // Checked here rather than only in the editor, so a setting arriving from a
        // non-UI ingress cannot be applied unacknowledged.
        if (isSensitiveParameter(name) && !setting.isAcknowledged) {
            return ParameterError.NeedsAcknowledgement
        }
        return null
    }

    /**
     * Validates a whole list the way the apply path needs it: duplicates resolved
     * across the list and the row cap enforced.
     *
     * The editor validates row-by-row so it can show inline messages; this is the
     * single chokepoint that also covers non-UI ingress, where `validateSetting`
     * alone was passing `others: []` and therefore never detecting duplicates.
     *
     * @return the rows that may be applied, and a reason per rejected row.
     */
    fun partitionSettings(
        settings: List<StartupSetting>,
    ): Pair<List<StartupSetting>, List<Pair<StartupSetting, ParameterError>>> {
        val allowed = mutableListOf<StartupSetting>()
        val rejected = mutableListOf<Pair<StartupSetting, ParameterError>>()
        val seen = mutableSetOf<String>()

        for (setting in settings) {
            val error = validateSetting(setting, others = emptyList())
            if (error != null) {
                rejected.add(setting to error)
                continue
            }
            val key = setting.syncKey.lowercase()
            if (!seen.add(key)) {
                rejected.add(setting to ParameterError.Duplicate)
                continue
            }
            if (allowed.size >= MAX_ROW_COUNT) {
                rejected.add(setting to ParameterError.TooManyRows)
                continue
            }
            allowed.add(setting)
        }
        return allowed to rejected
    }
}

// MARK: - DQL Construction

/**
 * Builds the DQL for the advanced settings. Pure and synchronous so the statements
 * and arguments are unit-testable without a Ditto instance.
 */
object AdvancedSettingsDql {
    const val SYNC_SCOPES_PARAMETER = "USER_COLLECTION_SYNC_SCOPES"
    const val SYNC_SCOPES_READ_PARAMETER = "user_collection_sync_scopes"

    const val SET_SYNC_SCOPES_QUERY = "ALTER SYSTEM SET $SYNC_SCOPES_PARAMETER = :scopes"
    const val SHOW_SYNC_SCOPES_QUERY = "SHOW $SYNC_SCOPES_READ_PARAMETER"
    const val RESET_ALL_QUERY = "ALTER SYSTEM RESET ALL"

    sealed class ScopeMapError(message: String) : Exception(message) {
        data class DuplicateCollection(val collection: String) :
            ScopeMapError("Duplicate collection: $collection")
        data class InvalidCollection(val collection: String) :
            ScopeMapError("Invalid collection: $collection")
        data class TooManyScopes(val count: Int) :
            ScopeMapError("Too many scopes: $count")
    }

    /**
     * Collection → DQL scope string, ready to pass as a query argument.
     *
     * Throws rather than resolving conflicts: a duplicate could otherwise silently
     * pick the wider scope of the two, which for `LocalPeerOnly` means data leaving
     * the device.
     */
    fun scopeMap(scopes: List<CollectionSyncScope>): Map<String, String> {
        if (scopes.size > AdvancedSettingsValidator.MAX_ROW_COUNT) {
            throw ScopeMapError.TooManyScopes(scopes.size)
        }
        val map = mutableMapOf<String, String>()
        for (entry in scopes) {
            val name = entry.syncKey
            // Same rule set as the editor (empty / system / needs-quoting), so a row
            // that never passed through the UI cannot become a scope key that matches
            // no collection and then verifies as applied.
            if (AdvancedSettingsValidator.validateCollection(name, others = emptyList()) != null) {
                throw ScopeMapError.InvalidCollection(entry.collection)
            }
            if (map.containsKey(name)) {
                throw ScopeMapError.DuplicateCollection(name)
            }
            // The raw value, never `displayName` — mixing those up would silently
            // mis-scope every collection.
            map[name] = entry.scope.dqlValue
        }
        return map
    }

    /**
     * The statement for one startup setting. The parameter name is interpolated
     * (DQL cannot parameterize identifiers), so callers must have validated it.
     */
    fun settingStatement(setting: StartupSetting): String =
        "ALTER SYSTEM SET ${setting.syncKey} = :value"
}
