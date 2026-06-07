import Foundation
import Testing

@testable import Ditto_Edge_Studio

// MARK: - QueryProfileParser Tests
//
// Covers the dictionary -> QueryProfile parser used by
// QueryService.executeSelectedAppQueryWithProfile.
//
// The parser is forgiving by design:
//   - Returns nil when the input isn't a recognisable profile envelope
//     (lets the caller treat "no profile" the same whether PROFILE
//     wasn't requested or the SDK didn't return one).
//   - Missing optional fields default rather than fail (so a partial
//     Ditto response still surfaces *something* useful).
//
// The fixture is the worked example from the user's spec
// (plans/dql-profile-feature.md) — keep this in sync if Ditto's
// `~request_profile` envelope shape changes.

@Suite("QueryProfileParser Tests")
struct QueryProfileParserTests {

    // MARK: - Happy path

    @Suite("Happy path")
    struct HappyPathTests {
        @Test(.tags(.model, .fast))
        func `Parses the canonical envelope`() throws {
            // ARRANGE
            let item = QueryProfileFixtures.canonicalEnvelope

            // ACT
            let profile = QueryProfileParser.parseItem(item)

            // ASSERT
            let parsed = try #require(profile)
            #expect(parsed.id == "e526fe68-04e9-4881-bf76-d0a582827e9b")
            #expect(parsed.appId == "f5e954d9-0092-47a0-9a79-2829e767ba7b")
            #expect(parsed.featureFlags == "0x3a")
            #expect(parsed.queryType == "select")
            #expect(parsed.requestType == "SDK")
            #expect(parsed.resultCount == 1)
            #expect(parsed.state == "completed")
            #expect(parsed.text == "PROFILE SELECT * FROM tasks LIMIT 1")
        }

        @Test(.tags(.model, .fast))
        func `Times are nanoseconds at source`() {
            // ARRANGE
            let item = QueryProfileFixtures.canonicalEnvelope

            // ACT
            let profile = QueryProfileParser.parseItem(item)

            // ASSERT
            #expect(profile?.times.elapsedNs == 1_294_166)
            #expect(profile?.times.parseNs == 49_834)
            #expect(profile?.times.planNs == 32_167)
            #expect(profile?.times.startISO == "2026-05-26T20:59:21.310-05:00")
        }

        @Test(.tags(.model, .fast))
        func `Root plan operator is sequence with two children`() {
            // ARRANGE
            let item = QueryProfileFixtures.canonicalEnvelope

            // ACT
            let profile = QueryProfileParser.parseItem(item)

            // ASSERT
            #expect(profile?.plan.name == "sequence")
            #expect(profile?.plan.children.count == 2)
            #expect(profile?.plan.children.first?.name == "scan")
            #expect(profile?.plan.children.last?.name == "limit")
        }

        @Test(.tags(.model, .fast))
        func `Operator stats parsed from phaseTimes`() {
            // ARRANGE
            let item = QueryProfileFixtures.canonicalEnvelope

            // ACT
            let profile = QueryProfileParser.parseItem(item)

            // ASSERT — scan: out only (no documentsIn), exec/recv/send all present
            let scan = profile?.plan.children[0]
            #expect(scan?.stats?.documentsOut == 1)
            #expect(scan?.stats?.documentsIn == nil)
            #expect(scan?.stats?.execNs == 209)
            #expect(scan?.stats?.recvNs == 990_459)
            #expect(scan?.stats?.sendNs == 61_500)

            // limit: in + out, exec/send present but no recv
            let limit = profile?.plan.children[1]
            #expect(limit?.stats?.documentsIn == 2)
            #expect(limit?.stats?.documentsOut == 1)
            #expect(limit?.stats?.execNs == 2_083)
            #expect(limit?.stats?.recvNs == nil)
            #expect(limit?.stats?.sendNs == 6_584)
        }

        @Test(.tags(.model, .fast))
        func `Operator attributes captured in sorted order with reserved keys stripped`() {
            // ARRANGE
            let item = QueryProfileFixtures.canonicalEnvelope

            // ACT
            let profile = QueryProfileParser.parseItem(item)

            // ASSERT
            // `scan` has collection + datasource attributes; `#operator`
            // and `#stats` must be filtered out, and the surviving keys
            // sorted alphabetically.
            let scan = profile?.plan.children[0]
            #expect(scan?.attributes.map(\.key) == ["collection", "datasource"])
            #expect(scan?.attributes.first(where: { $0.key == "collection" })?.value == "tasks")
            #expect(scan?.attributes.first(where: { $0.key == "datasource" })?.value == "default")

            // `limit` has a single numeric attribute
            let limit = profile?.plan.children[1]
            #expect(limit?.attributes.map(\.key) == ["limit"])
            #expect(limit?.attributes.first?.value == "1")
        }

        @Test(.tags(.model, .fast))
        func `capturedAt is set to current instant on parse`() {
            // ARRANGE
            let before = Date()

            // ACT
            let profile = QueryProfileParser.parseItem(QueryProfileFixtures.canonicalEnvelope)
            let after = Date()

            // ASSERT
            let captured = try? #require(profile?.capturedAt)
            #expect(captured ?? Date.distantPast >= before)
            #expect(captured ?? Date.distantFuture <= after)
        }
    }

    // MARK: - Negative cases

    @Suite("Negative cases")
    struct NegativeCaseTests {
        @Test(.tags(.model, .fast))
        func `Empty dictionary returns nil`() {
            #expect(QueryProfileParser.parseItem([:]) == nil)
        }

        @Test(.tags(.model, .fast))
        func `Normal user document without envelope returns nil`() {
            // ARRANGE — looks like a regular SELECT row, not a profile
            let userRow: [String: Any] = [
                "_id": "task-001",
                "title": "Buy milk",
                "done": false
            ]

            // ACT + ASSERT
            #expect(QueryProfileParser.parseItem(userRow) == nil)
        }

        @Test(.tags(.model, .fast))
        func `Envelope missing required _id returns nil`() {
            // ARRANGE — has plan but no _id
            let bad: [String: Any] = [
                QueryProfileParser.envelopeKey: [
                    "plan": ["#operator": "scan"]
                ]
            ]

            // ACT + ASSERT
            #expect(QueryProfileParser.parseItem(bad) == nil)
        }

        @Test(.tags(.model, .fast))
        func `Envelope missing plan returns nil`() {
            // ARRANGE
            let bad: [String: Any] = [
                QueryProfileParser.envelopeKey: [
                    "_id": "x",
                    "queryType": "select"
                ]
            ]

            // ACT + ASSERT
            #expect(QueryProfileParser.parseItem(bad) == nil)
        }

        @Test(.tags(.model, .fast))
        func `Plan operator missing _operator key returns nil parse`() {
            // ARRANGE — envelope is otherwise complete but the plan
            // node has no `#operator` field, which makes the node
            // meaningless.
            let bad: [String: Any] = [
                QueryProfileParser.envelopeKey: [
                    "_id": "x",
                    "plan": ["#stats": [:]]
                ]
            ]

            // ACT + ASSERT
            #expect(QueryProfileParser.parseItem(bad) == nil)
        }
    }

    // MARK: - Defensive / partial data

    @Suite("Partial data")
    struct PartialDataTests {
        @Test(.tags(.model, .fast))
        func `Missing times object defaults to zero`() {
            // ARRANGE — strip out the `times` key entirely
            var raw = QueryProfileFixtures.canonicalEnvelope
            if var inner = raw[QueryProfileParser.envelopeKey] as? [String: Any] {
                inner.removeValue(forKey: "times")
                raw[QueryProfileParser.envelopeKey] = inner
            }

            // ACT
            let profile = QueryProfileParser.parseItem(raw)

            // ASSERT
            #expect(profile?.times.elapsedNs == 0)
            #expect(profile?.times.parseNs == 0)
            #expect(profile?.times.planNs == 0)
            #expect(profile?.times.startISO == "")
        }

        @Test(.tags(.model, .fast))
        func `Operator with no children produces empty children array not nil`() {
            // ARRANGE — leaf-only plan
            let raw: [String: Any] = [
                QueryProfileParser.envelopeKey: [
                    "_id": "x",
                    "plan": [
                        "#operator": "scan",
                        "collection": "tasks"
                    ]
                ]
            ]

            // ACT
            let profile = QueryProfileParser.parseItem(raw)

            // ASSERT
            #expect(profile?.plan.children.isEmpty == true)
        }

        @Test(.tags(.model, .fast))
        func `Unknown attribute types still render via String describing`() {
            // ARRANGE — array attribute (not a primitive)
            let raw: [String: Any] = [
                QueryProfileParser.envelopeKey: [
                    "_id": "x",
                    "plan": [
                        "#operator": "scan",
                        "indexes": ["idx1", "idx2"]
                    ]
                ]
            ]

            // ACT
            let profile = QueryProfileParser.parseItem(raw)
            let indexes = profile?.plan.attributes.first { $0.key == "indexes" }?.value

            // ASSERT — re-encoded as compact JSON
            #expect(indexes == #"["idx1","idx2"]"#)
        }

        @Test(.tags(.model, .fast))
        func `Bare profile dict without envelope wrapper still parses`() {
            // ARRANGE — same content as canonicalEnvelope but without
            // the outer ~request_profile wrapper (defensive: covers
            // SDK changes that strip the wrapper).
            guard let inner = QueryProfileFixtures.canonicalEnvelope[QueryProfileParser.envelopeKey]
                as? [String: Any] else
            {
                Issue.record("Fixture envelope missing inner dict")
                return
            }

            // ACT
            let profile = QueryProfileParser.parseItem(inner)

            // ASSERT — falls through the bare-profile detection branch
            #expect(profile?.id == "e526fe68-04e9-4881-bf76-d0a582827e9b")
        }
    }

    // MARK: - QueryProfile convenience

    @Suite("displayQueryText")
    struct DisplayQueryTextTests {
        @Test(.tags(.model, .fast))
        func `Strips leading PROFILE prefix`() {
            // ARRANGE
            let profile = QueryProfileParser.parseItem(QueryProfileFixtures.canonicalEnvelope)

            // ASSERT — original text in the envelope is
            // "PROFILE SELECT * FROM tasks LIMIT 1"; user should see
            // just "SELECT * FROM tasks LIMIT 1"
            #expect(profile?.displayQueryText == "SELECT * FROM tasks LIMIT 1")
        }
    }
}

// MARK: - Fixtures

/// Worked example from plans/dql-profile-feature.md. Keep in sync
/// with the spec — both the plan doc and this fixture model the
/// real `~request_profile` envelope Ditto emits.
enum QueryProfileFixtures {
    // Immutable test fixture; safe to share across concurrency domains.
    nonisolated(unsafe) static let canonicalEnvelope: [String: Any] = [
        "~request_profile": [
            "_id": "e526fe68-04e9-4881-bf76-d0a582827e9b",
            "app_id": "f5e954d9-0092-47a0-9a79-2829e767ba7b",
            "featureFlags": "0x3a",
            "plan": [
                "#operator": "sequence",
                "children": [
                    [
                        "#operator": "scan",
                        "#stats": [
                            "documentsOut": 1,
                            "phaseTimes": [
                                "exec": 209,
                                "recv": 990_459,
                                "send": 61_500
                            ]
                        ],
                        "collection": "tasks",
                        "datasource": "default"
                    ],
                    [
                        "#operator": "limit",
                        "#stats": [
                            "documentsIn": 2,
                            "documentsOut": 1,
                            "phaseTimes": [
                                "exec": 2_083,
                                "send": 6_584
                            ]
                        ],
                        "limit": 1
                    ]
                ]
            ],
            "queryType": "select",
            "requestType": "SDK",
            "resultCount": 1,
            "state": "completed",
            "text": "PROFILE SELECT * FROM tasks LIMIT 1",
            "times": [
                "elapsed": 1_294_166,
                "parse": 49_834,
                "plan": 32_167,
                "start": "2026-05-26T20:59:21.310-05:00"
            ]
        ]
    ]
}
