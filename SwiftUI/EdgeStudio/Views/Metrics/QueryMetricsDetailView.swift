import SwiftUI

struct QueryMetricsDetailView: View {
    @State private var records: [QueryExplainRecord] = []
    @State private var selectedRecord: QueryExplainRecord?

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            contentArea
        }
        .task {
            await loadRecords()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("Query Metrics")
                .font(.title2)
                .bold()
            Spacer()
            Text("\(records.count) record\(records.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                Task {
                    await QueryMetricsRepository.shared.clearRecords()
                    await loadRecords()
                    selectedRecord = nil
                }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.glass)
            .clipShape(Circle())
            .help("Clear all query records")
            .disabled(records.isEmpty)
            Button {
                Task { await loadRecords() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.glass)
            .clipShape(Circle())
            .help("Refresh records")
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if records.isEmpty {
            ContentUnavailableView(
                "No Query Records",
                systemImage: "text.magnifyingglass",
                description: Text("Run DQL queries from the Query view to see EXPLAIN output here.")
            )
        } else {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    recordList
                        .frame(width: geometry.size.width * 0.40)
                    Divider()
                    recordDetail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: - Record List

    private var recordList: some View {
        List(records, selection: $selectedRecord) { record in
            recordRow(record)
                .tag(record)
        }
        .listStyle(.sidebar)
    }

    private func recordRow(_ record: QueryExplainRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.formattedTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                HStack(spacing: 4) {
                    Text(record.formattedExecutionTime)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(latencyColor(record.executionTimeMs))
                    Circle()
                        .fill(record.usedIndex ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                        .help(record.usedIndex ? "Index used" : "Full scan")
                }
            }
            Text(record.dql)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Record Detail

    private var recordDetail: some View {
        Group {
            if let record = selectedRecord {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("DQL Statement", systemImage: "text.page")
                                .font(.headline)
                            Text(record.dql)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(10)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                        }

                        HStack(spacing: 12) {
                            statBadge(
                                label: "Time",
                                value: record.formattedExecutionTime,
                                color: latencyColor(record.executionTimeMs)
                            )
                            statBadge(label: "Results", value: "\(record.resultCount)", color: .secondary)
                            statBadge(
                                label: "Index",
                                value: record.usedIndex ? "✓ Yes" : "✗ No",
                                color: record.usedIndex ? .green : .orange
                            )
                            statBadge(label: "At", value: record.formattedTimestamp, color: .secondary)
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Label("EXPLAIN Output", systemImage: "doc.text.magnifyingglass")
                                .font(.headline)
                            if record.explainOutput.isEmpty {
                                Text("(no output)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(8)
                            } else {
                                JsonSyntaxView(jsonString: record.explainOutput)
                                    .background(Color.secondary.opacity(0.05))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "No Query Selected",
                    systemImage: "text.magnifyingglass",
                    description: Text("Select a query from the list to view its EXPLAIN output.")
                )
            }
        }
    }

    private func statBadge(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .bold()
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }

    private func latencyColor(_ ms: Double) -> Color {
        if ms < 10 { return .green }
        if ms < 100 { return .primary }
        return .orange
    }

    private func loadRecords() async {
        records = await QueryMetricsRepository.shared.allRecords()
    }
}
