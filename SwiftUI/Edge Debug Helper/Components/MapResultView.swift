//
//  MapResultView.swift
//  Edge Studio
//
//  Created by Claude Code on 10/21/25.
//

import SwiftUI
import MapKit

struct MapResultView: View {
    @Binding var jsonResults: [String]
    var hasExecutedQuery: Bool = false

    // Configurable map settings
    private let initialLatitude: Double = 37.7749  // San Francisco
    private let initialLongitude: Double = -122.4194
    private let initialZoom: Double = 0.05  // Zoom level (smaller = more zoomed in)

    @State private var region: MKCoordinateRegion
    @State private var annotations: [MapAnnotation] = []

    init(jsonResults: Binding<[String]>, hasExecutedQuery: Bool = false) {
        self._jsonResults = jsonResults
        self.hasExecutedQuery = hasExecutedQuery

        // Initialize region with configurable values
        self._region = State(initialValue: MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: initialLatitude,
                longitude: initialLongitude
            ),
            span: MKCoordinateSpan(
                latitudeDelta: initialZoom,
                longitudeDelta: initialZoom
            )
        ))
    }

    var body: some View {
        ZStack {
            // Always show the map
            Map(coordinateRegion: $region, annotationItems: annotations) { annotation in
                MapMarker(coordinate: annotation.coordinate, tint: .blue)
            }

            // Show info overlay
            if !hasExecutedQuery {
                // Before query execution
                VStack(spacing: 16) {
                    Image(systemName: "map")
                        .font(.system(size: 48))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                    Text("Execute a query to view results on map")
                        .font(.headline)
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.3))
            } else if hasExecutedQuery && annotations.isEmpty {
                // After query execution but no locations found
                VStack(spacing: 16) {
                    Image(systemName: "map.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                    Text("No locations to display")
                        .font(.headline)
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                    Text("Records must contain 'lat' and 'lon' fields")
                        .font(.caption)
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                }
                .padding(24)
                .background(Color.black.opacity(0.6))
                .cornerRadius(12)
            }

            // Location counter when there are annotations
            if !annotations.isEmpty {
                VStack(alignment: .trailing, spacing: 8) {
                    Text("\(annotations.count) location\(annotations.count == 1 ? "" : "s")")
                        .font(.caption)
                        .padding(8)
                        .background(Color.white.opacity(0.9))
                        .cornerRadius(8)
                        .shadow(radius: 2)
                        .padding(12)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .onChange(of: jsonResults) { _, newResults in
            updateAnnotations(from: newResults)
        }
        .onAppear {
            updateAnnotations(from: jsonResults)
        }
    }

    private func updateAnnotations(from results: [String]) {
        var newAnnotations: [MapAnnotation] = []

        for (index, jsonString) in results.enumerated() {
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Try to extract lat and lon fields
            if let lat = extractDouble(from: json, key: "lat"),
               let lon = extractDouble(from: json, key: "lon") {
                let annotation = MapAnnotation(
                    id: UUID(),
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    title: "Location \(index + 1)"
                )
                newAnnotations.append(annotation)
            }
        }

        annotations = newAnnotations

        // Center map on annotations if we have any
        if !newAnnotations.isEmpty {
            centerMapOnAnnotations()
        }
    }

    private func extractDouble(from json: [String: Any], key: String) -> Double? {
        if let value = json[key] as? Double {
            return value
        } else if let value = json[key] as? Int {
            return Double(value)
        } else if let value = json[key] as? String, let doubleValue = Double(value) {
            return doubleValue
        }
        return nil
    }

    private func centerMapOnAnnotations() {
        guard !annotations.isEmpty else { return }

        if annotations.count == 1 {
            // Single annotation - center on it with default zoom
            region = MKCoordinateRegion(
                center: annotations[0].coordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: initialZoom,
                    longitudeDelta: initialZoom
                )
            )
        } else {
            // Multiple annotations - calculate bounding box
            var minLat = annotations[0].coordinate.latitude
            var maxLat = annotations[0].coordinate.latitude
            var minLon = annotations[0].coordinate.longitude
            var maxLon = annotations[0].coordinate.longitude

            for annotation in annotations {
                minLat = min(minLat, annotation.coordinate.latitude)
                maxLat = max(maxLat, annotation.coordinate.latitude)
                minLon = min(minLon, annotation.coordinate.longitude)
                maxLon = max(maxLon, annotation.coordinate.longitude)
            }

            let centerLat = (minLat + maxLat) / 2
            let centerLon = (minLon + maxLon) / 2
            let spanLat = (maxLat - minLat) * 1.5  // Add 50% padding
            let spanLon = (maxLon - minLon) * 1.5

            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                span: MKCoordinateSpan(
                    latitudeDelta: max(spanLat, 0.01),  // Minimum span
                    longitudeDelta: max(spanLon, 0.01)
                )
            )
        }
    }
}

struct MapAnnotation: Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let title: String
}

#Preview {
    MapResultView(
        jsonResults: .constant([
            "{\"_id\": \"1\", \"name\": \"Location 1\", \"lat\": 37.7749, \"lon\": -122.4194}",
            "{\"_id\": \"2\", \"name\": \"Location 2\", \"lat\": 37.8044, \"lon\": -122.2712}"
        ]),
        hasExecutedQuery: true
    )
}
