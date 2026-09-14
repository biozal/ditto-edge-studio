package com.costoda.dittoedgestudio.ui.mainstudio.presence

/** Top-left corner of a detail card, in viewport pixels. */
internal data class CardPlacement(val x: Float, val y: Float)

/**
 * Where to put an expanded peer card: **centred in the viewport**.
 *
 * The card used to be anchored to its peer, which meant it sat wherever that peer
 * happened to be — including hard against an edge, where the parent's `clipToBounds()`
 * cut off the bottom rows. Those are the sync rows, which are the whole reason the card
 * exists. Centring removes the failure mode entirely rather than papering over it with
 * flip-and-clamp rules, and it also means the card no longer has to chase its node
 * during a pan or a pinch.
 *
 * The trade is that the card covers the middle of the graph, which is where the focused
 * peer sits. That is acceptable for a modal inspector — the graph is still there when
 * the card closes, and the peer's pill is highlighted underneath.
 *
 * Pure, no Compose types, so it is unit-testable on the JVM like the layout engine.
 * A card larger than the viewport pins to the margin and is expected to scroll rather
 * than overflow; see the height cap on the card itself.
 */
internal fun centreDetailCard(
    cardWidthPx: Float,
    cardHeightPx: Float,
    viewportWidthPx: Float,
    viewportHeightPx: Float,
    marginPx: Float,
): CardPlacement = CardPlacement(
    x = centre(cardWidthPx, viewportWidthPx, marginPx),
    y = centre(cardHeightPx, viewportHeightPx, marginPx),
)

/**
 * Centre one axis, never letting the leading edge cross the margin. When the card is
 * bigger than the space available the naive centre goes negative, which would clip the
 * top of the card — the half carrying the peer name — so pin to the margin instead and
 * let the card scroll.
 */
private fun centre(size: Float, extent: Float, margin: Float): Float =
    ((extent - size) * 0.5f).coerceAtLeast(margin)

/**
 * True when [pointX], [pointY] land on a card placed at [placement].
 *
 * The graph's gesture handler uses this to ignore touches that belong to the card.
 * Without it a press on the card reaches the canvas handler, which sees no peer under
 * the point and treats it as an empty-canvas tap — dismissing the card the user just
 * touched — or, where the card happens to cover an orbit pill, starts dragging a peer
 * that is not visible.
 */
internal fun cardContains(
    pointX: Float,
    pointY: Float,
    placement: CardPlacement,
    cardWidthPx: Float,
    cardHeightPx: Float,
): Boolean = pointX >= placement.x &&
    pointX <= placement.x + cardWidthPx &&
    pointY >= placement.y &&
    pointY <= placement.y + cardHeightPx
