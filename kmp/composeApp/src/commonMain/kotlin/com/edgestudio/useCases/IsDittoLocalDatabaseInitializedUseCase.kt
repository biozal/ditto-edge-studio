package com.edgestudio.useCases

import com.edgestudio.data.IDittoManager

class IsDittoLocalDatabaseInitializedUseCase(
    private val dittoManager: IDittoManager
) {
    suspend operator fun invoke() = dittoManager.isDittoLocalDatabaseInitialized()
}