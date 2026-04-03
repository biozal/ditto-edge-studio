package com.costoda.dittoedgestudio.data.di

import com.costoda.dittoedgestudio.data.db.AppDatabase
import com.costoda.dittoedgestudio.data.db.DatabaseKeyManager
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
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.ui.qrcode.QrDisplayViewModel
import com.costoda.dittoedgestudio.ui.qrcode.QrScannerViewModel
import com.costoda.dittoedgestudio.viewmodel.AppMetricsViewModel
import com.costoda.dittoedgestudio.viewmodel.DatabaseEditorViewModel
import com.costoda.dittoedgestudio.viewmodel.DatabaseListViewModel
import com.costoda.dittoedgestudio.viewmodel.DiskUsageViewModel
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel
import com.costoda.dittoedgestudio.viewmodel.QueryEditorViewModel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.koin.android.ext.koin.androidContext
import org.koin.core.module.dsl.viewModel
import org.koin.core.module.dsl.viewModelOf
import org.koin.dsl.module

val dataModule = module {
    // App-level CoroutineScope for Ditto operations
    single<CoroutineScope> { CoroutineScope(SupervisorJob() + Dispatchers.Default) }

    single { DatabaseKeyManager(androidContext()) }
    single { AppDatabase.create(androidContext(), get<DatabaseKeyManager>().getOrCreateKey()) }
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
    viewModelOf(::DatabaseListViewModel)
    viewModel { (editId: Long) -> DatabaseEditorViewModel(editId, get()) }
    viewModel { (id: Long) -> MainStudioViewModel(id, get(), get(), get(), get(), get(), get(), get(), get()) }
    viewModel { AppMetricsViewModel(androidContext(), get(), get()) }
    viewModel { DiskUsageViewModel(androidContext(), get(), get()) }
    viewModel { (databaseId: String) -> QueryEditorViewModel(databaseId, get(), get(), get(), get(), get()) }
    viewModelOf(::QrScannerViewModel)
    viewModel { (db: DittoDatabase) -> QrDisplayViewModel(db, get()) }
}
