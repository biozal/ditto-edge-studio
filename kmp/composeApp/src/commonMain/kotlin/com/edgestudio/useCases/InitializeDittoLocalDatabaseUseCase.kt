package com.edgestudio.useCases
import com.edgestudio.data.IDittoManager

class InitializeDittoLocalDatabaseUseCase(
    private val dittoManager: IDittoManager) {
    suspend operator fun invoke() = dittoManager.initializeDittoStore()

}