import Charts
import SwiftUI

struct MetricCard: View {
    let title: String
    let systemImage: String
    let currentValue: String
    let samples: [MetricSample]
    var unit = ""
    var helpText: String?
    var helpURL: URL?

    @State private var showHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if helpText != nil {
                    Button {
                        showHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showHelp, arrowEdge: .top) {
                        helpPopoverContent
                            .padding()
                            .frame(maxWidth: 280)
                    }
                }
            }

            Text(currentValue)
                .font(.title3)
                .bold()
                .monospacedDigit()
                .lineLimit(1)

            if !samples.isEmpty {
                Chart(samples, id: \.timestamp) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Value", sample.value)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 36)
                .clipped()
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 36)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    private var helpPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            if let text = helpText {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = helpURL {
                Link("Learn more →", destination: url)
                    .font(.callout)
            }
        }
    }
}
