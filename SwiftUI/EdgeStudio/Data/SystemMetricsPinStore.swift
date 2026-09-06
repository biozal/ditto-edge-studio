import Foundation

/// A pinned `system:metrics` series — the metric key plus the label map that,
/// together, identify one series. Deliberately NOT the whole sample: values
/// change every poll, pins do not.
struct SystemMetricSeriesRef: Codable, Equatable, Hashable, Identifiable {
    let key: String
    let labels: [String: String]

    /// Stable identity: metric key + sorted label map. The same scheme as
    /// `SystemMetricsAccumulator.seriesSignature`, the VS Code extension's
    /// `seriesId`, and the Android `SystemMetricSeriesRef.id`, so all four agree
    /// on what "the same series" means.
    var id: String {
        let sorted = labels.keys.sorted().map { "\($0)=\(labels[$0] ?? "")" }.joined(separator: ",")
        return "\(key)|\(sorted)"
    }

    /// The `key=value,key=value` line rendered under a row's metric name.
    var labelLine: String {
        labels.keys.sorted().map { "\($0)=\(labels[$0] ?? "")" }.joined(separator: ",")
    }

    init(key: String, labels: [String: String]) {
        self.key = key
        self.labels = labels
    }

    init(sample: SystemMetricSample) {
        self.init(key: sample.key, labels: sample.labels)
    }
}

/// Per-database pinned system-metrics series, persisted in `UserDefaults` under a
/// versioned per-database key so a developer's troubleshooting set survives
/// leaving the screen, closing the database, and relaunching the app.
///
/// The view owns edits and hands back the complete replacement list, so writes
/// here are wholesale — there is no merge to get wrong. Both entry points funnel
/// through `dedupe`, which is what enforces the "a series may never appear twice"
/// invariant no matter what produced the input (a hand-edited defaults plist, a
/// list written by an older build, a racing write).
enum SystemMetricsPinStore {
    private static let keyPrefix = "dittoSystemMetricsPins.v1."

    private static func defaultsKey(databaseId: String) -> String {
        keyPrefix + databaseId
    }

    private static func dedupe(_ pins: [SystemMetricSeriesRef]) -> [SystemMetricSeriesRef] {
        var seen = Set<String>()
        return pins.filter { seen.insert($0.id).inserted }
    }

    /// Pinned series for one database, in pin order. A stored value that no
    /// longer decodes is treated as "no pins" rather than failing the screen.
    static func read(databaseId: String, defaults: UserDefaults = .standard) -> [SystemMetricSeriesRef] {
        guard let data = defaults.data(forKey: defaultsKey(databaseId: databaseId)),
              let pins = try? JSONDecoder().decode([SystemMetricSeriesRef].self, from: data) else
        {
            return []
        }
        return dedupe(pins)
    }

    /// Replaces the pinned list for one database. An empty list removes the key
    /// entirely, so "Clear" leaves no residue behind.
    static func write(
        _ pins: [SystemMetricSeriesRef],
        databaseId: String,
        defaults: UserDefaults = .standard
    ) {
        let key = defaultsKey(databaseId: databaseId)
        let unique = dedupe(pins)
        guard !unique.isEmpty, let data = try? JSONEncoder().encode(unique) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}

/// Reordering rules for the pinned list, kept separate from the view so the index
/// arithmetic — the part that is easy to get subtly wrong — can be tested directly.
///
/// The rules match the VS Code extension's drag handler exactly, so a developer who
/// reorders pins on one platform gets the same result on the other.
enum SystemMetricsPinOrdering {
    /// Moves `draggedID` to sit immediately before (or after) `targetID`.
    ///
    /// The dragged entry is removed *first* and the insertion point resolved
    /// against what remains — the reason a downward drag lands where the pointer
    /// is rather than one slot short of it. A drop on the dragged row itself, or
    /// on a target that is no longer in the list (unpinned mid-drag), is a no-op.
    static func moved(
        _ pins: [SystemMetricSeriesRef],
        draggedID: String,
        targetID: String,
        insertBefore: Bool
    ) -> [SystemMetricSeriesRef] {
        guard draggedID != targetID,
              let dragged = pins.first(where: { $0.id == draggedID }) else { return pins }
        var rest = pins.filter { $0.id != draggedID }
        guard var index = rest.firstIndex(where: { $0.id == targetID }) else { return pins }
        if !insertBefore {
            index += 1
        }
        rest.insert(dragged, at: index)
        return rest
    }

    /// Moves the entry at `source` to `destination`, clamping both to the list.
    /// Backs the Move Up / Move Down commands, which are the keyboard- and
    /// VoiceOver-reachable equivalent of dragging.
    static func moved(
        _ pins: [SystemMetricSeriesRef],
        from source: Int,
        to destination: Int
    ) -> [SystemMetricSeriesRef] {
        guard pins.indices.contains(source), pins.indices.contains(destination), source != destination else {
            return pins
        }
        var reordered = pins
        reordered.insert(reordered.remove(at: source), at: destination)
        return reordered
    }
}
