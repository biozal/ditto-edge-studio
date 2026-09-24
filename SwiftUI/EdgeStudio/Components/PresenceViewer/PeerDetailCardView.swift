import SwiftUI

/// Expanded detail for one peer in the presence graph.
///
/// Rendered as a **screen-space overlay centred in the viewport**, above the SpriteKit
/// scene rather than inside it. That is deliberate on two counts:
///
/// - A focus orbit holds up to 12 peers (the SDK caps connections per peer for battery).
///   Twelve nodes of width W on a ring need radius ≈ 1.93·(W+20), so the content the
///   focus camera has to frame is always ~6× the card width, and the rendered card comes
///   back at ≈ viewport ÷ 4.9 no matter how large it was drawn. Measured on Android: on a
///   344 dp screen a 145 dp card renders at 55 dp and a 240 dp card at 60 dp. A card
///   inside the scene cannot be legible on a small window at any size.
/// - Being outside the `SKCameraNode` means it is not scaled by zoom, and its size never
///   reaches the layout engine's `peerFootprints` — where it would move ring radii every
///   time a card opened.
///
/// Rows are always present, even when empty. A missing value shows an explicit reason
/// rather than disappearing: the absence is itself the information.
struct PeerDetailCardView: View {
    let detail: PresencePeerDetail
    /// Non-nil when this peer can be focused from here — i.e. it is not already the
    /// focused peer and not the local device. Tapping a peer no longer refocuses, so the
    /// traversal lives here, labelled rather than hidden in a gesture.
    let onFocusPeer: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(detail.displayName)
                .font(.headline)
                .lineLimit(2)
                .accessibilityLabel("Details for \(detail.displayName)")

            Divider().padding(.vertical, 8)

            detailRow("Peer key", detail.peerKey.isEmpty ? nil : detail.peerKey, monospaced: true, missing: "not reported")
            detailRow("OS", detail.os?.displayName, missing: "not yet known")
            detailRow("Ditto SDK", detail.sdkVersion, missing: "not yet known")
            detailRow("Cloud link", detail.isConnectedToDittoCloud ? "Connected" : "None")
            detailRow("Compatible", detail.isCompatible.map { $0 ? "Yes" : "No" }, missing: "not yet known")

            Divider().padding(.vertical, 8)

            detailRow("Peer metadata", metadataSummary(detail.peerMetadataKeyCount, detail.peerMetadataJSON))
            detailRow("Identity metadata", metadataSummary(detail.identityMetadataKeyCount, detail.identityMetadataJSON))

            Divider().padding(.vertical, 8)

            syncSection

            if let onFocusPeer {
                Divider().padding(.vertical, 8)
                Button("Focus this peer", action: onFocusPeer)
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("PeerDetailFocusButton")
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .shadow(radius: 12)
    }

    /// Three states, and the distinction is the point.
    ///
    /// `system:data_sync_info` is a local table computed from where this device actually
    /// receives data. It has no row for a peer we hold no session with, and none for
    /// ourselves — so a blank here would read as a bug rather than as the fact it is.
    @ViewBuilder
    private var syncSection: some View {
        if detail.isLocal {
            Text("This device")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Sync progress is tracked per remote peer, not for the local device.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        } else if detail.isDirectlyConnected {
            detailRow("Synced to commit", detail.syncedUpToLocalCommitId.map(String.init), missing: "nothing yet")
            detailRow("Last update", formattedLastUpdate, missing: "never")
        } else {
            Text("No sync session — not directly connected")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Commit progress is only tracked for peers this device syncs with directly.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private func detailRow(
        _ label: String,
        _ value: String?,
        monospaced: Bool = false,
        missing: String = "—"
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 108, alignment: .leading)
            Text(value ?? missing)
                .font(monospaced ? .caption.monospaced() : .caption)
                // .secondary rather than a dimmer tone: on Android the equivalent copy
                // was rendered in an outline colour that measured 2.1:1 against the card,
                // making the "why this is empty" explanation itself invisible.
                .foregroundStyle(value == nil ? .secondary : .primary)
                .lineLimit(monospaced ? 2 : 1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    /// Metadata is shown as a key count, never as the raw document — the SDK caps each
    /// object at 4 KB, which no card can hold, and inlining it would make the card's
    /// height depend on the peer.
    private func metadataSummary(_ keyCount: Int, _ raw: String?) -> String? {
        if keyCount > 0 {
            return keyCount == 1 ? "1 key" : "\(keyCount) keys"
        }
        // Present but not countable (came from the sync-row enrichment rather than the
        // presence graph): say something truthful rather than claiming it is empty.
        if let raw, !raw.isEmpty, raw.trimmingCharacters(in: .whitespacesAndNewlines) != "{}" {
            return "present"
        }
        return nil
    }

    private var formattedLastUpdate: String? {
        guard let ms = detail.lastUpdateReceivedTime, ms > 0 else { return nil }
        let date = Date(timeIntervalSince1970: ms / 1000)
        let elapsed = Date().timeIntervalSince(date)
        switch elapsed {
        case ..<0:
            return date.formatted(date: .abbreviated, time: .shortened)
        case ..<60:
            return "Just now"
        case ..<3600:
            return "\(Int(elapsed / 60)) min ago"
        case ..<86400:
            return "\(Int(elapsed / 3600)) hr ago"
        default:
            return date.formatted(date: .abbreviated, time: .shortened)
        }
    }
}
