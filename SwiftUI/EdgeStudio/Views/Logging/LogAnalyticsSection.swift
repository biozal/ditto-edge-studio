import Charts
import DittoSwift
import SwiftUI

/// Level → color, matching the VS Code analyzer's `LEVEL_COLORS` and the
/// Android palette so the same log renders the same way on all three platforms.
func logLevelColor(_ level: DittoLogLevel) -> Color {
    switch level {
    case .error: return Color(red: 1.0, green: 0.32, blue: 0.32) // #ff5252
    case .warning: return Color(red: 0.83, green: 0.63, blue: 0.09) // #d4a017
    case .info: return Color(red: 0.31, green: 0.63, blue: 1.0) // #4ea1ff
    case .debug: return Color(white: 0.53) // #888888
    case .verbose: return Color(white: 0.33) // #555555
    @unknown default: return .gray
    }
}

/// Stable render order for the stacked volume bars, coarsest (most common) at
/// the bottom. A dictionary's iteration order is not stable, so relying on it
/// would make the stack reshuffle between refreshes.
private let volumeLevelOrder: [DittoLogLevel] = [.verbose, .debug, .info, .warning, .error]

// MARK: - Log Volume by Level

/// Stacked bars of entry volume per time bin. Bin width is chosen by
/// `LogAnalytics.pickBinWidthMs`, so a short capture and a 14-hour one both
/// render a readable number of bars.
struct LogVolumeHistogram: View {
    let bins: [LogAnalytics.VolumeBin]

    /// Flattened (bin, level, count) rows — `Chart` needs one mark per stack
    /// segment, and building this in the view body keeps `LogAnalytics` free of
    /// presentation concerns.
    private struct Segment: Identifiable {
        let id: String
        let start: Date
        let level: DittoLogLevel
        let count: Int
    }

    private var segments: [Segment] {
        bins.flatMap { bin in
            volumeLevelOrder.compactMap { level -> Segment? in
                guard let count = bin.counts[level], count > 0 else { return nil }
                return Segment(id: "\(bin.startMs)-\(level.shortName)", start: bin.start, level: level, count: count)
            }
        }
    }

    var body: some View {
        Group {
            if bins.isEmpty {
                LogChartPlaceholder(text: "No volume data yet.")
            } else {
                Chart(segments) { segment in
                    BarMark(
                        x: .value("Time", segment.start),
                        y: .value("Entries", segment.count)
                    )
                    .foregroundStyle(logLevelColor(segment.level))
                }
                .chartLegend(.hidden)
                .chartYAxis {
                    // `horizontalSpacing` is the gap between the value label and
                    // the plot area. Without it the leading labels sit flush
                    // against the plot and the first bar draws on top of them.
                    AxisMarks(position: .leading) {
                        AxisGridLine()
                        AxisValueLabel(horizontalSpacing: 8).font(.system(size: 9))
                    }
                }
                .chartXAxis {
                    AxisMarks {
                        AxisValueLabel(format: .dateTime.hour().minute(), verticalSpacing: 6)
                            .font(.system(size: 9))
                    }
                }
                .chartPlotStyle { $0.padding(.leading, 4) }
                .frame(minHeight: 70, idealHeight: LogAnalyticsSection.chartHeight, maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("LogVolumeHistogram")
    }
}

// MARK: - Problems over Time

/// One bar per time bin, colored by that bin's worst severity — the same ramp
/// the Problems list and pattern manager use.
struct LogProblemsHistogram: View {
    let bins: [LogAnalytics.ProblemBin]

    var body: some View {
        Group {
            if bins.isEmpty {
                LogChartPlaceholder(text: "No problems yet.")
            } else {
                Chart(bins) { bin in
                    BarMark(
                        x: .value("Time", bin.start),
                        y: .value("Problems", bin.count)
                    )
                    .foregroundStyle(logSeverityColor(bin.maxSeverity))
                }
                .chartLegend(.hidden)
                .chartYAxis {
                    // `horizontalSpacing` is the gap between the value label and
                    // the plot area. Without it the leading labels sit flush
                    // against the plot and the first bar draws on top of them.
                    AxisMarks(position: .leading) {
                        AxisGridLine()
                        AxisValueLabel(horizontalSpacing: 8).font(.system(size: 9))
                    }
                }
                .chartXAxis {
                    AxisMarks {
                        AxisValueLabel(format: .dateTime.hour().minute(), verticalSpacing: 6)
                            .font(.system(size: 9))
                    }
                }
                .chartPlotStyle { $0.padding(.leading, 4) }
                .frame(minHeight: 70, idealHeight: LogAnalyticsSection.chartHeight, maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("LogProblemsHistogram")
    }
}

// MARK: - Connection Durations

/// Closed-connection counts per duration bucket, as a `label │ track │ count`
/// row list — the same shape as the VS Code analyzer's `duration-histogram`.
///
/// Deliberately **not** a `Chart`. A categorical bar chart wants far more
/// vertical room than five buckets deserve: at the height this section can
/// afford, the band labels collide with each other, a lone populated bucket
/// renders as a hairline across a mostly-empty plot, and the numeric axis adds
/// clutter for a five-row table. It also is not a `GeometryReader` — that has no
/// intrinsic size and reports whatever it is offered, which previously grew the
/// window past the screen (see `LogAnalyticsSection`).
///
/// `ProgressView` gives a correctly proportioned, natively sized bar with
/// neither hazard.
struct LogConnectionDurationsChart: View {
    let bins: [LogAnalytics.DurationBin]

    private static let barColor = Color(red: 0.31, green: 0.63, blue: 1.0) // #4ea1ff

    var body: some View {
        // Summed rather than compared per-bin against zero: SwiftLint's
        // empty_count rule autocorrects `$0.count == 0` to `$0.isEmpty`, which
        // DurationBin does not have.
        let totalClosed = bins.reduce(0) { $0 + $1.count }
        // Scale to the busiest bucket so the widest bar always fills the track.
        let maximum = max(bins.map(\.count).max() ?? 0, 1)

        return Group {
            if totalClosed == 0 {
                LogChartPlaceholder(text: "No closed connections yet.")
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(bins) { bin in
                        HStack(spacing: 10) {
                            Text(bin.label)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                // Fixed so every track starts at the same x —
                                // "30s–5m" is much wider than "5m+".
                                .frame(width: 54, alignment: .leading)

                            ProgressView(value: Double(bin.count), total: Double(maximum))
                                .progressViewStyle(.linear)
                                .tint(Self.barColor)

                            Text("\(bin.count)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(!bin.isEmpty ? .secondary : .tertiary)
                                .frame(width: 26, alignment: .trailing)
                        }
                        // Empty buckets stay on screen so the ladder does not
                        // reflow as connections close.
                        .opacity(!bin.isEmpty ? 1 : 0.45)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .accessibilityIdentifier("LogConnectionDurationsChart")
    }
}

// MARK: - Shared placeholder

private struct LogChartPlaceholder: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
    }
}

// MARK: - Container

/// Collapsible Summary + Histograms block.
///
/// ## Why this is height-bounded and internally scrollable
///
/// The app's main window uses `.windowResizability(.contentSize)`
/// (`Ditto_Edge_StudioApp.swift`), so the window is sized from its content's
/// **minimum** height. An earlier version of this view stacked two
/// `.frame(height: 110)` charts plus a `GeometryReader`-based bar list directly
/// in the detail column, contributing ~330pt of *incompressible* minimum. On a
/// laptop display that pushed the window's minimum past the screen: the window
/// grew taller than the display, its top clipped above the title bar, and both
/// the sidebar and the log list extended below the visible area — which reads as
/// "scrolling is broken and the UI is locked up".
///
/// The fix is structural. Everything expensive lives inside a `ScrollView` with
/// a `maxHeight` cap: a `ScrollView`'s minimum height is ~0, so this section now
/// contributes almost nothing to the window minimum no matter what it contains,
/// and the charts flex within the cap instead of dictating it.
struct LogAnalyticsSection: View {
    let analytics: LogAnalytics

    /// Ideal height for each time-series chart inside the bounded region.
    static let chartHeight: CGFloat = 150

    /// Hard cap on the histogram region.
    ///
    /// Sized to clear the content comfortably — one 150pt chart row plus the
    /// five duration rows and their titles land near 290pt — so nothing scrolls
    /// at a normal window size. The enclosing `ScrollView` is retained anyway:
    /// it is what keeps this section's *minimum* height near zero, and that is
    /// the property that stops a short display from growing the window off the
    /// screen. It is a safety net, not the everyday path.
    static let histogramsMaxHeight: CGFloat = 340

    @State private var isHistogramsExpanded: Bool

    #if os(macOS)
    private let isCompact = false
    #else
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    #endif

    init(analytics: LogAnalytics, histogramsExpandedByDefault: Bool = false) {
        self.analytics = analytics
        _isHistogramsExpanded = State(initialValue: histogramsExpandedByDefault)
    }

    var body: some View {
        if analytics.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // No Summary block: its Critical / Errors / Warnings / Problems
                // / Lines figures are the same numbers the filter tabs already
                // carry as badges, a few points below. Two readings of one
                // statistic invite them to disagree.
                DisclosureGroup(isExpanded: $isHistogramsExpanded) {
                    ScrollView(.vertical) {
                        histograms
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: Self.histogramsMaxHeight)
                } label: {
                    sectionLabel("Histograms")
                }
                .accessibilityIdentifier("LogHistogramsDisclosure")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            // Belt and braces: even with the internal ScrollView, this section
            // must never win a height fight against the log list below it.
            .frame(maxHeight: Self.histogramsMaxHeight + 44)
        }
    }

    private var histograms: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Side-by-side needs real width; on a compact iPad column the two
            // time-series charts stack instead of squeezing to illegibility.
            if isCompact {
                titled("Log Volume by Level") { LogVolumeHistogram(bins: analytics.volumeByLevel) }
                titled("Problems over Time") { LogProblemsHistogram(bins: analytics.problemsOverTime) }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    titled("Log Volume by Level") { LogVolumeHistogram(bins: analytics.volumeByLevel) }
                    titled("Problems over Time") { LogProblemsHistogram(bins: analytics.problemsOverTime) }
                }
            }
            titled("Connection Durations") {
                LogConnectionDurationsChart(bins: analytics.connectionDurations)
            }
        }
    }

    private func titled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }
}
