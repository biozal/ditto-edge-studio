package com.edgestudio.useCases

import com.edgestudio.data.IDittoManager

class CloseDittoLocalDatabaseUseCase(private val dittoManager: IDittoManager) {
    operator fun invoke() = dittoManager.closeLocalDatabase()
}