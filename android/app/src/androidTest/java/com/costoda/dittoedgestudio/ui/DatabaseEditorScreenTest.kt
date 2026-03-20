package com.costoda.dittoedgestudio.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.costoda.dittoedgestudio.data.repository.DatabaseRepository
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.ui.database.DatabaseEditorScreen
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import com.costoda.dittoedgestudio.viewmodel.DatabaseEditorViewModel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Compose UI tests for DatabaseEditorScreen.
 *
 * Uses a [FakeDatabaseRepository] backed by an in-memory list to avoid
 * SQLCipher/Keystore initialisation in the test context.
 */
@RunWith(AndroidJUnit4::class)
class DatabaseEditorScreenTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    /** Minimal in-memory repository for UI testing. */
    class FakeDatabaseRepository : DatabaseRepository {
        val databases = mutableListOf<DittoDatabase>()
        private var nextId = 1L

        override fun observeAll(): Flow<List<DittoDatabase>> = flowOf(databases.toList())
        override suspend fun getAll() = databases.toList()
        override suspend fun getById(id: Long): DittoDatabase? =
            databases.firstOrNull { it.id == id }

        override suspend fun getByDatabaseId(databaseId: String) =
            databases.firstOrNull { it.databaseId == databaseId }

        override suspend fun save(database: DittoDatabase): Long {
            return if (database.id == 0L) {
                val id = nextId++
                databases.add(database.copy(id = id))
                id
            } else {
                val idx = databases.indexOfFirst { it.id == database.id }
                if (idx >= 0) databases[idx] = database
                database.id
            }
        }

        override suspend fun delete(id: Long) {
            databases.removeAll { it.id == id }
        }

        override suspend fun deleteByDatabaseId(databaseId: String) {
            databases.removeAll { it.databaseId == databaseId }
        }
    }

    private fun newItemViewModel(repo: DatabaseRepository = FakeDatabaseRepository()) =
        DatabaseEditorViewModel(-1L, repo)

    private fun editItemViewModel(
        db: DittoDatabase,
        repo: DatabaseRepository = FakeDatabaseRepository(),
    ): DatabaseEditorViewModel {
        val vm = DatabaseEditorViewModel(db.id, repo)
        vm.loadForEdit(db)
        return vm
    }

    // --- Title tests ---

    @Test
    fun screenShowsRegisterDatabaseTitleForNewItem() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseEditorScreen(
                    databaseId = -1L,
                    onDismiss = {},
                    viewModel = newItemViewModel(),
                )
            }
        }

        composeTestRule.onNodeWithText("Register Database").assertIsDisplayed()
    }

    @Test
    fun screenShowsEditDatabaseTitleForExistingItem() {
        val db = DittoDatabase(id = 5L, name = "Existing", databaseId = "ex-id", token = "tok")
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseEditorScreen(
                    databaseId = 5L,
                    onDismiss = {},
                    viewModel = editItemViewModel(db),
                )
            }
        }

        composeTestRule.onNodeWithText("Edit Database").assertIsDisplayed()
    }

    // --- Tab tests ---

    @Test
    fun serverTabIsSelectedByDefault() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseEditorScreen(
                    databaseId = -1L,
                    onDismiss = {},
                    viewModel = newItemViewModel(),
                )
            }
        }

        // Server tab label is visible and Auth URL field is present
        composeTestRule.onNodeWithText("Server").assertIsDisplayed()
        composeTestRule.onNodeWithTag("AuthUrlField").assertIsDisplayed()
    }

    @Test
    fun switchingToSmallPeersOnlyTabHidesAuthUrlField() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseEditorScreen(
                    databaseId = -1L,
                    onDismiss = {},
                    viewModel = newItemViewModel(),
                )
            }
        }

        composeTestRule.onNodeWithText("Small Peers Only").performClick()

        // Auth URL is not composed when in Small Peers Only mode
        composeTestRule.onNodeWithTag("AuthUrlField").assertDoesNotExist()
    }

    @Test
    fun switchingToSmallPeersOnlyTabShowsSharedKeyField() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseEditorScreen(
                    databaseId = -1L,
                    onDismiss = {},
                    viewModel = newItemViewModel(),
                )
            }
        }

        composeTestRule.onNodeWithText("Small Peers Only").performClick()

        composeTestRule.onNodeWithTag("SharedKeyField").assertIsDisplayed()
    }

    @Test
    fun serverTabShowsAuthUrlField() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseEditorScreen(
                    databaseId = -1L,
                    onDismiss = {},
                    viewModel = newItemViewModel(),
                )
            }
        }

        composeTestRule.onNodeWithTag("AuthUrlField").assertIsDisplayed()
    }

    @Test
    fun serverTabDoesNotShowWebsocketUrlField() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseEditorScreen(
                    databaseId = -1L,
                    onDismiss = {},
                    viewModel = newItemViewModel(),
                )
            }
        }

        // Websocket URL is intentionally omitted for SDK 5.0
        composeTestRule.onNodeWithText("Websocket URL").assertDoesNotExist()
        composeTestRule.onNodeWithText("WebSocket URL").assertDoesNotExist()
    }

    // --- Save button validation ---

    @Test
    fun saveButtonIsDisabledWhenRequiredFieldsAreEmpty() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseEditorScreen(
                    databaseId = -1L,
                    onDismiss = {},
                    viewModel = newItemViewModel(),
                )
            }
        }

        composeTestRule.onNodeWithTag("SaveButton").assertIsNotEnabled()
    }

    @Test
    fun saveButtonEnablesWhenAllRequiredFieldsAreFilled() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseEditorScreen(
                    databaseId = -1L,
                    onDismiss = {},
                    viewModel = newItemViewModel(),
                )
            }
        }

        composeTestRule.onNodeWithTag("NameField").performTextInput("My DB")
        composeTestRule.onNodeWithTag("DatabaseIdField").performTextInput("db-id-123")
        composeTestRule.onNodeWithTag("TokenField").performTextInput("token-abc")

        composeTestRule.onNodeWithTag("SaveButton").assertIsEnabled()
    }

    @Test
    fun tappingSaveNavigatesBackViaDismiss() {
        var dismissed = false
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseEditorScreen(
                    databaseId = -1L,
                    onDismiss = { dismissed = true },
                    viewModel = newItemViewModel(),
                )
            }
        }

        composeTestRule.onNodeWithTag("NameField").performTextInput("New DB")
        composeTestRule.onNodeWithTag("DatabaseIdField").performTextInput("new-db-id")
        composeTestRule.onNodeWithTag("TokenField").performTextInput("new-token")
        composeTestRule.onNodeWithTag("SaveButton").performClick()

        composeTestRule.waitForIdle()
        assert(dismissed) { "onDismiss was not called after save" }
    }

    @Test
    fun savedItemAppearsInRepository() {
        val repo = FakeDatabaseRepository()
        var dismissed = false
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseEditorScreen(
                    databaseId = -1L,
                    onDismiss = { dismissed = true },
                    viewModel = newItemViewModel(repo),
                )
            }
        }

        composeTestRule.onNodeWithTag("NameField").performTextInput("Saved DB")
        composeTestRule.onNodeWithTag("DatabaseIdField").performTextInput("saved-db-id")
        composeTestRule.onNodeWithTag("TokenField").performTextInput("saved-token")
        composeTestRule.onNodeWithTag("SaveButton").performClick()

        composeTestRule.waitForIdle()
        assert(repo.databases.any { it.name == "Saved DB" }) { "Saved database not found in repository" }
    }

    // --- Info banner ---

    @Test
    fun infoBannerShowsForNewItem() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseEditorScreen(
                    databaseId = -1L,
                    onDismiss = {},
                    viewModel = newItemViewModel(),
                )
            }
        }

        composeTestRule.onNodeWithText(
            "This information comes from the Ditto Portal",
            substring = true,
        ).assertIsDisplayed()
    }

    @Test
    fun infoBannerDoesNotShowForExistingItem() {
        val db = DittoDatabase(id = 5L, name = "Existing", databaseId = "ex-id", token = "tok")
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseEditorScreen(
                    databaseId = 5L,
                    onDismiss = {},
                    viewModel = editItemViewModel(db),
                )
            }
        }

        composeTestRule.onNodeWithText(
            "This information comes from the Ditto Portal",
            substring = true,
        ).assertDoesNotExist()
    }

    // --- Log level dropdown ---

    @Test
    fun logLevelDropdownShowsAllOptionsWhenExpanded() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseEditorScreen(
                    databaseId = -1L,
                    onDismiss = {},
                    viewModel = newItemViewModel(),
                )
            }
        }

        // Click on the current value text to expand
        composeTestRule.onNodeWithText("Info (Default)").performClick()

        composeTestRule.onNodeWithTag("LogLevel_error").assertIsDisplayed()
        composeTestRule.onNodeWithTag("LogLevel_warning").assertIsDisplayed()
        composeTestRule.onNodeWithTag("LogLevel_debug").assertIsDisplayed()
        composeTestRule.onNodeWithTag("LogLevel_verbose").assertIsDisplayed()
    }

    @Test
    fun selectingLogLevelUpdatesTheField() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseEditorScreen(
                    databaseId = -1L,
                    onDismiss = {},
                    viewModel = newItemViewModel(),
                )
            }
        }

        composeTestRule.onNodeWithText("Info (Default)").performClick()
        composeTestRule.onNodeWithTag("LogLevel_debug").performClick()

        // After selecting Debug, the field should display "Debug"
        composeTestRule.onNodeWithText("Debug").assertIsDisplayed()
    }

    // --- Cancel / X ---

    @Test
    fun cancelButtonCallsOnDismissWithoutSaving() {
        var dismissed = false
        val repo = FakeDatabaseRepository()
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseEditorScreen(
                    databaseId = -1L,
                    onDismiss = { dismissed = true },
                    viewModel = newItemViewModel(repo),
                )
            }
        }

        composeTestRule.onNodeWithContentDescription("Dismiss").performClick()

        assert(dismissed) { "onDismiss was not called when X was tapped" }
        assert(repo.databases.isEmpty()) { "No database should have been saved on cancel" }
    }
}
