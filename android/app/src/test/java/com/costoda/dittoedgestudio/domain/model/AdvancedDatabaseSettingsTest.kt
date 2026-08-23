package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AdvancedDatabaseSettingsTest {

    // MARK: SyncScope wire format

    @Test
    fun `scope dql values are the exact DQL wire strings`() {
        // These are a wire format, not a display concern — never rename them.
        assertEquals("AllPeers", SyncScope.AllPeers.dqlValue)
        assertEquals("BigPeerOnly", SyncScope.BigPeerOnly.dqlValue)
        assertEquals("SmallPeersOnly", SyncScope.SmallPeersOnly.dqlValue) // plural
        assertEquals("LocalPeerOnly", SyncScope.LocalPeerOnly.dqlValue)
    }

    // MARK: typedValue coercion

    @Test
    fun `string value allows empty`() {
        val setting = StartupSetting(parameter = "p", type = StartupSettingType.String, value = "")
        assertEquals(DQLValue.StringValue(""), setting.typedValue())
    }

    @Test
    fun `json value must parse`() {
        val valid = StartupSetting(parameter = "p", type = StartupSettingType.Json, value = """["a","b"]""")
        assertNotNull(valid.typedValue())
        val invalid = StartupSetting(parameter = "p", type = StartupSettingType.Json, value = "{not json")
        assertNull(invalid.typedValue())
        val empty = StartupSetting(parameter = "p", type = StartupSettingType.Json, value = "")
        assertNull(empty.typedValue())
    }

    @Test
    fun `integer falls back to ULong above Long MAX`() {
        val small = StartupSetting(parameter = "p", type = StartupSettingType.Integer, value = "42")
        assertEquals(DQLValue.IntValue(42L), small.typedValue())

        // dql_request_history_log_dump_limit ships as 18446744073709551615.
        val big = StartupSetting(
            parameter = "p",
            type = StartupSettingType.Integer,
            value = "18446744073709551615",
        )
        assertEquals(DQLValue.UIntValue(ULong.MAX_VALUE), big.typedValue())

        val notANumber = StartupSetting(parameter = "p", type = StartupSettingType.Integer, value = "4.2")
        assertNull(notANumber.typedValue())
    }

    @Test
    fun `double accepts scientific notation`() {
        val setting = StartupSetting(
            parameter = "p",
            type = StartupSettingType.Double,
            value = "1.0000000000000001e-09",
        )
        assertEquals(DQLValue.DoubleValue(1.0000000000000001e-09), setting.typedValue())
    }

    @Test
    fun `boolean maps case-insensitively`() {
        // The `Bool("True") is nil` trap — capitalised picker text must map.
        listOf("true", "True", "TRUE").forEach {
            val s = StartupSetting(parameter = "p", type = StartupSettingType.Boolean, value = it)
            assertEquals(DQLValue.BoolValue(true), s.typedValue())
        }
        listOf("false", "False", "FALSE").forEach {
            val s = StartupSetting(parameter = "p", type = StartupSettingType.Boolean, value = it)
            assertEquals(DQLValue.BoolValue(false), s.typedValue())
        }
        val invalid = StartupSetting(parameter = "p", type = StartupSettingType.Boolean, value = "yes")
        assertNull(invalid.typedValue())
    }

    @Test
    fun `canonicalBooleanValue matches case-insensitively`() {
        assertEquals("True", StartupSetting.canonicalBooleanValue("true"))
        assertEquals("False", StartupSetting.canonicalBooleanValue("FALSE"))
        assertNull(StartupSetting.canonicalBooleanValue("not-bool"))
    }

    // MARK: Parameter name injection guard

    @Test
    fun `parameter name guard is whole-string`() {
        assertTrue(AdvancedSettingsValidator.isValidParameterName("sqlite3_synchronous"))
        assertTrue(AdvancedSettingsValidator.isValidParameterName("_leading_underscore"))
        assertFalse(AdvancedSettingsValidator.isValidParameterName(""))
        assertFalse(AdvancedSettingsValidator.isValidParameterName("9starts_with_digit"))
        assertFalse(AdvancedSettingsValidator.isValidParameterName("has space"))
        // Injection attempts must fail whole-string validation.
        assertFalse(AdvancedSettingsValidator.isValidParameterName("ok; ALTER SYSTEM SET data_sync_enabled = false --"))
        assertFalse(AdvancedSettingsValidator.isValidParameterName("name\nwith_newline"))
        assertFalse(AdvancedSettingsValidator.isValidParameterName("a".repeat(129)))
    }

    // MARK: Reserved and sensitive parameters

    @Test
    fun `reserved parameters are blocked`() {
        listOf(
            "user_collection_sync_scopes",
            "dql_strict_mode",
            "mesh_chooser_max_wlan_clients",
            "data_sync_enabled",
            "transports_ble_server_is_enabled",
            "udp_server_enabled",
            "USER_COLLECTION_SYNC_SCOPES", // case-insensitive
        ).forEach {
            assertTrue("$it should be reserved", AdvancedSettingsValidator.isReservedParameter(it))
        }
        assertFalse(AdvancedSettingsValidator.isReservedParameter("sqlite3_synchronous"))
    }

    @Test
    fun `sensitive parameters match by suffix prefix and token`() {
        assertTrue(AdvancedSettingsValidator.isSensitiveParameter("metrics_exporter_prometheus_http_listener_addr"))
        assertTrue(AdvancedSettingsValidator.isSensitiveParameter("additional_p2p_trusted_ca_certs"))
        assertTrue(AdvancedSettingsValidator.isSensitiveParameter("sqlite3_synchronous"))
        assertTrue(AdvancedSettingsValidator.isSensitiveParameter("some_port"))
        assertTrue(AdvancedSettingsValidator.isSensitiveParameter("some_ports"))
        // Token match, not substring: "exporter" contains "port" but must NOT match.
        assertFalse(AdvancedSettingsValidator.isSensitiveParameter("metrics_exporter_enabled"))
        assertFalse(AdvancedSettingsValidator.isSensitiveParameter("dql_request_history_log_dump_limit"))
    }

    // MARK: Collection validation

    @Test
    fun `collection validation rules`() {
        assertEquals(
            AdvancedSettingsValidator.CollectionError.Empty,
            AdvancedSettingsValidator.validateCollection("   ", emptyList()),
        )
        assertEquals(
            AdvancedSettingsValidator.CollectionError.SystemCollection,
            AdvancedSettingsValidator.validateCollection("__system", emptyList()),
        )
        assertEquals(
            AdvancedSettingsValidator.CollectionError.SystemCollection,
            AdvancedSettingsValidator.validateCollection("system:foo", emptyList()),
        )
        assertEquals(
            AdvancedSettingsValidator.CollectionError.NeedsQuoting,
            AdvancedSettingsValidator.validateCollection("has space", emptyList()),
        )
        assertEquals(
            AdvancedSettingsValidator.CollectionError.NeedsQuoting,
            AdvancedSettingsValidator.validateCollection("has\"quote", emptyList()),
        )
        assertEquals(
            AdvancedSettingsValidator.CollectionError.Duplicate,
            AdvancedSettingsValidator.validateCollection("orders", listOf(" orders ")),
        )
        assertNull(AdvancedSettingsValidator.validateCollection("orders", listOf("customers")))
    }

    // MARK: Setting validation

    @Test
    fun `sensitive setting without acknowledgement is rejected`() {
        val setting = StartupSetting(
            parameter = "metrics_exporter_prometheus_http_listener_addr",
            type = StartupSettingType.String,
            value = "127.0.0.1:9000",
            isAcknowledged = false,
        )
        assertEquals(
            AdvancedSettingsValidator.ParameterError.NeedsAcknowledgement,
            AdvancedSettingsValidator.validateSetting(setting, emptyList()),
        )
        assertNull(AdvancedSettingsValidator.validateSetting(setting.copy(isAcknowledged = true), emptyList()))
    }

    @Test
    fun `duplicate detection is case-insensitive`() {
        val setting = StartupSetting(parameter = "My_Param", type = StartupSettingType.String, value = "x")
        assertEquals(
            AdvancedSettingsValidator.ParameterError.Duplicate,
            AdvancedSettingsValidator.validateSetting(setting, listOf("my_param")),
        )
    }

    @Test
    fun `partitionSettings rejects duplicates and enforces row cap across the whole list`() {
        val rows = (1..70).map {
            StartupSetting(parameter = "param_$it", type = StartupSettingType.String, value = "v")
        } + StartupSetting(parameter = "PARAM_1", type = StartupSettingType.String, value = "dupe")

        val (allowed, rejected) = AdvancedSettingsValidator.partitionSettings(rows)

        assertEquals(AdvancedSettingsValidator.MAX_ROW_COUNT, allowed.size)
        // 6 over the cap + 1 case-insensitive duplicate.
        assertEquals(7, rejected.size)
        assertTrue(rejected.any { it.second == AdvancedSettingsValidator.ParameterError.Duplicate })
        assertEquals(6, rejected.count { it.second == AdvancedSettingsValidator.ParameterError.TooManyRows })
    }

    // MARK: DQL construction

    @Test
    fun `scopeMap uses raw dql values and rejects duplicates`() {
        val map = AdvancedSettingsDql.scopeMap(
            listOf(
                CollectionSyncScope(collection = "orders", scope = SyncScope.LocalPeerOnly),
                CollectionSyncScope(collection = "customers", scope = SyncScope.BigPeerOnly),
            ),
        )
        assertEquals(mapOf("orders" to "LocalPeerOnly", "customers" to "BigPeerOnly"), map)
    }

    @Test(expected = AdvancedSettingsDql.ScopeMapError.DuplicateCollection::class)
    fun `scopeMap throws on duplicate collection`() {
        AdvancedSettingsDql.scopeMap(
            listOf(
                CollectionSyncScope(collection = "orders", scope = SyncScope.AllPeers),
                CollectionSyncScope(collection = " orders ", scope = SyncScope.LocalPeerOnly),
            ),
        )
    }

    @Test(expected = AdvancedSettingsDql.ScopeMapError.InvalidCollection::class)
    fun `scopeMap throws on invalid collection`() {
        AdvancedSettingsDql.scopeMap(listOf(CollectionSyncScope(collection = "__system")))
    }

    @Test
    fun `setting statement interpolates name and binds value`() {
        val setting = StartupSetting(parameter = " sqlite3_synchronous ", type = StartupSettingType.String, value = "FULL")
        assertEquals("ALTER SYSTEM SET sqlite3_synchronous = :value", AdvancedSettingsDql.settingStatement(setting))
    }

    // MARK: Storage JSON

    @Test
    fun `storage round trip preserves rows`() {
        val scopes = listOf(
            CollectionSyncScope(collection = "orders", scope = SyncScope.LocalPeerOnly),
            CollectionSyncScope(collection = "customers", scope = SyncScope.SmallPeersOnly),
        )
        assertEquals(scopes, AdvancedSettingsJson.decodeScopes(AdvancedSettingsJson.encodeScopes(scopes)))

        val settings = listOf(
            StartupSetting(
                parameter = "sqlite3_synchronous",
                type = StartupSettingType.String,
                value = "FULL",
                isAcknowledged = true,
            ),
        )
        assertEquals(settings, AdvancedSettingsJson.decodeSettings(AdvancedSettingsJson.encodeSettings(settings)))
    }

    @Test(expected = Exception::class)
    fun `unknown scope value fails to decode rather than coercing`() {
        // A scope added by a future SDK must not silently become some other scope.
        AdvancedSettingsJson.decodeScopes("""[{"collection":"orders","scope":"FutureScope"}]""")
    }

    @Test
    fun `missing isAcknowledged decodes as false`() {
        val decoded = AdvancedSettingsJson.decodeSettings(
            """[{"parameter":"some_port","type":"String","value":"9000"}]""",
        )
        assertEquals(1, decoded.size)
        assertFalse(decoded[0].isAcknowledged)
    }

    @Test
    fun `json argument value becomes plain maps and lists`() {
        val setting = StartupSetting(
            parameter = "p",
            type = StartupSettingType.Json,
            value = """{"a": [1, 2], "b": "text", "c": true}""",
        )
        val arg = (setting.typedValue() as DQLValue.JsonValue).argumentValue()
        @Suppress("UNCHECKED_CAST")
        val asMap = arg as Map<String, Any?>
        assertEquals(listOf(1L, 2L), asMap["a"])
        assertEquals("text", asMap["b"])
        assertEquals(true, asMap["c"])
    }
}
