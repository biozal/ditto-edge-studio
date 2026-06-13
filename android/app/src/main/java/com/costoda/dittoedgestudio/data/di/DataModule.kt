package com.costoda.dittoedgestudio.data.di

import com.costoda.dittoedgestudio.data.db.AppDatabase
import com.costoda.dittoedgestudio.data.db.DatabaseKeyManager
import com.costoda.dittoedgestudio.data.db.DatabaseOpener
import com.costoda.dittoedgestudio.data.db.DatabaseRecovery
import com.costoda.dittoedgestudio.data.ditto.DittoManager
import com.costoda.dittoedgestudio.data.logging.DittoLogCaptureService
import com.costoda.dittoedgestudio.data.logging.LoggingService
import com.costoda.dittoedgestudio.data.repository.AppMetricsRepository
import com.costoda.dittoedgestudio.data.repository.AppMetricsRepositoryImpl
import com.costoda.dittoedgestudio.data.repository.CollectionsRepository
import com.costoda.dittoedgestudio.data.repository.CollectionsRepositoryImpl
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
    single { DittoLogCaptureService(get<LoggingService>(), get<CoroutineScope>()) }
    single { DittoManager(get<CoroutineScope>(), get<DittoLogCaptureService>()) }
    single<SystemRepository> { SystemRepositoryImpl(get<CoroutineScope>()) }
    single<NetworkDiagnosticsRepository> { NetworkDiagnosticsRepositoryImpl(androidContext()) }
    single<CollectionsRepository> { CollectionsRepositoryImpl(get<CoroutineScope>()) }
    single { QueryExecutionService(get()) }
    single<QueryMetricsRepository> { QueryMetricsRepositoryImpl(get()) }
    single<AppMetricsRepository> { AppMetricsRepositoryImpl() }
    // AppHealthViewModel takes an ioDispatcher with a default of Dispatchers.IO for
    // testability; in production we let the default win. Use an explicit factory so
    // Koin doesn't try to resolve a CoroutineDispatcher binding it doesn't have.
    viewModel { AppHealthViewModel(get(), get()) }
    viewModelOf(::DatabaseListViewModel)
    viewModel { (editId: Long) -> DatabaseEditorViewModel(editId, get()) }
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
    // The session is supplied by the UI via parametersOf(session) after resolving it from
    // the studio scope; the VM stays plain so unit tests don't need a Koin scope.
    // Koin resolves SavedStateHandle from CreationExtras for viewModel {} factories.
    viewModel { (session: StudioSession) ->
        MainStudioViewModel(session = session, savedStateHandle = get())
    }
    viewModel { AppMetricsViewModel(androidContext(), get(), get()) }
    viewModel { DiskUsageViewModel(androidContext(), get(), get()) }
    // QueryEditorViewModel is parameterised on (databaseId, workbench). The workbench state
    // holder lives on the StudioSession's uiState so the editor draft, results, pagination,
    // and inspector tab survive rail-section switches that destroy/recreate this VM. See
    // [com.costoda.dittoedgestudio.data.session.QueryWorkbenchState].
    viewModel { (databaseId: String, workbench: com.costoda.dittoedgestudio.data.session.QueryWorkbenchState) ->
        QueryEditorViewModel(databaseId, workbench, get(), get(), get(), get(), get())
    }
    viewModelOf(::QrScannerViewModel)
    viewModel { (db: DittoDatabase) -> QrDisplayViewModel(db, get()) }
}
