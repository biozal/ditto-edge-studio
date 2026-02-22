# DittoBot App — KMP Architecture & Design

**Status:** Updated — All decisions applied (2026-02-22)
**Last Updated:** 2026-02-22

This document covers the technical architecture for the DittoBot companion app — the mobile app that runs on physical bot devices (iOS + Android) during simulations.

---

## Technology Decision: KMP Confirmed

**Kotlin Multiplatform + Compose Multiplatform is the correct choice.** Three hard constraints decide it:

1. **Ditto has an official KMP demo:** [`getditto/demoapp-kmp`](https://github.com/getditto/demoapp-kmp) shows exactly how to wrap both the Android Kotlin SDK and iOS Swift SDK in a KMP app. This is the reference implementation.

2. **Scenario engine is pure business logic:** Timers, state machines, coroutines, DQL execution, REST calls — all native KMP capabilities that live in `commonMain` shared code.

3. **Flutter is risky:** The `ditto_live` Flutter package exists on pub.dev but is **public preview (v4.9 only)** — not production-stable, breaking changes possible. React Native has **no official Ditto package** at all.

### Decision Matrix

| Criterion | KMP | Flutter | React Native |
|-----------|-----|---------|--------------|
| Official Ditto SDK | ✅ KMP demo app | ⚠️ Public preview | ❌ No package |
| Background execution | ✅ ForegroundService / BGTask | ⚠️ Community packages | ❌ Android only (Headless JS) |
| Concurrency | ✅ Structured coroutines | ✅ Dart isolates | ❌ JS event loop (wrong model) |
| Scenario engine code share | ✅ 100% commonMain | ✅ 100% Dart | ✅ 100% JS |
| iOS background execution | ✅ BGTaskScheduler via iosMain | ⚠️ Community | ❌ Very limited |
| Production maturity 2026 | ✅ Stable, Google-endorsed | ✅ Stable, Google-maintained | ✅ Stable, Meta |

---

## KMP Background Threading

`kotlinx.coroutines` is fully multiplatform. The same coroutine code runs on Android (JVM dispatchers) and iOS (Kotlin Native dispatchers).

### Key Coroutine Primitives for Scenario Runner

| Primitive | Use Case |
|-----------|----------|
| `launch` | Fire-and-forget step execution |
| `delay(ms)` | Sleep step — suspends, does NOT block a thread |
| `async / await` | Steps that must run in parallel and all complete |
| `withTimeout(ms)` | Guard each step against hanging forever |
| `SupervisorJob` | One failing step does NOT cancel the whole scenario |
| `CoroutineScope` | Lifecycle-scoped — cancel all work when needed |
| `StateFlow` | Push status updates to Compose UI reactively |
| `SharedFlow` | Broadcast log entries to multiple observers |

### ⚠️ Critical iOS Rule

Updating `StateFlow` from a background thread **crashes** on iOS Kotlin Native. Always wrap UI state updates:

```kotlin
withContext(Dispatchers.Main) { _status.value = newState }
```

---

## Scenario Step Model (commonMain)

The step types map exactly to the JSON scenario file format from `03-scenario-file-format.md`. Loaded using `kotlinx.serialization`:

```kotlin
@Serializable
sealed class BotStep {
    @Serializable @SerialName("sleep")
    data class Sleep(val minMs: Long, val maxMs: Long? = null) : BotStep()

    @Serializable @SerialName("dqlExecute")
    data class DqlExecute(
        val statement: String,
        val args: Map<String, JsonElement> = emptyMap(),
        val timeoutMs: Long? = null,
        val expectMutations: Boolean = false
    ) : BotStep()

    @Serializable @SerialName("httpRequest")
    data class HttpRequest(
        val method: String,
        val url: String,
        val headers: Map<String, String> = emptyMap(),
        val body: JsonElement? = null,
        val timeoutMs: Long? = null,
        val expectStatusCode: Int? = null
    ) : BotStep()

    @Serializable @SerialName("dittoStartSync")   data object DittoStartSync : BotStep()
    @Serializable @SerialName("dittoStopSync")    data object DittoStopSync : BotStep()

    @Serializable @SerialName("dittoTransportConfig")
    data class DittoTransportConfig(
        val isBluetoothLeEnabled: Boolean? = null,
        val isLanEnabled: Boolean? = null,
        val isAwdlEnabled: Boolean? = null,
        val isCloudSyncEnabled: Boolean? = null
    ) : BotStep()

    @Serializable @SerialName("loadData")
    data class LoadData(
        val dataSetKey: String,
        val strategy: String = "sequential",
        val updateTimestamp: Boolean = true
    ) : BotStep()

    @Serializable @SerialName("log")
    data class Log(val message: String, val level: String = "info") : BotStep()

    @Serializable @SerialName("updateScreen")
    data class UpdateScreen(
        val message: String,
        val style: String = "info",
        val duration: Long = 0
    ) : BotStep()

    @Serializable @SerialName("alertOrchestrator")
    data class AlertOrchestrator(
        val message: String,
        val isFatal: Boolean = false,
        val errorType: String = "step_execution_failed"
    ) : BotStep()
}
```

---

## Scenario Runner (commonMain)

```kotlin
class ScenarioRunner(
    private val ditto: DittoService,     // expect/actual per platform
    private val http: HttpClient,         // Ktor — shared
    private val logger: KermitLogger,     // Kermit — shared
    private val botConfig: BotConfig,
) {
    private val _status = MutableStateFlow<RunnerStatus>(RunnerStatus.Idle)
    val status: StateFlow<RunnerStatus> = _status.asStateFlow()

    private val job = SupervisorJob()
    private val scope = CoroutineScope(Dispatchers.Default + job)

    fun startSequentialScenario(scenario: Scenario) {
        scope.launch {
            val totalIterations = if (scenario.repeat.count == -1L) Long.MAX_VALUE else scenario.repeat.count
            var iteration = 0L
            while (iteration < totalIterations && !job.isCancelled) {
                scenario.steps.forEachIndexed { i, step ->
                    updateProgress(scenario.index, i)
                    val result = withTimeout(step.timeoutMs ?: 30_000L) { executeStep(step) }
                    writeBotLog(scenario, i, step, result)
                }
                delay(scenario.repeat.delayMs)
                iteration++
            }
        }
    }

    fun startReactiveScenario(scenario: Scenario, simStartMs: Long) {
        scope.launch {
            // Natural backpressure via Kotlin Flows (Q10): the observer does not
            // re-fire until the collect block completes. No manual concurrency cap needed.
            ditto.observeQuery(scenario.observer.query).collect { triggerEvent ->
                scenario.steps.forEach { step -> executeStep(step, trigger = triggerEvent) }

                // Opt-in propagation latency measurement (R2)
                if (scenario.measurePropagationLatency) {
                    val tsField = scenario.propagationLatencyField ?: "__des_sim_ts"
                    val insertedAtMs = triggerEvent.document[tsField] as? Long
                    if (insertedAtMs != null) {
                        val latencyMs = relativeNowMs(simStartMs) - insertedAtMs
                        writePropagationLatencyLog(triggerEvent, latencyMs, simStartMs)
                    }
                }
            }
        }
    }

    private suspend fun executeStep(step: BotStep, trigger: TriggerEvent? = null): StepResult {
        return when (step) {
            is BotStep.Sleep -> {
                val duration = if (step.maxMs != null)
                    Random.nextLong(step.minMs, step.maxMs) else step.minMs
                delay(duration)
                StepResult.Success(durationMs = duration)
            }
            is BotStep.DqlExecute -> {
                val resolved = resolveTemplateVars(step.statement, trigger)
                ditto.executeQuery(resolved, step.args)
            }
            is BotStep.HttpRequest -> {
                val resolved = resolveTemplateVars(step.url, trigger)
                http.request(resolved, step.method, step.headers, step.body)
            }
            is BotStep.DittoStartSync -> ditto.startSync().let { StepResult.Success() }
            is BotStep.DittoStopSync -> ditto.stopSync().let { StepResult.Success() }
            is BotStep.DittoTransportConfig -> ditto.applyTransportConfig(step).let { StepResult.Success() }
            is BotStep.LoadData -> loadNextDataItem(step).let { StepResult.Success() }
            is BotStep.Log -> writeLog(step, trigger).let { StepResult.Success() }
            is BotStep.UpdateScreen -> {
                withContext(Dispatchers.Main) {
                    _status.value = RunnerStatus.Running(
                        message = resolveTemplateVars(step.message, trigger),
                        style = step.style
                    )
                }
                StepResult.Success()
            }
            is BotStep.AlertOrchestrator -> {
                writeProblemToDitto(step, trigger)
                if (step.isFatal) throw FatalBotError(step.message)
                StepResult.Success()
            }
        }
    }

    fun cancel() = job.cancel()

    // Relative timestamp (ms since simulation start) — used for latency and all log timestamps
    private fun relativeNowMs(simStartMs: Long): Long = System.currentTimeMillis() - simStartMs

    // Log propagation latency when reactive observer receives a document from another bot
    private suspend fun writePropagationLatencyLog(
        trigger: TriggerEvent,
        latencyMs: Long,
        simStartMs: Long
    ) {
        ditto.executeQuery("""
            INSERT INTO __des_sim_bot_logs DOCUMENTS (:entry) ON ID CONFLICT DO NOTHING
        """, mapOf("entry" to buildLogEntry(
            eventType = "propagation_latency",
            data = mapOf(
                "documentId" to trigger.document["_id"],
                "latencyMs" to latencyMs,
                "activeTransports" to botConfig.activeTransports
            )
        )))
    }

    // Periodic system:system_info snapshot (runs every 30s in a separate coroutine — Q11)
    fun startSystemInfoPoller(simStartMs: Long, simStartUnixSeconds: Long) {
        scope.launch {
            while (!job.isCancelled) {
                delay(30_000L)
                val rows = ditto.executeQuery("SELECT * FROM system:system_info").items
                val filtered = rows.filter { (it["timestamp"] as? Long ?: 0L) >= simStartUnixSeconds }
                val snapshot = buildSystemInfoSnapshot(filtered)
                ditto.executeQuery("""
                    INSERT INTO __des_sim_bot_logs DOCUMENTS (:entry) ON ID CONFLICT DO NOTHING
                """, mapOf("entry" to mapOf(
                    "eventType" to "system_info_snapshot",
                    "relativeMs" to relativeNowMs(simStartMs),
                    "data" to snapshot
                )))
            }
        }
    }
}
```

---

## Offline Recovery Logic (Q7 — Required Phase 1)

When the bot app restarts or reconnects mid-simulation, the `ScenarioEngine` must resume from the last known good step rather than starting over.

```kotlin
class ScenarioEngine(private val ditto: DittoService, private val simId: String, private val peerKey: String) {

    suspend fun resumeOrStart(simStartMs: Long) {
        val lastLog = findLastStepLog()

        if (lastLog == null) {
            // No previous progress — start from the beginning
            start(simStartMs)
        } else {
            val resumeScenario = lastLog["scenarioIndex"] as Int
            val resumeStep = (lastLog["stepIndex"] as Int) + 1  // next step after last completed

            // Log the resume event
            writeResumeLog(resumeScenario, resumeStep, simStartMs)

            // Increment offline counter
            ditto.executeQuery("""
                UPDATE __des_sim_bots
                SET offlineCount = offlineCount + 1, lastOfflineAt = :now
                WHERE _id.simId = :simId AND _id.peerKey = :peerKey
            """, mapOf("simId" to simId, "peerKey" to peerKey, "now" to System.currentTimeMillis()))

            // Resume from saved position
            start(simStartMs, fromScenario = resumeScenario, fromStep = resumeStep)
        }
    }

    private suspend fun findLastStepLog(): Map<String, Any>? {
        val result = ditto.executeQuery("""
            SELECT * FROM __des_sim_bot_logs
            WHERE _id.simId = :simId AND _id.peerKey = :peerKey
              AND eventType IN ('step_completed', 'step_started')
            ORDER BY _id.seq DESC
            LIMIT 1
        """, mapOf("simId" to simId, "peerKey" to peerKey))
        return result.items.firstOrNull()?.value
    }

    private suspend fun writeResumeLog(scenarioIndex: Int, stepIndex: Int, simStartMs: Long) {
        ditto.executeQuery("""
            INSERT INTO __des_sim_bot_logs DOCUMENTS (:entry) ON ID CONFLICT DO NOTHING
        """, mapOf("entry" to mapOf(
            "eventType" to "resumed_after_offline",
            "resumedFromScenarioIndex" to scenarioIndex,
            "resumedFromStepIndex" to stepIndex,
            "relativeMs" to (System.currentTimeMillis() - simStartMs)
        )))
    }
}
```

### Recovery Scenarios

| Situation | Recovery Behavior |
|-----------|------------------|
| App killed mid-step | Resume from same step (step_started not followed by step_completed) |
| App killed between steps | Resume from next step (step_completed is the last entry) |
| App killed between scenarios | Resume from first step of next scenario |
| App killed, no log entries | Start from beginning |
| Sync disconnected but app running | Scenario continues locally (Ditto is offline-first); logs sync when reconnected |

---

## Propagation Latency Embedding (R2)

When a `dqlExecute` step inserts documents into a user collection, the bot embeds a relative timestamp for the receiving bot to measure sync latency:

```kotlin
// In executeStep for DqlExecute:
is BotStep.DqlExecute -> {
    var resolvedArgs = resolveTemplateVarArgs(step.args, trigger)

    // If the step's args contain a document object (e.g., `:order`),
    // and we're in a simulation with latency measurement enabled,
    // embed the relative timestamp into the document:
    if (scenario.measurePropagationLatency == true && resolvedArgs.containsDocumentArg()) {
        resolvedArgs = resolvedArgs.embedTimestamp("__des_sim_ts", relativeNowMs(simStartMs))
    }

    ditto.executeQuery(step.statement, resolvedArgs)
}
```

The receiving bot's reactive observer computes:
```kotlin
val latencyMs = relativeNowMs(simStartMs) - (trigger.document["__des_sim_ts"] as Long)
```

This works because both bots subtract the same `simulationStartTimeMs` base, so NTP drift cancels out.

---

## DittoService: expect/actual Pattern

```
commonMain/DittoService.kt           ← interface + expect factory
androidMain/DittoService.android.kt  ← actual (direct Kotlin SDK)
iosMain/DittoService.ios.kt          ← actual (ObjC interop to Swift SDK)
```

**commonMain:**
```kotlin
interface DittoService {
    suspend fun startSync()
    suspend fun stopSync()
    suspend fun executeQuery(dql: String, args: Map<String, JsonElement> = emptyMap()): QueryResult
    fun observeQuery(dql: String): Flow<TriggerEvent>
    suspend fun applyTransportConfig(config: BotStep.DittoTransportConfig)
    val localPeerKey: String
}

expect fun createDittoService(appId: String, token: String, authUrl: String): DittoService
```

**androidMain (Kotlin Ditto SDK):**
```kotlin
actual fun createDittoService(appId: String, token: String, authUrl: String): DittoService =
    AndroidDittoService(appId, token, authUrl)

class AndroidDittoService(appId: String, token: String, authUrl: String) : DittoService {
    private val ditto = Ditto(
        androidContext,
        DittoIdentity.OnlinePlayground(appId, token, authUrl)
    )

    override fun observeQuery(dql: String): Flow<TriggerEvent> = callbackFlow {
        val observer = ditto.store.registerObserver(dql) { result ->
            result.items.forEach { doc -> trySend(TriggerEvent(doc.value)) }
        }
        awaitClose { observer.close() }
    }

    override val localPeerKey: String
        get() = ditto.presence.graph.localPeer.peerKey.toString()
}
```

**iosMain (ObjC interop to Ditto iOS Swift SDK):**
```kotlin
actual fun createDittoService(appId: String, token: String, authUrl: String): DittoService =
    IosDittoService(appId, token, authUrl)

// Calls the DittoBridge.swift ObjC-compatible wrapper
// If Ditto iOS SDK uses Swift-only features (actors, non-bridged generic APIs),
// a thin DittoBridge.swift class exposes them in ObjC-compatible form
class IosDittoService(appId: String, token: String, authUrl: String) : DittoService {
    private val bridge = DittoBridge(appId, token, authUrl)

    override fun observeQuery(dql: String): Flow<TriggerEvent> = callbackFlow {
        bridge.registerObserver(dql) { docJson ->
            trySend(TriggerEvent(parseJson(docJson)))
        }
        awaitClose { bridge.cancelObserver(dql) }
    }
}
```

---

## Background Execution Strategy

### Android: Foreground Service

WorkManager has a 15-minute minimum interval — useless for continuous scenario execution. Use a **Foreground Service** for the simulation runner:

```kotlin
// androidMain
class SimulationForegroundService : Service() {
    override fun onStartCommand(intent: Intent, flags: Int, startId: Int): Int {
        startForeground(NOTIF_ID, buildNotification("Simulation running..."))
        serviceScope.launch { runner.start(loadScenarios()) }
        return START_STICKY  // Restart if killed
    }
}
```

Use WorkManager for periodic log sync (deferrable, short-lived periodic task — fine for WorkManager).

### iOS: Foreground-First Strategy

iOS aggressively suspends background apps. For Phase 1 POC:

1. **Primary:** Keep app in foreground during simulation
   ```swift
   UIApplication.shared.isIdleTimerDisabled = true  // Prevent screen sleep
   ```
2. **Fallback:** Register `BGProcessingTask` for short-term backgrounding (incoming call, etc.)
3. **Recovery:** Use `__des_sim_bots` Ditto document to track last-completed step. On relaunch, resume from last known position.

**Note for bot device setup:** Bots should have "Auto-Lock: Never" configured during simulations.

---

## REST API Calls (Ktor — Shared)

Ktor is fully multiplatform. Zero platform-specific code needed:

```kotlin
// commonMain — Android uses OkHttp engine, iOS uses Darwin (NSURLSession)
val client = HttpClient {
    install(ContentNegotiation) { json() }
    install(HttpTimeout) { requestTimeoutMillis = 30_000 }
}

suspend fun callDittoHttpApi(url: String, body: JsonObject, apiKey: String): DittoApiResponse =
    client.post(url) {
        contentType(ContentType.Application.Json)
        header("x-api-key", apiKey)
        setBody(body)
    }.body()
```

---

## Logging (Kermit — Shared)

[Kermit by Touchlab](https://github.com/touchlab/Kermit) is the standard KMP logging library:

```kotlin
val logger = Logger(
    config = StaticConfig(logWriters = listOf(CommonWriter(), FileLogWriter(logFilePath))),
    tag = "DittoBot"
)

// Use anywhere in shared code:
logger.i { "Step 3: Inserted order $orderId in ${durationMs}ms" }
logger.w { "WiFi disabled — Bluetooth-only mode" }
logger.e(throwable) { "REST API call failed: ${throwable.message}" }
```

Structured entries also written to `__des_sim_bot_logs` in Ditto for orchestrator access:

```kotlin
ditto.executeQuery("""
    INSERT INTO __des_sim_bot_logs DOCUMENTS (:entry) ON ID CONFLICT DO NOTHING
""", mapOf("entry" to buildLogEntry(scenarioIndex, stepIndex, message, durationMs)))
```

---

## Bot App UI (Compose Multiplatform — Shared)

Compose Multiplatform 1.8.0 is stable for iOS (2025). All bot UI lives in `commonMain`:

```kotlin
@Composable
fun SimulationRunningScreen(viewModel: BotViewModel) {
    val status by viewModel.status.collectAsStateWithLifecycle()
    val logs by viewModel.logs.collectAsState()
    val timeRemaining by viewModel.timeRemaining.collectAsState()

    Column(Modifier.fillMaxSize().background(Color.Black).padding(16.dp)) {
        // Status header
        StatusBanner(status = status)

        // Time remaining
        Text("Time remaining: ${timeRemaining.toMinuteSeconds()}", color = Color.White)

        // Current step display
        Text("Current: ${status.currentStepDescription}", color = Color.Yellow)

        // Scrolling log
        LazyColumn(modifier = Modifier.weight(1f)) {
            items(logs.takeLast(50)) { entry -> LogRow(entry) }
        }
    }
}
```

---

## Recommended Dependency Stack

| Library | Version | Purpose |
|---------|---------|---------|
| `kotlinx.coroutines` | 1.9+ | Async scenario execution engine |
| `kotlinx.serialization` | 1.7+ | JSON scenario file loading |
| `ktor-client-core` | 3.0+ | REST API calls to Ditto HTTP API |
| `kermit` (Touchlab) | 2.0+ | Cross-platform file + console logging |
| `compose-multiplatform` | 1.8.0+ | Shared bot status UI (iOS stable) |
| Ditto Kotlin SDK | 5.x | Android DQL + sync |
| Ditto iOS SDK | 5.x | iOS DQL + sync (ObjC interop) |

---

## Recommended Project Structure

```
dittobot-kmp/
├── shared/
│   ├── commonMain/
│   │   ├── data/
│   │   │   ├── DittoService.kt           # expect interface
│   │   │   ├── BotStep.kt                # sealed class (JSON deserializes to these)
│   │   │   ├── BotScenario.kt            # full scenario model
│   │   │   └── BotConfig.kt              # simulation assignment from orchestrator
│   │   ├── engine/
│   │   │   ├── ScenarioRunner.kt         # core execution engine
│   │   │   ├── TemplateEngine.kt         # {{variable}} resolution
│   │   │   └── DataSetManager.kt         # sample data loading/cycling
│   │   ├── network/
│   │   │   └── DittoRestApiClient.kt     # Ktor HTTP client
│   │   ├── logging/
│   │   │   └── BotLogger.kt              # Kermit wrapper + Ditto log writes
│   │   └── ui/
│   │       ├── BotViewModel.kt           # StateFlow ViewModels
│   │       ├── SimulationRunningScreen.kt
│   │       ├── SimulationListScreen.kt   # Shows assigned simulations
│   │       └── QRScanScreen.kt           # expect/actual QR camera
│   ├── androidMain/
│   │   ├── DittoService.android.kt       # wraps Kotlin Ditto SDK
│   │   ├── QRScanner.android.kt          # CameraX + ML Kit
│   │   └── BackgroundRunner.android.kt   # ForegroundService
│   └── iosMain/
│       ├── DittoService.ios.kt           # ObjC interop → DittoBridge.swift
│       ├── QRScanner.ios.kt              # AVFoundation
│       └── BackgroundRunner.ios.kt       # BGProcessingTask
├── androidApp/
│   ├── MainActivity.kt
│   └── SimulationForegroundService.kt
└── iosApp/
    ├── ContentView.swift                  # Hosts Compose Multiplatform
    ├── DittoBridge.swift                  # ObjC-compatible Ditto SDK wrapper
    └── Info.plist                         # Background modes: processing
```

---

## Implementation Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| iOS ObjC interop boundary | High | Wrap any Swift-only Ditto APIs in `DittoBridge.swift` (ObjC-compatible). Reference `demoapp-kmp` for pattern. |
| StateFlow on background threads (iOS) | High | Enforce `withContext(Dispatchers.Main)` for all UI state updates. |
| iOS background execution during long simulations | Medium | Foreground-only for Phase 1 POC with `isIdleTimerDisabled`. BGProcessingTask as fallback. |
| Ditto iOS SDK API surface coverage | Medium | Verify transport config API availability in v5 iOS SDK before Phase 2 implementation. |
| `ditto_live` Flutter package breaking changes | Low | Not using Flutter — KMP only. |

---

## Reference: getditto/demoapp-kmp

The official Ditto KMP demo is the primary reference for `DittoService` expect/actual implementation:
- Shows how to wrap both Android Kotlin SDK and iOS Swift SDK
- Demonstrates ObjC interop pattern for iOS
- Maintained by the Ditto team alongside SDK updates
- URL: `https://github.com/getditto/demoapp-kmp`
