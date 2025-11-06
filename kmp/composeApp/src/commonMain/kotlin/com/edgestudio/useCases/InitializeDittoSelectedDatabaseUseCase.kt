package com.edgestudio.useCases

import com.edgestudio.data.IDittoManager
import com.edgestudio.models.ESDatabaseConfig

class InitializeDittoSelectedDatabaseUseCase(
    private val dittoManager: IDittoManager,
    private val databaseConfig: ESDatabaseConfig
) {
    suspend operator fun invoke() = dittoManager.initializeDittoSelectedDatabase(databaseConfig)
}