package com.edgestudio.useCases

import com.edgestudio.data.IDittoManager

class IsDittoSelectedDatabaseSyncingUseCase(
    private val dittoManager: IDittoManager) {
    suspend operator fun invoke () = dittoManager.isDittoSelectedDatabaseSyncing()
}