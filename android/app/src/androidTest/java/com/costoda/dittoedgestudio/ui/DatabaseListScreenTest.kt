package com.costoda.dittoedgestudio.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.longClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.costoda.dittoedgestudio.domain.model.AuthMode
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.ui.database.EmptyDatabasesView
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import com.costoda.dittoedgestudio.viewmodel.DatabaseListUiState
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import com.costoda.dittoedgestudio.ui.database.DatabaseCard

@RunWith(AndroidJUnit4::class)
class DatabaseListScreenTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    // --- Empty state tests ---

    @Test
    fun emptyStateShowsStorageIconAndNoDBsText() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                EmptyDatabasesView()
            }
        }

        composeTestRule.onNodeWithText("No Databases").assertIsDisplayed()
    }

    @Test
    fun emptyStateMessageReadsTapPlusInstruction() {
        composeTestRule.setContent {
            EdgeStudioTheme {
                EmptyDatabasesView()
            }
        }

        composeTestRule.onNodeWithText("Tap + to register a database configuration").assertIsDisplayed()
    }

    // --- DatabaseCard tests ---

    @Test
    fun databaseCardShowsNameAndMaskedInfo() {
        val db = DittoDatabase(
            id = 1L,
            name = "Production DB",
            databaseId = "abc123",
            token = "tok_abc123_xyz",
            mode = AuthMode.SERVER,
        )
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseCard(
                    database = db,
                    onTap = {},
                    onEdit = {},
                    onDelete = {},
                )
            }
        }

        composeTestRule.onNodeWithText("Production DB").assertIsDisplayed()
        composeTestRule.onNodeWithText("Database ID").assertIsDisplayed()
        // databaseId should be masked by default
        composeTestRule.onNodeWithText("••••••••••••••••").assertIsDisplayed()
    }

    @Test
    fun tappingEyeIconRevealsDatabaseId() {
        val db = DittoDatabase(
            id = 1L,
            name = "Test DB",
            databaseId = "visible-db-id",
            token = "tok_abc",
            mode = AuthMode.SERVER,
        )
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseCard(
                    database = db,
                    onTap = {},
                    onEdit = {},
                    onDelete = {},
                )
            }
        }

        // Initially masked
        composeTestRule.onNodeWithText("••••••••••••••••").assertIsDisplayed()
        // Tap eye to reveal
        composeTestRule.onNodeWithContentDescription("Show database ID").performClick()
        // Now shown
        composeTestRule.onNodeWithText("visible-db-id").assertIsDisplayed()
    }

    @Test
    fun longPressingCardShowsContextMenu() {
        val db = DittoDatabase(id = 1L, name = "My DB", databaseId = "db-1", token = "tok")
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseCard(
                    database = db,
                    onTap = {},
                    onEdit = {},
                    onDelete = {},
                )
            }
        }

        composeTestRule.onNodeWithText("My DB").performTouchInput { longClick() }

        composeTestRule.onNodeWithText("Edit").assertIsDisplayed()
        composeTestRule.onNodeWithText("QR Code").assertIsDisplayed()
        composeTestRule.onNodeWithText("Delete").assertIsDisplayed()
    }

    @Test
    fun contextMenuContainsEditQrCodeAndDelete() {
        val db = DittoDatabase(id = 1L, name = "My DB", databaseId = "db-1", token = "tok")
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseCard(
                    database = db,
                    onTap = {},
                    onEdit = {},
                    onDelete = {},
                )
            }
        }

        composeTestRule.onNodeWithText("My DB").performTouchInput { longClick() }

        composeTestRule.onNodeWithText("Edit").assertIsDisplayed()
        composeTestRule.onNodeWithText("QR Code").assertIsDisplayed()
        composeTestRule.onNodeWithText("Delete").assertIsDisplayed()
    }

    @Test
    fun tappingDeleteInContextMenuCallsOnDelete() {
        var deleted = false
        val db = DittoDatabase(id = 1L, name = "DeleteMe", databaseId = "db-1", token = "tok")
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseCard(
                    database = db,
                    onTap = {},
                    onEdit = {},
                    onDelete = { deleted = true },
                )
            }
        }

        composeTestRule.onNodeWithText("DeleteMe").performTouchInput { longClick() }
        composeTestRule.onNodeWithText("Delete").performClick()

        assert(deleted) { "onDelete callback was not called" }
    }

    @Test
    fun tappingEditInContextMenuCallsOnEdit() {
        var edited = false
        val db = DittoDatabase(id = 1L, name = "EditMe", databaseId = "db-1", token = "tok")
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseCard(
                    database = db,
                    onTap = {},
                    onEdit = { edited = true },
                    onDelete = {},
                )
            }
        }

        composeTestRule.onNodeWithText("EditMe").performTouchInput { longClick() }
        composeTestRule.onNodeWithText("Edit").performClick()

        assert(edited) { "onEdit callback was not called" }
    }

    @Test
    fun tappingCardCallsOnTap() {
        var tapped = false
        val db = DittoDatabase(id = 1L, name = "TapMe", databaseId = "db-1", token = "tok")
        composeTestRule.setContent {
            EdgeStudioTheme {
                DatabaseCard(
                    database = db,
                    onTap = { tapped = true },
                    onEdit = {},
                    onDelete = {},
                )
            }
        }

        composeTestRule.onNodeWithText("TapMe").performClick()

        assert(tapped) { "onTap callback was not called" }
    }
}
