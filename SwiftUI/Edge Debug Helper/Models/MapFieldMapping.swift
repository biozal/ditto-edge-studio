//
//  MapFieldMapping.swift
//  Edge Studio
//

import Foundation

/// Configuration for mapping document fields to map coordinates
struct MapFieldMapping: Codable, Identifiable {
    var id: String { "\(appId)_\(collectionName)" }
    let appId: String
    let collectionName: String
    var latitudeField: String
    var longitudeField: String

    init(appId: String, collectionName: String, latitudeField: String = "lat", longitudeField: String = "lon") {
        self.appId = appId
        self.collectionName = collectionName
        self.latitudeField = latitudeField
        self.longitudeField = longitudeField
    }
}

/// Repository for managing map field mappings
@MainActor
class MapFieldMappingRepository: ObservableObject {
    static let shared = MapFieldMappingRepository()

    @Published private(set) var mappings: [String: MapFieldMapping] = [:]
    private let storageKey = "mapFieldMappings"

    private init() {
        loadMappings()
    }

    /// Get mapping for a specific app/collection combination
    func getMapping(appId: String, collectionName: String) -> MapFieldMapping {
        let key = "\(appId)_\(collectionName)"
        return mappings[key] ?? MapFieldMapping(appId: appId, collectionName: collectionName)
    }

    /// Save or update a mapping
    func saveMapping(_ mapping: MapFieldMapping) {
        mappings[mapping.id] = mapping
        persistMappings()
    }

    /// Extract available numeric/coordinate-like fields from sample results
    func extractPotentialCoordinateFields(from jsonResults: [String]) -> [String] {
        guard let firstResult = jsonResults.first,
              let data = firstResult.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var potentialFields: [String] = []

        for (key, value) in json {
            // Skip internal Ditto fields
            if key.hasPrefix("_") { continue }

            // Check if the value is numeric or could be a coordinate
            if value is Double || value is Int || value is Float {
                potentialFields.append(key)
            } else if let stringValue = value as? String, Double(stringValue) != nil {
                potentialFields.append(key)
            }
        }

        return potentialFields.sorted()
    }

    /// Smart detection of lat/lon fields based on common naming patterns
    func detectCoordinateFields(from jsonResults: [String]) -> (lat: String?, lon: String?)? {
        let potentialFields = extractPotentialCoordinateFields(from: jsonResults)

        // Common patterns for latitude fields
        let latPatterns = ["lat", "latitude", "y", "coord_lat", "location_lat", "geo_lat"]
        // Common patterns for longitude fields
        let lonPatterns = ["lon", "lng", "long", "longitude", "x", "coord_lon", "coord_lng", "location_lon", "location_lng", "geo_lon", "geo_lng"]

        var detectedLat: String?
        var detectedLon: String?

        // Find lat field
        for pattern in latPatterns {
            if let field = potentialFields.first(where: { $0.lowercased().contains(pattern) }) {
                detectedLat = field
                break
            }
        }

        // Find lon field
        for pattern in lonPatterns {
            if let field = potentialFields.first(where: { $0.lowercased().contains(pattern) }) {
                detectedLon = field
                break
            }
        }

        if detectedLat != nil && detectedLon != nil {
            return (detectedLat, detectedLon)
        }

        return nil
    }

    // MARK: - Persistence

    private func loadMappings() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }

        guard let decoded = try? JSONDecoder().decode([MapFieldMapping].self, from: data) else {
            return
        }

        mappings = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
    }

    private func persistMappings() {
        let mappingsArray = Array(mappings.values)

        guard let encoded = try? JSONEncoder().encode(mappingsArray) else {
            return
        }

        UserDefaults.standard.set(encoded, forKey: storageKey)
        UserDefaults.standard.synchronize()
    }
}
