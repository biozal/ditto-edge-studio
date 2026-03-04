# DittoSim — Open Questions and Design Decisions

**Status:** Awaiting Answers
**Last Updated:** 2026-02-22

This document captures all design questions that need decisions before implementation begins. These are grouped by priority.

---

## Priority 1 — Must Decide Before Starting Phase 1 (Wizard + Data Model)

### Q1: Can multiple simulations be active simultaneously?

**Context:** The current design assumes one active simulation at a time. If multiple simulations can be active, subscription queries need an additional `status` filter to avoid syncing data from completed simulations.

**Options:**
- A) One active simulation at a time per Ditto database (simplest)
- B) Multiple simulations per database (more complex subscription filtering needed)

**Recommended:** A — one at a time. Users creating a new simulation should see a warning if one is running.

**Decision:**  it's always going to be A.  This is a simple simulator to show off data flowing that can be used to learn and demo Ditto. 

---

### Q2: How should sample data _id fields be handled?

**Context:** When a bot uses `loadData` and runs the same order multiple times (loop), the `_id` field of the order will conflict on the second INSERT.

**Options:**
- A) Bot generates a new random `_id` before each INSERT (replaces `current.item._id` with a UUID)
- B) User is responsible for using `ON ID CONFLICT DO UPDATE` in their DQL statement
- C) The `loadData` step auto-generates unique IDs using a `{{uuid}}` template variable

**Recommended:** C — add `{{uuid}}` as a template variable, and the `loadData` step automatically appends a run-specific suffix to the `_id` when `updateTimestamp: true` is set. Document clearly in the schema.

**Decision:**  C 

---

### Q3: What happens when a bot's simulation start time passes but the bot hasn't confirmed?

**Context:** A bot in `pending` status that never becomes `acknowledged` will block the "Schedule" button. What if the user wants to start anyway?

**Options:**
- A) User can force-start, skipping unconfirmed bots entirely (those bots won't execute)
- B) User can remove an unconfirmed bot and reschedule
- C) Require all bots to confirm before scheduling (current design)
- D) Time-limited auto-cancellation of unconfirmed bots (e.g., after 10 minutes)

**Recommended:** A + B — allow force-start (with warning) and allow removing unconfirmed bots.

**Decision:** C - the simulation doesn't start if the status isn't set to ready.  All bots must check in prior to start.  A simuluation is ran usually by a single person with phones on there desk.  This isn't an issue. 

---

### Q4: What does the running screen card color represent?

**Context:** The `running-screen.png` mockup shows bot cards in different colors (blue, orange, green, purple). This could mean:

**Options:**
- A) Colors represent **bot role** (each role type gets a consistent color)
- B) Colors represent **bot status** (green=running, orange=warning, red=error)
- C) Colors are **auto-assigned randomly** at simulation creation time for visual differentiation
- D) Colors represent **transport type** (blue=Bluetooth, green=WiFi, purple=Cloud)

**Recommended:** A — role-based colors. This helps users quickly identify which type of device is having an issue. The card should also show a status indicator separately (a small colored dot in the corner).

**Decision:** It's D.  As devices change transports most developers want to see oh I see the ordering system is now using Blueooth instead of P2P Wifi for example. 

---

### Q5: How many bots maximum?

**Context:** The mockup shows 8. The description says "at most 12." The Ditto presence graph may have many more devices.

**Options:**
- A) Hard cap at 8 (fits the 2x4 grid in the mockup)
- B) Hard cap at 12 (as described)
- C) No hard cap (UI must scroll for >8)

**Recommended:** B — cap at 12 for Phase 1 POC. The UI can show 2x4 = 8 visible at once with scroll for 9-12.

**Decision:** It's 3 x 4 grid for a max of 12 bots in the POC.  On average I would only be testing with up to 5 devices.  

---

## Priority 2 — Must Decide Before Starting Phase 2 (Bot App)

### Q6: iOS Background Execution

**Context:** iOS aggressively suspends apps. A simulation may run for 60+ minutes. The bot app cannot rely on background execution APIs for long-running work.

**Options:**
- A) Require bot app to stay in foreground — show a "Keep App Open" warning, disable device sleep
- B) Use BGProcessingTask (max 30 minutes, requires charging + WiFi)
- C) Build a watchdog that re-launches suspended work on foreground return

**Recommended:** A for Phase 1 POC. Add screen lock prevention. Document limitation clearly in the UI.

**Decision:** A - this will run in a lab where the devices have sleep during off and are always running with a power cable attached.  It's a very simple simulator.  No need for a message since this is used by developers.   

---

### Q7: Bot recovery after being offline mid-simulation

**Context:** A bot could go offline during a simulation (battery dies, user accidentally closes app). When it comes back:

**Options:**
- A) Bot resumes from current step based on its last logged position (complex — requires checkpointing)
- B) Bot marks itself `failed` and notifies orchestrator (simple)
- C) Bot marks itself `offline`, and when it reconnects, resumes from the step after the last logged step (medium complexity)
- D) Bot restarts scenario from the beginning of the current scenario (simpler but repeats work)

**Recommended:** C for Phase 2. The `seq` counter in bot logs enables detecting the last completed step. For Phase 1 POC, option B is acceptable.

**Decision:** It's C - but needs to be logged so we know that happened. 

---

### Q8: What Ditto SDK identity type should bots use?

**Context:** The QR code from Edge Studio contains the same auth credentials as the database config. The bot needs to authenticate with Ditto to join the mesh.

**Options:**
- A) Online Playground identity (uses token + authUrl) — requires internet for initial auth
- B) Small Peers Only with Shared Key — fully offline, no cloud auth required
- C) Online Playground with fallback to Offline Playground

**Impact:** If bots use Shared Key, they can work fully offline (Bluetooth + P2P WiFi only). If they use Online Playground, they need internet to authenticate at least once.

**Recommended:** A for simplicity in Phase 1 POC. Add shared key support in Phase 2.

**Decision:** It's what ever is shared in the QR Code.  We already do this today in Ditto Edge Server where we share the config and then based on that we calculate how to initialize the Ditto SDK.  I'm not worried about this. 

---

### Q9: How complex should the template variable engine be?

**Context:** The scenario file format uses `{{variable}}` for simple path interpolation. But some use cases need expressions:

- `{{trigger.document.items.length}}` — property access on nested object
- `{{step.insert_order.result.mutatedDocumentIds[0]}}` — array indexing
- `{{current.item.total * 1.08}}` — arithmetic

**Options:**
- A) Simple path-only interpolation (dots and array indexing only) — fast to implement
- B) Full expression evaluation (add arithmetic, comparisons, string functions) — much more complex
- C) JSONPath-based interpolation (`{{$.step.insert_order.result.mutatedDocumentIds[0]}}`)

**Recommended:** A for Phase 1 POC, with explicit TODO for B in Phase 2. Most scenario files can work with path interpolation.

**Decision:** A is the right answer for our simple POC and we might never move past that.  For more complex things it would be way easier to use something like n8n.io for this.   

---

### Q10: Reactive scenario lifecycle

**Context:** A reactive scenario observes a Ditto collection and runs steps for each triggering event. But:
- What if the observer fires 100 times before the scenario steps finish once?
- When does the reactive scenario stop?

**Options:**
- A) Each trigger creates an independent coroutine (up to `maxConcurrentReactiveScenarios`)
- B) Each trigger queues work; only one execution at a time (backpressure)
- C) Latest-wins: new trigger cancels running execution, starts fresh

**Recommended:** A with the `maxConcurrentReactiveScenarios` cap to prevent runaway concurrent execution. New triggers beyond the cap are dropped (with a log warning).

**Decision:** this is not an issue - Kotlin supports flows with built in backpressure - an observer won't fire until the you complete the current one, so B is the answer but you don't have to worry about this the SDK handles this. 

---

## Priority 3 — Results and Analysis

### Q11: What latency metrics should the results view show?

**Context:** The primary goal is helping developers understand data model performance impact. What metrics matter most?

**Suggested metrics:**
1. **Document propagation latency** — Time from INSERT on one bot to receipt on another bot (requires timestamp tagging in documents + cross-bot log correlation)
2. **Sync queue depth** — How many docs were waiting to sync at any given time
3. **Transport-specific latency** — Separate metrics for WiFi vs Bluetooth vs Cloud sync
4. **Step execution duration distribution** — Histogram of how long DQL operations took
5. **Bot availability** — Uptime percentage, offline periods

**Question:** Is document propagation latency tracking part of the POC scope? It requires that the scenario file include logic to timestamp documents with the bot's peerKey, and the receiving bot to log when it received the document. This is additional complexity in the scenario file design.

**Decision:** Everything and anything we can log.  We want to know how long it took between putting in a document and then someone receiving it via an observer.  This is the most important thing to log is that latency.  Anything else we can log obviously will only help us understand things beter, but we can only log what the SDK exposes and that's not a lot right now.  We need to do more research into this - so we should probably come back around to this. 

We would probably want to dump the information from SELECT * FROM system:system_info every so often from each bot into a lot file as that has stats in it that we can use to calculate a picture of what was going on and it has good timestamps.  

https://docs.ditto.live/dql/virtual-collections#systemsystem_info

---

### Q12: Should simulation results be exportable?

**Context:** Developers may want to share results with their team or save them for comparison across multiple test runs.

**Options:**
- A) Export as JSON (raw log data)
- B) Export as CSV (tabular summary)
- C) Export as PDF (formatted report)
- D) No export in Phase 1 POC

**Recommended:** D for Phase 1. A + B in Phase 2.

**Decision:** it should be A - but really we should build some kind of results viewer that allows the user to get results and put them in a PDF via export option so also C. 

---

## Priority 4 — UX Decisions

### Q13: Simulation list — what information to show per card?

**Context:** The empty state mockup (`simulator-empty.png`) shows the simulation section within the existing Edge Studio sidebar. When simulations exist, what does the list look like?

**Suggested card contents:**
- Simulation name
- Status badge (draft/pending/running/completed)
- Number of bots
- Scheduled time (or "ran on" date)
- Duration

**Decision:** we wont have a lot of them so it should be name, status, number of bots, scheudle time, and duration. 

---

### Q14: Can a simulation be edited after creation?

**Context:** After a simulation is created and sent to bots, changing it would invalidate bot acknowledgements.

**Options:**
- A) No editing after creation — must delete and recreate
- B) Allow editing only while in `draft` status
- C) Allow scenario file replacement while in `pending_confirmation` (resets all bot acks)

**Recommended:** B — allow editing while draft only. After "Create Simulation" is clicked, treat it as immutable.

**Decision:** B - otherwise this gets too complex in the POC. 

---

### Q15: What is the "Save Progress" button in the wizard mockup?

**Context:** The wizard mockups show a "Save Progress" button in the top right. This suggests the wizard can be saved mid-completion as a draft.

**Implication:** The wizard state (selected peers, uploaded files, bot names/roles) must be persisted to SQLCipher as a draft simulation. The user can leave and return without losing their work.

**Question:** Is this feature in scope for Phase 1, or can we simplify to "complete the wizard in one sitting"?

**Recommended:** Include "Save as Draft" in Phase 1 — it's important for a wizard that requires external file uploads which may take time to prepare.

**Decision:** You have to be able to save it as it takes time to make the files for each bot.  So you would be able to save it in draft status and then once the user says I'm ready it can't be edited anymore - they would have to delete it and re-create it.

---

## Architecture Questions

### Q16: Should scenario docs include steps as an embedded array or separate documents?

**Current design:** Steps are embedded in the `__des_sim_scenarios` document as an array.

**Rationale for embedding:** The orchestrator is the only writer. No concurrent writes = no LWW conflict risk. Embedded steps are simpler to sync and query.

**Concern:** Very large scenario files (200+ steps) could create very large documents that slow sync.

**Alternative:** Create one `__des_sim_steps` document per step.

**Recommendation:** Embed steps for Phase 1 (simpler). Add a maximum step count validation (e.g., warn if >100 steps per scenario). Split into separate documents if benchmarking shows sync performance degradation.

**Decision:** Arrays are bad in CRDTs - you can do maps with embedded objects, but if we are storing the informaiton in Ditto, because of different network transports and speed it's always beter to make smaller documents than one large document because then it can sync over any transport. 

---

### Q17: How does the bot app know its own peer key?

**Context:** The bot needs to know its Ditto peer key to subscribe to its own documents. The peer key is assigned by the Ditto SDK.

**Implementation:** After initializing Ditto, the bot calls `ditto.presence.graph.localPeer.peerKey` (or equivalent SDK API) to get its own peer key. This is then used to filter subscriptions.

**Question:** Does the Ditto SDK v5 expose the local peer key via the same API on both Android and iOS?

**Research needed:** Verify the SDK API for getting own peer key in Kotlin and Swift.

**Decision:**   Yes it's exposed in all SDKs and that is what we will use. 

---

### Q18: Multi-simulation cleanup

**Context:** After a simulation completes, the `__des_sim_*` documents remain in the Ditto database forever. Over time, this could accumulate a lot of data.

**Options:**
- A) Manual cleanup — user can delete a simulation from the list, which EVICTs all related docs
- B) Automatic cleanup — after N days, old simulation data is evicted
- C) Archive to local SQLCipher — move completed simulation results to local storage and evict from Ditto

**Recommended:** A for Phase 1. Add B/C in Phase 2.

**Decision:** C but wha we do is offer some kind of dump that will just dump everything to a folder of raw JSON and zip it up.  We offer the schema in the docs and some kind of python script to view it in fancy reports. 

---

### Q19: Scenario file format — one file per bot OR one bundled file for all bots?

**Context:** Two valid approaches emerged from load testing research (Artillery, k6):

**Option A: One file per bot (current design)**
- Wizard Step 2 shows an "Upload Scenario JSON" button per selected bot
- Each file is specific to that bot (its name, role, and steps)
- Visual: drag-drop a file onto each device row in the wizard
- Simpler mental model: "this file runs on this device"

**Option B: One bundled file for all bots**
- Single JSON file uploaded once in the wizard
- Contains a `scripts[]` array (reusable script definitions)
- Contains a `botAssignments[]` array mapping peerKey → scriptId + startOffsetSeconds
- Multiple bots can share the same script without duplicating JSON

```json
{
  "scripts": [
    { "id": "order-taker", "name": "POS Script", "steps": [...] },
    { "id": "kitchen",     "name": "KDS Script", "steps": [...] }
  ],
  "botAssignments": [
    { "peerKey": "PEER-1", "scriptId": "order-taker", "startOffsetSeconds": 0 },
    { "peerKey": "PEER-2", "scriptId": "order-taker", "startOffsetSeconds": 5 },
    { "peerKey": "PEER-3", "scriptId": "kitchen",     "startOffsetSeconds": 0 }
  ]
}
```

**Tradeoffs:**

| | Per-Bot File (A) | Bundled File (B) |
|-|-----------------|-----------------|
| Sharing scripts across bots | ❌ Must duplicate JSON | ✅ Script defined once |
| Wizard UX | ✅ Intuitive per-device | 🔶 Single upload, assignments inside file |
| Start offset per bot | Set in wizard UI | Declared in file |
| File complexity | Simple (one script each) | Higher (scripts[] + botAssignments[]) |
| Validation | Simpler | Must validate all peerKey references |

**Recommended:** A for Phase 1 — simpler wizard UX, simpler validation. If users frequently want to share the same script across multiple bots, add Option B in Phase 2.

**Decision:** It's one file per bot.  It's easiser to manage with one file per bot.   

---

### Q20: Should bots have a `startOffsetSeconds` (staggered start)?

**Context:** k6 and JMeter both support per-bot start delays to stagger load. In DittoSim, you might want the kitchen display bot to start 10 seconds after the POS terminals so there are already orders in the queue.

**Options:**
- A) All bots start at exactly the same `scheduledStartTime`
- B) Orchestrator sets a `startOffsetSeconds` per bot (configurable in wizard Step 2)
- C) Bot starts when it sees its first matching reactive scenario document in Ditto (event-driven start)

**Recommended:** B — add a `startOffsetSeconds` field to each bot's wizard config (Step 2). Defaults to 0. The orchestrator sets the bot's effective start time = `scheduledStartTime + offset`. Easy to implement, powerful for realistic simulations.

**Decision:** B 

---

## Questions for Ditto SDK Team

1. **Peer key stability:** Does a device's peer key change if the app is reinstalled? If so, bots need to re-scan the QR code after reinstall to get new assignments.

They are stable and only change if someone deletes a directory in the database folder which for our usage will never happen, so this is fine.

2. **system:data_sync_info availability:** Is this DQL table available in the Ditto v5 SDK on mobile (not just cloud)?

No, not available on SDK/mobile. 

3. **Transport config API on iOS:** Is `DittoTransportConfig` fully available on iOS in the same way as Android?
 
 Yes all SDKs are based on rust and then FFI to platform so if one feature is in one language, it's in all of them.

4. **Maximum document size:** Is there a practical limit on document size for P2P sync performance? What's the sweet spot?

It's 5 MB.  We want to test that because it's about what transports you are using.  The whole point for the simulator is for developers to simulate load with different document sizes and see based on what transports they use the performance.  So if anything, this is the purpose of this tool is to tell them the sweet spot, but it's based more on transports and how many nodes than document size as a single factor.

5. **Subscription count per device:** Is there a practical limit on how many concurrent sync subscriptions a mobile device should have?

There isn't, but most customer apps have under 8 and probably won't have more than 8 since we are simulating customers workflow.
