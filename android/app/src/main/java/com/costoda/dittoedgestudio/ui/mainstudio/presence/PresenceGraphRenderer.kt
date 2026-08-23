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
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
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
 * @param parallelOffsetPx perpendicular shift in pixels for parallel-edge separation
 *                         (matches `ConnectionLine.lineOffset` in iOS).
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
    path: Path,
    /** Reusable PathMeasure for cloud-edge decorative circles. Allocating one per
     *  frame on a cloud-heavy graph was a measurable hotspot; the caller pools one
     *  alongside [path]. */
    pathMeasure: PathMeasure = PathMeasure(),
) {
    val dx = toPos.x - fromPos.x
    val dy = toPos.y - fromPos.y
    val distance = sqrt(dx * dx + dy * dy)

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
                width = strokeWidthPx,
                cap = StrokeCap.Round,
                join = StrokeJoin.Round,
                pathEffect = dashEffect,
            ),
        )
        return
    }

    val (from, to) = if (parallelOffsetPx == 0f) {
        fromPos to toPos
    } else {
        val ox = -dy / distance * parallelOffsetPx
        val oy = dx / distance * parallelOffsetPx
        Offset(fromPos.x + ox, fromPos.y + oy) to Offset(toPos.x + ox, toPos.y + oy)
    }

    val midX = (from.x + to.x) * 0.5f
    val midY = (from.y + to.y) * 0.5f

    val arcAmount90Px = 90.dp.toPx()
    val arcAmount60Px = 60.dp.toPx()

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
            width = strokeWidthPx,
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
            radiusPx = 3.dp.toPx(),
            spacingPx = cloudCircleSpacingPx,
        )
    }
}

/**
 * Render a single peer pill (rounded rectangle) with the text label centered inside.
 *
 * @param center  pixel position where the pill is centered.
 * @param widthPx measured pill width including horizontal padding.
 * @param heightPx pill height (= text height + vertical padding).
 * @param scale animation scale factor (1.0 = neutral, 1.1 = highlighted).
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

    val textW = textLayout.size.width.toFloat() * scale
    val textH = textLayout.size.height.toFloat() * scale
    val textTopLeft = Offset(center.x - textW * 0.5f, center.y - textH * 0.5f)
    drawText(
        textLayoutResult = textLayout,
        color = textColor,
        topLeft = textTopLeft,
        alpha = alpha,
    )
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
