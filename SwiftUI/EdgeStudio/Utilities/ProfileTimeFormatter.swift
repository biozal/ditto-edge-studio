import Foundation

/// Formats `Int64` nanoseconds as a human-readable duration using a
/// three-tier auto-scale (ms / µs / ns).
///
/// Choice of tiers is grounded in cross-platform research (see
/// `plans/dql-profile-feature.md` → "Time format research"):
///
///   - **Postgres** / **MongoDB** `explain` always use ms with decimals,
///     which hides precision when the value is sub-millisecond
///     (e.g. `0.056 ms` is harder to read than `55.56 µs`).
///   - **MongoDB profiler** and **SQL Server Profiler** both ship a
///     "microseconds" toggle for that reason — sub-ms is more
///     readable in µs.
///   - **The Edge Studio web app reference** already uses µs/ms
///     auto-scaled per value (matches what users have seen).
///   - **Nanoseconds** are surfaced only when the raw value is
///     genuinely sub-µs (e.g. an operator's 209 ns exec time from the
///     Ditto worked example) — showing `0.21 µs` there throws away a
///     digit of useful precision.
///
/// Output examples:
///   - `432_430_000` → `"432.43 ms"`
///   - `55_560`      → `"55.56 µs"`
///   - `209`         → `"209 ns"`
///   - `0`           → `"0 ns"`
enum ProfileTimeFormatter {
    /// Boundary: nanoseconds at which we promote to microseconds.
    private static let nsPerMicro: Int64 = 1000
    /// Boundary: nanoseconds at which we promote to milliseconds.
    private static let nsPerMilli: Int64 = 1_000_000

    /// Formats a nanosecond duration. Negative values render with a
    /// leading minus; the duration logic uses the absolute value to
    /// pick the unit so a small negative doesn't fall into ms by
    /// accident.
    static func format(ns: Int64) -> String {
        let magnitude = ns < 0 ? -ns : ns
        let sign = ns < 0 ? "-" : ""

        if magnitude >= nsPerMilli {
            let ms = Double(magnitude) / Double(nsPerMilli)
            return "\(sign)\(String(format: "%.2f", ms)) ms"
        }
        if magnitude >= nsPerMicro {
            let us = Double(magnitude) / Double(nsPerMicro)
            return "\(sign)\(String(format: "%.2f", us)) µs"
        }
        return "\(sign)\(magnitude) ns"
    }

    /// Convenience for `Int64?` so call sites don't have to unwrap.
    /// Returns `"—"` (em dash) for nil — visually distinguishes "stat
    /// not reported by Ditto" from "stat is zero".
    static func format(ns: Int64?) -> String {
        guard let ns else { return "—" }
        return format(ns: ns)
    }

    /// Renders the share of total `elapsedNs` represented by the given
    /// raw value as a percentage string (e.g. `"19.1%"`). Returns nil
    /// if the share is below `threshold` (default 5%) so the caller
    /// can hide low-noise badges entirely.
    ///
    /// Used by the Plan view to attach a `(19.1%)` annotation to
    /// hotspot operators — see `plans/dql-profile-feature.md` for the
    /// Couchbase-style display this mimics.
    static func percentOfTotal(
        ns: Int64?,
        totalNs: Int64,
        threshold: Double = 0.05
    ) -> String? {
        guard let ns, totalNs > 0 else { return nil }
        let share = Double(ns) / Double(totalNs)
        if share < threshold { return nil }
        return String(format: "%.1f%%", share * 100)
    }
}
