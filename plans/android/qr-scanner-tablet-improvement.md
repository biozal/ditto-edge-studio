# Plan: Improve QR Scanner Reliability on Tablet

**Date:** 2026-03-10
**Issue:** QR code scanning works instantly on Pixel 10a but is nearly impossible on Pixel Tablet.
**File:** `android/app/src/main/java/com/costoda/dittoedgestudio/ui/qrcode/QrScannerScreen.kt`

---

## Root Causes

### 1. Default `ImageAnalysis` Resolution is Too Low (Primary Cause)
`ImageAnalysis.Builder()` with no resolution hint defaults to `640×480`. On a phone, the QR code typically fills a large portion of that frame. On a tablet:
- The camera has a **wider field of view** — the same QR code occupies far fewer pixels
- ML Kit needs the QR code to be roughly **≥100×100px** to decode reliably
- At 640×480 on a wide tablet camera, a QR code held at a normal distance may be only 30–50px — below the detection threshold

**Fix:** Set `setTargetResolution(Size(1280, 720))` on `ImageAnalysis`. This gives ML Kit 4× more pixels to work with at the same physical distance.

### 2. Scanning All Barcode Formats (Secondary Cause)
`BarcodeScanning.getClient()` with no options scans for every barcode format (QR, PDF417, Data Matrix, Aztec, EAN, UPC, etc.), splitting ML Kit's processing budget across all of them. This slows down the per-frame detection rate.

**Fix:** Use `BarcodeScannerOptions` scoped to `Barcode.FORMAT_QR_CODE` only.

### 3. No Continuous Autofocus
CameraX does not configure autofocus by default for the `ImageAnalysis` use case. The tablet camera may sit at a fixed focus distance that doesn't happen to match where the user holds the QR code.

**Fix:** After binding the camera, retrieve the `Camera` instance from `bindToLifecycle` and start a `FocusMeteringAction` with `AutoFocusCallback` to enable continuous autofocus.

### 4. No Viewfinder Guidance
On a large tablet screen with a full-bleed camera preview, there is no visual target indicating where to aim. Users try random distances and angles without feedback.

**Fix:** Add a semi-transparent overlay with a centered square cutout ("scan window"). This also helps the user keep the QR code close to the center of the frame where ML Kit analysis is most reliable.

---

## Changes

### `QrScannerScreen.kt`

#### 1. Add `BarcodeScannerOptions` with QR-only format
```kotlin
// Before
val barcodeScanner = remember { BarcodeScanning.getClient() }

// After
val barcodeScanner = remember {
    val options = BarcodeScannerOptions.Builder()
        .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
        .build()
    BarcodeScanning.getClient(options)
}
```
New import: `com.google.mlkit.vision.barcode.BarcodeScannerOptions`

#### 2. Set higher target resolution on `ImageAnalysis`
```kotlin
// Before
val imageAnalysis = ImageAnalysis.Builder()
    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
    .build()

// After
val imageAnalysis = ImageAnalysis.Builder()
    .setTargetResolution(android.util.Size(1280, 720))
    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
    .build()
```
New import: `android.util.Size`

#### 3. Enable continuous autofocus after camera bind
```kotlin
// Before
cameraProvider.bindToLifecycle(
    lifecycleOwner,
    CameraSelector.DEFAULT_BACK_CAMERA,
    preview,
    imageAnalysis,
)

// After
val camera = cameraProvider.bindToLifecycle(
    lifecycleOwner,
    CameraSelector.DEFAULT_BACK_CAMERA,
    preview,
    imageAnalysis,
)
// Enable continuous autofocus
val meteringPointFactory = previewView.meteringPointFactory
val centerPoint = meteringPointFactory.createPoint(0.5f, 0.5f)
val action = FocusMeteringAction.Builder(centerPoint, FocusMeteringAction.FLAG_AF)
    .setAutoCancelDuration(2, TimeUnit.SECONDS)
    .build()
camera.cameraControl.startFocusAndMetering(action)
```
New imports:
- `androidx.camera.core.FocusMeteringAction`
- `java.util.concurrent.TimeUnit`

#### 4. Add scan window overlay composable
Add a new private composable `ScanOverlay` drawn on top of the camera preview:

```kotlin
@Composable
private fun ScanOverlay(modifier: Modifier = Modifier) {
    val overlayColor = Color.Black.copy(alpha = 0.5f)
    val strokeColor = SulfurYellow
    Canvas(modifier = modifier) {
        val windowSize = minOf(size.width, size.height) * 0.65f
        val left = (size.width - windowSize) / 2f
        val top = (size.height - windowSize) / 2f

        // Darken outside the window
        drawRect(overlayColor)
        drawRect(
            color = Color.Transparent,
            topLeft = Offset(left, top),
            size = androidx.compose.ui.geometry.Size(windowSize, windowSize),
            blendMode = BlendMode.Clear,
        )

        // Corner brackets
        val cornerLen = windowSize * 0.1f
        val stroke = Stroke(width = 4.dp.toPx(), cap = StrokeCap.Round)
        val corners = listOf(
            Offset(left, top) to listOf(Offset(left + cornerLen, top), Offset(left, top + cornerLen)),
            Offset(left + windowSize, top) to listOf(Offset(left + windowSize - cornerLen, top), Offset(left + windowSize, top + cornerLen)),
            Offset(left, top + windowSize) to listOf(Offset(left + cornerLen, top + windowSize), Offset(left, top + windowSize - cornerLen)),
            Offset(left + windowSize, top + windowSize) to listOf(Offset(left + windowSize - cornerLen, top + windowSize), Offset(left + windowSize, top + windowSize - cornerLen)),
        )
        corners.forEach { (origin, ends) ->
            ends.forEach { end ->
                drawLine(strokeColor, start = origin, end = end, strokeWidth = stroke.width, cap = stroke.cap)
            }
        }
    }
}
```

Wire it into the `Box` in `QrScannerScreen`:
```kotlin
CameraPreview(...)
ScanOverlay(modifier = Modifier.fillMaxSize())  // ← add after CameraPreview
```

New imports:
- `androidx.compose.foundation.Canvas`
- `androidx.compose.ui.geometry.Offset`
- `androidx.compose.ui.graphics.BlendMode`
- `androidx.compose.ui.graphics.drawscope.Stroke`
- `androidx.compose.ui.graphics.StrokeCap`
- `com.costoda.dittoedgestudio.ui.theme.SulfurYellow`

---

## Required Imports Summary

```kotlin
import android.util.Size
import androidx.camera.core.FocusMeteringAction
import androidx.compose.foundation.Canvas
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.costoda.dittoedgestudio.ui.theme.SulfurYellow
import java.util.concurrent.TimeUnit
```

---

## Expected Impact

| Issue | Before | After |
|-------|--------|-------|
| QR code pixel size at normal distance | ~30–50px (too small) | ~120–200px (detectable) |
| ML Kit frame processing | All barcode types | QR only (faster) |
| Autofocus | Static / manual | Continuous center-point AF |
| User guidance | None | Centered scan window with yellow corner brackets |

---

## Verification

- Test on Pixel Tablet in both portrait and landscape
- Test at ~20cm, ~30cm, and ~40cm distance from QR code
- Confirm phone experience (Pixel 10a) is unchanged
- Confirm scan window is centered and visually clear on both form factors
