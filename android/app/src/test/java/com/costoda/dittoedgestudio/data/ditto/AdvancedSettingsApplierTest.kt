package com.costoda.dittoedgestudio.data.ditto

import com.costoda.dittoedgestudio.domain.model.AdvancedSettingsDql
import com.costoda.dittoedgestudio.domain.model.CollectionSyncScope
import com.costoda.dittoedgestudio.domain.model.StartupSetting
import com.costoda.dittoedgestudio.domain.model.StartupSettingType
import com.costoda.dittoedgestudio.domain.model.SyncScope
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class AdvancedSettingsApplierTest {

    /** Records every statement in order and can be scripted to fail or return rows. */
    private class RecordingExecutor(
        private val showResult: List<Map<String, Any?>> = emptyList(),
        private val failOn: (String) -> Boolean = { false },
    ) : DQLExecuting {
        data class Call(val query: String, val arguments: Map<String, Any?>)

        val calls = mutableListOf<Call>()

        override suspend fun runDQL(query: String, arguments: Map<String, Any?>): List<Map<String, Any?>> {
            calls.add(Call(query, arguments))
            if (failOn(query)) throw RuntimeException("scripted failure for: $query")
            if (query == AdvancedSettingsDql.SHOW_SYNC_SCOPES_QUERY) return showResult
            return emptyList()
        }
    }

    private fun showRows(scopes: Map<String, String>): List<Map<String, Any?>> =
        listOf(mapOf(AdvancedSettingsDql.SYNC_SCOPES_READ_PARAMETER to scopes))

    // MARK: Startup settings (best-effort)

    @Test
    fun `startup settings apply each row and skip failures`() = runTest {
        val executor = RecordingExecutor(failOn = { it.contains("bad_param") })
        val applier = AdvancedSettingsApplier(executor)

        val result = applier.applyStartupSettings(
            listOf(
                StartupSetting(parameter = "good_param", type = StartupSettingType.String, value = "x"),
                StartupSetting(parameter = "bad_param", type = StartupSettingType.String, value = "x"),
            ),
        )

        assertEquals(listOf("good_param"), result.appliedSettings)
        assertEquals(1, result.skippedSettings.size)
        assertEquals("bad_param", result.skippedSettings[0].name)
        assertTrue(result.hasFailures)
    }

    @Test
    fun `startup settings reject invalid rows before any statement is issued`() = runTest {
        val executor = RecordingExecutor()
        val applier = AdvancedSettingsApplier(executor)

        val result = applier.applyStartupSettings(
            listOf(
                // Reserved parameters never reach the executor.
                StartupSetting(parameter = "dql_strict_mode", type = StartupSettingType.Boolean, value = "True"),
                // Sensitive without acknowledgement never reaches the executor.
                StartupSetting(parameter = "some_port", type = StartupSettingType.Integer, value = "9000"),
            ),
        )

        assertTrue(executor.calls.isEmpty())
        assertEquals(2, result.skippedSettings.size)
    }

    // MARK: Sync scopes (fail-closed)

    @Test
    fun `scopes apply and verify via read-back`() = runTest {
        val executor = RecordingExecutor(showResult = showRows(mapOf("orders" to "LocalPeerOnly")))
        val applier = AdvancedSettingsApplier(executor)

        val (applied, verified) = applier.applySyncScopes(
            listOf(CollectionSyncScope(collection = "orders", scope = SyncScope.LocalPeerOnly)),
        )

        assertEquals(1, applied)
        assertTrue(verified)
        val setCall = executor.calls.first { it.query == AdvancedSettingsDql.SET_SYNC_SCOPES_QUERY }
        @Suppress("UNCHECKED_CAST")
        assertEquals(
            mapOf("orders" to "LocalPeerOnly"),
            setCall.arguments["scopes"] as Map<String, String>,
        )
    }

    @Test
    fun `empty scope list still issues the statement`() = runTest {
        // Deleting the last row must take effect: ALTER SYSTEM state is in-memory, so
        // returning early would leave the old scope enforced while the UI shows none.
        val executor = RecordingExecutor(showResult = showRows(emptyMap()))
        val applier = AdvancedSettingsApplier(executor)

        val (applied, verified) = applier.applySyncScopes(emptyList())

        assertEquals(0, applied)
        assertTrue(verified)
        assertTrue(executor.calls.any { it.query == AdvancedSettingsDql.SET_SYNC_SCOPES_QUERY })
    }

    @Test
    fun `statement failure aborts before read-back`() = runTest {
        val executor = RecordingExecutor(failOn = { it == AdvancedSettingsDql.SET_SYNC_SCOPES_QUERY })
        val applier = AdvancedSettingsApplier(executor)

        try {
            applier.applySyncScopes(listOf(CollectionSyncScope(collection = "orders")))
            fail("expected ScopeStatementFailed")
        } catch (e: AdvancedSettingsApplier.ApplyError.ScopeStatementFailed) {
            assertEquals(listOf("orders"), e.collections)
        }
        assertFalse(executor.calls.any { it.query == AdvancedSettingsDql.SHOW_SYNC_SCOPES_QUERY })
    }

    @Test
    fun `read-back disagreement aborts the open`() = runTest {
        val executor = RecordingExecutor(showResult = showRows(mapOf("orders" to "AllPeers")))
        val applier = AdvancedSettingsApplier(executor)

        try {
            applier.applySyncScopes(
                listOf(CollectionSyncScope(collection = "orders", scope = SyncScope.LocalPeerOnly)),
            )
            fail("expected ScopeVerificationMismatch")
        } catch (e: AdvancedSettingsApplier.ApplyError.ScopeVerificationMismatch) {
            assertEquals(mapOf("orders" to "AllPeers"), e.actual)
        }
    }

    @Test
    fun `verification is subset not equality`() = runTest {
        // The instance may legitimately carry scopes this config did not set.
        val executor = RecordingExecutor(
            showResult = showRows(mapOf("orders" to "LocalPeerOnly", "other" to "AllPeers")),
        )
        val applier = AdvancedSettingsApplier(executor)

        val (applied, verified) = applier.applySyncScopes(
            listOf(CollectionSyncScope(collection = "orders", scope = SyncScope.LocalPeerOnly)),
        )
        assertEquals(1, applied)
        assertTrue(verified)
    }

    @Test
    fun `unparseable read-back proceeds but reports unverified`() = runTest {
        val executor = RecordingExecutor(showResult = listOf(mapOf("unexpected" to "shape")))
        val applier = AdvancedSettingsApplier(executor)

        val (applied, verified) = applier.applySyncScopes(
            listOf(CollectionSyncScope(collection = "orders", scope = SyncScope.LocalPeerOnly)),
        )
        assertEquals(1, applied)
        assertFalse(verified)
    }

    @Test
    fun `failed SHOW proceeds but reports unverified`() = runTest {
        val executor = RecordingExecutor(failOn = { it == AdvancedSettingsDql.SHOW_SYNC_SCOPES_QUERY })
        val applier = AdvancedSettingsApplier(executor)

        val (applied, verified) = applier.applySyncScopes(
            listOf(CollectionSyncScope(collection = "orders", scope = SyncScope.LocalPeerOnly)),
        )
        assertEquals(1, applied)
        assertFalse(verified)
    }

    @Test
    fun `read-back accepts name value row shape`() = runTest {
        val executor = RecordingExecutor(
            showResult = listOf(
                mapOf(
                    "name" to AdvancedSettingsDql.SYNC_SCOPES_READ_PARAMETER,
                    "value" to mapOf("orders" to "LocalPeerOnly"),
                ),
            ),
        )
        val applier = AdvancedSettingsApplier(executor)

        val (_, verified) = applier.applySyncScopes(
            listOf(CollectionSyncScope(collection = "orders", scope = SyncScope.LocalPeerOnly)),
        )
        assertTrue(verified)
    }

    @Test
    fun `invalid scopes throw before any statement`() = runTest {
        val executor = RecordingExecutor()
        val applier = AdvancedSettingsApplier(executor)

        try {
            applier.applySyncScopes(listOf(CollectionSyncScope(collection = "__system")))
            fail("expected InvalidScopes")
        } catch (e: AdvancedSettingsApplier.ApplyError.InvalidScopes) {
            // expected
        }
        assertTrue(executor.calls.isEmpty())
    }

    // MARK: Open sequence ordering

    @Test
    fun `open sequence orders settings before transports before strict mode before scopes before sync`() = runTest {
        val executor = RecordingExecutor(showResult = showRows(mapOf("orders" to "LocalPeerOnly")))
        val applier = AdvancedSettingsApplier(executor)
        val events = mutableListOf<String>()

        val sequence = AdvancedSettingsApplier.OpenSequence(
            applier = applier,
            applyTransportConfig = { events.add("transports") },
            isStrictModeEnabled = true,
            startSync = { events.add("startSync") },
        )

        sequence.run(
            startupSettings = listOf(
                StartupSetting(parameter = "some_setting", type = StartupSettingType.String, value = "v"),
            ),
            syncScopes = listOf(CollectionSyncScope(collection = "orders", scope = SyncScope.LocalPeerOnly)),
        )

        val dqlOrder = executor.calls.map { it.query }
        assertEquals("ALTER SYSTEM SET some_setting = :value", dqlOrder[0])
        assertEquals("ALTER SYSTEM SET DQL_STRICT_MODE = true", dqlOrder[1])
        assertEquals(AdvancedSettingsDql.SET_SYNC_SCOPES_QUERY, dqlOrder[2])
        assertEquals(AdvancedSettingsDql.SHOW_SYNC_SCOPES_QUERY, dqlOrder[3])
        // Transports run after user settings but before the app's own ALTER SYSTEMs.
        assertEquals(listOf("transports", "startSync"), events)
    }

    @Test
    fun `open sequence never reaches startSync when scopes fail`() = runTest {
        val executor = RecordingExecutor(failOn = { it == AdvancedSettingsDql.SET_SYNC_SCOPES_QUERY })
        val applier = AdvancedSettingsApplier(executor)
        var syncStarted = false

        val sequence = AdvancedSettingsApplier.OpenSequence(
            applier = applier,
            applyTransportConfig = {},
            isStrictModeEnabled = false,
            startSync = { syncStarted = true },
        )

        try {
            sequence.run(emptyList(), listOf(CollectionSyncScope(collection = "orders")))
            fail("expected ApplyError")
        } catch (e: AdvancedSettingsApplier.ApplyError) {
            // expected
        }
        assertFalse("startSync must not run when scopes fail", syncStarted)
    }

    @Test
    fun `reset issues RESET ALL`() = runTest {
        val executor = RecordingExecutor()
        AdvancedSettingsApplier(executor).resetAllToDefaults()
        assertEquals(listOf(AdvancedSettingsDql.RESET_ALL_QUERY), executor.calls.map { it.query })
    }
}
