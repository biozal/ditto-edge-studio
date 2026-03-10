package com.costoda.dittoedgestudio.ui.qrcode

import android.Manifest
import android.content.pm.PackageManager
import android.util.Size
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Canvas
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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.costoda.dittoedgestudio.ui.theme.SulfurYellow
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import org.koin.androidx.compose.koinViewModel
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QrScannerScreen(
    onNavigateBack: () -> Unit,
    viewModel: QrScannerViewModel = koinViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED,
        )
    }
    var showRationale by remember { mutableStateOf(false) }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) {
            hasCameraPermission = true
            viewModel.startScanning()
        } else {
            showRationale = true
        }
    }

    LaunchedEffect(Unit) {
        if (hasCameraPermission) {
            viewModel.startScanning()
        } else {
            permissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    // Navigate back on successful import
    LaunchedEffect(uiState) {
        if (uiState is QrScannerUiState.Success) {
            onNavigateBack()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Scan QR Code") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
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
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues),
            contentAlignment = Alignment.Center,
        ) {
            if (hasCameraPermission && uiState !is QrScannerUiState.Success) {
                CameraPreview(
                    modifier = Modifier.fillMaxSize(),
                    lifecycleOwner = lifecycleOwner,
                    onBarcodeDetected = { barcode ->
                        barcode.rawValue?.let { viewModel.processBarcode(it) }
                    },
                )
                ScanOverlay(modifier = Modifier.fillMaxSize())
            }

            if (uiState is QrScannerUiState.Processing) {
                CircularProgressIndicator()
            }

            if (uiState is QrScannerUiState.Error) {
                AlertDialog(
                    onDismissRequest = { viewModel.resetError() },
                    title = { Text("Invalid QR Code") },
                    text = { Text((uiState as QrScannerUiState.Error).message) },
                    confirmButton = {
                        TextButton(onClick = { viewModel.resetError() }) {
                            Text("Retry")
                        }
                    },
                )
            }

            if (showRationale) {
                AlertDialog(
                    onDismissRequest = onNavigateBack,
                    title = { Text("Camera Permission Required") },
                    text = { Text("Camera access is needed to scan QR codes for importing database configs.") },
                    confirmButton = {
                        TextButton(onClick = {
                            showRationale = false
                            permissionLauncher.launch(Manifest.permission.CAMERA)
                        }) {
                            Text("Grant Permission")
                        }
                    },
                    dismissButton = {
                        TextButton(onClick = onNavigateBack) {
                            Text("Cancel")
                        }
                    },
                )
            }
        }
    }
}

@Composable
private fun CameraPreview(
    modifier: Modifier = Modifier,
    lifecycleOwner: LifecycleOwner,
    onBarcodeDetected: (Barcode) -> Unit,
) {
    val context = LocalContext.current
    val executor = remember { Executors.newSingleThreadExecutor() }
    val barcodeScanner = remember {
        val options = BarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .build()
        BarcodeScanning.getClient(options)
    }
    val hasDetected = remember { AtomicBoolean(false) }

    DisposableEffect(Unit) {
        onDispose {
            executor.shutdown()
            barcodeScanner.close()
        }
    }

    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            val previewView = PreviewView(ctx)
            val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)
            cameraProviderFuture.addListener({
                val cameraProvider = cameraProviderFuture.get()
                val preview = Preview.Builder().build().also {
                    it.surfaceProvider = previewView.surfaceProvider
                }
                val imageAnalysis = ImageAnalysis.Builder()
                    .setTargetResolution(Size(1280, 720))
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                imageAnalysis.setAnalyzer(executor) { imageProxy ->
                    val mediaImage = imageProxy.image
                    if (mediaImage != null && !hasDetected.get()) {
                        val image = InputImage.fromMediaImage(
                            mediaImage,
                            imageProxy.imageInfo.rotationDegrees,
                        )
                        barcodeScanner.process(image)
                            .addOnSuccessListener { barcodes ->
                                barcodes.firstOrNull()?.let { barcode ->
                                    if (hasDetected.compareAndSet(false, true)) {
                                        onBarcodeDetected(barcode)
                                    }
                                }
                            }
                            .addOnCompleteListener { imageProxy.close() }
                    } else {
                        imageProxy.close()
                    }
                }
                try {
                    cameraProvider.unbindAll()
                    val camera = cameraProvider.bindToLifecycle(
                        lifecycleOwner,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        imageAnalysis,
                    )
                    // Enable continuous autofocus on the center of the frame
                    val centerPoint = previewView.meteringPointFactory.createPoint(0.5f, 0.5f)
                    val focusAction = FocusMeteringAction.Builder(centerPoint, FocusMeteringAction.FLAG_AF)
                        .setAutoCancelDuration(2, TimeUnit.SECONDS)
                        .build()
                    camera.cameraControl.startFocusAndMetering(focusAction)
                } catch (_: Exception) { }
            }, ContextCompat.getMainExecutor(ctx))
            previewView
        },
    )
}

@Composable
private fun ScanOverlay(modifier: Modifier = Modifier) {
    val overlayColor = Color.Black.copy(alpha = 0.5f)
    val strokeColor = SulfurYellow
    Canvas(modifier = modifier) {
        val windowSize = minOf(size.width, size.height) * 0.65f
        val left = (size.width - windowSize) / 2f
        val top = (size.height - windowSize) / 2f
        val right = left + windowSize
        val bottom = top + windowSize
        val cornerLen = windowSize * 0.1f
        val strokeWidth = 4.dp.toPx()

        // Darken the area outside the scan window
        drawRect(color = overlayColor)
        drawRect(
            color = Color.Transparent,
            topLeft = Offset(left, top),
            size = androidx.compose.ui.geometry.Size(windowSize, windowSize),
            blendMode = BlendMode.Clear,
        )

        // Corner brackets — top-left
        drawLine(strokeColor, Offset(left, top), Offset(left + cornerLen, top), strokeWidth, StrokeCap.Round)
        drawLine(strokeColor, Offset(left, top), Offset(left, top + cornerLen), strokeWidth, StrokeCap.Round)
        // Corner brackets — top-right
        drawLine(strokeColor, Offset(right, top), Offset(right - cornerLen, top), strokeWidth, StrokeCap.Round)
        drawLine(strokeColor, Offset(right, top), Offset(right, top + cornerLen), strokeWidth, StrokeCap.Round)
        // Corner brackets — bottom-left
        drawLine(strokeColor, Offset(left, bottom), Offset(left + cornerLen, bottom), strokeWidth, StrokeCap.Round)
        drawLine(strokeColor, Offset(left, bottom), Offset(left, bottom - cornerLen), strokeWidth, StrokeCap.Round)
        // Corner brackets — bottom-right
        drawLine(strokeColor, Offset(right, bottom), Offset(right - cornerLen, bottom), strokeWidth, StrokeCap.Round)
        drawLine(strokeColor, Offset(right, bottom), Offset(right, bottom - cornerLen), strokeWidth, StrokeCap.Round)
    }
}
