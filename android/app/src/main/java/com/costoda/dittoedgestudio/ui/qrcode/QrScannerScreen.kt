package com.costoda.dittoedgestudio.ui.qrcode

import android.Manifest
import android.content.pm.PackageManager
import android.view.ScaleGestureDetector
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.Camera
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
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.costoda.dittoedgestudio.ui.theme.SulfurYellow
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import kotlinx.coroutines.delay
import org.koin.androidx.compose.koinViewModel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

// Initial zoom applied on camera bind. 2× helps fixed-focus tablet cameras
// (e.g. Pixel Tablet) whose focal plane is calibrated for arm's-length video
// calls rather than close-up scanning. The user can pinch to adjust further.
private const val INITIAL_ZOOM = 2.0f

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
    // Incremented on retry to reset the hasDetected flag inside CameraPreview
    var scanResetKey by remember { mutableIntStateOf(0) }
    // Current zoom ratio reported back by CameraPreview for display
    var currentZoom by remember { mutableFloatStateOf(INITIAL_ZOOM) }

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
                    resetKey = scanResetKey,
                    onBarcodeDetected = { barcode ->
                        barcode.rawValue?.let { viewModel.processBarcode(it) }
                    },
                    onZoomChanged = { ratio -> currentZoom = ratio },
                )
                ScanOverlay(
                    modifier = Modifier.fillMaxSize(),
                    zoomRatio = currentZoom,
                )
            }

            if (uiState is QrScannerUiState.Processing) {
                CircularProgressIndicator()
            }

            if (uiState is QrScannerUiState.Error) {
                AlertDialog(
                    onDismissRequest = {
                        viewModel.resetError()
                        scanResetKey++
                    },
                    title = { Text("Invalid QR Code") },
                    text = { Text((uiState as QrScannerUiState.Error).message) },
                    confirmButton = {
                        TextButton(onClick = {
                            viewModel.resetError()
                            scanResetKey++
                        }) {
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
    resetKey: Int = 0,
    onBarcodeDetected: (Barcode) -> Unit,
    onZoomChanged: (Float) -> Unit = {},
) {
    val context = LocalContext.current
    val executor = remember { Executors.newSingleThreadExecutor() }
    val barcodeScanner = remember {
        val options = BarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .build()
        BarcodeScanning.getClient(options)
    }
    // resetKey causes this to reset when the user retries after an error
    val hasDetected = remember(resetKey) { AtomicBoolean(false) }
    val cameraRef = remember { mutableStateOf<Camera?>(null) }
    val previewViewRef = remember { mutableStateOf<PreviewView?>(null) }

    // On autofocus cameras (phones) re-trigger AF periodically.
    // On fixed-focus cameras (Pixel Tablet) this is a no-op for focus but
    // keeps AE metering locked to the centre frame, which helps exposure.
    LaunchedEffect(cameraRef.value) {
        val cam = cameraRef.value ?: return@LaunchedEffect
        while (true) {
            delay(2_000)
            val pv = previewViewRef.value ?: continue
            try {
                val centerPoint = pv.meteringPointFactory.createPoint(0.5f, 0.5f)
                val action = FocusMeteringAction.Builder(centerPoint, FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE)
                    .build()
                cam.cameraControl.startFocusAndMetering(action)
            } catch (_: Exception) { }
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            executor.shutdown()
            barcodeScanner.close()
        }
    }

    androidx.compose.ui.viewinterop.AndroidView(
        modifier = modifier,
        factory = { ctx ->
            val previewView = PreviewView(ctx)
            previewViewRef.value = previewView

            val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)
            cameraProviderFuture.addListener({
                val cameraProvider = cameraProviderFuture.get()
                val preview = Preview.Builder().build().also {
                    it.surfaceProvider = previewView.surfaceProvider
                }
                val imageAnalysis = ImageAnalysis.Builder()
                    .setResolutionSelector(
                        ResolutionSelector.Builder()
                            .setResolutionStrategy(
                                ResolutionStrategy(
                                    android.util.Size(1920, 1080),
                                    ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER,
                                ),
                            )
                            .build(),
                    )
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

                    // Apply initial zoom. 2× works well for fixed-focus tablet
                    // cameras by bringing the QR code into the focal sweet spot
                    // without the user needing to move the tablet.
                    val maxZoom = camera.cameraInfo.zoomState.value?.maxZoomRatio ?: 1f
                    val initialZoom = INITIAL_ZOOM.coerceAtMost(maxZoom)
                    camera.cameraControl.setZoomRatio(initialZoom)
                    onZoomChanged(initialZoom)

                    // Initial AE/AF metering on screen centre
                    val centerPoint = previewView.meteringPointFactory.createPoint(0.5f, 0.5f)
                    val action = FocusMeteringAction.Builder(centerPoint, FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE)
                        .build()
                    camera.cameraControl.startFocusAndMetering(action)

                    // Pinch-to-zoom: lets users fine-tune the zoom level when
                    // the default 2× isn't quite right for their screen distance.
                    val scaleDetector = ScaleGestureDetector(
                        ctx,
                        object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
                            override fun onScale(detector: ScaleGestureDetector): Boolean {
                                val current = camera.cameraInfo.zoomState.value?.zoomRatio ?: 1f
                                val minZoom = camera.cameraInfo.zoomState.value?.minZoomRatio ?: 1f
                                val max = camera.cameraInfo.zoomState.value?.maxZoomRatio ?: maxZoom
                                val next = (current * detector.scaleFactor).coerceIn(minZoom, max)
                                camera.cameraControl.setZoomRatio(next)
                                onZoomChanged(next)
                                return true
                            }
                        },
                    )
                    previewView.setOnTouchListener { view, event ->
                        scaleDetector.onTouchEvent(event)
                        view.performClick()
                        true
                    }

                    cameraRef.value = camera
                } catch (_: Exception) { }
            }, ContextCompat.getMainExecutor(ctx))
            previewView
        },
    )
}

@Composable
private fun ScanOverlay(
    modifier: Modifier = Modifier,
    zoomRatio: Float = INITIAL_ZOOM,
) {
    val overlayColor = Color.Black.copy(alpha = 0.5f)
    val strokeColor = SulfurYellow

    Box(modifier = modifier) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val windowSize = minOf(size.width, size.height) * 0.65f
            val left = (size.width - windowSize) / 2f
            val top = (size.height - windowSize) / 2f
            val right = left + windowSize
            val bottom = top + windowSize
            val cornerLen = windowSize * 0.1f
            val strokeWidth = 4.dp.toPx()

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

        // Zoom level badge — bottom-centre of scan window
        Text(
            text = "${"%.1f".format(zoomRatio)}×  ·  Pinch to zoom",
            color = Color.White,
            style = MaterialTheme.typography.labelSmall,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 48.dp),
        )

        // Distance hint — below the zoom badge
        Text(
            text = "Hold tablet ~40 cm from the screen",
            color = Color.White.copy(alpha = 0.7f),
            style = MaterialTheme.typography.labelSmall,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 28.dp),
        )
    }
}
