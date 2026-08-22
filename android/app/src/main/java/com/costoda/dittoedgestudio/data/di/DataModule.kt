package com.costoda.dittoedgestudio.data.di

import com.costoda.dittoedgestudio.data.db.AppDatabase
import com.costoda.dittoedgestudio.data.db.DatabaseKeyManager
import com.costoda.dittoedgestudio.data.db.DatabaseOpener
import com.costoda.dittoedgestudio.data.db.DatabaseRecovery
import com.costoda.dittoedgestudio.data.ditto.DittoManager
import com.costoda.dittoedgestudio.data.logging.DittoLogCaptureService
import com.costoda.dittoedgestudio.data.logging.LoggingService
import com.costoda.dittoedgestudio.data.preferences.AppPreferences
import com.costoda.dittoedgestudio.data.preferences.appPreferencesDataStore
import com.costoda.dittoedgestudio.data.repository.AppMetricsRepository
import com.costoda.dittoedgestudio.data.repository.AppMetricsRepositoryImpl
import com.costoda.dittoedgestudio.data.repository.CollectionsRepository
import com.costoda.dittoedgestudio.data.repository.CollectionsRepositoryImpl
import com.costoda.dittoedgestudio.data.repository.DatabaseMetricsRepository
import com.costoda.dittoedgestudio.data.repository.DatabaseMetricsRepositoryImpl
import com.costoda.dittoedgestudio.data.repository.DatabaseRepository
import com.costoda.dittoedgestudio.data.repository.DatabaseRepositoryImpl
import com.costoda.dittoedgestudio.data.repository.FavoritesRepository
import com.costoda.dittoedgestudio.data.repository.FavoritesRepositoryImpl
import com.costoda.dittoedgestudio.data.repository.HistoryRepository
import com.costoda.dittoedgestudio.data.repository.HistoryRepositoryImpl
import com.costoda.dittoedgestudio.data.repository.NetworkDiagnosticsRepository
import com.costoda.dittoedgestudio.data.repository.NetworkDiagnosticsRepositoryImpl
import com.costoda.dittoedgestudio.data.repository.ObservableRepository
import com.costoda.dittoedgestudio.data.repository.ObservableRepositoryImpl
import com.costoda.dittoedgestudio.data.repository.LocalQueryExecutionService
import com.costoda.dittoedgestudio.data.repository.QueryExecutionService
import com.costoda.dittoedgestudio.data.repository.QueryMetricsRepository
import com.costoda.dittoedgestudio.data.repository.QueryMetricsRepositoryImpl
import com.costoda.dittoedgestudio.data.repository.SubscriptionsRepository
import com.costoda.dittoedgestudio.data.repository.SubscriptionsRepositoryImpl
import com.costoda.dittoedgestudio.data.repository.SystemRepository
import com.costoda.dittoedgestudio.data.repository.SystemRepositoryImpl
import com.costoda.dittoedgestudio.data.session.StudioSession
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.ui.qrcode.QrDisplayViewModel
import com.costoda.dittoedgestudio.ui.qrcode.QrScannerViewModel
import com.costoda.dittoedgestudio.viewmodel.AppHealthViewModel
import com.costoda.dittoedgestudio.viewmodel.AppMetricsViewModel
import com.costoda.dittoedgestudio.viewmodel.DatabaseEditorViewModel
import com.costoda.dittoedgestudio.viewmodel.DatabaseListViewModel
import com.costoda.dittoedgestudio.viewmodel.DiskUsageViewModel
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel
import com.costoda.dittoedgestudio.viewmodel.QueryEditorViewModel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import androidx.lifecycle.SavedStateHandle
import org.koin.android.ext.koin.androidContext
import org.koin.core.module.dsl.viewModel
import org.koin.core.module.dsl.viewModelOf
import org.koin.core.qualifier.named
import org.koin.dsl.module
import org.koin.dsl.onClose
import com.ditto.kotlin.serialization.toDittoCbor

val dataModule = module {
    // App-level CoroutineScope for Ditto operations
    single<CoroutineScope> { CoroutineScope(SupervisorJob() + Dispatchers.Default) }

    single { DatabaseKeyManager(androidContext()) }
    single { DatabaseOpener(androidContext(), get<DatabaseKeyManager>()) }
    single { DatabaseRecovery(androidContext(), get<DatabaseKeyManager>(), get<DatabaseOpener>()) }
    // AppDatabase is built via DatabaseOpener so its open + decrypt path runs through
    // the same probe that drives AppHealthViewModel. If the probe failed, this
    // resolution path is never reached — the UI forks at the app root into the
    // KeyFailureScreen before any DAO is touched. See data/db/DatabaseOpener.kt and
    // plans/android/config-loss-investigation.md (B3).
    single {
        when (val result = get<DatabaseOpener>().openAndProbe()) {
            is com.costoda.dittoedgestudio.data.db.DatabaseOpenResult.Ok -> result.db
            is com.costoda.dittoedgestudio.data.db.DatabaseOpenResult.KeyFailure ->
                throw IllegalStateException(
                    "AppDatabase resolved while key-failure recovery should be visible. " +
                        "This indicates a bug in the AppNavGraph health-state fork.",
                    result.throwable,
                )
        }
    }
    single { get<AppDatabase>().databaseConfigDao() }
    single { get<AppDatabase>().subscriptionDao() }
    single { get<AppDatabase>().historyDao() }
    single { get<AppDatabase>().favoriteDao() }
    single { get<AppDatabase>().observableDao() }
    single { get<AppDatabase>().queryMetricsDao() }
    single<DatabaseRepository> { DatabaseRepositoryImpl(get()) }
    single<SubscriptionsRepository> { SubscriptionsRepositoryImpl(get()) }
    single<FavoritesRepository> { FavoritesRepositoryImpl(get()) }
    single<HistoryRepository> { HistoryRepositoryImpl(get()) }
    single<ObservableRepository> { ObservableRepositoryImpl(get()) }
    single { LoggingService(androidContext()) }
    single { AppPreferences(androidContext().appPreferencesDataStore) }
    single { DittoLogCaptureService(get<LoggingService>(), get<CoroutineScope>()) }
    single { DittoManager(get<CoroutineScope>(), get<DittoLogCaptureService>()) }
    single<SystemRepository> { SystemRepositoryImpl(get<CoroutineScope>()) }
    single<NetworkDiagnosticsRepository> { NetworkDiagnosticsRepositoryImpl(androidContext()) }
    single<CollectionsRepository> { CollectionsRepositoryImpl(get<CoroutineScope>()) }
    single { okhttp3.OkHttpClient() }
    single { kotlinx.serialization.json.Json { ignoreUnknownKeys = true } }
    single { LocalQueryExecutionService(get<com.costoda.dittoedgestudio.data.ditto.DittoManager>()) }
    single {
        com.costoda.dittoedgestudio.data.repository.HttpQueryExecutionService(
            client = get(),
            json = get(),
            databaseProvider = { get<com.costoda.dittoedgestudio.data.ditto.DittoManager>().currentDatabase() },
        )
    }
    single { QueryExecutionService(local = get(), http = get()) }
    single<QueryMetricsRepository> { QueryMetricsRepositoryImpl(get()) }
    single<AppMetricsRepository> { AppMetricsRepositoryImpl() }
    single<DatabaseMetricsRepository> { DatabaseMetricsRepositoryImpl() }
    single<com.costoda.dittoedgestudio.data.repository.AttachmentStoreGateway> {
        object : com.costoda.dittoedgestudio.data.repository.AttachmentStoreGateway {
            override suspend fun newAttachment(
                path: String,
                metadata: Map<String, String>,
            ): String {
                val ditto = get<com.costoda.dittoedgestudio.data.ditto.DittoManager>().currentInstance()
                    ?: error("No active Ditto instance")
                // DittoCborSerializable.Dictionary takes Map<DittoCborSerializable, DittoCborSerializable>;
                // string keys and values are Utf8String (not Text — that type does not exist in 5.0.x).
                val md = com.ditto.kotlin.serialization.DittoCborSerializable.Dictionary(
                    metadata.map { (k, v) ->
                        com.ditto.kotlin.serialization.DittoCborSerializable.Utf8String(k) to
                            com.ditto.kotlin.serialization.DittoCborSerializable.Utf8String(v)
                    }.toMap(),
                )
                // newAttachment is a regular (non-suspend) function in SDK 5.0.x.
                val att = ditto.store.newAttachment(path = path, metadata = md)
                return att.id
            }

            override suspend fun createAndLink(
                path: String,
                metadata: Map<String, String>,
                collection: String,
                fieldName: String,
                documentId: String,
            ) {
                val ditto = get<com.costoda.dittoedgestudio.data.ditto.DittoManager>().currentInstance()
                    ?: error("No active Ditto instance")

                // Build CBOR metadata dictionary for newAttachment.
                val md = com.ditto.kotlin.serialization.DittoCborSerializable.Dictionary(
                    metadata.map { (k, v) ->
                        com.ditto.kotlin.serialization.DittoCborSerializable.Utf8String(k) to
                            com.ditto.kotlin.serialization.DittoCborSerializable.Utf8String(v)
                    }.toMap(),
                )
                val attachment = ditto.store.newAttachment(path = path, metadata = md)

                // Bind the DittoAttachment to the DQL UPDATE via the CBOR Dictionary overload.
                //
                // BINDING RATIONALE: The Kotlin SDK's execute(query, Map<String,Any?>) overload
                // uses toCborOrThrow() which only supports primitives/strings/bytes/null — it does
                // NOT accept a DittoAttachment value. The reified execute<T> overload requires
                // @Serializable types; DittoAttachment has no serializer. The only correct path is
                // execute(query, DittoCborSerializable.Dictionary) using attachment.toDittoCbor()
                // which is a published SDK extension that converts DittoAttachment to its internal
                // CBOR representation (defined in serializationHelpers.kt, SDK 5.0.1).
                //
                // The DQL UPDATE uses :att and :docId argument placeholders. The :att binding
                // carries the attachment's full CBOR token so Ditto can resolve the attachment
                // object on the document.
                val cborArgs = com.ditto.kotlin.serialization.DittoCborSerializable.Dictionary(
                    mapOf(
                        com.ditto.kotlin.serialization.DittoCborSerializable.Utf8String("att")
                            to attachment.toDittoCbor(),
                        com.ditto.kotlin.serialization.DittoCborSerializable.Utf8String("docId")
                            to com.ditto.kotlin.serialization.DittoCborSerializable.Utf8String(documentId),
                    ),
                )
                ditto.store.execute(
                    query = "UPDATE $collection SET $fieldName = :att WHERE _id = :docId",
                    arguments = cborArgs,
                )
            }

            override suspend fun fetchAttachment(tokenMap: Map<String, Any>): java.io.InputStream {
                val ditto = get<com.costoda.dittoedgestudio.data.ditto.DittoManager>().currentInstance()
                    ?: error("No active Ditto instance")
                val res = ditto.store.fetchAttachment(tokenMap) { _, _ -> }
                val completed = res.asCompleted() ?: error("Attachment deleted before fetch completed")
                // Use copyToPath to land bytes in a temp file regardless of internal stream type,
                // then stream from there. Safe across SDK internal-stream changes.
                val tmp = java.io.File.createTempFile("ditto-att-", ".bin")
                completed.attachment.copyToPath(tmp.absolutePath)
                tmp.deleteOnExit()
                return tmp.inputStream()
            }
        }
    }
    single {
        com.costoda.dittoedgestudio.data.repository.AttachmentService(
            gateway = get(),
            cacheDirProvider = { androidContext().cacheDir },
        )
    }
    // AppHealthViewModel takes an ioDispatcher with a default of Dispatchers.IO for
    // testability; in production we let the default win. Use an explicit factory so
    // Koin doesn't try to resolve a CoroutineDispatcher binding it doesn't have.
    viewModel { AppHealthViewModel(get(), get()) }
    viewModelOf(::DatabaseListViewModel)
    viewModel { (editId: Long) -> DatabaseEditorViewModel(editId, get(), get()) }
    // Studio session scope — one StudioSession instance per scope id ("studio:<databaseId>").
    // The session is *not* a ViewModel: Koin scopes don't drive `onCleared`, they fire
    // `onClose` when the scope itself is closed. We rely on that to tear down Ditto exactly
    // once when no studio rail-section entry for the databaseId remains on the back stack
    // (driven by StudioScopeManager in AppNavGraph).
    scope(named(StudioSession.SCOPE_QUALIFIER)) {
        scoped { (databaseId: Long) ->
            StudioSession(
                databaseId = databaseId,
                databaseRepository = get(),
                dittoManager = get(),
                systemRepository = get(),
                networkRepo = get(),
                subscriptionsRepository = get(),
                collectionsRepository = get(),
                loggingCaptureService = get(),
                observableRepository = get(),
            )
        } onClose { it?.close() }
    }
    // The VM accepts a session-provider lambda so it can always resolve the CURRENT
    // session from Koin (re-entry-safe — see MainStudioViewModel KDoc). The UI calls
    // `parametersOf(databaseId)` and the factory below builds the lookup lambda; the
    // scope is keyed by databaseId so the lambda returns the live session even
    // across close-and-reopen cycles. Tests can construct the VM directly with
    // `{ mockSession }` and bypass Koin entirely.
    viewModel { (databaseId: Long) ->
        val scopedKoin = getKoin()
        MainStudioViewModel(
            sessionProvider = {
                scopedKoin.getOrCreateScope(
                    StudioSession.scopeId(databaseId),
                    org.koin.core.qualifier.named(StudioSession.SCOPE_QUALIFIER),
                ).get<StudioSession> { org.koin.core.parameter.parametersOf(databaseId) }
            },
            savedStateHandle = get(),
        )
    }
    viewModel { AppMetricsViewModel(get<AppMetricsRepository>()) }
    viewModel { DiskUsageViewModel(get<DittoManager>(), get<DatabaseMetricsRepository>()) }
    // QueryEditorViewModel is parameterised on (databaseId, workbench). The workbench state
    // holder lives on the StudioSession's uiState so the editor draft, results, pagination,
    // and inspector tab survive rail-section switches that destroy/recreate this VM. See
    // [com.costoda.dittoedgestudio.data.session.QueryWorkbenchState].
    viewModel { (databaseId: String, workbench: com.costoda.dittoedgestudio.data.session.QueryWorkbenchState) ->
        QueryEditorViewModel(databaseId, workbench, get(), get(), get(), get(), get(), get<AppPreferences>(), get())
    }
    viewModelOf(::QrScannerViewModel)
    viewModel { (db: DittoDatabase) -> QrDisplayViewModel(db, get()) }
}
