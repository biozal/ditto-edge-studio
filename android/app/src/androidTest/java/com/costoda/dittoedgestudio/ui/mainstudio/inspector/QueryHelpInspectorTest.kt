package com.costoda.dittoedgestudio.ui.mainstudio.inspector

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class QueryHelpInspectorTest {

    @get:Rule
    val rule = createComposeRule()

    @Test
    fun helpTabExistsAndRendersMarkdown() {
        rule.setContent {
            MaterialTheme {
                HelpContentView(assetFileName = "query.md")
            }
        }
        // The query.md asset has a heading we pin against. Inspect
        // `android/app/src/main/assets/help/query.md` for the actual top-level heading; if it
        // does not contain "Query Workbench", change this substring to whatever H1 the asset
        // actually carries. Do NOT modify the asset.
        rule.onNodeWithText("Query Workbench", substring = true).assertIsDisplayed()
    }
}
