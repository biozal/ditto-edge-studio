package com.edgestudio.useCases

import com.edgestudio.data.IDittoManager

class IsDittoSelectedDatabaseInitializedUseCase(
    private val dittoManager: IDittoManager) {

    suspend operator fun invoke() = dittoManager.isDittoSelectedDatabaseInitialized()
}