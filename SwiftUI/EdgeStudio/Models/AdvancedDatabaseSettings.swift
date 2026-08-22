import Foundation

// MARK: - Sync Scopes

/// Where a single user collection is allowed to synchronize.
///
/// The raw values are the literal strings DQL expects in
/// `ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES` — they are a wire format, not a
/// display concern, so they must never be renamed. Note `SmallPeersOnly` is plural.
///
/// There is deliberately **no** tolerant parser here. Sync scopes are a data
/// containment control: silently coercing an unrecognized value (say, a scope added
/// by a future SDK) into some other scope could let data leave a device the user
/// believed was local-only. An unknown value fails to decode instead.
enum SyncScope: String, CaseIterable, Codable, Sendable {
    case allPeers = "AllPeers"
    case bigPeerOnly = "BigPeerOnly"
    case smallPeersOnly = "SmallPeersOnly"
    case localPeerOnly = "LocalPeerOnly"

    var displayName: String {
        switch self {
        case .allPeers: return "All Peers"
        case .bigPeerOnly: return "Big Peer Only"
        case .smallPeersOnly: return "Small Peers Only"
        case .localPeerOnly: return "Local Peer Only"
        }
    }

    /// Legend copy shown beneath the sync-scope rows.
    var explanation: String {
        switch self {
        case .allPeers: return "Ditto Server and Small Peers"
        case .bigPeerOnly: return "Ditto Server only"
        case .smallPeersOnly: return "Small Peers only"
        case .localPeerOnly: return "never leaves this device"
        }
    }
}

/// One collection → scope mapping.
///
/// `id` is a synthetic, stable `UUID`, **not** the collection name. Using the
/// user-editable text as identity breaks three ways: two not-yet-named rows collide
/// on `""`, `removeAll { $0.id == id }` deletes every row sharing a name, and the
/// identity changes on every keystroke so `ForEach` tears the row's `TextField` down
/// and drops focus. The collection name remains the *validation* key via `syncKey`.
///
/// `id` is excluded from `Codable` (it has a default, so synthesis still works) and
/// from `==`, so a decoded row still equals the row it was encoded from.
struct CollectionSyncScope: Codable, Identifiable, Sendable {
    var id = UUID()
    var collection: String
    var scope: SyncScope

    /// The trimmed collection name — the key used for validation and DQL.
    var syncKey: String {
        collection.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum CodingKeys: String, CodingKey {
        case collection
        case scope
    }
}

extension CollectionSyncScope: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.collection == rhs.collection && lhs.scope == rhs.scope
    }
}

// MARK: - Startup System Settings

/// Value kinds offered for a startup `ALTER SYSTEM` setting.
///
/// `ALTER SYSTEM` also accepts arrays; there is no dedicated array editor, but any
/// valid JSON document is accepted under `.json`, so `["a","b"]` already produces a
/// real array.
enum StartupSettingType: String, CaseIterable, Codable, Sendable {
    case string
    case json
    case integer
    case double
    case boolean

    var displayName: String {
        switch self {
        case .string: return "String"
        case .json: return "JSON"
        case .integer: return "Integer"
        case .double: return "Double"
        case .boolean: return "Boolean"
        }
    }
}

/// A typed value on its way into `ditto.store.execute(query:arguments:)`.
///
/// Deliberately a closed `Sendable` enum rather than `Any?`: `Any` is not `Sendable`,
/// and these values are handed from the `@MainActor` editor to the `DittoManager`
/// actor. The bridge to `Any` happens at the `execute` call site inside the actor.
enum DQLValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case uint(UInt64)
    case double(Double)
    case bool(Bool)
    /// Raw JSON text, validated at construction and re-parsed at the call site.
    case json(Data)

    /// The `Any` form the SDK's argument dictionary expects.
    var argumentValue: Any {
        switch self {
        case let .string(value): return value
        case let .int(value): return value
        case let .uint(value): return value
        case let .double(value): return value
        case let .bool(value): return value
        case let .json(data):
            // Validated non-nil by `StartupSetting.typedValue`; fall back to the raw
            // text rather than crashing if that ever stops holding.
            if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                return object
            }
            return String(bytes: data, encoding: .utf8) ?? ""
        }
    }
}

/// One startup `ALTER SYSTEM SET <parameter> = <value>` row.
///
/// `value` is always stored as text — that keeps the model `Codable`/`Equatable` and
/// lets the editor hold a single field type — and is coerced only when the statement
/// is built. `syncKey` (the trimmed parameter name) is the validation/DQL key; DQL
/// treats parameter names case-insensitively on write and reads them back lowercased,
/// so dedupe compares case-insensitively while the write preserves what was typed.
struct StartupSetting: Codable, Identifiable, Sendable {
    /// Synthetic stable identity — see `CollectionSyncScope.id` for why the parameter
    /// name cannot serve as one.
    var id = UUID()
    var parameter: String
    var type: StartupSettingType
    var value: String
    /// Set once the user has explicitly acknowledged a `isSensitiveParameter` name.
    ///
    /// **Persisted on purpose.** The acknowledgement used to live only in the editor's
    /// view model, which meant a setting arriving from any non-UI ingress (a scanned
    /// QR code, a seeded plist, a hand-edited database) was applied with no prompt at
    /// all — including `metrics_exporter_prometheus_http_listener_addr`, which opens a
    /// listening socket on every interface. The apply path now requires this flag.
    var isAcknowledged: Bool

    /// The name used for validation, dedupe and DQL, trimmed.
    var syncKey: String {
        parameter.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum CodingKeys: String, CodingKey {
        case parameter
        case type
        case value
        case isAcknowledged
    }

    init(parameter: String, type: StartupSettingType, value: String, isAcknowledged: Bool = false) {
        self.parameter = parameter
        self.type = type
        self.value = value
        self.isAcknowledged = isAcknowledged
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        parameter = try container.decode(String.self, forKey: .parameter)
        type = try container.decode(StartupSettingType.self, forKey: .type)
        value = try container.decode(String.self, forKey: .value)
        // Absent means "never acknowledged" — the safe default for older rows.
        isAcknowledged = try container.decodeIfPresent(Bool.self, forKey: .isAcknowledged) ?? false
    }

    /// The coerced value, or `nil` when `value` does not parse as `type` — which the
    /// editor surfaces as a row-level error and which blocks Save.
    var typedValue: DQLValue? {
        switch type {
        case .string:
            // Empty is legal: `transports_ble_adapter_mac` ships as "".
            return .string(value)

        case .json:
            let data = Data(value.utf8)
            guard !value.isEmpty,
                  (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else { return nil }
            return .json(data)

        case .integer:
            // `Int` is not sufficient: real parameters ship as UInt64.max, e.g.
            // `dql_request_history_log_dump_limit` == 18446744073709551615, which
            // `Int(_:)` cannot represent.
            if let intValue = Int(value) {
                return .int(intValue)
            }
            if let uintValue = UInt64(value) {
                return .uint(uintValue)
            }
            return nil

        case .double:
            // Accepts scientific notation, e.g. "1.0000000000000001e-09".
            guard let doubleValue = Double(value) else { return nil }
            return .double(doubleValue)

        case .boolean:
            // `Bool.init?(String)` is case-sensitive — `Bool("True")` is nil — so the
            // picker's capitalised text must be mapped explicitly.
            switch value.lowercased() {
            case "true": return .bool(true)
            case "false": return .bool(false)
            default: return nil
            }
        }
    }

    /// Canonical picker values for `.boolean` rows.
    static let booleanValues = ["True", "False"]

    /// The canonical spelling of a boolean value, or `nil` when the text is not boolean
    /// at all.
    ///
    /// The value `Picker` tags rows with these exact strings, so a case variant — `true`,
    /// `FALSE` — is a *valid* setting (`typedValue` lowercases before matching) that the
    /// picker cannot render: no tag matches, so it draws blank while Save stays enabled.
    /// Reachable without any external ingress: type `false` as a String, switch the type
    /// to Boolean, and `setType`'s case-insensitive check keeps it verbatim.
    static func canonicalBooleanValue(_ value: String) -> String? {
        booleanValues.first { $0.caseInsensitiveCompare(value) == .orderedSame }
    }
}

extension StartupSetting: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.parameter == rhs.parameter
            && lhs.type == rhs.type
            && lhs.value == rhs.value
            && lhs.isAcknowledged == rhs.isAcknowledged
    }
}

// MARK: - Apply Result

/// What `DittoManager` actually managed to apply, returned rather than only logged so
/// tests and the UI can assert on it (`LoggingService` has no injectable sink, and
/// CocoaLumberjack writes asynchronously, so log scraping is untestable).
struct AdvancedApplyResult: Sendable, Equatable {
    struct Skipped: Sendable, Equatable {
        let name: String
        let reason: String
    }

    var appliedSettings: [String] = []
    var skippedSettings: [Skipped] = []
    var appliedScopeCount = 0
    /// True when scopes were written but the read-back could not confirm them — the
    /// write succeeded, so the open proceeds, but we must not claim verification.
    var scopesUnverified = false

    var hasFailures: Bool {
        !skippedSettings.isEmpty
    }
}

// MARK: - Validation

/// Pure validation shared by the editor and the apply path.
///
/// The apply path is the real chokepoint — configs can reach it without passing
/// through the editor (seeded plists, imports, a future JSON import) — so every rule
/// lives here rather than in the view.
enum AdvancedSettingsValidator {
    /// Upper bound on a single setting value. Nothing else bounds a pasted blob that
    /// would then be re-parsed on every database open.
    static let maxValueLength = 4096
    /// Upper bound on rows per list.
    static let maxRowCount = 64

    /// Parameters the app owns through dedicated UI. Allowing them here would create
    /// two controls writing one parameter with order-dependent precedence.
    static let reservedParameterExactNames: Set = [
        "user_collection_sync_scopes",
        "dql_strict_mode",
        "mesh_chooser_max_wlan_clients",
        "data_sync_enabled"
    ]

    /// Prefixes owned by the transport configuration UI.
    static let reservedParameterPrefixes = ["transports_", "udp_"]

    /// Parameters that can expose data on the network or weaken durability. Allowed,
    /// but the editor requires an explicit acknowledgement first.
    ///
    /// - `*_listener_addr` can open a listening socket on every interface
    ///   (`metrics_exporter_prometheus_http_listener_addr` defaults to "0.0.0.0:9000").
    /// - `*_certs` adds a trusted CA.
    /// - `sqlite3_*` includes `synchronous` / `journal_mode`, i.e. store durability.
    static func isSensitiveParameter(_ name: String) -> Bool {
        let lowered = name.lowercased()
        if lowered.hasSuffix("_listener_addr") || lowered.hasSuffix("_certs") {
            return true
        }
        if lowered.hasPrefix("sqlite3_") {
            return true
        }
        // Token match, NOT `contains("port")`: that substring also matches "exporter",
        // "import" and "report", which flagged every `metrics_exporter_*` parameter and
        // trained users to tick the acknowledgement without reading it.
        let tokens = lowered.split(separator: "_")
        return tokens.contains("port") || tokens.contains("ports")
    }

    // MARK: Collections

    enum CollectionError: Equatable {
        case empty
        case systemCollection
        case needsQuoting
        case duplicate

        var message: String {
            switch self {
            case .empty: return "Enter a collection name."
            case .systemCollection: return "System collections cannot be scoped."
            case .needsQuoting: return "Collection names cannot contain quotes or spaces."
            case .duplicate: return "This collection already has a scope."
            }
        }
    }

    /// Validates one collection name. `others` is every other row's raw name.
    static func validateCollection(_ raw: String, others: [String]) -> CollectionError? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Trim first: "   " and "orders " both pass a naive non-empty check and would
        // produce a scope key that matches no collection, silently doing nothing.
        if name.isEmpty {
            return .empty
        }
        if isSystemCollection(name) {
            return .systemCollection
        }
        if name.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
            || name.contains("\"") || name.contains("'") || name.contains("`")
        {
            return .needsQuoting
        }
        let normalizedOthers = others.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if normalizedOthers.contains(name) {
            return .duplicate
        }
        return nil
    }

    /// System collections are `__`-prefixed in DQL; this codebase also surfaces them
    /// as `system:`-prefixed names.
    static func isSystemCollection(_ name: String) -> Bool {
        name.hasPrefix("__") || name.lowercased().hasPrefix("system:")
    }

    // MARK: Parameters

    enum ParameterError: Equatable {
        case empty
        case invalidName
        case reserved
        case duplicate
        case valueTooLong
        case valueNotParsable(StartupSettingType)
        case needsAcknowledgement
        case tooManyRows

        var message: String {
            switch self {
            case .empty: return "Enter a parameter name."
            case .invalidName: return "Use letters, digits and underscores only."
            case .reserved: return "This parameter is managed elsewhere in Edge Studio."
            case .duplicate: return "This parameter is already set."
            case .valueTooLong: return "Value is too long (max \(maxValueLength) characters)."
            case let .valueNotParsable(type): return "Value is not a valid \(type.displayName)."
            case .needsAcknowledgement:
                return "Confirm you understand this parameter's risk before saving."
            case .tooManyRows:
                return "Too many startup settings (max \(maxRowCount))."
            }
        }
    }

    /// True when `name` is a legal `ALTER SYSTEM` parameter identifier.
    ///
    /// Whole-string matched on purpose. `range(of:options:.regularExpression)` accepts
    /// a *partial* match, which would let `"ok; ALTER SYSTEM SET data_sync_enabled =
    /// false --"` through, and ICU's `$` also matches before a trailing newline — the
    /// parameter name is interpolated into DQL, so this is the injection guard.
    static func isValidParameterName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 128 else { return false }
        var isFirst = true
        for scalar in name.unicodeScalars {
            let isLetter = (scalar >= "a" && scalar <= "z") || (scalar >= "A" && scalar <= "Z")
            let isDigit = scalar >= "0" && scalar <= "9"
            let isUnderscore = scalar == "_"
            if isFirst {
                guard isLetter || isUnderscore else { return false }
                isFirst = false
            } else {
                guard isLetter || isDigit || isUnderscore else { return false }
            }
        }
        return true
    }

    static func isReservedParameter(_ name: String) -> Bool {
        let lowered = name.lowercased()
        if reservedParameterExactNames.contains(lowered) {
            return true
        }
        return reservedParameterPrefixes.contains { lowered.hasPrefix($0) }
    }

    /// Validates one startup setting. `others` is every other row's raw parameter name.
    static func validateSetting(_ setting: StartupSetting, others: [String]) -> ParameterError? {
        let name = setting.parameter.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return .empty
        }
        if !isValidParameterName(name) {
            return .invalidName
        }
        if isReservedParameter(name) {
            return .reserved
        }
        let normalizedOthers = others.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if normalizedOthers.contains(name.lowercased()) {
            return .duplicate
        }
        if setting.value.count > maxValueLength {
            return .valueTooLong
        }
        if setting.typedValue == nil {
            return .valueNotParsable(setting.type)
        }
        // Checked here rather than only in the editor, so a setting arriving from a
        // scanned QR code or a seeded plist cannot be applied unacknowledged.
        if isSensitiveParameter(name), !setting.isAcknowledged {
            return .needsAcknowledgement
        }
        return nil
    }

    /// Validates a whole list the way the apply path needs it: duplicates resolved
    /// across the list and the row cap enforced.
    ///
    /// The editor validates row-by-row so it can show inline messages; this is the
    /// single chokepoint that also covers non-UI ingress, where `validateSetting`
    /// alone was passing `others: []` and therefore never detecting duplicates.
    ///
    /// - Returns: the rows that may be applied, and a reason per rejected row.
    static func partitionSettings(
        _ settings: [StartupSetting]
    ) -> (allowed: [StartupSetting], rejected: [(setting: StartupSetting, error: ParameterError)]) {
        var allowed: [StartupSetting] = []
        var rejected: [(setting: StartupSetting, error: ParameterError)] = []
        var seen: Set<String> = []

        for setting in settings {
            if let error = validateSetting(setting, others: []) {
                rejected.append((setting, error))
                continue
            }
            let key = setting.syncKey.lowercased()
            if seen.contains(key) {
                rejected.append((setting, .duplicate))
                continue
            }
            guard allowed.count < maxRowCount else {
                rejected.append((setting, .tooManyRows))
                continue
            }
            seen.insert(key)
            allowed.append(setting)
        }
        return (allowed, rejected)
    }
}

// MARK: - DQL Construction

/// Builds the DQL for the advanced settings. Pure and synchronous so the statements
/// and arguments are unit-testable without a Ditto instance.
enum AdvancedSettingsDQL {
    static let syncScopesParameter = "USER_COLLECTION_SYNC_SCOPES"
    static let syncScopesReadParameter = "user_collection_sync_scopes"

    static let setSyncScopesQuery = "ALTER SYSTEM SET \(syncScopesParameter) = :scopes"
    static let showSyncScopesQuery = "SHOW \(syncScopesReadParameter)"
    static let resetAllQuery = "ALTER SYSTEM RESET ALL"

    enum ScopeMapError: Error, Equatable {
        case duplicateCollection(String)
        case invalidCollection(String)
        case tooManyScopes(Int)
    }

    /// Collection → DQL scope string, ready to pass as a query argument.
    ///
    /// Throws rather than resolving conflicts: a duplicate could otherwise silently
    /// pick the wider scope of the two, which for `LocalPeerOnly` means data leaving
    /// the device.
    static func scopeMap(from scopes: [CollectionSyncScope]) throws -> [String: String] {
        guard scopes.count <= AdvancedSettingsValidator.maxRowCount else {
            throw ScopeMapError.tooManyScopes(scopes.count)
        }
        var map: [String: String] = [:]
        for entry in scopes {
            let name = entry.syncKey
            guard AdvancedSettingsValidator.validateCollection(name, others: []) == nil else {
                // Same rule set as the editor (empty / system / needs-quoting), so a row
                // that never passed through the UI cannot become a scope key that matches
                // no collection and then verifies as applied.
                throw ScopeMapError.invalidCollection(entry.collection)
            }
            guard map[name] == nil else {
                throw ScopeMapError.duplicateCollection(name)
            }
            // The raw value, never `displayName` — mixing those up would silently
            // mis-scope every collection.
            map[name] = entry.scope.rawValue
        }
        return map
    }

    /// The statement for one startup setting. The parameter name is interpolated
    /// (DQL cannot parameterize identifiers), so callers must have validated it.
    static func settingStatement(for setting: StartupSetting) -> String {
        "ALTER SYSTEM SET \(setting.syncKey) = :value"
    }
}
