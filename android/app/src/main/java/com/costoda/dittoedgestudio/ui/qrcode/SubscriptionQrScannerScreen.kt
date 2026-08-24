package com.costoda.dittoedgestudio.ui.qrcode

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.ExperimentalGetImage
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.costoda.dittoedgestudio.util.SubscriptionsQrCodec
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel
import kotlinx.coroutines.launch

/**
 * Scans an `EDS_SUBS1:` QR code and bulk-imports the subscriptions it carries
 * (parity with the SwiftUI `SubscriptionQRScannerView`). Saves go through the
 * studio session's [MainStudioViewModel.addSubscription] so Room persistence,
 * live `ditto.sync.registerSubscription`, and the save-completion
 * (NonCancellable) semantics match the by-hand editor flow.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SubscriptionQrScannerScreen(
    viewModel: MainStudioViewModel,
    onClose: (importedCount: Int) -> Unit,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()

    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED,
        )
    }
    var scanResetKey by remember { mutableIntStateOf(0) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var importing by remember { mutableStateOf(false) }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> hasCameraPermission = granted }

    LaunchedEffect(Unit) {
        if (!hasCameraPermission) permissionLauncher.launch(Manifest.permission.CAMERA)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Import subscriptions") },
                navigationIcon = {
                    IconButton(onClick = { onClose(0) }) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
            )
        },
    ) { paddingValues ->
        Box(
            modifier = Modifier.fillMaxSize().padding(paddingValues),
            contentAlignment = Alignment.Center,
        ) {
            if (hasCameraPermission && !importing) {
                CameraPreview(
                    modifier = Modifier.fillMaxSize(),
                    lifecycleOwner = lifecycleOwner,
                    resetKey = scanResetKey,
                    onBarcodeDetected = { barcode ->
                        val raw = barcode.rawValue ?: return@CameraPreview
                        val items = SubscriptionsQrCodec.decode(raw)
                        if (items == null) {
                            errorMessage = "Not an Edge Studio subscriptions QR code"
                            return@CameraPreview
                        }
                        importing = true
                        scope.launch {
                            var imported = 0
                            for (item in items) {
                                if (viewModel.addSubscription(item.name, item.query).isSuccess) {
                                    imported++
                                }
                            }
                            onClose(imported)
                        }
                    },
                )
                ScanOverlay(modifier = Modifier.fillMaxSize(), zoomRatio = 1.0f)
            }

            if (importing) {
                CircularProgressIndicator()
            }

            errorMessage?.let { message ->
                AlertDialog(
                    onDismissRequest = {
                        errorMessage = null
                        scanResetKey++
                    },
                    title = { Text("Invalid QR Code") },
                    text = { Text(message) },
                    confirmButton = {
                        TextButton(onClick = {
                            errorMessage = null
                            scanResetKey++
                        }) {
                            Text("Retry")
                        }
                    },
                )
            }
        }
    }
}
