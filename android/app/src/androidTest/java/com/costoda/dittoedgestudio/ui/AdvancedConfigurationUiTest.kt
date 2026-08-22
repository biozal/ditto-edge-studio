package com.costoda.dittoedgestudio.ui

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.costoda.dittoedgestudio.domain.model.AdvancedSettingsValidator
import com.costoda.dittoedgestudio.domain.model.CollectionSyncScope
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.domain.model.StartupSetting
import com.costoda.dittoedgestudio.domain.model.StartupSettingType
import com.costoda.dittoedgestudio.domain.model.SyncScope
import com.costoda.dittoedgestudio.ui.database.DatabaseEditorScreen
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import com.costoda.dittoedgestudio.viewmodel.DatabaseEditorViewModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Compose UI tests for the Advanced Configuration section of DatabaseEditorScreen:
 * collection sync scopes, startup system settings, acknowledgement gating, corrupt
 * scope recovery, and reset-to-defaults.
 *
 * Spec: docs/ADVANCED_DATABASE_CONFIG.md (SwiftUI parity —
 * plans/android/advanced-database-config-parity.md).
 *
 * Uses the same [DatabaseEditorScreenTest.FakeDatabaseRepository] in-memory fake to
 * avoid SQLCipher/Keystore initialisation in the test context.
 */
@RunWith(AndroidJUnit4::class)
class AdvancedConfigurationUiTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private fun newEditor(
        repo: DatabaseEditorScreenTest.FakeDatabaseRepository =
            DatabaseEditorScreenTest.FakeDatabaseRepository(),
        onDismiss: () -> Unit = {},
    ): DatabaseEditorViewModel {
        val vm = DatabaseEditorViewModel(-1L, repo)
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseEditorScreen(databaseId = -1L, onDismiss = onDismiss, viewModel = vm)
            }
        }
        return vm
    }

    private fun editEditor(
        db: DittoDatabase,
        repo: DatabaseEditorScreenTest.FakeDatabaseRepository =
            DatabaseEditorScreenTest.FakeDatabaseRepository(),
    ): DatabaseEditorViewModel {
        repo.databases.add(db)
        val vm = DatabaseEditorViewModel(db.id, repo)
        vm.loadForEdit(db)
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseEditorScreen(databaseId = db.id, onDismiss = {}, viewModel = vm)
            }
        }
        return vm
    }

    /** Fills the required basics so Save gating reflects only the advanced section. */
    private fun fillBasics() {
        composeTestRule.onNodeWithTag("NameField").performScrollTo().performTextInput("My DB")
        composeTestRule.onNodeWithTag("DatabaseIdField").performScrollTo().performTextInput("db-id")
        composeTestRule.onNodeWithTag("TokenField").performScrollTo().performTextInput("token")
    }

    private fun expandAdvanced() {
        composeTestRule.onNodeWithTag("AdvancedConfigDisclosure")
            .performScrollTo()
            .performClick()
        composeTestRule.waitForIdle()
    }

    // --- Disclosure ---

    @Test
    fun advancedSectionIsCollapsedByDefaultAndExpandsOnTap() {
        newEditor()

        composeTestRule.onNodeWithTag("AddSyncScopeButton").assertDoesNotExist()

        expandAdvanced()

        composeTestRule.onNodeWithTag("AddSyncScopeButton").performScrollTo().assertIsDisplayed()
        composeTestRule.onNodeWithTag("AddStartupSettingButton").performScrollTo().assertIsDisplayed()
    }

    @Test
    fun disclosureShowsSummaryCounts() {
        newEditor()
        expandAdvanced()

        composeTestRule.onNodeWithTag("AdvancedConfigDisclosure").performScrollTo()
        composeTestRule.onNodeWithText("0 scopes · 0 startup settings", substring = true)
            .assertIsDisplayed()
    }

    // --- Collection sync scopes ---

    @Test
    fun addScopeRowShowsCollectionFieldAndScopeDropdown() {
        val vm = newEditor()
        expandAdvanced()

        composeTestRule.onNodeWithTag("AddSyncScopeButton").performScrollTo().performClick()
        composeTestRule.waitForIdle()

        val rowId = vm.collectionSyncScopes.value.first().id
        composeTestRule.onNodeWithTag("SyncScopeRow_$rowId").performScrollTo().assertIsDisplayed()
        composeTestRule.onNodeWithTag("SyncScopeDropdown_$rowId").assertIsDisplayed()
    }

    @Test
    fun blankCollectionShowsErrorAndBlocksSave() {
        val vm = newEditor()
        fillBasics()
        expandAdvanced()
        composeTestRule.onNodeWithTag("SaveButton").assertIsEnabled()

        composeTestRule.onNodeWithTag("AddSyncScopeButton").performScrollTo().performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithText("Enter a collection name.")
            .performScrollTo().assertIsDisplayed()
        composeTestRule.onNodeWithTag("SaveButton").assertIsNotEnabled()
        // The disclosure flags the section when collapsed content has errors.
        composeTestRule.onNodeWithText("needs attention").assertExists()

        val rowId = vm.collectionSyncScopes.value.first().id
        composeTestRule.onNodeWithTag("SyncScopeCollection_$rowId")
            .performScrollTo().performTextInput("orders")
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithTag("SaveButton").assertIsEnabled()
    }

    @Test
    fun systemCollectionIsRejected() {
        val vm = newEditor()
        expandAdvanced()
        composeTestRule.onNodeWithTag("AddSyncScopeButton").performScrollTo().performClick()
        composeTestRule.waitForIdle()

        val rowId = vm.collectionSyncScopes.value.first().id
        composeTestRule.onNodeWithTag("SyncScopeCollection_$rowId")
            .performScrollTo().performTextInput("__users")
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithText("System collections cannot be scoped.")
            .performScrollTo().assertIsDisplayed()
    }

    @Test
    fun duplicateCollectionsAreRejected() {
        val vm = newEditor()
        expandAdvanced()
        composeTestRule.onNodeWithTag("AddSyncScopeButton").performScrollTo().performClick()
        composeTestRule.onNodeWithTag("AddSyncScopeButton").performScrollTo().performClick()
        composeTestRule.waitForIdle()

        val ids = vm.collectionSyncScopes.value.map { it.id }
        composeTestRule.onNodeWithTag("SyncScopeCollection_${ids[0]}")
            .performScrollTo().performTextInput("orders")
        composeTestRule.onNodeWithTag("SyncScopeCollection_${ids[1]}")
            .performScrollTo().performTextInput("orders")
        composeTestRule.waitForIdle()

        // Both rows flag each other.
        composeTestRule.onAllNodesWithText("This collection already has a scope.")
            .assertCountEquals(2)
    }

    @Test
    fun scopeDropdownSelectsScope() {
        val vm = newEditor()
        expandAdvanced()
        composeTestRule.onNodeWithTag("AddSyncScopeButton").performScrollTo().performClick()
        composeTestRule.waitForIdle()
        val rowId = vm.collectionSyncScopes.value.first().id

        composeTestRule.onNodeWithTag("SyncScopeDropdown_$rowId")
            .performScrollTo().performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithTag("SyncScope_LocalPeerOnly").performClick()
        composeTestRule.waitForIdle()

        assertEquals(SyncScope.LocalPeerOnly, vm.collectionSyncScopes.value.first().scope)
        composeTestRule.onNodeWithTag("SyncScopeDropdown_$rowId").performScrollTo()
        composeTestRule.onNodeWithText("Local Peer Only").assertIsDisplayed()
    }

    @Test
    fun scopeLegendAndQrExclusionNoteAreShown() {
        newEditor()
        expandAdvanced()

        composeTestRule.onNodeWithText("• Local Peer Only — never leaves this device", substring = true)
            .performScrollTo().assertIsDisplayed()
        composeTestRule.onNodeWithText("not included when sharing a database by QR code", substring = true)
            .performScrollTo().assertIsDisplayed()
    }

    @Test
    fun removeScopeRowRemovesIt() {
        val vm = newEditor()
        expandAdvanced()
        composeTestRule.onNodeWithTag("AddSyncScopeButton").performScrollTo().performClick()
        composeTestRule.waitForIdle()
        val rowId = vm.collectionSyncScopes.value.first().id

        composeTestRule.onNodeWithTag("SyncScopeRow_$rowId").performScrollTo()
        composeTestRule.onNodeWithText("Remove").performClick()
        composeTestRule.waitForIdle()

        assertTrue(vm.collectionSyncScopes.value.isEmpty())
    }

    // --- Startup system settings ---

    @Test
    fun addSettingRowShowsParameterTypeAndValueControls() {
        val vm = newEditor()
        expandAdvanced()

        composeTestRule.onNodeWithTag("AddStartupSettingButton").performScrollTo().performClick()
        composeTestRule.waitForIdle()

        val rowId = vm.startupSettings.value.first().id
        composeTestRule.onNodeWithTag("StartupSettingRow_$rowId").performScrollTo().assertIsDisplayed()
        composeTestRule.onNodeWithTag("StartupSettingType_$rowId").assertIsDisplayed()
        composeTestRule.onNodeWithTag("StartupSettingValue_$rowId").assertIsDisplayed()
    }

    @Test
    fun invalidParameterNameShowsInjectionGuardError() {
        val vm = newEditor()
        expandAdvanced()
        composeTestRule.onNodeWithTag("AddStartupSettingButton").performScrollTo().performClick()
        composeTestRule.waitForIdle()
        val rowId = vm.startupSettings.value.first().id

        composeTestRule.onNodeWithTag("StartupSettingParameter_$rowId")
            .performScrollTo().performTextInput("bad; DROP")
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithText("Use letters, digits and underscores only.")
            .performScrollTo().assertIsDisplayed()
    }

    @Test
    fun reservedParameterIsRejected() {
        val vm = newEditor()
        expandAdvanced()
        composeTestRule.onNodeWithTag("AddStartupSettingButton").performScrollTo().performClick()
        composeTestRule.waitForIdle()
        val rowId = vm.startupSettings.value.first().id

        composeTestRule.onNodeWithTag("StartupSettingParameter_$rowId")
            .performScrollTo().performTextInput("dql_strict_mode")
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithText("This parameter is managed elsewhere in Edge Studio.")
            .performScrollTo().assertIsDisplayed()
    }

    @Test
    fun unparsableTypedValueShowsError() {
        val vm = newEditor()
        expandAdvanced()
        composeTestRule.onNodeWithTag("AddStartupSettingButton").performScrollTo().performClick()
        composeTestRule.waitForIdle()
        val rowId = vm.startupSettings.value.first().id

        composeTestRule.onNodeWithTag("StartupSettingParameter_$rowId")
            .performScrollTo().performTextInput("some_setting")
        // Type selection is driven through the VM: the dropdown interaction itself is
        // covered by booleanTypeSwitchShowsTrueFalseDropdown, and clicking it with the
        // IME open is flaky on emulators.
        vm.setType(rowId, StartupSettingType.Integer)
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithTag("StartupSettingValue_$rowId")
            .performScrollTo().performTextInput("not-a-number")
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithText("Value is not a valid Integer.")
            .performScrollTo().assertIsDisplayed()
    }

    @Test
    fun booleanTypeSwitchShowsTrueFalseDropdown() {
        val vm = newEditor()
        expandAdvanced()
        composeTestRule.onNodeWithTag("AddStartupSettingButton").performScrollTo().performClick()
        composeTestRule.waitForIdle()
        val rowId = vm.startupSettings.value.first().id

        composeTestRule.onNodeWithTag("StartupSettingType_$rowId")
            .performScrollTo().performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithTag("SettingType_Boolean").performClick()
        composeTestRule.waitForIdle()

        // The seeded value renders in the dropdown field.
        assertEquals("True", vm.startupSettings.value.first().value)
        composeTestRule.onNodeWithTag("StartupSettingValue_$rowId")
            .performScrollTo().performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithTag("SettingValue_False").performClick()
        composeTestRule.waitForIdle()

        assertEquals("False", vm.startupSettings.value.first().value)
    }

    @Test
    fun sensitiveParameterRequiresAcknowledgementBeforeSave() {
        val vm = newEditor()
        fillBasics()
        expandAdvanced()
        composeTestRule.onNodeWithTag("AddStartupSettingButton").performScrollTo().performClick()
        composeTestRule.waitForIdle()
        val rowId = vm.startupSettings.value.first().id

        composeTestRule.onNodeWithTag("StartupSettingParameter_$rowId")
            .performScrollTo().performTextInput("metrics_exporter_prometheus_http_listener_addr")
        composeTestRule.onNodeWithTag("StartupSettingValue_$rowId")
            .performScrollTo().performTextInput("127.0.0.1:9000")
        composeTestRule.waitForIdle()

        // The acknowledgement switch appears and Save is blocked.
        composeTestRule.onNodeWithTag("StartupSettingAcknowledge_$rowId")
            .performScrollTo().assertIsDisplayed()
        composeTestRule.onNodeWithText(
            "Confirm you understand this parameter's risk before saving.",
        ).performScrollTo().assertIsDisplayed()
        composeTestRule.onNodeWithTag("SaveButton").assertIsNotEnabled()

        composeTestRule.onNodeWithTag("StartupSettingAcknowledge_$rowId")
            .performScrollTo().performClick()
        composeTestRule.waitForIdle()

        assertTrue(vm.startupSettings.value.first().isAcknowledged)
        composeTestRule.onNodeWithTag("SaveButton").assertIsEnabled()
    }

    @Test
    fun renamingAcknowledgedSensitiveRowRevokesAndReblocksSave() {
        val vm = newEditor()
        fillBasics()
        expandAdvanced()
        composeTestRule.onNodeWithTag("AddStartupSettingButton").performScrollTo().performClick()
        composeTestRule.waitForIdle()
        val rowId = vm.startupSettings.value.first().id

        composeTestRule.onNodeWithTag("StartupSettingParameter_$rowId")
            .performScrollTo().performTextInput("some_port")
        composeTestRule.onNodeWithTag("StartupSettingValue_$rowId")
            .performScrollTo().performTextInput("9000")
        composeTestRule.onNodeWithTag("StartupSettingAcknowledge_$rowId")
            .performScrollTo().performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithTag("SaveButton").assertIsEnabled()

        // Renaming to a different sensitive parameter revokes the acknowledgement.
        // ("some_port" → "another_port": still token-matches "port", so the row stays
        // sensitive and the revoked acknowledgement blocks Save again.)
        composeTestRule.onNodeWithTag("StartupSettingParameter_$rowId")
            .performScrollTo().performTextReplacement("another_port")
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithTag("SaveButton").assertIsNotEnabled()
    }

    // --- Reset to SDK defaults ---

    @Test
    fun resetToDefaultsClearsRowsAndUndoRestoresThem() {
        val vm = newEditor()
        expandAdvanced()
        composeTestRule.onNodeWithTag("AddSyncScopeButton").performScrollTo().performClick()
        composeTestRule.waitForIdle()
        val rowId = vm.collectionSyncScopes.value.first().id
        composeTestRule.onNodeWithTag("SyncScopeCollection_$rowId")
            .performScrollTo().performTextInput("orders")
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithTag("ResetToDefaultsButton").performScrollTo().performClick()
        composeTestRule.waitForIdle()

        assertTrue(vm.collectionSyncScopes.value.isEmpty())
        composeTestRule.onNodeWithTag("UndoResetButton").assertIsDisplayed()
        composeTestRule.onNodeWithText("restored to Ditto's defaults", substring = true)
            .assertIsDisplayed()

        composeTestRule.onNodeWithTag("UndoResetButton").performClick()
        composeTestRule.waitForIdle()

        assertEquals(1, vm.collectionSyncScopes.value.size)
        assertEquals("orders", vm.collectionSyncScopes.value.first().collection)
    }

    // --- Corrupt scopes ---

    @Test
    fun corruptScopesShowBannerAndBlockSaveUntilDiscarded() {
        val db = DittoDatabase(
            id = 5L,
            name = "Existing",
            databaseId = "ex-id",
            token = "tok",
            hasCorruptSyncScopes = true,
        )
        editEditor(db)
        expandAdvanced()

        composeTestRule.onNodeWithTag("CorruptSyncScopesBanner").performScrollTo().assertIsDisplayed()
        composeTestRule.onNodeWithText("could not be read", substring = true).assertIsDisplayed()
        composeTestRule.onNodeWithTag("SaveButton").assertIsNotEnabled()

        composeTestRule.onNodeWithTag("DiscardCorruptScopesToggle")
            .performScrollTo().performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithTag("SaveButton").assertIsEnabled()
    }

    // --- End-to-end save through the UI ---

    @Test
    fun savePersistsScopesAndSettingsEnteredThroughTheUi() {
        val repo = DatabaseEditorScreenTest.FakeDatabaseRepository()
        var dismissed = false
        val vm = newEditor(repo, onDismiss = { dismissed = true })
        fillBasics()
        expandAdvanced()

        composeTestRule.onNodeWithTag("AddSyncScopeButton").performScrollTo().performClick()
        composeTestRule.waitForIdle()
        val scopeRowId = vm.collectionSyncScopes.value.first().id
        composeTestRule.onNodeWithTag("SyncScopeCollection_$scopeRowId")
            .performScrollTo().performTextInput("orders")
        // Scope selection via the VM: the dropdown interaction itself is covered by
        // scopeDropdownSelectsScope, and clicking it with the IME open is flaky on
        // emulators. This test's subject is persistence through Save.
        vm.updateScope(scopeRowId, SyncScope.LocalPeerOnly)
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithTag("AddStartupSettingButton").performScrollTo().performClick()
        composeTestRule.waitForIdle()
        val settingRowId = vm.startupSettings.value.first().id
        composeTestRule.onNodeWithTag("StartupSettingParameter_$settingRowId")
            .performScrollTo().performTextInput("sqlite3_synchronous")
        composeTestRule.onNodeWithTag("StartupSettingValue_$settingRowId")
            .performScrollTo().performTextInput("FULL")
        composeTestRule.onNodeWithTag("StartupSettingAcknowledge_$settingRowId")
            .performScrollTo().performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithTag("SaveButton").performClick()
        composeTestRule.waitForIdle()

        assertTrue(dismissed)
        val saved = repo.databases.single()
        assertEquals(1, saved.collectionSyncScopes.size)
        assertEquals("orders", saved.collectionSyncScopes[0].collection)
        assertEquals(SyncScope.LocalPeerOnly, saved.collectionSyncScopes[0].scope)
        assertEquals(1, saved.startupSettings.size)
        assertEquals("sqlite3_synchronous", saved.startupSettings[0].parameter)
        assertEquals("FULL", saved.startupSettings[0].value)
        assertTrue(saved.startupSettings[0].isAcknowledged)
    }

    @Test
    fun editingExistingDatabaseLoadsScopesAndSettingsIntoRows() {
        val db = DittoDatabase(
            id = 7L,
            name = "Existing",
            databaseId = "ex-id",
            token = "tok",
            collectionSyncScopes = listOf(
                CollectionSyncScope(collection = "orders", scope = SyncScope.BigPeerOnly),
            ),
            startupSettings = listOf(
                StartupSetting(
                    parameter = "sqlite3_synchronous",
                    type = StartupSettingType.String,
                    value = "FULL",
                    isAcknowledged = true,
                ),
            ),
        )
        editEditor(db)
        expandAdvanced()

        composeTestRule.onNodeWithTag("SyncScopeCollection_${db.collectionSyncScopes[0].id}")
            .performScrollTo().assertIsDisplayed()
        composeTestRule.onNodeWithTag("SyncScopeDropdown_${db.collectionSyncScopes[0].id}")
            .performScrollTo().assertIsDisplayed()
        composeTestRule.onNodeWithText("Big Peer Only").assertIsDisplayed()
        composeTestRule.onNodeWithTag("StartupSettingParameter_${db.startupSettings[0].id}")
            .performScrollTo().assertIsDisplayed()
        // The stored acknowledgement survives the round trip into the editor.
        composeTestRule.onNodeWithTag("StartupSettingAcknowledge_${db.startupSettings[0].id}")
            .assertIsOn()
    }

    @Test
    fun acknowledgementSwitchCanBeWithdrawn() {
        val db = DittoDatabase(
            id = 8L,
            name = "Existing",
            databaseId = "ex-id",
            token = "tok",
            startupSettings = listOf(
                StartupSetting(
                    parameter = "some_port",
                    type = StartupSettingType.Integer,
                    value = "9000",
                    isAcknowledged = true,
                ),
            ),
        )
        val vm = editEditor(db)
        expandAdvanced()

        val rowId = vm.startupSettings.value.first().id
        composeTestRule.onNodeWithTag("StartupSettingAcknowledge_$rowId")
            .performScrollTo().assertIsOn()
        composeTestRule.onNodeWithTag("StartupSettingAcknowledge_$rowId").performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithTag("StartupSettingAcknowledge_$rowId").assertIsOff()
        composeTestRule.onNodeWithTag("SaveButton").assertIsNotEnabled()
    }

    @Test
    fun rowCapDisablesAddButtons() {
        val vm = newEditor()
        // Fill to the cap directly — clicking Add 64 times would be needlessly slow.
        vm.collectionSyncScopes.value = List(AdvancedSettingsValidator.MAX_ROW_COUNT) {
            CollectionSyncScope(collection = "c$it")
        }
        vm.startupSettings.value = List(AdvancedSettingsValidator.MAX_ROW_COUNT) {
            StartupSetting(parameter = "p$it", type = StartupSettingType.String, value = "v")
        }
        expandAdvanced()

        composeTestRule.onNodeWithTag("AddSyncScopeButton").performScrollTo().assertIsNotEnabled()
        composeTestRule.onNodeWithTag("AddStartupSettingButton").performScrollTo().assertIsNotEnabled()
    }
}
