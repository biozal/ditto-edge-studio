# DittoSim — Simulation Engine for Ditto Edge Studio

**Status:** Design Complete — All Documents Updated — Ready for Implementation Planning
**Last Updated:** 2026-02-22
**Feature Code:** `dittosim`

---

## What Is DittoSim?

DittoSim is a workflow simulation engine built into Ditto Edge Studio (the macOS/iPadOS orchestrator) and a companion mobile bot app (Kotlin Multiplatform). It allows developers to simulate realistic multi-device Ditto workflows to benchmark sync performance, validate data model design, and identify bottlenecks before production.

**Problem it solves:**
Developers building apps on Ditto's mesh network often discover performance issues with their data models too late — in production. Document sizes that are too large to sync over Bluetooth, subscription queries that are too broad, or CRDT conflicts from poorly designed arrays. DittoSim lets them discover these issues in a controlled, repeatable simulation environment.

---

## Documentation Index

### Research
- **[01-research-references.md](./01-research-references.md)** — Findings from workflow engines (n8n, Airflow, Temporal, Dapr, AWS Step Functions, Cloudflare Workflows), simulation frameworks (Artillery, Robot Framework), and Ditto SDK internals. Start here for design context.

### Design Documents
- **[02-data-model-design.md](./02-data-model-design.md)** — ✅ All 7 collection schemas (`__des_sim_*`), including new `__des_sim_steps` collection (Q16). Updated for Q7, Q20.
- **[03-scenario-file-format.md](./03-scenario-file-format.md)** — ✅ JSON schema for scenario files. Removed `maxConcurrentReactiveScenarios` (Q10); added `measurePropagationLatency` (R2).
- **[04-system-workflow.md](./04-system-workflow.md)** — ✅ Complete state machine and workflow. Updated for transport-colored cards (Q4), bot recovery flow (Q7), staggered starts (Q20), `system:system_info` polling (Q11).
- **[05-questions-and-decisions.md](./05-questions-and-decisions.md)** — ✅ All 20 questions answered.
- **[06-bot-app-kmp-design.md](./06-bot-app-kmp-design.md)** — ✅ KMP bot app architecture. Updated for Kotlin Flows backpressure (Q10), offline recovery logic (Q7), propagation latency embedding (R2), system_info poller (Q11).
- **[07-decisions-summary-and-design-updates.md](./07-decisions-summary-and-design-updates.md)** — ✅ Decision table, breaking changes, update checklist (all items complete). **Start here for design context.**
- **[08-n8n-orchestration-research.md](./08-n8n-orchestration-research.md)** — n8n as supplemental orchestrator: community edition features, Docker setup, Ditto HTTP API integration options, build-vs-integrate assessment.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              Ditto Edge Studio (macOS/iPadOS)                │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Simulation UI (new feature in this plan)            │  │
│  │  ├── Simulation List (empty state, list view)        │  │
│  │  ├── Simulation Wizard (3 steps)                     │  │
│  │  ├── Simulation Monitor (running dashboard)          │  │
│  │  └── Simulation Results (post-run analysis)          │  │
│  └──────────────────────────────────────────────────────┘  │
│                            │ writes to                      │
│                     Ditto Database                          │
│              (internal __des_sim_* collections)             │
└──────────────────────────────────┬──────────────────────────┘
                                   │ P2P Sync / Cloud Sync
              ┌────────────────────┼──────────────────────┐
              │                    │                       │
    ┌─────────▼──────┐   ┌────────▼───────┐   ┌─────────▼──────┐
    │   Bot App      │   │   Bot App      │   │   Bot App      │
    │  (KMP/iOS)     │   │  (KMP/Android) │   │  (KMP/Android) │
    │  Role: POS     │   │  Role: KDS     │   │  Role: Payment │
    └────────────────┘   └────────────────┘   └────────────────┘
```

---

## Key Design Constraints

1. **All simulation data stored in `__des_sim_*` collections** — filtered from the main Collections UI so developers don't accidentally modify them
2. **Steps are individual documents** — each scenario step is a separate `__des_sim_steps` document (not an embedded array), so each syncs as a small packet over Bluetooth (Q16)
3. **No arrays for concurrent data** — Ditto arrays are atomic (LWW); each instruction/log entry is its own document
4. **Subscriptions are bot-scoped** — each bot only syncs its own scenario/step docs (filtered by peerKey)
5. **Orchestrator is non-blocking** — Edge Studio only writes instruction docs; it never directly executes steps on bots
6. **Bot app is offline-resilient** — bots resume from their last logged step when they reconnect (Q7)
7. **Card colors = current transport** — running dashboard cards dynamically change color as bots switch transport (Q4)

---

## Mockup Reference

UI mockups are in `screens/dittosim/`:
- `simulator-empty.png` — Empty state with + FAB
- `add-step1.png` — Wizard step 1: General Info + peer selection
- `add-step2.png` — Wizard step 2: Per-bot name, role, scenario JSON upload
- `add-step3.png` — Wizard step 3: Summary before creating
- `running-screen.png` — Live monitoring dashboard with 8-bot grid

---

## Implementation Phases (Proposed, Not Yet Approved)

| Phase | Scope | App |
|-------|-------|-----|
| **Phase 1 (POC)** | Simulation wizard, data model, collection creation | Edge Studio (SwiftUI) |
| **Phase 2 (POC)** | Bot app: QR scan, scenario load, sequential step execution | Bot App (KMP) |
| **Phase 3** | Reactive scenarios, transport config steps | Both |
| **Phase 4** | Live monitoring dashboard, results view | Edge Studio (SwiftUI) |
| **Phase 5** | Results analysis, export, performance metrics | Edge Studio (SwiftUI) |
