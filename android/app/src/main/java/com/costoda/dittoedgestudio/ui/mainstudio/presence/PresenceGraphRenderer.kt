package com.costoda.dittoedgestudio.ui.mainstudio.presence

import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Pure draw helpers for the presence graph. No state, no remember{}, no recompose
 * triggers. Callers pass in pre-allocated [Path] / [PathEffect] objects so the hot
 * path (`drawBehind { … }`) makes zero allocations per frame.
 *
 * DrawScope inherits from Density, so dp-to-px conversions happen inline — no extra
 * threading of LocalDensity through call sites.
 */

/**
 * Draw a quadratic Bézier edge between two canvas-space points.
 *
 * @param fromPos endpoint A in canvas pixels (post y-flip, post scene translate).
 * @param toPos   endpoint B in canvas pixels.
 * @param sceneCenter pixel position of the local peer. Used only when [arcOutward]
 *                    is true: the Bézier control point is pushed radially outward
 *                    from this point so remote↔remote arcs bend around the cluster
 *                    instead of cutting through it.
 * @param parallelOffsetPx perpendicular shift for parallel-edge separation, in
 *                         DESIGN pixels at 1x zoom (matches `ConnectionLine.lineOffset`
 *                         in iOS). Scaled by [zoom] here — see below.
 * @param zoom camera zoom. [fromPos] / [toPos] arrive already in canvas space, but
 *             every *thickness* in this function is a design-space constant, so each
 *             one is scaled here. That matters most for [parallelOffsetPx]: an
 *             unscaled 10 dp perpendicular shift is a fifth of a pill's height at
 *             100% but nearly three times it at 34%, which walks the endpoint clear
 *             out of the pill the edge is supposed to terminate in.
 * @param path reusable [Path] buffer; reset and refilled in place.
 */
@Suppress("LongParameterList")
internal fun DrawScope.drawPresenceEdge(
    fromPos: Offset,
    toPos: Offset,
    sceneCenter: Offset,
    color: Color,
    dashEffect: PathEffect,
    strokeWidthPx: Float,
    alpha: Float,
    isCloud: Boolean,
    arcOutward: Boolean,
    parallelOffsetPx: Float,
    cloudCircleSpacingPx: Float,
    zoom: Float,
    path: Path,
    /** Reusable PathMeasure for cloud-edge decorative circles. Allocating one per
     *  frame on a cloud-heavy graph was a measurable hotspot; the caller pools one
     *  alongside [path]. */
    pathMeasure: PathMeasure = PathMeasure(),
) {
    val dx = toPos.x - fromPos.x
    val dy = toPos.y - fromPos.y
    val distance = sqrt(dx * dx + dy * dy)

    val strokePx = edgeStrokeWidthPx(strokeWidthPx, zoom, MIN_EDGE_STROKE_DP.dp.toPx())

    path.reset()
    if (distance < 0.1f) {
        // Coincident endpoints — collapse to a single point to avoid NaN math. Matches
        // iOS `ConnectionLine.createCurvedPath` fallback.
        path.moveTo(fromPos.x, fromPos.y)
        path.lineTo(fromPos.x, fromPos.y)
        drawPath(
            path = path,
            color = color,
            alpha = alpha,
            style = Stroke(
                width = strokePx,
                cap = StrokeCap.Round,
                join = StrokeJoin.Round,
                pathEffect = dashEffect,
            ),
        )
        return
    }

    // Scale the separation with the camera so both endpoints stay inside their pills.
    val offsetPx = parallelEdgeOffsetPx(parallelOffsetPx, zoom)
    val (from, to) = if (offsetPx == 0f) {
        fromPos to toPos
    } else {
        val ox = -dy / distance * offsetPx
        val oy = dx / distance * offsetPx
        Offset(fromPos.x + ox, fromPos.y + oy) to Offset(toPos.x + ox, toPos.y + oy)
    }

    val midX = (from.x + to.x) * 0.5f
    val midY = (from.y + to.y) * 0.5f

    // Arc-height ceilings are design-space too: unscaled, they stop clamping as the
    // camera zooms out and start over-clamping as it zooms in, so the same topology
    // bows by a different amount at different zooms.
    val arcAmount90Px = 90.dp.toPx() * zoom
    val arcAmount60Px = 60.dp.toPx() * zoom

    val control: Offset = if (arcOutward) {
        val rx = midX - sceneCenter.x
        val ry = midY - sceneCenter.y
        val midLen = sqrt(rx * rx + ry * ry)
        val curveAmount = minOf(distance * 0.25f, arcAmount90Px)
        if (midLen > 1f) {
            Offset(midX + (rx / midLen) * curveAmount, midY + (ry / midLen) * curveAmount)
        } else {
            val fallback = minOf(distance * 0.15f, arcAmount60Px)
            Offset(midX + (-dy / distance) * fallback, midY + (dx / distance) * fallback)
        }
    } else {
        val curveAmount = minOf(distance * 0.15f, arcAmount60Px)
        Offset(midX + (-dy / distance) * curveAmount, midY + (dx / distance) * curveAmount)
    }

    path.moveTo(from.x, from.y)
    path.quadraticTo(control.x, control.y, to.x, to.y)

    drawPath(
        path = path,
        color = color,
        alpha = alpha,
        style = Stroke(
            width = strokePx,
            cap = StrokeCap.Round,
            join = StrokeJoin.Round,
            pathEffect = dashEffect,
        ),
    )

    if (isCloud) {
        drawCloudCirclesAlongPath(
            path = path,
            pathMeasure = pathMeasure,
            color = color,
            alpha = alpha * 0.8f,
            radiusPx = 3.dp.toPx() * zoom,
            spacingPx = cloudCircleSpacingPx * zoom,
        )
    }
}

/**
 * Minimum on-screen edge thickness, in dp. Edge strokes scale with the camera so a
 * line never looks heavy against a zoomed-out pill, but a hairline that vanishes at
 * 25% would hide a connection — and a missing connection is exactly what this view
 * is used to diagnose.
 */
internal const val MIN_EDGE_STROKE_DP = 1f

/**
 * Perpendicular separation between parallel edges (same peer pair, several
 * transports) at the current camera [zoom].
 *
 * Design-space constants have to be scaled to canvas space, or the separation stops
 * being a property of the drawing and becomes a property of the zoom level. At 34%
 * an unscaled 10 dp shift exceeds a pill's half-height and the edge terminates in
 * empty space beside the peer instead of under it.
 */
internal fun parallelEdgeOffsetPx(designOffsetPx: Float, zoom: Float): Float =
    designOffsetPx * zoom

/** Edge thickness at the current camera [zoom], never thinner than [minWidthPx]. */
internal fun edgeStrokeWidthPx(designWidthPx: Float, zoom: Float, minWidthPx: Float): Float =
    max(designWidthPx * zoom, minWidthPx)

/**
 * Render a single peer pill (rounded rectangle) with the text label centered inside.
 *
 * @param center  pixel position where the pill is centered.
 * @param widthPx measured pill width including horizontal padding, ALREADY multiplied
 *                by the camera zoom by the caller.
 * @param heightPx pill height (= text height + vertical padding), likewise zoomed.
 * @param scale animation scale factor (1.0 = neutral, 1.1 = highlighted).
 * @param zoom  camera zoom the caller baked into [widthPx] / [heightPx]. The label is
 *              a pre-measured [TextLayoutResult] at 1x, so it must be re-scaled by the
 *              same factor here — otherwise a zoomed-out pill shrinks while its text
 *              stays full size and the device name spills outside its pill. Peer names
 *              are the whole point of this view when debugging a mesh, so they have to
 *              track their container exactly.
 * @param alpha animation alpha (0..1).
 */
@Suppress("LongParameterList")
internal fun DrawScope.drawPresencePeerPill(
    center: Offset,
    widthPx: Float,
    heightPx: Float,
    fillColor: Color,
    strokeColor: Color,
    textColor: Color,
    textLayout: TextLayoutResult,
    scale: Float,
    zoom: Float,
    alpha: Float,
) {
    val w = widthPx * scale
    val h = heightPx * scale
    val topLeft = Offset(center.x - w * 0.5f, center.y - h * 0.5f)
    val cornerRadius = CornerRadius(h * 0.5f, h * 0.5f)

    drawRoundRect(
        color = fillColor,
        topLeft = topLeft,
        size = Size(w, h),
        cornerRadius = cornerRadius,
        alpha = alpha,
    )
    drawRoundRect(
        color = strokeColor,
        topLeft = topLeft,
        size = Size(w, h),
        cornerRadius = cornerRadius,
        alpha = alpha * 0.8f,
        style = Stroke(width = 2f),
    )

    // Draw the 1x-measured label centred on the pill, then scale the whole draw about
    // that centre by the same factor the pill rect got (camera zoom x highlight pop).
    // Scaling the draw beats re-measuring at a zoomed font size: measurement is the
    // expensive part and it is cached per label string across frames.
    val textScale = zoom * scale
    val textTopLeft = Offset(
        center.x - textLayout.size.width * 0.5f,
        center.y - textLayout.size.height * 0.5f,
    )
    withTransform({ scale(scaleX = textScale, scaleY = textScale, pivot = center) }) {
        drawText(
            textLayoutResult = textLayout,
            color = textColor,
            topLeft = textTopLeft,
            alpha = alpha,
        )
    }
}

private fun DrawScope.drawCloudCirclesAlongPath(
    path: Path,
    pathMeasure: PathMeasure,
    color: Color,
    alpha: Float,
    radiusPx: Float,
    spacingPx: Float,
) {
    val measure = pathMeasure.apply { setPath(path, false) }
    val length = measure.length
    if (length <= 0f || spacingPx <= 0f) return
    val numCircles = (length / spacingPx).toInt()
    if (numCircles <= 0) return

    for (i in 1 until numCircles) {
        val pos = measure.getPosition(spacingPx * i)
        if (pos == Offset.Unspecified) continue
        drawCircle(
            color = color,
            radius = radiusPx,
            center = pos,
            alpha = alpha,
        )
    }
}

/**
 * Pre-measured pill bundle: width/height + the text layout to draw inside. Stored in
 * a `remember(label)` per peer so the renderer doesn't re-measure every frame.
 */
internal data class PillMeasurement(
    val width: Float,
    val height: Float,
    val text: TextLayoutResult,
)

/**
 * Measure a peer label and compute the pill width.
 *
 * @param horizontalPaddingPx total horizontal padding (left + right). Plan: 22.5 dp.
 * @param fixedHeightPx       pill height in pixels. Plan: 22.5 dp.
 */
internal fun measurePeerPill(
    measurer: TextMeasurer,
    label: String,
    style: TextStyle,
    horizontalPaddingPx: Float,
    fixedHeightPx: Float,
): PillMeasurement {
    val layout = measurer.measure(
        text = label,
        style = style,
        softWrap = false,
        maxLines = 1,
        constraints = Constraints(),
    )
    return PillMeasurement(
        width = layout.size.width.toFloat() + horizontalPaddingPx,
        height = fixedHeightPx,
        text = layout,
    )
}

/**
 * Bounding rect of a peer pill in canvas-px (post y-flip, post scene translate). Used by
 * the parallel semantics layer for tap-target placement and a11y framing.
 */
internal fun peerPillBounds(center: Offset, widthPx: Float, heightPx: Float): Rect =
    Rect(
        left = center.x - widthPx * 0.5f,
        top = center.y - heightPx * 0.5f,
        right = center.x + widthPx * 0.5f,
        bottom = center.y + heightPx * 0.5f,
    )
