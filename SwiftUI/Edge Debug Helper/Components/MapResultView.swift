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
    @Binding var latitudeField: String
    @Binding var longitudeField: String

    // Configurable map settings
    private let initialLatitude: Double = 37.7749  // San Francisco
    private let initialLongitude: Double = -122.4194
    private let initialZoom: Double = 0.05  // Zoom level (smaller = more zoomed in)

    @State private var region: MKCoordinateRegion
    @State private var cameraPosition: MapCameraPosition
    @State private var annotations: [LocationAnnotation] = []

    // Computed property to determine if we should show the "execute query" message
    private var shouldShowExecuteMessage: Bool {
        let hasResults = !jsonResults.isEmpty
        return !hasResults && !hasExecutedQuery
    }

    init(jsonResults: Binding<[String]>, hasExecutedQuery: Bool = false, latitudeField: Binding<String>, longitudeField: Binding<String>) {
        self._jsonResults = jsonResults
        self.hasExecutedQuery = hasExecutedQuery
        self._latitudeField = latitudeField
        self._longitudeField = longitudeField

        // Initialize region with configurable values
        let initialRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: initialLatitude,
                longitude: initialLongitude
            ),
            span: MKCoordinateSpan(
                latitudeDelta: initialZoom,
                longitudeDelta: initialZoom
            )
        )
        self._region = State(initialValue: initialRegion)
        self._cameraPosition = State(initialValue: .region(initialRegion))
    }

    var body: some View {
        ZStack {
            mapView
            overlayView
            counterView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: jsonResults) { _, newResults in
            updateAnnotations(from: newResults)
        }
        .onChange(of: latitudeField) { _, _ in
            updateAnnotations(from: jsonResults)
        }
        .onChange(of: longitudeField) { _, _ in
            updateAnnotations(from: jsonResults)
        }
        .onAppear {
            updateAnnotations(from: jsonResults)
        }
    }

    // MARK: - View Components

    private var mapView: some View {
        Map(position: $cameraPosition) {
            ForEach(annotations) { annotation in
                Annotation(annotation.title, coordinate: annotation.coordinate) {
                    customMarker
                }
            }
        }
        .mapStyle(.standard)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var customMarker: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                    )
                    .shadow(radius: 4)

                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
            }

            Triangle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .offset(y: -6)
                .shadow(radius: 2)
        }
        .offset(y: -20)
    }

    @ViewBuilder
    private var overlayView: some View {
        if shouldShowExecuteMessage {
            executeQueryMessage
        } else if !shouldShowExecuteMessage && jsonResults.isEmpty {
            noResultsMessage
        } else if !jsonResults.isEmpty && annotations.isEmpty {
            noLocationsMessage
        }
    }

    private var executeQueryMessage: some View {
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
        .padding(24)
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
        .allowsHitTesting(false)
    }

    private var noResultsMessage: some View {
        VStack(spacing: 16) {
            Image(systemName: "map.circle")
                .font(.system(size: 48))
                .foregroundColor(.white)
                .shadow(radius: 2)
            Text("No results from query")
                .font(.headline)
                .foregroundColor(.white)
                .shadow(radius: 2)
            Text("The query returned no documents")
                .font(.caption)
                .foregroundColor(.white)
                .shadow(radius: 2)
        }
        .padding(24)
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
        .allowsHitTesting(false)
    }

    private var noLocationsMessage: some View {
        VStack(spacing: 16) {
            Image(systemName: "map.circle")
                .font(.system(size: 48))
                .foregroundColor(.white)
                .shadow(radius: 2)
            Text("No valid locations to display")
                .font(.headline)
                .foregroundColor(.white)
                .shadow(radius: 2)
            Text("Looking for '\(latitudeField)' and '\(longitudeField)' fields")
                .font(.caption)
                .foregroundColor(.white)
                .shadow(radius: 2)
            Text("Use 'Map Fields' button to configure field mapping")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
                .shadow(radius: 2)
        }
        .padding(24)
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var counterView: some View {
        if hasExecutedQuery || !jsonResults.isEmpty {
            VStack(alignment: .trailing, spacing: 8) {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(jsonResults.count) record\(jsonResults.count == 1 ? "" : "s")")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("\(annotations.count) marker\(annotations.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(annotations.count > 0 ? .green : .red)
                        .fontWeight(.semibold)
                    Text("Fields: \(latitudeField)/\(longitudeField)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.white.opacity(0.9))
                .cornerRadius(8)
                .shadow(radius: 2)
                .padding(12)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .allowsHitTesting(false)
        }
    }

    private func updateAnnotations(from results: [String]) {
        var newAnnotations: [LocationAnnotation] = []

        for (index, jsonString) in results.enumerated() {
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Try to extract lat and lon fields using configured field names
            if let lat = extractDouble(from: json, key: latitudeField),
               let lon = extractDouble(from: json, key: longitudeField) {

                // Validate coordinates are within valid ranges
                guard lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180 else {
                    continue
                }

                let annotation = LocationAnnotation(
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
            let newRegion = MKCoordinateRegion(
                center: annotations[0].coordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: initialZoom,
                    longitudeDelta: initialZoom
                )
            )
            region = newRegion
            cameraPosition = .region(newRegion)
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

            let newRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                span: MKCoordinateSpan(
                    latitudeDelta: max(spanLat, 0.01),  // Minimum span
                    longitudeDelta: max(spanLon, 0.01)
                )
            )
            region = newRegion
            cameraPosition = .region(newRegion)
        }
    }
}

struct LocationAnnotation: Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let title: String
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    MapResultView(
        jsonResults: .constant([
            "{\"_id\": \"1\", \"name\": \"Location 1\", \"lat\": 37.7749, \"lon\": -122.4194}",
            "{\"_id\": \"2\", \"name\": \"Location 2\", \"lat\": 37.8044, \"lon\": -122.2712}"
        ]),
        hasExecutedQuery: true,
        latitudeField: .constant("lat"),
        longitudeField: .constant("lon")
    )
}
