import CoreImage.CIFilterBuiltins
import Foundation
import SwiftUI

// MARK: - Payload Types

struct QRCodePayload: Codable {
    let version: Int
    let config: DittoConfigForDatabase
    let favorites: [FavoriteQueryItem]
}

struct FavoriteQueryItem: Codable {
    let q: String
}

struct SubscriptionsQRPayload: Codable {
    let version: Int
    let subscriptions: [SubscriptionQRItem]
}

struct SubscriptionQRItem: Codable {
    let name: String
    let query: String
    let args: String?
}

// MARK: - Generator

enum QRCodeGenerator {
    private static let v2Prefix = "EDS2:"
    private static let v1SubsPrefix = "EDS_SUBS1:"
    private static let maxPayloadBytes = 2200

    // MARK: Generate

    static func generate(from config: DittoConfigForDatabase) -> Image? {
        generate(from: config, favorites: [])
    }

    static func generate(from config: DittoConfigForDatabase, favorites: [FavoriteQueryItem]) -> Image? {
        var favoritesToEncode = favorites
        while true {
            guard let payloadString = encodePayload(config: config, favorites: favoritesToEncode),
                  let data = payloadString.data(using: .utf8) else { return nil }
            if data.count <= maxPayloadBytes || favoritesToEncode.isEmpty {
                return generateQRImage(from: data)
            }
            // Drop oldest favorite (last element — list is most-recent-first)
            favoritesToEncode.removeLast()
        }
    }

    // MARK: Decode

    /// Decodes a scanned QR payload string into config + favorites.
    /// Supports v2 (EDS2: prefix, compressed) and v1 (legacy raw JSON) formats.
    static func decode(from payload: String) -> (config: DittoConfigForDatabase, favorites: [FavoriteQueryItem])? {
        if payload.hasPrefix(v2Prefix) {
            let b64 = String(payload.dropFirst(v2Prefix.count))
            guard let compressed = Data(base64Encoded: b64),
                  let json = try? (compressed as NSData).decompressed(using: .zlib) as Data,
                  let qrPayload = try? JSONDecoder().decode(QRCodePayload.self, from: json) else
            {
                return nil
            }
            // Sanitize on the way IN as well, so a payload produced by another client
            // (or a future version of this app) can never silently import sync scopes or
            // startup settings onto this device.
            return (config: qrPayload.config.sanitizedForSharing(), favorites: qrPayload.favorites)
        } else {
            // Legacy v1: raw JSON of DittoConfigForDatabase
            guard let data = payload.data(using: .utf8),
                  let config = try? JSONDecoder().decode(DittoConfigForDatabase.self, from: data) else
            {
                return nil
            }
            return (config: config.sanitizedForSharing(), favorites: [])
        }
    }

    // MARK: Subscriptions Encode / Decode

    static func encodeSubscriptions(_ items: [SubscriptionQRItem]) -> String? {
        let payload = SubscriptionsQRPayload(version: 1, subscriptions: items)
        guard let json = try? JSONEncoder().encode(payload),
              let compressed = try? (json as NSData).compressed(using: .zlib) as Data else { return nil }
        return v1SubsPrefix + compressed.base64EncodedString()
    }

    static func decodeSubscriptions(from payload: String) -> [SubscriptionQRItem]? {
        guard payload.hasPrefix(v1SubsPrefix) else { return nil }
        let b64 = String(payload.dropFirst(v1SubsPrefix.count))
        guard let compressed = Data(base64Encoded: b64),
              let json = try? (compressed as NSData).decompressed(using: .zlib) as Data,
              let subsPayload = try? JSONDecoder().decode(SubscriptionsQRPayload.self, from: json) else
        {
            return nil
        }
        return subsPayload.subscriptions
    }

    // MARK: Private Helpers

    private static func encodePayload(config: DittoConfigForDatabase, favorites: [FavoriteQueryItem]) -> String? {
        // Advanced configuration is deliberately NOT shared. Importing another device's
        // sync scopes changes what syncs in both directions — a scanned `LocalPeerOnly`
        // silently stops a collection from syncing, and a scanned `AllPeers` pushes data
        // the sender meant to keep on-device — and startup settings are
        // environment-specific (some open network listeners or install a trusted CA).
        // `sanitizedForSharing()` returns a NEW instance; clearing in place would delete
        // the user's real scopes just by displaying a QR code.
        let payload = QRCodePayload(version: 2, config: config.sanitizedForSharing(), favorites: favorites)
        guard let json = try? JSONEncoder().encode(payload),
              let compressed = try? (json as NSData).compressed(using: .zlib) as Data else { return nil }
        return v2Prefix + compressed.base64EncodedString()
    }

    // MARK: Test Seams

    // Compiled out of Release. Neither of these exposes anything the shipping API doesn't
    // — `testPayloadString(config:favorites:)` forwards to `encodePayload`, which `generate`
    // already calls in Release, sanitisation included — so this is convention, not a leak
    // being closed: a seam that exists for tests should not be part of the shipping
    // surface. Matched by `SQLCipherService.executeRawForTesting` and
    // `DatabaseRepository.clearCacheForTesting`. The tests that call these
    // (`QRCodeAdvancedExclusionTests`) build against Debug, so they are unaffected; the
    // Release build is what proves nothing production-side depended on them.
    #if DEBUG
    /// The payload string `generate` would encode, without rasterizing a QR image.
    ///
    /// Exposed so the advanced-settings exclusion can be asserted on the real encoder
    /// rather than on a reimplementation of it.
    static func testPayloadString(config: DittoConfigForDatabase, favorites: [FavoriteQueryItem]) -> String? {
        encodePayload(config: config, favorites: favorites)
    }

    /// Wraps arbitrary payload JSON in the v2 envelope, for testing that a foreign
    /// payload carrying advanced settings still cannot import them.
    static func testPayloadString(rawJSON: String) -> String? {
        guard let compressed = try? (Data(rawJSON.utf8) as NSData).compressed(using: .zlib) as Data else { return nil }
        return v2Prefix + compressed.base64EncodedString()
    }
    #endif

    /// Pixels per QR module in the generated bitmap.
    private static let qrModuleScale: CGFloat = 20

    static func generateQRImage(from data: Data) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        // "L", not "M". Error correction trades data capacity for damage
        // tolerance, and damage tolerance buys nothing here — this code is
        // displayed on a clean screen and scanned seconds later, not printed on
        // a box that gets scuffed. Spending that budget on capacity instead
        // means fewer modules for the same payload, and fewer modules means
        // each one is physically bigger for the camera. Measured at the 2200
        // byte cap: 147 modules at "M" versus 131 at "L", i.e. every module is
        // 12% larger. The level is encoded in the symbol, so every scanner
        // adapts automatically — this is not a wire-format change.
        filter.correctionLevel = "L"
        guard let output = filter.outputImage else { return nil }
        // `CIQRCodeGenerator` emits one pixel per QR module, so this scale is
        // the module size in pixels. Doubled from 10 to 20: the bitmap is drawn
        // with `.interpolation(.none)`, so a larger source means crisper module
        // edges when the view scales it, and crisper edges are what a phone
        // camera needs to threshold reliably. Cheap — even a dense payload is
        // well under 200x200 modules, so this is a few hundred KB of CGImage
        // that lives only as long as the sheet.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: qrModuleScale, y: qrModuleScale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return Image(decorative: cgImage, scale: 1)
    }
}
