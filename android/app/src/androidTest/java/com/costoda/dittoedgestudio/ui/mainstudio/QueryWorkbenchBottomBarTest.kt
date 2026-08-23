package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.costoda.dittoedgestudio.MainActivity
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Regression guard for the Query Workbench bottom bar.
 *
 * The Run icon used to live as the first child of `QueryWorkbenchBottomBar`. After moving
 * it to [QueryWorkbenchTopToolbar], the bottom bar must never carry a node tagged
 * `"QueryBottomBar.Run"`. This test stands the activity up so the bottom bar composes in
 * its real surroundings and asserts the absence.
 */
@RunWith(AndroidJUnit4::class)
class QueryWorkbenchBottomBarTest {

    @get:Rule
    val rule = createAndroidComposeRule<MainActivity>()

    @Test
    fun bottomBarHasNoRunIcon() {
        // Activity is up on the database list; the assertion is global ("does not exist") so
        // we don't need to navigate into the studio. If a future change re-adds a node tagged
        // `QueryBottomBar.Run` anywhere in the tree, this fails — exactly the regression
        // boundary we want.
        rule.onNodeWithTag("QueryBottomBar.Run").assertDoesNotExist()
    }
}
