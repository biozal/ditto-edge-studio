package com.costoda.dittoedgestudio.data.di

import com.costoda.dittoedgestudio.data.db.AppDatabase
import com.costoda.dittoedgestudio.data.db.DatabaseKeyManager
import com.costoda.dittoedgestudio.data.repository.DatabaseRepository
import com.costoda.dittoedgestudio.data.repository.DatabaseRepositoryImpl
import com.costoda.dittoedgestudio.data.repository.FavoritesRepository
import com.costoda.dittoedgestudio.data.repository.FavoritesRepositoryImpl
import com.costoda.dittoedgestudio.data.repository.HistoryRepository
import com.costoda.dittoedgestudio.data.repository.HistoryRepositoryImpl
import com.costoda.dittoedgestudio.data.repository.ObservableRepository
import com.costoda.dittoedgestudio.data.repository.ObservableRepositoryImpl
import com.costoda.dittoedgestudio.data.repository.SubscriptionsRepository
import com.costoda.dittoedgestudio.data.repository.SubscriptionsRepositoryImpl
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.ui.qrcode.QrDisplayViewModel
import com.costoda.dittoedgestudio.ui.qrcode.QrScannerViewModel
import com.costoda.dittoedgestudio.viewmodel.DatabaseEditorViewModel
import com.costoda.dittoedgestudio.viewmodel.DatabaseListViewModel
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel
import org.koin.android.ext.koin.androidContext
import org.koin.core.module.dsl.viewModel
import org.koin.core.module.dsl.viewModelOf
import org.koin.dsl.module

val dataModule = module {
    single { DatabaseKeyManager(androidContext()) }
    single { AppDatabase.create(androidContext(), get<DatabaseKeyManager>().getOrCreateKey()) }
    single { get<AppDatabase>().databaseConfigDao() }
    single { get<AppDatabase>().subscriptionDao() }
    single { get<AppDatabase>().historyDao() }
    single { get<AppDatabase>().favoriteDao() }
    single { get<AppDatabase>().observableDao() }
    single<DatabaseRepository> { DatabaseRepositoryImpl(get()) }
    single<SubscriptionsRepository> { SubscriptionsRepositoryImpl(get()) }
    single<FavoritesRepository> { FavoritesRepositoryImpl(get()) }
    single<HistoryRepository> { HistoryRepositoryImpl(get()) }
    single<ObservableRepository> { ObservableRepositoryImpl(get()) }
    viewModelOf(::DatabaseListViewModel)
    viewModel { (editId: Long) -> DatabaseEditorViewModel(editId, get()) }
    viewModel { (id: Long) -> MainStudioViewModel(id) }
    viewModelOf(::QrScannerViewModel)
    viewModel { (db: DittoDatabase) -> QrDisplayViewModel(db, get()) }
}
