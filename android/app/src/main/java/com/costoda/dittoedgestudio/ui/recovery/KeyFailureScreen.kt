package com.costoda.dittoedgestudio.ui.recovery

import android.app.Activity
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.LockReset
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * Block screen rendered at the app root when the encrypted database can't be opened
 * (see `data/db/DatabaseOpenResult.KeyFailure`). NO silent wipe — the only way past
 * this screen is an explicit user tap on **Reset stored data**, or backing out of
 * the app via **Close app**.
 *
 * Why this screen instead of crashing: the SQLCipher key is keyed to an Android
 * Keystore alias that can be invalidated outside the app's control (OS security
 * event, biometric/PIN reset on some OEMs, keystore corruption, restored backup
 * whose keystore key didn't travel). Without this surface, the app crashes on the
 * first DAO call with no path to recovery short of clearing app data manually.
 *
 * Design constraints (see plans/android/config-loss-investigation.md item B3):
 * - One explicit destructive action ("Reset stored data") — primary brand-yellow button.
 * - One copy-error action so users can share details with maintainers.
 * - One "Close app" escape hatch so users can back out and seek help BEFORE wiping.
 *   This MUST be a no-op on data.
 * - All text uses explicit theme colors (no implicit LocalContentColor) so dark-mode
 *   contrast is guaranteed.
 */
@Composable
fun KeyFailureScreen(
    errorSummary: String,
    onReset: (onComplete: (success: Boolean) -> Unit) -> Unit,
    isWorking: Boolean = false,
) {
    val context = LocalContext.current
    @Suppress("DEPRECATION") val clipboard = LocalClipboardManager.current
    var showConfirmReset by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues),
            contentAlignment = Alignment.Center,
        ) {
            Surface(
                color = MaterialTheme.colorScheme.surface,
                contentColor = MaterialTheme.colorScheme.onSurface,
                tonalElevation = 2.dp,
                shape = MaterialTheme.shapes.large,
                modifier = Modifier
                    .widthIn(max = 560.dp)
                    .padding(24.dp),
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .padding(24.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    Text(
                        text = "Stored configurations can't be opened",
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                    )

                    Text(
                        text = "The encryption key that protects your saved database " +
                            "configurations is no longer available. This usually happens " +
                            "after an OS security event (PIN/biometric reset on some " +
                            "devices, restored backup, or keystore corruption). The " +
                            "existing data can't be recovered.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                    )

                    Text(
                        text = "Resetting will:",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        text = "• Delete saved database configurations, subscriptions, " +
                            "favorites, observers, and query history.\n" +
                            "• Delete Ditto's local sync data (peers will re-sync from the " +
                            "cloud once you re-add a database).\n" +
                            "• Generate a fresh encryption key.\n\n" +
                            "You can re-import configurations by scanning a QR code if you " +
                            "backed them up from another device.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                    )

                    // Error summary block — monospace so users can copy / read it.
                    Surface(
                        color = MaterialTheme.colorScheme.surfaceContainerHigh,
                        contentColor = MaterialTheme.colorScheme.onSurface,
                        shape = MaterialTheme.shapes.small,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(
                            text = errorSummary,
                            style = MaterialTheme.typography.bodySmall,
                            fontFamily = FontFamily.Monospace,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(12.dp),
                        )
                    }

                    OutlinedButton(
                        onClick = { clipboard.setText(AnnotatedString(errorSummary)) },
                        enabled = !isWorking,
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("KeyFailureCopyErrorButton"),
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.ContentCopy,
                            contentDescription = null,
                        )
                        Text(
                            text = "  Copy error details",
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                    }

                    Button(
                        onClick = { showConfirmReset = true },
                        enabled = !isWorking,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.primary,
                            contentColor = MaterialTheme.colorScheme.onPrimary,
                        ),
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("KeyFailureResetButton"),
                    ) {
                        if (isWorking) {
                            CircularProgressIndicator(
                                color = MaterialTheme.colorScheme.onPrimary,
                                strokeWidth = 2.dp,
                                modifier = Modifier.padding(end = 8.dp),
                            )
                        } else {
                            Icon(
                                imageVector = Icons.Outlined.LockReset,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onPrimary,
                            )
                        }
                        Text(
                            text = if (isWorking) "  Working..." else "  Reset stored data",
                            color = MaterialTheme.colorScheme.onPrimary,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }

                    TextButton(
                        onClick = { (context as? Activity)?.finish() },
                        enabled = !isWorking,
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("KeyFailureCloseAppButton"),
                    ) {
                        Text(
                            text = "Close app",
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                    }
                }
            }
        }
    }

    if (showConfirmReset) {
        AlertDialog(
            onDismissRequest = { showConfirmReset = false },
            containerColor = MaterialTheme.colorScheme.surface,
            iconContentColor = MaterialTheme.colorScheme.onSurface,
            titleContentColor = MaterialTheme.colorScheme.onSurface,
            textContentColor = MaterialTheme.colorScheme.onSurface,
            title = {
                Text(
                    text = "Reset stored data?",
                    color = MaterialTheme.colorScheme.onSurface,
                )
            },
            text = {
                Text(
                    text = "This permanently deletes all saved configurations, history, " +
                        "favorites, and local Ditto data. This cannot be undone.",
                    color = MaterialTheme.colorScheme.onSurface,
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        showConfirmReset = false
                        onReset { success ->
                            // After a successful reset, recreate the activity so a fresh
                            // Koin graph is built and we land on the empty database list.
                            if (success) {
                                (context as? ComponentActivity)?.recreate()
                            }
                        }
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary,
                        contentColor = MaterialTheme.colorScheme.onPrimary,
                    ),
                ) {
                    Text(
                        text = "Reset",
                        color = MaterialTheme.colorScheme.onPrimary,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { showConfirmReset = false }) {
                    Text(
                        text = "Cancel",
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                }
            },
        )
    }
}
