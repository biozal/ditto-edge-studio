//
//  MapFieldSelector.swift
//  Edge Studio
//

import SwiftUI

struct MapFieldSelector: View {
  @Binding var latitudeField: String
  @Binding var longitudeField: String
  let availableFields: [String]
  let onApply: () -> Void

  @State private var showPopover = false

  var body: some View {
    Button {
      showPopover.toggle()
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "map.circle")
        Text("Map Fields")
      }
    }
    .buttonStyle(.borderless)
    .popover(isPresented: $showPopover, arrowEdge: .bottom) {
      VStack(alignment: .leading, spacing: 12) {
        Text("Map Coordinate Fields")
          .font(.headline)
          .padding(.bottom, 4)

        if availableFields.isEmpty {
          Text("No numeric fields found in results")
            .foregroundColor(.secondary)
            .font(.caption)
            .padding()
        } else {
          // Latitude field picker
          VStack(alignment: .leading, spacing: 4) {
            Text("Latitude Field:")
              .font(.caption)
              .foregroundColor(.secondary)

            Picker("Latitude", selection: $latitudeField) {
              ForEach(availableFields, id: \.self) { field in
                Text(field).tag(field)
              }
            }
            .pickerStyle(.menu)
            .labelsHidden()
          }

          // Longitude field picker
          VStack(alignment: .leading, spacing: 4) {
            Text("Longitude Field:")
              .font(.caption)
              .foregroundColor(.secondary)

            Picker("Longitude", selection: $longitudeField) {
              ForEach(availableFields, id: \.self) { field in
                Text(field).tag(field)
              }
            }
            .pickerStyle(.menu)
            .labelsHidden()
          }

          Divider()

          // Current mapping display
          VStack(alignment: .leading, spacing: 2) {
            Text("Current Mapping:")
              .font(.caption)
              .foregroundColor(.secondary)
            Text("Lat: \(latitudeField), Lon: \(longitudeField)")
              .font(.caption)
              .foregroundColor(.primary)
          }

          // Apply button
          HStack {
            Spacer()
            Button("Apply") {
              onApply()
              showPopover = false
            }
            .buttonStyle(.borderedProminent)
          }
        }
      }
      .padding()
      .frame(minWidth: 250)
    }
    .help("Configure which fields contain latitude and longitude coordinates")
  }
}

#Preview {
  MapFieldSelector(
    latitudeField: .constant("lat"),
    longitudeField: .constant("lon"),
    availableFields: ["lat", "lon", "latitude", "longitude", "x", "y"],
    onApply: {}
  )
}
