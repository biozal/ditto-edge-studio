package com.costoda.dittoedgestudio.ui.mainstudio.inspector

import android.widget.TextView
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.assertion.ViewAssertions.matches
import androidx.test.espresso.matcher.ViewMatchers.isAssignableFrom
import androidx.test.espresso.matcher.ViewMatchers.isDisplayed
import androidx.test.espresso.matcher.ViewMatchers.withText
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.hamcrest.Matchers.allOf
import org.hamcrest.Matchers.containsString
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
        // Markwon renders into a native TextView inside AndroidView, not Compose
        // text semantics. Asset loading also runs on Dispatchers.IO, so wait for
        // the rendered heading rather than assuming Compose idleness completes IO.
        val renderedHelp = allOf(
            isAssignableFrom(TextView::class.java),
            withText(containsString("Query Workbench")),
        )
        rule.waitUntil(timeoutMillis = 5_000) {
            var displayed = false
            onView(renderedHelp).check { view, _ ->
                displayed = view != null && isDisplayed().matches(view)
            }
            displayed
        }
        onView(renderedHelp).check(matches(isDisplayed()))
    }
}
